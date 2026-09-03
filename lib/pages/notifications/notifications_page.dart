import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import '../../core/navigation/main_navigation.dart';

import '../../models/asignatura.dart';
import '../../models/evaluacion.dart';
import '../../models/notificacion_app.dart';
import '../../models/tarea.dart';
import '../../services/asignaturas_service.dart';
import '../../services/evaluaciones_service.dart';
import '../../services/notification_feed_service.dart';
import '../../services/notification_state_service.dart';
import '../../services/tareas_service.dart';
import '../../services/time_format_service.dart';
import '../../services/translation_service.dart';
import '../../widgets/app_pressable.dart';
import '../../widgets/app_reveal.dart';
import '../../widgets/app_scroll_header.dart';
import '../../widgets/app_status_snackbar.dart';
import '../../widgets/main_bottom_nav.dart';
import '../../widgets/main_section_scroll.dart';
import '../../core/auth/auth_service.dart';
import '../../models/perfil_usuario.dart';
import '../../services/perfil_service.dart';
import '../../services/horario_conflict_service.dart';
import '../tasks/widgets/task_detail_sheet.dart';
import '../tasks/widgets/task_edit_sheet.dart';
import '../calendar/widgets/evaluation_detail_sheet.dart';
import '../calendar/widgets/evaluation_edit_sheet.dart';
import '../calendar/widgets/calendar_class_detail_sheet.dart';
import '../schedule/widgets/schedule_class_edit_sheet.dart';
import '../subjects/subject_detail_page.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, this.initialPayload});

  final String? initialPayload;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  static const Color _primaryColor = Color(0xFF5B5FEF);

  final AsignaturasService _asignaturasService = AsignaturasService.instance;
  final TareasService _tareasService = TareasService.instance;
  final EvaluacionesService _evaluacionesService = EvaluacionesService.instance;

  final NotificationFeedService _feedService = NotificationFeedService.instance;
  final NotificationStateService _stateService =
      NotificationStateService.instance;

  final TranslationService _translationService = TranslationService.instance;
  final TimeFormatService _timeFormatService = TimeFormatService.instance;

  final AuthService _authService = AuthService();
  final PerfilService _perfilService = PerfilService();
  final HorarioConflictService _horarioConflictService =
      HorarioConflictService.instance;

  final ScrollController _scrollController = ScrollController();

  PerfilUsuario? _perfil;
  List<Asignatura> _asignaturas = [];
  List<Tarea> _tareas = [];
  List<Evaluacion> _evaluaciones = [];
  List<NotificacionApp> _notificaciones = [];

  bool _cargando = true;
  bool _error = false;
  bool _procesandoTodas = false;
  bool _initialPayloadProcessed = false;

  double _progresoHeader = 0;

  bool get _espanol => _translationService.isSpanish;

  bool get _esEscolar {
    final NivelEducativoPerfil nivel =
        _perfil?.nivelEducativo ?? NivelEducativoPerfil.vacio;

    return nivel == NivelEducativoPerfil.basica ||
        nivel == NivelEducativoPerfil.media;
  }

  List<NotificacionApp> get _recientes => _notificaciones
      .where((n) => n.grupo == GrupoNotificacionApp.reciente)
      .toList();

  List<NotificacionApp> get _anteriores => _notificaciones
      .where((n) => n.grupo == GrupoNotificacionApp.anterior)
      .toList();

  int get _cantidadNoLeidas => _notificaciones.where((n) => !n.leida).length;

  @override
  void initState() {
    super.initState();

    _translationService.addListener(_actualizarPantalla);
    _timeFormatService.addListener(_actualizarPantalla);
    _scrollController.addListener(_escucharScroll);

    _cargarDatos();
  }

  @override
  void dispose() {
    _translationService.removeListener(_actualizarPantalla);
    _timeFormatService.removeListener(_actualizarPantalla);
    _scrollController.removeListener(_escucharScroll);
    _scrollController.dispose();

    super.dispose();
  }

  void _actualizarPantalla() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  void _escucharScroll() {
    if (!_scrollController.hasClients) {
      return;
    }

    final double offset = _scrollController.offset;

    const double inicio = 45;
    const double fin = 145;

    final double progreso = ((offset - inicio) / (fin - inicio)).clamp(
      0.0,
      1.0,
    );

    if ((progreso - _progresoHeader).abs() < 0.01) {
      return;
    }

    setState(() {
      _progresoHeader = progreso;
    });
  }

  // =========================================================
  // CARGA
  // =========================================================

  Future<void> _cargarDatos({bool silencioso = false}) async {
    if (!silencioso && mounted) {
      setState(() {
        _cargando = true;
        _error = false;
      });
    }

    try {
      final usuario = _authService.usuarioActual;

      if (usuario == null) {
        if (mounted) {
          Navigator.of(context).maybePop();
        }

        return;
      }

      final List<dynamic> resultados = await Future.wait([
        _perfilService.obtenerPerfil(usuario.uid),
        _asignaturasService.obtenerTodas(),
        _tareasService.obtenerTodas(),
        _evaluacionesService.obtenerTodas(),
        _stateService.obtenerEstados(),
      ]);

      final PerfilUsuario? perfil = resultados[0] as PerfilUsuario?;

      final List<Asignatura> asignaturas = resultados[1] as List<Asignatura>;

      final List<Tarea> tareas = resultados[2] as List<Tarea>;

      final List<Evaluacion> evaluaciones = resultados[3] as List<Evaluacion>;

      final Map<String, EstadoNotificacionApp> estados =
          resultados[4] as Map<String, EstadoNotificacionApp>;

      final List<NotificacionApp> generadas = _feedService.generar(
        asignaturas: asignaturas,
        tareas: tareas,
        evaluaciones: evaluaciones,
        spanish: _espanol,
      );

      final List<NotificacionApp> aplicadas = _stateService.aplicarEstados(
        notificaciones: generadas,
        estados: estados,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _perfil = perfil;
        _asignaturas = asignaturas;
        _tareas = tareas;
        _evaluaciones = evaluaciones;
        _notificaciones = aplicadas;
        _error = false;
      });

      _programarAperturaPayloadInicial();
    } catch (_) {
      if (!mounted) {
        return;
      }

      if (!silencioso) {
        setState(() {
          _error = true;
        });
      }
    } finally {
      if (mounted && !silencioso) {
        setState(() {
          _cargando = false;
        });
      }
    }
  }

  Future<void> _refrescar() async {
    await _cargarDatos(silencioso: true);
  }

  // =========================================================
  // APERTURA DESDE NOTIFICACIÓN DEL SISTEMA
  // =========================================================

  void _programarAperturaPayloadInicial() {
    if (_initialPayloadProcessed) {
      return;
    }

    final String payload = widget.initialPayload?.trim() ?? '';

    _initialPayloadProcessed = true;

    if (payload.isEmpty) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _abrirPayloadSistema(payload);
    });
  }

  Future<void> _abrirPayloadSistema(String payload) async {
    final List<String> parts = payload.split('|');

    if (parts.length < 3 || parts[0] != 'academic') {
      _contenidoNoDisponible();
      return;
    }

    switch (parts[1]) {
      case 'task':
        final String taskId = parts[2];

        final Tarea? tarea = _buscarTarea(taskId);

        if (tarea == null) {
          _contenidoNoDisponible();
          return;
        }

        final NotificacionApp notificacion =
            _buscarNotificacionPorReferencia(
              TipoNotificacionApp.tarea,
              taskId,
            ) ??
            NotificacionApp(
              id: 'tarea-$taskId',
              tipo: TipoNotificacionApp.tarea,
              grupo: GrupoNotificacionApp.reciente,
              titulo: '',
              mensaje: '',
              fechaEvento: tarea.fechaEntrega ?? DateTime.now(),
              horaEvento: tarea.horaEntrega,
              referenciaId: taskId,
              asignaturaId: tarea.asignaturaId,
            );

        await _marcarComoLeida(notificacion);

        if (!mounted) {
          return;
        }

        await _abrirTarea(notificacion, tarea);
        return;

      case 'evaluation':
        final String evaluationId = parts[2];

        final Evaluacion? evaluacion = _buscarEvaluacion(evaluationId);

        if (evaluacion == null) {
          _contenidoNoDisponible();
          return;
        }

        final NotificacionApp notificacion =
            _buscarNotificacionPorReferencia(
              TipoNotificacionApp.evaluacion,
              evaluationId,
            ) ??
            NotificacionApp(
              id: 'evaluacion-$evaluationId',
              tipo: TipoNotificacionApp.evaluacion,
              grupo: GrupoNotificacionApp.reciente,
              titulo: '',
              mensaje: '',
              fechaEvento: evaluacion.fecha,
              horaEvento: evaluacion.hora,
              referenciaId: evaluationId,
              asignaturaId: evaluacion.asignaturaId,
            );

        await _marcarComoLeida(notificacion);

        if (!mounted) {
          return;
        }

        await _abrirEvaluacion(notificacion, evaluacion);
        return;

      case 'class':
        if (parts.length < 6) {
          _contenidoNoDisponible();
          return;
        }

        final String subjectId = parts[2];
        final DateTime? date = _parseAcademicDate(parts[3]);
        final int? blockIndex = int.tryParse(parts[4]);
        final String startTime = parts[5];

        if (date == null || blockIndex == null) {
          _contenidoNoDisponible();
          return;
        }

        final NotificacionApp notificacion =
            _buscarNotificacionClase(
              subjectId: subjectId,
              date: date,
              startTime: startTime,
            ) ??
            NotificacionApp(
              id:
                  'clase-$subjectId-'
                  '${_academicDateKey(date)}-$startTime',
              tipo: TipoNotificacionApp.clase,
              grupo: GrupoNotificacionApp.reciente,
              titulo: '',
              mensaje: '',
              fechaEvento: date,
              horaEvento: startTime,
              referenciaId: subjectId,
              asignaturaId: subjectId,
              bloqueIndex: blockIndex,
            );

        final _ClaseNotificacion? clase = _resolverClase(notificacion);

        if (clase == null) {
          _contenidoNoDisponible();
          return;
        }

        await _marcarComoLeida(notificacion);

        if (!mounted) {
          return;
        }

        await _abrirClase(notificacion, clase);
        return;

      default:
        _contenidoNoDisponible();
    }
  }

  NotificacionApp? _buscarNotificacionPorReferencia(
    TipoNotificacionApp tipo,
    String referenceId,
  ) {
    for (final NotificacionApp notification in _notificaciones) {
      if (notification.tipo == tipo &&
          notification.referenciaId == referenceId) {
        return notification;
      }
    }

    return null;
  }

  NotificacionApp? _buscarNotificacionClase({
    required String subjectId,
    required DateTime date,
    required String startTime,
  }) {
    for (final NotificacionApp notification in _notificaciones) {
      if (notification.tipo != TipoNotificacionApp.clase) {
        continue;
      }

      if (notification.asignaturaId != subjectId) {
        continue;
      }

      if (notification.horaEvento != startTime) {
        continue;
      }

      if (_academicDateKey(notification.fechaEvento) !=
          _academicDateKey(date)) {
        continue;
      }

      return notification;
    }

    return null;
  }

  DateTime? _parseAcademicDate(String value) {
    if (value.length != 8) {
      return null;
    }

    final int? year = int.tryParse(value.substring(0, 4));
    final int? month = int.tryParse(value.substring(4, 6));
    final int? day = int.tryParse(value.substring(6, 8));

    if (year == null || month == null || day == null) {
      return null;
    }

    return DateTime(year, month, day);
  }

  String _academicDateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
  }

  // =========================================================
  // ESTADOS
  // =========================================================

  Future<void> _marcarComoLeida(NotificacionApp notificacion) async {
    if (notificacion.leida) {
      return;
    }

    final int index = _notificaciones.indexWhere(
      (n) => n.id == notificacion.id,
    );

    if (index == -1) {
      return;
    }

    setState(() {
      _notificaciones[index] = notificacion.copyWith(leida: true);
    });

    try {
      await _stateService.marcarLeida(
        notificationId: notificacion.id,
        leida: true,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _notificaciones[index] = notificacion;
      });

      _mostrarEstado(
        mensaje: _espanol
            ? 'No pudimos actualizar la notificación.'
            : 'We could not update the notification.',
        tipo: AppStatusType.error,
      );
    }
  }

  Future<void> _alternarEstado(NotificacionApp notificacion) async {
    HapticFeedback.selectionClick();

    final int index = _notificaciones.indexWhere(
      (n) => n.id == notificacion.id,
    );

    if (index == -1) {
      return;
    }

    final NotificacionApp actualizada = notificacion.copyWith(
      leida: !notificacion.leida,
    );

    setState(() {
      _notificaciones[index] = actualizada;
    });

    try {
      await _stateService.marcarLeida(
        notificationId: notificacion.id,
        leida: actualizada.leida,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _notificaciones[index] = notificacion;
      });

      _mostrarEstado(
        mensaje: _espanol
            ? 'No pudimos cambiar el estado.'
            : 'We could not change the status.',
        tipo: AppStatusType.error,
      );
    }
  }

  Future<void> _marcarTodasComoLeidas() async {
    if (_cantidadNoLeidas == 0 || _procesandoTodas) {
      return;
    }

    HapticFeedback.mediumImpact();

    final List<NotificacionApp> anteriores = [..._notificaciones];

    setState(() {
      _procesandoTodas = true;
      _notificaciones = _notificaciones
          .map((n) => n.copyWith(leida: true))
          .toList();
    });

    try {
      await _stateService.marcarTodasComoLeidas(
        anteriores.where((n) => !n.leida).map((n) => n.id),
      );

      if (!mounted) {
        return;
      }

      _mostrarEstado(
        mensaje: _espanol
            ? 'Todas las notificaciones quedaron como leídas.'
            : 'All notifications were marked as read.',
        tipo: AppStatusType.success,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _notificaciones = anteriores;
      });

      _mostrarEstado(
        mensaje: _espanol
            ? 'No pudimos marcar todas como leídas.'
            : 'We could not mark all notifications as read.',
        tipo: AppStatusType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _procesandoTodas = false;
        });
      }
    }
  }

  Future<void> _eliminarNotificacion(NotificacionApp notificacion) async {
    HapticFeedback.mediumImpact();

    final bool confirmar = await _confirmarAccionPeligrosa(
      titulo: _espanol ? '¿Ocultar notificación?' : 'Hide notification?',
      mensaje: _espanol
          ? 'Esta notificación desaparecerá de tu bandeja. La tarea, evaluación o clase original no se eliminará.'
          : 'This notification will disappear from your inbox. The original task, evaluation or class will not be deleted.',
      textoAccion: _espanol ? 'Ocultar' : 'Hide',
      icono: Icons.visibility_off_outlined,
    );

    if (!confirmar || !mounted) {
      return;
    }

    final List<NotificacionApp> anteriores = [..._notificaciones];

    setState(() {
      _notificaciones.removeWhere((n) => n.id == notificacion.id);
    });

    try {
      await _stateService.ocultar(notificacion.id);

      if (!mounted) {
        return;
      }

      _mostrarEstado(
        mensaje: _espanol ? 'Notificación ocultada.' : 'Notification hidden.',
        tipo: AppStatusType.success,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _notificaciones = anteriores;
      });

      _mostrarEstado(
        mensaje: _espanol
            ? 'No pudimos ocultar la notificación.'
            : 'We could not hide the notification.',
        tipo: AppStatusType.error,
      );
    }
  }

  void _mostrarEstado({required String mensaje, required AppStatusType tipo}) {
    showAppStatusSnackBar(
      context,
      message: mensaje,
      type: tipo,
      bottomMargin: 92,
    );
  }

  // =========================================================
  // ABRIR CONTENIDO DE UNA NOTIFICACIÓN
  // =========================================================

  Future<void> _abrirNotificacion(NotificacionApp notificacion) async {
    HapticFeedback.selectionClick();

    await _marcarComoLeida(notificacion);

    if (!mounted) {
      return;
    }

    switch (notificacion.tipo) {
      case TipoNotificacionApp.tarea:
        final Tarea? tarea = _buscarTarea(notificacion.referenciaId);

        if (tarea == null) {
          _contenidoNoDisponible();
          return;
        }

        await _abrirTarea(notificacion, tarea);
        break;

      case TipoNotificacionApp.evaluacion:
        final Evaluacion? evaluacion = _buscarEvaluacion(
          notificacion.referenciaId,
        );

        if (evaluacion == null) {
          _contenidoNoDisponible();
          return;
        }

        await _abrirEvaluacion(notificacion, evaluacion);
        break;

      case TipoNotificacionApp.clase:
        final _ClaseNotificacion? clase = _resolverClase(notificacion);

        if (clase == null) {
          _contenidoNoDisponible();
          return;
        }

        await _abrirClase(notificacion, clase);
        break;

      case TipoNotificacionApp.recordatorio:
      case TipoNotificacionApp.sistema:
        break;
    }
  }

  void _contenidoNoDisponible() {
    _mostrarEstado(
      mensaje: _espanol
          ? 'Este contenido ya no está disponible.'
          : 'This content is no longer available.',
      tipo: AppStatusType.info,
    );
  }

  // =========================================================
  // TAREAS
  // =========================================================

  Tarea? _buscarTarea(String? id) {
    final String limpio = id?.trim() ?? '';

    if (limpio.isEmpty) {
      return null;
    }

    for (final Tarea tarea in _tareas) {
      if (tarea.id == limpio) {
        return tarea;
      }
    }

    return null;
  }

  String _nombreAsignaturaTarea(Tarea tarea) {
    final String id = tarea.asignaturaId?.trim() ?? '';

    if (id.isEmpty) {
      return _espanol ? 'Tarea general' : 'General task';
    }

    for (final Asignatura asignatura in _asignaturas) {
      if (asignatura.id == id) {
        return asignatura.nombre;
      }
    }

    return _espanol ? 'Asignatura no disponible' : 'Subject unavailable';
  }

  String _valorPrioridad(PrioridadTarea prioridad) {
    switch (prioridad) {
      case PrioridadTarea.baja:
        return _espanol ? 'Baja' : 'Low';
      case PrioridadTarea.media:
        return _espanol ? 'Media' : 'Medium';
      case PrioridadTarea.alta:
        return _espanol ? 'Alta' : 'High';
    }
  }

  String _textoEntregaTarea(Tarea tarea) {
    final DateTime? fecha = tarea.fechaEntrega;

    if (fecha == null) {
      return _espanol ? 'Sin fecha límite' : 'No due date';
    }

    final String fechaTexto = _espanol
        ? '${fecha.day.toString().padLeft(2, '0')}/'
              '${fecha.month.toString().padLeft(2, '0')}/'
              '${fecha.year}'
        : '${fecha.month.toString().padLeft(2, '0')}/'
              '${fecha.day.toString().padLeft(2, '0')}/'
              '${fecha.year}';

    final String hora = tarea.horaEntrega?.trim() ?? '';

    if (hora.isEmpty) {
      return fechaTexto;
    }

    return '$fechaTexto · '
        '${_timeFormatService.formatStoredTime(context, hora)}';
  }

  Future<void> _abrirTarea(NotificacionApp notificacion, Tarea tarea) async {
    final TaskDetailAction? action = await showTaskDetailSheet(
      context: context,
      task: tarea,
      subjectName: _nombreAsignaturaTarea(tarea),
      dueText: _textoEntregaTarea(tarea),
      priorityText: _valorPrioridad(tarea.prioridad),
      spanish: _espanol,
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case TaskDetailAction.edit:
        await _editarTarea(tarea);
        break;

      case TaskDetailAction.delete:
        await _eliminarTarea(notificacion, tarea);
        break;
    }
  }

  Future<void> _editarTarea(Tarea tarea) async {
    final TaskEditResult? result = await showTaskEditSheet(
      context: context,
      subjects: _asignaturas,
      spanish: _espanol,
      task: tarea,
    );

    if (!mounted || result == null) {
      return;
    }

    try {
      final Tarea actualizada = tarea.copyWith(
        titulo: result.title,
        descripcion: result.description,
        limpiarDescripcion: result.description == null,
        asignaturaId: result.subjectId,
        limpiarAsignatura: result.subjectId == null,
        prioridad: result.priority,
        fechaEntrega: result.dueDate,
        limpiarFechaEntrega: result.dueDate == null,
        horaEntrega: result.dueTime,
        limpiarHoraEntrega: result.dueTime == null,
      );

      await _tareasService.actualizar(actualizada);

      if (!mounted) {
        return;
      }

      await _cargarDatos(silencioso: true);

      if (!mounted) {
        return;
      }

      HapticFeedback.mediumImpact();

      _mostrarEstado(
        mensaje: _espanol ? 'Tarea actualizada.' : 'Task updated.',
        tipo: AppStatusType.success,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      HapticFeedback.heavyImpact();

      _mostrarEstado(
        mensaje: _espanol
            ? 'No pudimos actualizar la tarea.'
            : 'We could not update the task.',
        tipo: AppStatusType.error,
      );
    }
  }

  Future<void> _eliminarTarea(NotificacionApp notificacion, Tarea tarea) async {
    final bool confirmar = await _confirmarAccionPeligrosa(
      titulo: _espanol ? '¿Eliminar tarea?' : 'Delete task?',
      mensaje: _espanol
          ? '¿Seguro que quieres eliminar "${tarea.titulo}"? Esta acción no se puede deshacer.'
          : 'Are you sure you want to delete "${tarea.titulo}"? This action cannot be undone.',
      textoAccion: _espanol ? 'Eliminar' : 'Delete',
      icono: Icons.delete_outline_rounded,
    );

    if (!confirmar || !mounted) {
      return;
    }

    try {
      await _tareasService.eliminar(tarea.id);

      try {
        await _stateService.eliminarEstado(notificacion.id);
      } catch (_) {
        // El contenido académico ya fue eliminado.
        // Un estado huérfano no debe bloquear el flujo.
      }

      if (!mounted) {
        return;
      }

      await _cargarDatos(silencioso: true);

      if (!mounted) {
        return;
      }

      HapticFeedback.mediumImpact();

      _mostrarEstado(
        mensaje: _espanol ? 'Tarea eliminada.' : 'Task deleted.',
        tipo: AppStatusType.success,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      HapticFeedback.heavyImpact();

      _mostrarEstado(
        mensaje: _espanol
            ? 'No pudimos eliminar la tarea.'
            : 'We could not delete the task.',
        tipo: AppStatusType.error,
      );
    }
  }

  // =========================================================
  // EVALUACIONES
  // =========================================================

  Evaluacion? _buscarEvaluacion(String? id) {
    final String limpio = id?.trim() ?? '';

    if (limpio.isEmpty) {
      return null;
    }

    for (final Evaluacion evaluacion in _evaluaciones) {
      if (evaluacion.id == limpio) {
        return evaluacion;
      }
    }

    return null;
  }

  String _nombreAsignaturaEvaluacion(Evaluacion evaluacion) {
    for (final Asignatura asignatura in _asignaturas) {
      if (asignatura.id == evaluacion.asignaturaId) {
        return asignatura.nombre;
      }
    }

    return _espanol ? 'Asignatura no disponible' : 'Subject unavailable';
  }

  String _nombreTipoEvaluacion(TipoEvaluacion tipo) {
    if (_espanol) {
      switch (tipo) {
        case TipoEvaluacion.prueba:
          return 'Prueba';
        case TipoEvaluacion.examen:
          return 'Examen';
        case TipoEvaluacion.control:
          return 'Control';
        case TipoEvaluacion.quiz:
          return 'Quiz';
        case TipoEvaluacion.presentacion:
          return 'Presentación';
        case TipoEvaluacion.otro:
          return 'Otro';
      }
    }

    switch (tipo) {
      case TipoEvaluacion.prueba:
        return 'Test';
      case TipoEvaluacion.examen:
        return 'Exam';
      case TipoEvaluacion.control:
        return 'Assessment';
      case TipoEvaluacion.quiz:
        return 'Quiz';
      case TipoEvaluacion.presentacion:
        return 'Presentation';
      case TipoEvaluacion.otro:
        return 'Other';
    }
  }

  Future<void> _abrirEvaluacion(
    NotificacionApp notificacion,
    Evaluacion evaluacion,
  ) async {
    final EvaluationDetailAction? action = await showEvaluationDetailSheet(
      context: context,
      evaluation: evaluacion,
      subjectName: _nombreAsignaturaEvaluacion(evaluacion),
      typeName: _nombreTipoEvaluacion(evaluacion.tipo),
      spanish: _espanol,
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case EvaluationDetailAction.edit:
        await _editarEvaluacion(evaluacion);
        break;

      case EvaluationDetailAction.delete:
        await _eliminarEvaluacion(notificacion, evaluacion);
        break;
    }
  }

  Future<void> _editarEvaluacion(Evaluacion evaluacion) async {
    final EvaluationEditResult? result = await showEvaluationEditSheet(
      context: context,
      subjects: _asignaturas,
      spanish: _espanol,
      initialDate: evaluacion.fecha,
      evaluation: evaluacion,
    );

    if (!mounted || result == null) {
      return;
    }

    try {
      final Evaluacion actualizada = evaluacion.copyWith(
        titulo: result.title,
        asignaturaId: result.subjectId,
        tipo: result.type,
        fecha: result.date,
        hora: result.time,
        limpiarHora: result.time == null,
        descripcion: result.description,
        limpiarDescripcion: result.description == null,
        ponderacion: result.weight,
        limpiarPonderacion: result.weight == null,
      );

      await _evaluacionesService.actualizar(actualizada);

      if (!mounted) {
        return;
      }

      await _cargarDatos(silencioso: true);

      if (!mounted) {
        return;
      }

      HapticFeedback.mediumImpact();

      _mostrarEstado(
        mensaje: _espanol ? 'Evaluación actualizada.' : 'Evaluation updated.',
        tipo: AppStatusType.success,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      HapticFeedback.heavyImpact();

      _mostrarEstado(
        mensaje: _espanol
            ? 'No pudimos actualizar la evaluación.'
            : 'We could not update the evaluation.',
        tipo: AppStatusType.error,
      );
    }
  }

  Future<void> _eliminarEvaluacion(
    NotificacionApp notificacion,
    Evaluacion evaluacion,
  ) async {
    final bool confirmar = await _confirmarAccionPeligrosa(
      titulo: _espanol ? '¿Eliminar evaluación?' : 'Delete evaluation?',
      mensaje: _espanol
          ? '¿Seguro que quieres eliminar "${evaluacion.titulo}"? Esta acción no se puede deshacer.'
          : 'Are you sure you want to delete "${evaluacion.titulo}"? This action cannot be undone.',
      textoAccion: _espanol ? 'Eliminar' : 'Delete',
      icono: Icons.delete_outline_rounded,
    );

    if (!confirmar || !mounted) {
      return;
    }

    try {
      await _evaluacionesService.eliminar(evaluacion.id);

      try {
        await _stateService.eliminarEstado(notificacion.id);
      } catch (_) {
        // No bloqueamos la eliminación por
        // un estado de bandeja huérfano.
      }

      if (!mounted) {
        return;
      }

      await _cargarDatos(silencioso: true);

      if (!mounted) {
        return;
      }

      HapticFeedback.mediumImpact();

      _mostrarEstado(
        mensaje: _espanol ? 'Evaluación eliminada.' : 'Evaluation deleted.',
        tipo: AppStatusType.success,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      HapticFeedback.heavyImpact();

      _mostrarEstado(
        mensaje: _espanol
            ? 'No pudimos eliminar la evaluación.'
            : 'We could not delete the evaluation.',
        tipo: AppStatusType.error,
      );
    }
  }

  // =========================================================
  // CLASES
  // =========================================================

  _ClaseNotificacion? _resolverClase(NotificacionApp notificacion) {
    final String asignaturaId =
        (notificacion.asignaturaId ?? notificacion.referenciaId ?? '').trim();

    if (asignaturaId.isEmpty) {
      return null;
    }

    Asignatura? asignatura;

    for (final Asignatura item in _asignaturas) {
      if (item.id == asignaturaId) {
        asignatura = item;
        break;
      }
    }

    if (asignatura == null) {
      return null;
    }

    final int? indexGuardado = notificacion.bloqueIndex;

    if (indexGuardado != null &&
        indexGuardado >= 0 &&
        indexGuardado < asignatura.horario.length) {
      final BloqueHorario bloque = asignatura.horario[indexGuardado];

      if (notificacion.horaEvento == null ||
          bloque.horaInicio == notificacion.horaEvento) {
        return _ClaseNotificacion(
          asignatura: asignatura,
          bloque: bloque,
          blockIndex: indexGuardado,
        );
      }
    }

    final DiaSemana? dia = _diaSemanaModelo(notificacion.fechaEvento.weekday);

    for (int index = 0; index < asignatura.horario.length; index++) {
      final BloqueHorario bloque = asignatura.horario[index];

      if (dia != null && bloque.dia != dia) {
        continue;
      }

      if (notificacion.horaEvento != null &&
          bloque.horaInicio != notificacion.horaEvento) {
        continue;
      }

      return _ClaseNotificacion(
        asignatura: asignatura,
        bloque: bloque,
        blockIndex: index,
      );
    }

    return null;
  }

  DiaSemana? _diaSemanaModelo(int weekday) {
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

  Future<void> _abrirClase(
    NotificacionApp notificacion,
    _ClaseNotificacion clase,
  ) async {
    final CalendarClassDetailAction? action =
        await showCalendarClassDetailSheet(
          context: context,
          subject: clase.asignatura,
          block: clase.bloque,
          spanish: _espanol,
        );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case CalendarClassDetailAction.edit:
        await _editarClase(clase);
        break;

      case CalendarClassDetailAction.viewSubject:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SubjectDetailPage(subjectId: clase.asignatura.id),
          ),
        );

        if (!mounted) {
          return;
        }

        await _cargarDatos(silencioso: true);
        break;
    }
  }

  Future<void> _editarClase(_ClaseNotificacion clase) async {
    final BloqueHorario? editado = await showScheduleClassEditSheet(
      context: context,
      block: clase.bloque,
      spanish: _espanol,
      school: _esEscolar,
    );

    if (!mounted || editado == null) {
      return;
    }

    final List<ConflictoHorario> conflictos = _horarioConflictService
        .buscarConflictos(
          asignaturas: _asignaturas,
          asignaturaId: clase.asignatura.id,
          bloquePropuesto: editado,
          bloqueIndexIgnorar: clase.blockIndex,
        );

    if (conflictos.isNotEmpty) {
      final bool guardar = await _confirmarConflicto(
        asignatura: clase.asignatura,
        bloque: editado,
        conflictos: conflictos,
      );

      if (!mounted || !guardar) {
        return;
      }
    }

    if (clase.blockIndex < 0 ||
        clase.blockIndex >= clase.asignatura.horario.length) {
      return;
    }

    final Asignatura original = clase.asignatura;

    final List<BloqueHorario> horario = [...original.horario];

    horario[clase.blockIndex] = editado;

    horario.sort((a, b) {
      final int dia = _ordenDia(a.dia) - _ordenDia(b.dia);

      if (dia != 0) {
        return dia;
      }

      return a.horaInicio.compareTo(b.horaInicio);
    });

    final Asignatura actualizada = Asignatura(
      id: original.id,
      nombre: original.nombre,
      profesor: original.profesor,
      correoProfesor: original.correoProfesor,
      sala: original.sala,
      periodo: original.periodo,
      horario: horario,
      estado: original.estado,
      origen: original.origen,
      sigla: original.sigla,
      seccion: original.seccion,
      creditos: original.creditos,
      semestreMalla: original.semestreMalla,
      cursoNivel: original.cursoNivel,
      anioAcademico: original.anioAcademico,
      modalidad: original.modalidad,
      lugar: original.lugar,
      institucion: original.institucion,
      prerrequisitosIds: [...original.prerrequisitosIds],
      asignaturasSiguientesIds: [...original.asignaturasSiguientesIds],
    );

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (_) {
        return const PopScope(
          canPop: false,
          child: Center(child: CircularProgressIndicator(color: _primaryColor)),
        );
      },
    );

    try {
      await _asignaturasService.actualizar(actualizada);

      if (!mounted) {
        return;
      }

      Navigator.of(context, rootNavigator: true).pop();

      await _cargarDatos(silencioso: true);

      if (!mounted) {
        return;
      }

      HapticFeedback.mediumImpact();

      _mostrarEstado(
        mensaje: _espanol
            ? 'Clase actualizada correctamente.'
            : 'Class updated successfully.',
        tipo: AppStatusType.success,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      Navigator.of(context, rootNavigator: true).pop();

      HapticFeedback.heavyImpact();

      _mostrarEstado(
        mensaje: _espanol
            ? 'No pudimos actualizar la clase.'
            : 'We could not update the class.',
        tipo: AppStatusType.error,
      );
    }
  }

  int _ordenDia(DiaSemana dia) {
    switch (dia) {
      case DiaSemana.lunes:
        return 1;
      case DiaSemana.martes:
        return 2;
      case DiaSemana.miercoles:
        return 3;
      case DiaSemana.jueves:
        return 4;
      case DiaSemana.viernes:
        return 5;
      case DiaSemana.sabado:
        return 6;
    }
  }

  String _nombreDia(DiaSemana dia) {
    if (_espanol) {
      switch (dia) {
        case DiaSemana.lunes:
          return 'Lunes';
        case DiaSemana.martes:
          return 'Martes';
        case DiaSemana.miercoles:
          return 'Miércoles';
        case DiaSemana.jueves:
          return 'Jueves';
        case DiaSemana.viernes:
          return 'Viernes';
        case DiaSemana.sabado:
          return 'Sábado';
      }
    }

    switch (dia) {
      case DiaSemana.lunes:
        return 'Monday';
      case DiaSemana.martes:
        return 'Tuesday';
      case DiaSemana.miercoles:
        return 'Wednesday';
      case DiaSemana.jueves:
        return 'Thursday';
      case DiaSemana.viernes:
        return 'Friday';
      case DiaSemana.sabado:
        return 'Saturday';
    }
  }

  Future<bool> _confirmarConflicto({
    required Asignatura asignatura,
    required BloqueHorario bloque,
    required List<ConflictoHorario> conflictos,
  }) async {
    HapticFeedback.mediumImpact();

    final bool? resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (dialogContext) {
        final bool oscuro =
            Theme.of(dialogContext).brightness == Brightness.dark;

        return AlertDialog(
          backgroundColor: oscuro ? const Color(0xFF18181D) : Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
          contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 4),
          actionsPadding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: oscuro
                      ? const Color(0xFF35291D)
                      : const Color(0xFFFFF7E8),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFF59E0B),
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _espanol ? 'Conflicto de horario' : 'Schedule conflict',
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF111827),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _espanol
                    ? 'El horario que quieres guardar para "${asignatura.nombre}" se superpone con ${conflictos.length == 1 ? 'otra clase' : 'otras clases'}.'
                    : 'The schedule you want to save for "${asignatura.nombre}" overlaps with ${conflictos.length == 1 ? 'another class' : 'other classes'}.',
                style: TextStyle(
                  color: oscuro
                      ? const Color(0xFFB8BEC9)
                      : const Color(0xFF6B7280),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: oscuro
                      ? const Color(0xFF222229)
                      : const Color(0xFFFAFBFC),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: oscuro
                        ? const Color(0xFF34343C)
                        : const Color(0xFFE7EAF0),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.edit_calendar_outlined,
                      color: _primaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${_nombreDia(bloque.dia)} · '
                        '${_timeFormatService.formatStoredTime(context, bloque.horaInicio)} – '
                        '${_timeFormatService.formatStoredTime(context, bloque.horaFin)}',
                        style: TextStyle(
                          color: oscuro
                              ? const Color(0xFFF8FAFC)
                              : const Color(0xFF1F2937),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              for (final ConflictoHorario conflicto in conflictos) ...[
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: oscuro
                        ? const Color(0xFF2A2020)
                        : const Color(0xFFFFF5F5),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: oscuro
                          ? const Color(0xFF563030)
                          : const Color(0xFFFECACA),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        color: Color(0xFFEF4444),
                        size: 20,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              conflicto.asignatura.nombre,
                              style: TextStyle(
                                color: oscuro
                                    ? const Color(0xFFF8FAFC)
                                    : const Color(0xFF1F2937),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${_timeFormatService.formatStoredTime(context, conflicto.bloque.horaInicio)} – '
                              '${_timeFormatService.formatStoredTime(context, conflicto.bloque.horaFin)}',
                              style: const TextStyle(
                                color: Color(0xFFEF4444),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: Text(_espanol ? 'Volver y corregir' : 'Go back'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: const Color(0xFF1F1600),
              ),
              child: Text(
                _espanol ? 'Guardar de todos modos' : 'Save anyway',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );

    return resultado ?? false;
  }

  // =========================================================
  // CONFIRMACIÓN VISUAL REUTILIZABLE
  // =========================================================

  Future<bool> _confirmarAccionPeligrosa({
    required String titulo,
    required String mensaje,
    required String textoAccion,
    required IconData icono,
  }) async {
    HapticFeedback.mediumImpact();

    final bool? resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (dialogContext) {
        final bool oscuro =
            Theme.of(dialogContext).brightness == Brightness.dark;

        return AlertDialog(
          backgroundColor: oscuro ? const Color(0xFF18181D) : Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
          contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 4),
          actionsPadding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: oscuro
                      ? const Color(0xFF351F24)
                      : const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icono, color: const Color(0xFFEF4444), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF111827),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            mensaje,
            style: TextStyle(
              color: oscuro ? const Color(0xFFB8BEC9) : const Color(0xFF6B7280),
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: Text(_espanol ? 'Cancelar' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
              child: Text(
                textoAccion,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );

    return resultado ?? false;
  }

  // =========================================================
  // NAVEGACIÓN
  // =========================================================

  void _volverInicio() {
    HapticFeedback.selectionClick();
    MainNavigation.goTo(context, SeccionPrincipal.inicio);
  }

  void _volverArriba() {
    scrollMainSectionToTop(context, _scrollController);
  }

  void _abrirIA() {
    HapticFeedback.selectionClick();
    MainNavigation.goTo(context, SeccionPrincipal.ia);
  }

  void _abrirHorario() {
    HapticFeedback.selectionClick();
    MainNavigation.goTo(context, SeccionPrincipal.horario);
  }

  void _abrirCalendario() {
    HapticFeedback.selectionClick();
    MainNavigation.goTo(context, SeccionPrincipal.calendario);
  }

  // =========================================================
  // TEXTOS / COLORES
  // =========================================================

  Color _colorTipo(TipoNotificacionApp tipo) {
    switch (tipo) {
      case TipoNotificacionApp.tarea:
        return const Color(0xFFF59E0B);
      case TipoNotificacionApp.evaluacion:
        return const Color(0xFF8B5CF6);
      case TipoNotificacionApp.clase:
        return const Color(0xFF3B82F6);
      case TipoNotificacionApp.recordatorio:
        return const Color(0xFF059669);
      case TipoNotificacionApp.sistema:
        return _primaryColor;
    }
  }

  IconData _iconoTipo(TipoNotificacionApp tipo) {
    switch (tipo) {
      case TipoNotificacionApp.tarea:
        return Icons.description_outlined;
      case TipoNotificacionApp.evaluacion:
        return Icons.school_outlined;
      case TipoNotificacionApp.clase:
        return Icons.schedule_rounded;
      case TipoNotificacionApp.recordatorio:
        return Icons.alarm_rounded;
      case TipoNotificacionApp.sistema:
        return Ionicons.sparklesOutline;
    }
  }

  String _nombreTipo(TipoNotificacionApp tipo) {
    switch (tipo) {
      case TipoNotificacionApp.tarea:
        return _espanol ? 'TAREA' : 'TASK';
      case TipoNotificacionApp.evaluacion:
        return _espanol ? 'EVALUACIÓN' : 'EVALUATION';
      case TipoNotificacionApp.clase:
        return _espanol ? 'CLASE' : 'CLASS';
      case TipoNotificacionApp.recordatorio:
        return _espanol ? 'RECORDATORIO' : 'REMINDER';
      case TipoNotificacionApp.sistema:
        return 'EDUFLOW';
    }
  }

  String _fechaTexto(NotificacionApp notificacion) {
    final DateTime ahora = DateTime.now();
    final DateTime hoy = DateTime(ahora.year, ahora.month, ahora.day);

    final DateTime fecha = DateTime(
      notificacion.fechaEvento.year,
      notificacion.fechaEvento.month,
      notificacion.fechaEvento.day,
    );

    final int diferencia = fecha.difference(hoy).inDays;

    if (diferencia == 0) {
      return _espanol ? 'Hoy' : 'Today';
    }

    if (diferencia == 1) {
      return _espanol ? 'Mañana' : 'Tomorrow';
    }

    if (diferencia == -1) {
      return _espanol ? 'Ayer' : 'Yesterday';
    }

    if (_espanol) {
      return '${fecha.day.toString().padLeft(2, '0')}/'
          '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
    }

    return '${fecha.month.toString().padLeft(2, '0')}/'
        '${fecha.day.toString().padLeft(2, '0')}/${fecha.year}';
  }

  String _momentoTexto(NotificacionApp notificacion) {
    final String fecha = _fechaTexto(notificacion);

    final String hora = notificacion.horaEvento?.trim() ?? '';

    if (hora.isEmpty) {
      return fecha;
    }

    return '$fecha · '
        '${_timeFormatService.formatStoredTime(context, hora)}';
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final bool oscuro = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: RefreshIndicator(
                color: _primaryColor,
                onRefresh: _refrescar,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final double ancho = constraints.maxWidth;

                    final double horizontal = ancho <= 480
                        ? 7
                        : ancho <= 700
                        ? 14
                        : 28;

                    final double inferior = ancho <= 480 ? 110 : 145;

                    return ListView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        22,
                        horizontal,
                        inferior,
                      ),
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1100),
                            child: _buildHeader(oscuro),
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (_cargando)
                          _buildLoading()
                        else if (_error)
                          _buildError(oscuro)
                        else
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1100),
                              child: AppReveal(child: _buildContent(oscuro)),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AppScrollHeader(
              progress: _progresoHeader,
              title: _espanol ? 'Notificaciones' : 'Notifications',
              trailing: _buildCompactReadAllButton(oscuro),
            ),
          ),
          MainBottomNav(
            currentIndex: 4,
            onHome: _volverInicio,
            onSchedule: _abrirHorario,
            onAi: _abrirIA,
            onCalendar: _abrirCalendario,
            onNotifications: _volverArriba,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool oscuro) {
    return Transform.translate(
      offset: Offset(0, -10 * _progresoHeader),
      child: Opacity(
        opacity: 1 - _progresoHeader,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'EDUCFLOW AI',
                    style: TextStyle(
                      color: _primaryColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _espanol ? 'Notificaciones' : 'Notifications',
                    style: TextStyle(
                      color: oscuro
                          ? const Color(0xFFF8FAFC)
                          : const Color(0xFF111827),
                      fontSize: 31,
                      height: 1.08,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _espanol
                        ? 'Mantente al día con tus clases, tareas y evaluaciones.'
                        : 'Stay up to date with classes, tasks and evaluations.',
                    style: TextStyle(
                      color: oscuro
                          ? const Color(0xFFA9B1BF)
                          : const Color(0xFF6B7280),
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _buildReadAllButton(oscuro),
          ],
        ),
      ),
    );
  }

  Widget _buildReadAllButton(bool oscuro) {
    final bool habilitado = _cantidadNoLeidas > 0 && !_procesandoTodas;

    return AppPressable(
      scale: habilitado ? 0.9 : 1,
      child: GestureDetector(
        onTap: habilitado ? _marcarTodasComoLeidas : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: oscuro ? const Color(0xFF18181D) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: habilitado
                  ? (oscuro ? const Color(0xFF454667) : const Color(0xFFDADBFF))
                  : (oscuro
                        ? const Color(0xFF303038)
                        : const Color(0xFFE7EAF0)),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_procesandoTodas)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: _primaryColor,
                    strokeWidth: 2,
                  ),
                )
              else
                Icon(
                  Icons.done_all_rounded,
                  color: habilitado
                      ? _primaryColor
                      : (oscuro
                            ? const Color(0xFF666A74)
                            : const Color(0xFFAEB3BD)),
                  size: 20,
                ),
              const SizedBox(width: 7),
              Text(
                _espanol ? 'Marcar leídas' : 'Mark read',
                style: TextStyle(
                  color: habilitado
                      ? _primaryColor
                      : (oscuro
                            ? const Color(0xFF666A74)
                            : const Color(0xFFAEB3BD)),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactReadAllButton(bool oscuro) {
    final bool habilitado = _cantidadNoLeidas > 0 && !_procesandoTodas;

    return AppPressable(
      scale: habilitado ? 0.86 : 1,
      child: GestureDetector(
        onTap: habilitado ? _marcarTodasComoLeidas : null,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: oscuro ? const Color(0xFF222229) : const Color(0xFFFAFBFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: oscuro ? const Color(0xFF303038) : const Color(0xFFE7EAF0),
            ),
          ),
          child: _procesandoTodas
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    color: _primaryColor,
                    strokeWidth: 2,
                  ),
                )
              : Icon(
                  Icons.done_all_rounded,
                  color: habilitado
                      ? _primaryColor
                      : (oscuro
                            ? const Color(0xFF666A74)
                            : const Color(0xFFAEB3BD)),
                  size: 20,
                ),
        ),
      ),
    );
  }

  Widget _buildContent(bool oscuro) {
    return Column(
      children: [
        _buildSummary(oscuro),
        const SizedBox(height: 24),
        if (_notificaciones.isEmpty)
          _buildEmptyState(oscuro)
        else ...[
          if (_recientes.isNotEmpty)
            _buildSection(
              oscuro: oscuro,
              eyebrow: _espanol ? 'ACTIVIDAD' : 'ACTIVITY',
              title: _espanol ? 'Próximas' : 'Upcoming',
              notifications: _recientes,
            ),
          if (_recientes.isNotEmpty && _anteriores.isNotEmpty)
            const SizedBox(height: 25),
          if (_anteriores.isNotEmpty)
            _buildSection(
              oscuro: oscuro,
              eyebrow: _espanol ? 'HISTORIAL' : 'HISTORY',
              title: _espanol ? 'Anteriores' : 'Previous',
              notifications: _anteriores,
            ),
        ],
      ],
    );
  }

  Widget _buildSummary(bool oscuro) {
    final int pendientes = _cantidadNoLeidas;

    final String titulo = pendientes == 1
        ? (_espanol ? '1 notificación sin leer' : '1 unread notification')
        : (_espanol
              ? '$pendientes notificaciones sin leer'
              : '$pendientes unread notifications');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(19),
      decoration: _panelDecoration(
        oscuro,
        borderColor: oscuro ? const Color(0xFF34354E) : const Color(0xFFDADBFF),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: oscuro ? const Color(0xFF292936) : const Color(0xFFEEF0FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Ionicons.notificationsOutline,
              color: _primaryColor,
              size: 25,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _espanol ? 'ESTADO ACTUAL' : 'CURRENT STATUS',
                  style: const TextStyle(
                    color: _primaryColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  titulo,
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF111827),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _espanol
                      ? 'Aquí reunimos tu actividad académica más importante.'
                      : 'Your most important academic activity appears here.',
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFA9B1BF)
                        : const Color(0xFF6B7280),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required bool oscuro,
    required String eyebrow,
    required String title,
    required List<NotificacionApp> notifications,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow,
                    style: TextStyle(
                      color: oscuro
                          ? const Color(0xFF7F899A)
                          : const Color(0xFF6B7280),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: TextStyle(
                      color: oscuro
                          ? const Color(0xFFF8FAFC)
                          : const Color(0xFF111827),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              constraints: const BoxConstraints(minWidth: 30),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: oscuro
                    ? const Color(0xFF292936)
                    : const Color(0xFFECEEFC),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${notifications.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _primaryColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (int index = 0; index < notifications.length; index++) ...[
          _buildNotificationCard(notifications[index], oscuro),
          if (index != notifications.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildNotificationCard(NotificacionApp notificacion, bool oscuro) {
    final Color color = _colorTipo(notificacion.tipo);

    return AppPressable(
      scale: 0.99,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _abrirNotificacion(notificacion);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
          decoration: BoxDecoration(
            color: !notificacion.leida
                ? (oscuro ? const Color(0xFF1C1C24) : const Color(0xFFFCFCFF))
                : (oscuro ? const Color(0xFF18181D) : Colors.white),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: !notificacion.leida
                  ? (oscuro ? const Color(0xFF3B3C59) : const Color(0xFFD9DCFF))
                  : (oscuro
                        ? const Color(0xFF303038)
                        : const Color(0xFFE7EAF0)),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: oscuro ? 0.17 : 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _iconoTipo(notificacion.tipo),
                      color: color,
                      size: 21,
                    ),
                  ),
                  if (!notificacion.leida)
                    Positioned(
                      top: -2,
                      left: -2,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _primaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: oscuro
                                ? const Color(0xFF18181D)
                                : Colors.white,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          _nombreTipo(notificacion.tipo),
                          style: TextStyle(
                            color: color,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.65,
                          ),
                        ),
                        Text(
                          _momentoTexto(notificacion),
                          style: TextStyle(
                            color: oscuro
                                ? const Color(0xFF7F899A)
                                : const Color(0xFF9CA3AF),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notificacion.titulo,
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF1F2937),
                        fontSize: 14,
                        fontWeight: notificacion.leida
                            ? FontWeight.w700
                            : FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notificacion.mensaje,
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFA9B1BF)
                            : const Color(0xFF6B7280),
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Column(
                children: [
                  _buildSmallAction(
                    oscuro: oscuro,
                    icon: notificacion.leida
                        ? Icons.mark_email_unread_outlined
                        : Icons.drafts_outlined,
                    tooltip: notificacion.leida
                        ? (_espanol ? 'Marcar como no leída' : 'Mark as unread')
                        : (_espanol ? 'Marcar como leída' : 'Mark as read'),
                    onTap: () {
                      _alternarEstado(notificacion);
                    },
                  ),
                  const SizedBox(height: 4),
                  _buildSmallAction(
                    oscuro: oscuro,
                    icon: Icons.delete_outline_rounded,
                    tooltip: _espanol ? 'Ocultar' : 'Hide',
                    danger: true,
                    onTap: () {
                      _eliminarNotificacion(notificacion);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmallAction({
    required bool oscuro,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: AppPressable(
        scale: 0.82,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 35,
            height: 35,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: danger
                  ? const Color(0xFFEF4444)
                  : (oscuro
                        ? const Color(0xFF8E97A5)
                        : const Color(0xFF8B94A3)),
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool oscuro) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 48),
      decoration: _panelDecoration(oscuro),
      child: Column(
        children: [
          Container(
            width: 66,
            height: 66,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: oscuro ? const Color(0xFF1F3029) : const Color(0xFFE8F8F2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.done_all_rounded,
              color: Color(0xFF059669),
              size: 30,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _espanol ? 'Todo al día' : 'All caught up',
            style: TextStyle(
              color: oscuro ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _espanol
                ? 'No tienes notificaciones académicas relevantes por ahora.'
                : 'You have no relevant academic notifications right now.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: oscuro ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const SizedBox(
      height: 430,
      child: Center(
        child: CircularProgressIndicator(color: _primaryColor, strokeWidth: 3),
      ),
    );
  }

  Widget _buildError(bool oscuro) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: oscuro ? const Color(0xFF321D22) : const Color(0xFFFFF1F2),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626)),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  _espanol
                      ? 'No pudimos cargar las notificaciones. Desliza hacia abajo para intentarlo nuevamente.'
                      : 'We could not load notifications. Pull down to try again.',
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFFCA5A5)
                        : const Color(0xFF991B1B),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _panelDecoration(bool oscuro, {Color? borderColor}) {
    return BoxDecoration(
      color: oscuro ? const Color(0xFF18181D) : Colors.white,
      borderRadius: BorderRadius.circular(19),
      border: Border.all(
        color:
            borderColor ??
            (oscuro ? const Color(0xFF303038) : const Color(0xFFE7EAF0)),
      ),
      boxShadow: oscuro
          ? const []
          : const [
              BoxShadow(
                color: Color(0x0E0F172A),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
    );
  }
}

class _ClaseNotificacion {
  const _ClaseNotificacion({
    required this.asignatura,
    required this.bloque,
    required this.blockIndex,
  });

  final Asignatura asignatura;
  final BloqueHorario bloque;
  final int blockIndex;
}
