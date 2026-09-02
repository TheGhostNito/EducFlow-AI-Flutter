import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/asignatura.dart';
import '../models/evaluacion.dart';
import '../models/tarea.dart';
import 'asignaturas_service.dart';
import 'evaluaciones_service.dart';
import 'notification_service.dart';
import 'tareas_service.dart';
import 'translation_service.dart';
import 'user_preferences_service.dart';

class AcademicNotificationScheduler {
  AcademicNotificationScheduler._();

  static final AcademicNotificationScheduler instance =
      AcademicNotificationScheduler._();

  static const String _payloadPrefix = 'academic|';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final NotificationService _notificationService = NotificationService.instance;

  final AsignaturasService _asignaturasService = AsignaturasService.instance;

  final TareasService _tareasService = TareasService.instance;

  final EvaluacionesService _evaluacionesService = EvaluacionesService.instance;

  final TranslationService _translationService = TranslationService.instance;

  final UserPreferencesService _preferencesService =
      UserPreferencesService.instance;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _preferencesSubscription;

  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _dataSubscriptions = [];

  Timer? _debounce;

  bool _started = false;
  bool _syncing = false;
  bool _syncPending = false;

  static const int _classHorizonDays = 14;

  // =========================================================
  // INICIO / ESCUCHA AUTOMÁTICA
  // =========================================================

  void start() {
    if (_started) {
      return;
    }

    _started = true;

    _authSubscription = _auth.authStateChanges().listen(_watchUser);

    _translationService.addListener(_onLanguageChanged);

    _watchUser(_auth.currentUser);
  }

  void _onLanguageChanged() {
    _scheduleSync();
  }

  void _watchUser(User? user) {
    _debounce?.cancel();

    unawaited(_preferencesSubscription?.cancel());
    _preferencesSubscription = null;

    for (final subscription in _dataSubscriptions) {
      unawaited(subscription.cancel());
    }

    _dataSubscriptions.clear();

    if (user == null) {
      unawaited(_cancelAcademicPending());
      return;
    }

    final DocumentReference<Map<String, dynamic>> userRef = _firestore
        .collection('usuarios')
        .doc(user.uid);

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

    _debounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(syncNow());
    });
  }

  // =========================================================
  // SINCRONIZACIÓN PRINCIPAL
  // =========================================================

  Future<void> syncNow() async {
    final bool spanish = _translationService.isSpanish;
    final User? user = _auth.currentUser;

    if (user == null) {
      await _cancelAcademicPending();
      return;
    }

    if (kIsWeb) {
      return;
    }

    if (_syncing) {
      _syncPending = true;
      return;
    }

    _syncing = true;

    try {
      final UserPreferences userPreferences = await _preferencesService
          .getCurrentPreferences(forceRefresh: true);

      final NotificationPreferences preferences = userPreferences.notifications;

      if (!preferences.enabled) {
        await _cancelAcademicPending();
        return;
      }

      final EstadoNotificaciones estado = await _notificationService
          .obtenerEstado();

      if (estado != EstadoNotificaciones.activadas) {
        return;
      }

      final List<dynamic> resultados = await Future.wait([
        _asignaturasService.obtenerTodas(),
        _tareasService.obtenerTodas(),
        _evaluacionesService.obtenerTodas(),
      ]);

      final List<Asignatura> asignaturas = resultados[0] as List<Asignatura>;

      final List<Tarea> tareas = resultados[1] as List<Tarea>;

      final List<Evaluacion> evaluaciones = resultados[2] as List<Evaluacion>;

      // Primero limpiamos solo las notificaciones académicas
      // creadas por este scheduler. Las generales/pruebas no
      // se tocan.
      await _cancelAcademicPending();

      final DateTime now = DateTime.now();

      if (preferences.classesEnabled) {
        await _scheduleClasses(
          asignaturas: asignaturas,
          now: now,
          spanish: spanish,
          leadMinutes: preferences.classLeadMinutes,
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
        );
      }
    } catch (error) {
      debugPrint(
        'No se pudieron sincronizar las notificaciones '
        'académicas: $error',
      );
    } finally {
      _syncing = false;

      if (_syncPending) {
        _syncPending = false;
        unawaited(syncNow());
      }
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

          await _notificationService.programarNotificacion(
            id: _stableNotificationId(key),
            titulo: spanish
                ? 'Tu clase comienza pronto'
                : 'Your class starts soon',
            cuerpo: body,
            fechaHora: reminder,
            tipo: TipoNotificacionLocal.clase,
            payload: '$_payloadPrefix$key|${block.horaInicio}',
          );
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

      await _notificationService.programarNotificacion(
        id: _stableNotificationId(key),
        titulo: spanish ? 'Tarea para mañana' : 'Task due tomorrow',
        cuerpo: body,
        fechaHora: reminder,
        tipo: TipoNotificacionLocal.tarea,
        payload: '$_payloadPrefix$key',
      );
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

      await _notificationService.programarNotificacion(
        id: _stableNotificationId(key),
        titulo: spanish ? 'Evaluación mañana' : 'Evaluation tomorrow',
        cuerpo: body,
        fechaHora: reminder,
        tipo: TipoNotificacionLocal.evaluacion,
        payload: '$_payloadPrefix$key',
      );
    }
  }

  // =========================================================
  // LIMPIEZA
  // =========================================================

  Future<void> _cancelAcademicPending() async {
    try {
      final pendientes = await _notificationService.obtenerProgramadas();

      for (final pending in pendientes) {
        final String payload = pending.payload ?? '';

        if (!payload.startsWith(_payloadPrefix)) {
          continue;
        }

        await _notificationService.cancelarNotificacion(pending.id);
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

    _translationService.removeListener(_onLanguageChanged);

    await _authSubscription?.cancel();
    await _preferencesSubscription?.cancel();

    for (final subscription in _dataSubscriptions) {
      await subscription.cancel();
    }

    _dataSubscriptions.clear();

    _started = false;
  }
}

class _ReminderClock {
  const _ReminderClock({required this.hour, required this.minute});

  final int hour;
  final int minute;
}
