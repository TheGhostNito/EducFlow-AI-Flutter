import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/auth/session_controller.dart';
import '../models/asignatura.dart';
import '../models/evaluacion.dart';
import '../models/tarea.dart';
import 'asignaturas_service.dart';
import 'evaluaciones_service.dart';
import 'notification_service.dart';
import 'tareas_service.dart';
import 'translation_service.dart';
import 'user_preferences_service.dart';

@immutable
class AcademicPendingNotification {
  const AcademicPendingNotification({required this.id, this.payload});

  final int id;
  final String? payload;
}

@immutable
class AcademicNotificationRequest {
  const AcademicNotificationRequest({
    required this.id,
    required this.title,
    required this.body,
    required this.dateTime,
    required this.type,
    required this.payload,
  });

  final int id;
  final String title;
  final String body;
  final DateTime dateTime;
  final TipoNotificacionLocal type;
  final String payload;
}

class AcademicNotificationScheduler {
  factory AcademicNotificationScheduler._() {
    final notificationService = NotificationService.instance;
    return AcademicNotificationScheduler._internal(
      sessionController: SessionController.instance,
      firestore: FirebaseFirestore.instance,
      translationService: TranslationService.instance,
      isSpanish: () => TranslationService.instance.isSpanish,
      loadPreferences: () => UserPreferencesService.instance
          .getCurrentPreferences(forceRefresh: true),
      notificationState: notificationService.obtenerEstado,
      loadSubjects: AsignaturasService.instance.obtenerTodas,
      loadTasks: TareasService.instance.obtenerTodas,
      loadEvaluations: EvaluacionesService.instance.obtenerTodas,
      loadPendingNotifications: () async {
        final pending = await notificationService.obtenerProgramadas();
        return pending
            .map(
              (item) => AcademicPendingNotification(
                id: item.id,
                payload: item.payload,
              ),
            )
            .toList();
      },
      cancelNotification: notificationService.cancelarNotificacion,
      scheduleNotification: (request) async {
        await notificationService.programarNotificacion(
          id: request.id,
          titulo: request.title,
          cuerpo: request.body,
          fechaHora: request.dateTime,
          tipo: request.type,
          payload: request.payload,
        );
      },
    );
  }

  AcademicNotificationScheduler._internal({
    required this._sessionController,
    required this._firestore,
    required this._translationService,
    required this._isSpanish,
    required this._loadPreferences,
    required this._notificationState,
    required this._loadSubjects,
    required this._loadTasks,
    required this._loadEvaluations,
    required this._loadPendingNotifications,
    required this._cancelNotification,
    required this._scheduleNotification,
    this.syncDelay = const Duration(milliseconds: 250),
  });

  @visibleForTesting
  factory AcademicNotificationScheduler.forTesting({
    required SessionController sessionController,
    required Future<List<AcademicPendingNotification>> Function()
    loadPendingNotifications,
    required Future<void> Function(int id) cancelNotification,
    required Future<void> Function(AcademicNotificationRequest request)
    scheduleNotification,
    Future<UserPreferences> Function()? loadPreferences,
    Future<EstadoNotificaciones> Function()? notificationState,
    Future<List<Asignatura>> Function()? loadSubjects,
    Future<List<Tarea>> Function()? loadTasks,
    Future<List<Evaluacion>> Function()? loadEvaluations,
    Duration syncDelay = const Duration(days: 1),
  }) {
    return AcademicNotificationScheduler._internal(
      sessionController: sessionController,
      firestore: null,
      translationService: null,
      isSpanish: () => true,
      loadPreferences: loadPreferences ?? () async => UserPreferences.defaults,
      notificationState:
          notificationState ?? () async => EstadoNotificaciones.activadas,
      loadSubjects: loadSubjects ?? () async => const [],
      loadTasks: loadTasks ?? () async => const [],
      loadEvaluations: loadEvaluations ?? () async => const [],
      loadPendingNotifications: loadPendingNotifications,
      cancelNotification: cancelNotification,
      scheduleNotification: scheduleNotification,
      syncDelay: syncDelay,
    );
  }

  static final AcademicNotificationScheduler instance =
      AcademicNotificationScheduler._();

  static const String _payloadPrefix = 'academic|';

  final SessionController _sessionController;
  final FirebaseFirestore? _firestore;
  final TranslationService? _translationService;
  final bool Function() _isSpanish;
  final Future<UserPreferences> Function() _loadPreferences;
  final Future<EstadoNotificaciones> Function() _notificationState;
  final Future<List<Asignatura>> Function() _loadSubjects;
  final Future<List<Tarea>> Function() _loadTasks;
  final Future<List<Evaluacion>> Function() _loadEvaluations;
  final Future<List<AcademicPendingNotification>> Function()
  _loadPendingNotifications;
  final Future<void> Function(int id) _cancelNotification;
  final Future<void> Function(AcademicNotificationRequest request)
  _scheduleNotification;
  final Duration syncDelay;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _preferencesSubscription;

  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _dataSubscriptions = [];

  Timer? _debounce;

  bool _started = false;
  bool _hasWatchedSession = false;
  SessionTicket? _watchedTicket;
  Future<void> _notificationWork = Future<void>.value();

  static const int _classHorizonDays = 14;

  // =========================================================
  // INICIO / ESCUCHA AUTOMÁTICA
  // =========================================================

  void start() {
    if (_started) {
      return;
    }

    _started = true;

    _translationService?.addListener(_onLanguageChanged);
    _sessionController.addListener(_onSessionChanged);
    _onSessionChanged();
  }

  void _onSessionChanged() {
    final ticket = _sessionController.captureTicket();
    if (_hasWatchedSession && _sameTicket(_watchedTicket, ticket)) return;
    _hasWatchedSession = true;
    _watchedTicket = ticket;
    _watchUser(ticket);
  }

  void _onLanguageChanged() {
    _scheduleSync();
  }

  void _watchUser(SessionTicket? ticket) {
    _debounce?.cancel();

    unawaited(_preferencesSubscription?.cancel());
    _preferencesSubscription = null;

    for (final subscription in _dataSubscriptions) {
      unawaited(subscription.cancel());
    }

    _dataSubscriptions.clear();

    if (ticket == null) {
      unawaited(_enqueueNotificationWork(_cancelAcademicPending));
      return;
    }

    final firestore = _firestore;
    if (firestore == null) {
      _scheduleSync();
      return;
    }

    final DocumentReference<Map<String, dynamic>> userRef = firestore
        .collection('usuarios')
        .doc(ticket.uid);

    _preferencesSubscription = userRef.snapshots().listen((_) {
      _scheduleSync();
    }, onError: (_) {});

    _listen(userRef.collection('asignaturas'));
    _listen(userRef.collection('tareas'));
    _listen(userRef.collection('evaluaciones'));

    _scheduleSync();
  }

  void _listen(CollectionReference<Map<String, dynamic>> collection) {
    final subscription = collection.snapshots().listen(
      (_) {
        _scheduleSync();
      },
      onError: (_) {
        // Un error temporal de escucha no debe borrar
        // recordatorios que ya estaban programados.
      },
    );

    _dataSubscriptions.add(subscription);
  }

  void _scheduleSync() {
    _debounce?.cancel();

    _debounce = Timer(syncDelay, () {
      unawaited(syncNow());
    });
  }

  // =========================================================
  // SINCRONIZACIÓN PRINCIPAL
  // =========================================================

  Future<void> syncNow() async {
    final ticket = _sessionController.captureTicket();
    if (ticket == null) {
      return _enqueueNotificationWork(_cancelAcademicPending);
    }

    return _enqueueNotificationWork(() => _syncTicket(ticket));
  }

  Future<void> _syncTicket(SessionTicket ticket) async {
    bool isValid() => _sessionController.isCurrentTicket(ticket);
    if (!isValid()) return;

    if (kIsWeb) {
      return;
    }

    try {
      final bool spanish = _isSpanish();
      final UserPreferences userPreferences = await _loadPreferences();
      if (!isValid()) return;

      final NotificationPreferences preferences = userPreferences.notifications;

      if (!preferences.enabled) {
        await _cancelAcademicPending(isValid: isValid);
        return;
      }

      final EstadoNotificaciones estado = await _notificationState();
      if (!isValid()) return;

      if (estado != EstadoNotificaciones.activadas) {
        return;
      }

      final List<dynamic> resultados = await Future.wait([
        _loadSubjects(),
        _loadTasks(),
        _loadEvaluations(),
      ]);
      if (!isValid()) return;

      final List<Asignatura> asignaturas = resultados[0] as List<Asignatura>;

      final List<Tarea> tareas = resultados[1] as List<Tarea>;

      final List<Evaluacion> evaluaciones = resultados[2] as List<Evaluacion>;

      // Primero limpiamos solo las notificaciones académicas
      // creadas por este scheduler. Las generales/pruebas no
      // se tocan.
      await _cancelAcademicPending(isValid: isValid);
      if (!isValid()) return;

      final DateTime now = DateTime.now();

      if (preferences.classesEnabled) {
        await _scheduleClasses(
          asignaturas: asignaturas,
          now: now,
          spanish: spanish,
          leadMinutes: preferences.classLeadMinutes,
          isValid: isValid,
        );
      }

      if (preferences.tasksEnabled) {
        final _ReminderClock taskClock = _parseReminderClock(
          preferences.taskReminderTime,
        );

        await _scheduleTasks(
          tareas: tareas,
          asignaturas: asignaturas,
          now: now,
          spanish: spanish,
          reminderHour: taskClock.hour,
          reminderMinute: taskClock.minute,
          isValid: isValid,
        );
      }

      if (preferences.evaluationsEnabled) {
        final _ReminderClock evaluationClock = _parseReminderClock(
          preferences.evaluationReminderTime,
        );

        await _scheduleEvaluations(
          evaluaciones: evaluaciones,
          asignaturas: asignaturas,
          now: now,
          spanish: spanish,
          reminderHour: evaluationClock.hour,
          reminderMinute: evaluationClock.minute,
          isValid: isValid,
        );
      }
    } catch (error) {
      debugPrint(
        'No se pudieron sincronizar las notificaciones '
        'académicas: $error',
      );
    }
  }

  // =========================================================
  // CLASES
  // =========================================================

  Future<void> _scheduleClasses({
    required List<Asignatura> asignaturas,
    required DateTime now,
    required bool spanish,
    required int leadMinutes,
    required bool Function() isValid,
  }) async {
    final DateTime today = DateTime(now.year, now.month, now.day);

    for (int dayOffset = 0; dayOffset <= _classHorizonDays; dayOffset++) {
      final DateTime date = today.add(Duration(days: dayOffset));

      final DiaSemana? weekday = _modelWeekday(date.weekday);

      if (weekday == null) {
        continue;
      }

      for (final Asignatura subject in asignaturas) {
        for (
          int blockIndex = 0;
          blockIndex < subject.horario.length;
          blockIndex++
        ) {
          final BloqueHorario block = subject.horario[blockIndex];

          if (block.dia != weekday) {
            continue;
          }

          final DateTime? classStart = _combineDateAndTime(
            date,
            block.horaInicio,
          );

          if (classStart == null) {
            continue;
          }

          final DateTime reminder = classStart.subtract(
            Duration(minutes: leadMinutes),
          );

          if (!reminder.isAfter(now)) {
            continue;
          }

          final String room = _classRoom(subject, block);

          final String body;

          if (spanish) {
            final String roomText = room.toLowerCase().startsWith('sala ')
                ? room
                : 'sala $room';

            body = room.isEmpty
                ? '${subject.nombre} comienza a las ${block.horaInicio}.'
                : '${subject.nombre} comienza a las ${block.horaInicio} en $roomText.';
          } else {
            final String roomText = room.toLowerCase().startsWith('room ')
                ? room
                : 'room $room';

            body = room.isEmpty
                ? '${subject.nombre} starts at ${block.horaInicio}.'
                : '${subject.nombre} starts at ${block.horaInicio} in $roomText.';
          }

          final String key =
              'class|${subject.id}|${_dateKey(date)}|$blockIndex';

          if (!isValid()) return;
          await _scheduleNotification(
            AcademicNotificationRequest(
              id: _stableNotificationId(key),
              title: spanish
                  ? 'Tu clase comienza pronto'
                  : 'Your class starts soon',
              body: body,
              dateTime: reminder,
              type: TipoNotificacionLocal.clase,
              payload: '$_payloadPrefix$key|${block.horaInicio}',
            ),
          );
          if (!isValid()) return;
        }
      }
    }
  }

  // =========================================================
  // TAREAS
  // =========================================================

  Future<void> _scheduleTasks({
    required List<Tarea> tareas,
    required List<Asignatura> asignaturas,
    required DateTime now,
    required bool spanish,
    required int reminderHour,
    required int reminderMinute,
    required bool Function() isValid,
  }) async {
    for (final Tarea task in tareas) {
      if (task.completada) {
        continue;
      }

      final DateTime? dueDate = task.fechaEntrega;

      if (dueDate == null) {
        continue;
      }

      final DateTime dueDay = DateTime(
        dueDate.year,
        dueDate.month,
        dueDate.day,
      );

      final DateTime reminder = DateTime(
        dueDay.year,
        dueDay.month,
        dueDay.day,
        reminderHour,
        reminderMinute,
      ).subtract(const Duration(days: 1));

      if (!reminder.isAfter(now)) {
        continue;
      }

      final String subjectName = _subjectName(
        task.asignaturaId,
        asignaturas,
        spanish: spanish,
        fallbackGeneralTask: true,
      );

      final String body = spanish
          ? '${task.titulo} · $subjectName.'
          : '${task.titulo} · $subjectName.';

      final String key = 'task|${task.id}';

      if (!isValid()) return;
      await _scheduleNotification(
        AcademicNotificationRequest(
          id: _stableNotificationId(key),
          title: spanish ? 'Tarea para mañana' : 'Task due tomorrow',
          body: body,
          dateTime: reminder,
          type: TipoNotificacionLocal.tarea,
          payload: '$_payloadPrefix$key',
        ),
      );
      if (!isValid()) return;
    }
  }

  // =========================================================
  // EVALUACIONES
  // =========================================================

  Future<void> _scheduleEvaluations({
    required List<Evaluacion> evaluaciones,
    required List<Asignatura> asignaturas,
    required DateTime now,
    required bool spanish,
    required int reminderHour,
    required int reminderMinute,
    required bool Function() isValid,
  }) async {
    for (final Evaluacion evaluation in evaluaciones) {
      final DateTime date = DateTime(
        evaluation.fecha.year,
        evaluation.fecha.month,
        evaluation.fecha.day,
      );

      final DateTime reminder = DateTime(
        date.year,
        date.month,
        date.day,
        reminderHour,
        reminderMinute,
      ).subtract(const Duration(days: 1));

      if (!reminder.isAfter(now)) {
        continue;
      }

      final String subjectName = _subjectName(
        evaluation.asignaturaId,
        asignaturas,
        spanish: spanish,
      );

      final String body = spanish
          ? '${evaluation.titulo} · $subjectName.'
          : '${evaluation.titulo} · $subjectName.';

      final String key = 'evaluation|${evaluation.id}';

      if (!isValid()) return;
      await _scheduleNotification(
        AcademicNotificationRequest(
          id: _stableNotificationId(key),
          title: spanish ? 'Evaluación mañana' : 'Evaluation tomorrow',
          body: body,
          dateTime: reminder,
          type: TipoNotificacionLocal.evaluacion,
          payload: '$_payloadPrefix$key',
        ),
      );
      if (!isValid()) return;
    }
  }

  // =========================================================
  // LIMPIEZA
  // =========================================================

  Future<void> _cancelAcademicPending({bool Function()? isValid}) async {
    try {
      final pendientes = await _loadPendingNotifications();
      if (isValid != null && !isValid()) return;

      for (final pending in pendientes) {
        final String payload = pending.payload ?? '';

        if (!payload.startsWith(_payloadPrefix)) {
          continue;
        }

        if (isValid != null && !isValid()) return;
        await _cancelNotification(pending.id);
        if (isValid != null && !isValid()) return;
      }
    } catch (error) {
      debugPrint(
        'No se pudieron limpiar notificaciones '
        'académicas pendientes: $error',
      );
    }
  }

  // =========================================================
  // HELPERS
  // =========================================================

  bool _sameTicket(SessionTicket? left, SessionTicket? right) {
    if (left == null || right == null) {
      return left == null && right == null;
    }
    return left.uid == right.uid && left.generation == right.generation;
  }

  Future<void> _enqueueNotificationWork(Future<void> Function() operation) {
    final result = _notificationWork.then((_) => operation());
    _notificationWork = result.catchError((Object error, StackTrace stack) {
      debugPrint(
        'Falló una operación serializada de notificaciones académicas: $error',
      );
    });
    return result;
  }

  @visibleForTesting
  Future<void> waitForIdle() => _notificationWork;

  DiaSemana? _modelWeekday(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return DiaSemana.lunes;
      case DateTime.tuesday:
        return DiaSemana.martes;
      case DateTime.wednesday:
        return DiaSemana.miercoles;
      case DateTime.thursday:
        return DiaSemana.jueves;
      case DateTime.friday:
        return DiaSemana.viernes;
      case DateTime.saturday:
        return DiaSemana.sabado;
      case DateTime.sunday:
        return null;
    }

    return null;
  }

  DateTime? _combineDateAndTime(DateTime date, String value) {
    final List<String> parts = value.split(':');

    if (parts.length != 2) {
      return null;
    }

    final int? hour = int.tryParse(parts[0]);
    final int? minute = int.tryParse(parts[1]);

    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }

    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  String _classRoom(Asignatura subject, BloqueHorario block) {
    final String blockRoom = block.sala?.trim() ?? '';

    if (blockRoom.isNotEmpty) {
      return blockRoom;
    }

    return subject.sala?.trim() ?? '';
  }

  String _subjectName(
    String? id,
    List<Asignatura> asignaturas, {
    required bool spanish,
    bool fallbackGeneralTask = false,
  }) {
    final String clean = id?.trim() ?? '';

    if (clean.isEmpty) {
      if (fallbackGeneralTask) {
        return spanish ? 'Tarea general' : 'General task';
      }

      return spanish ? 'Sin asignatura' : 'No subject';
    }

    for (final Asignatura subject in asignaturas) {
      if (subject.id == clean) {
        return subject.nombre;
      }
    }

    return spanish ? 'Asignatura' : 'Subject';
  }

  _ReminderClock _parseReminderClock(String value) {
    final List<String> parts = value.split(':');

    if (parts.length != 2) {
      return const _ReminderClock(hour: 18, minute: 0);
    }

    final int? hour = int.tryParse(parts[0]);
    final int? minute = int.tryParse(parts[1]);

    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return const _ReminderClock(hour: 18, minute: 0);
    }

    return _ReminderClock(hour: hour, minute: minute);
  }

  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
  }

  int _stableNotificationId(String value) {
    // FNV-1a 32-bit, reducido al rango positivo de int32
    // para obtener IDs estables entre ejecuciones.
    int hash = 0x811C9DC5;

    for (final int unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }

    final int positive = hash & 0x7FFFFFFF;

    return positive == 0 ? 1 : positive;
  }

  Future<void> dispose() async {
    _debounce?.cancel();

    _translationService?.removeListener(_onLanguageChanged);

    _sessionController.removeListener(_onSessionChanged);
    await _preferencesSubscription?.cancel();

    for (final subscription in _dataSubscriptions) {
      await subscription.cancel();
    }

    _dataSubscriptions.clear();

    await _notificationWork;

    _hasWatchedSession = false;
    _watchedTicket = null;
    _started = false;
  }
}

class _ReminderClock {
  const _ReminderClock({required this.hour, required this.minute});

  final int hour;
  final int minute;
}
