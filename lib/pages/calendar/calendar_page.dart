import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import '../../core/navigation/main_navigation.dart';

import '../../models/asignatura.dart';
import '../../models/evaluacion.dart';
import '../../models/tarea.dart';
import '../../services/asignaturas_service.dart';
import '../../services/evaluaciones_service.dart';
import '../../services/tareas_service.dart';
import '../../services/time_format_service.dart';
import '../../services/translation_service.dart';
import '../../widgets/app_pressable.dart';
import '../../widgets/app_reveal.dart';
import '../../widgets/app_scroll_header.dart';
import '../../widgets/main_bottom_nav.dart';
import '../../widgets/main_section_scroll.dart';
import '../tasks/widgets/task_edit_sheet.dart';
import 'widgets/calendar_add_sheet.dart';
import '../tasks/widgets/task_detail_sheet.dart';
import '../subjects/subject_detail_page.dart';
import 'widgets/calendar_class_detail_sheet.dart';
import 'widgets/evaluation_edit_sheet.dart';
import 'widgets/evaluation_detail_sheet.dart';
import '../../core/auth/auth_service.dart';
import '../../models/perfil_usuario.dart';
import '../../services/perfil_service.dart';
import '../../services/horario_conflict_service.dart';
import '../../widgets/app_status_snackbar.dart';

import '../schedule/widgets/schedule_class_edit_sheet.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({this.initialEvaluationId, super.key});

  final String? initialEvaluationId;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  static const Color _primaryColor = Color(0xFF5B5FEF);

  static const Color _classColor = Color(0xFF3B82F6);

  static const Color _evaluationColor = Color(0xFF8B5CF6);

  final AsignaturasService _asignaturasService = AsignaturasService.instance;

  final TareasService _tareasService = TareasService.instance;

  final EvaluacionesService _evaluacionesService = EvaluacionesService.instance;

  final TranslationService _translationService = TranslationService.instance;

  final TimeFormatService _timeFormatService = TimeFormatService.instance;

  final ScrollController _scrollController = ScrollController();

  final AuthService _authService = AuthService();

  final PerfilService _perfilService = PerfilService();

  final HorarioConflictService _horarioConflictService =
      HorarioConflictService.instance;

  PerfilUsuario? _perfil;

  List<Asignatura> _asignaturas = [];
  List<Tarea> _tareas = [];
  List<Evaluacion> _evaluaciones = [];

  bool _cargando = true;
  bool _error = false;
  bool _initialEvaluationHandled = false;

  bool _calendarioExpandido = false;

  bool get _esEscolar {
    final NivelEducativoPerfil nivel =
        _perfil?.nivelEducativo ?? NivelEducativoPerfil.vacio;

    return nivel == NivelEducativoPerfil.basica ||
        nivel == NivelEducativoPerfil.media;
  }

  double _progresoHeader = 0;

  late DateTime _hoy;
  late DateTime _fechaSeleccionada;
  late DateTime _mesVisible;

  bool get _espanol => _translationService.isSpanish;

  @override
  void initState() {
    super.initState();

    _hoy = _normalizarFecha(DateTime.now());

    _fechaSeleccionada = _hoy;

    _mesVisible = DateTime(_hoy.year, _hoy.month, 1);

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
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _perfil = resultados[0] as PerfilUsuario?;
        _asignaturas = resultados[1] as List<Asignatura>;
        _tareas = resultados[2] as List<Tarea>;
        _evaluaciones = resultados[3] as List<Evaluacion>;
        _error = false;
      });
      _scheduleInitialEvaluationDetail();
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

  void _scheduleInitialEvaluationDetail() {
    if (_initialEvaluationHandled) return;
    final Evaluacion? evaluation = findEvaluationForInitialDetail(
      _evaluaciones,
      widget.initialEvaluationId,
    );
    _initialEvaluationHandled = true;
    if (evaluation == null) return;
    setState(() => _fechaSeleccionada = evaluation.fecha);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _abrirEvaluacionCalendario(evaluation);
    });
  }

  Future<void> _refrescar() async {
    await _cargarDatos(silencioso: true);
  }

  // =========================================================
  // FECHAS
  // =========================================================

  DateTime _normalizarFecha(DateTime fecha) {
    return DateTime(fecha.year, fecha.month, fecha.day);
  }

  bool _mismaFecha(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime _inicioSemana(DateTime fecha) {
    final DateTime limpia = _normalizarFecha(fecha);

    return limpia.subtract(Duration(days: limpia.weekday - 1));
  }

  List<DateTime> get _diasSemanaVisible {
    final DateTime inicio = _inicioSemana(_fechaSeleccionada);

    return List<DateTime>.generate(
      7,
      (index) => inicio.add(Duration(days: index)),
    );
  }

  List<DateTime> get _diasMesVisible {
    final DateTime primerDia = DateTime(_mesVisible.year, _mesVisible.month, 1);

    final DateTime ultimoDia = DateTime(
      _mesVisible.year,
      _mesVisible.month + 1,
      0,
    );

    final DateTime primeraVisible = _inicioSemana(primerDia);

    final int diasHastaDomingo = 7 - ultimoDia.weekday;

    final DateTime ultimaVisible = ultimoDia.add(
      Duration(days: diasHastaDomingo),
    );

    final int total = ultimaVisible.difference(primeraVisible).inDays + 1;

    return List<DateTime>.generate(
      total,
      (index) => primeraVisible.add(Duration(days: index)),
    );
  }

  void _seleccionarFecha(DateTime fecha) {
    HapticFeedback.selectionClick();

    final DateTime limpia = _normalizarFecha(fecha);

    setState(() {
      _fechaSeleccionada = limpia;

      _mesVisible = DateTime(limpia.year, limpia.month, 1);
    });
  }

  void _irAHoy() {
    HapticFeedback.selectionClick();

    final DateTime ahora = _normalizarFecha(DateTime.now());

    setState(() {
      _hoy = ahora;
      _fechaSeleccionada = ahora;
      _mesVisible = DateTime(ahora.year, ahora.month, 1);
    });
  }

  void _cambiarMes(int diferencia) {
    HapticFeedback.selectionClick();

    final DateTime nuevoMes = DateTime(
      _mesVisible.year,
      _mesVisible.month + diferencia,
      1,
    );

    final int ultimoDia = DateTime(nuevoMes.year, nuevoMes.month + 1, 0).day;

    final int nuevoDia = _fechaSeleccionada.day > ultimoDia
        ? ultimoDia
        : _fechaSeleccionada.day;

    setState(() {
      _mesVisible = nuevoMes;

      _fechaSeleccionada = DateTime(nuevoMes.year, nuevoMes.month, nuevoDia);
    });
  }

  void _alternarExpansion() {
    HapticFeedback.selectionClick();

    setState(() {
      _calendarioExpandido = !_calendarioExpandido;
    });
  }

  // =========================================================
  // TEXTOS DE FECHA
  // =========================================================

  String get _nombreMes {
    const List<String> es = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];

    const List<String> en = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return (_espanol ? es : en)[_mesVisible.month - 1];
  }

  List<String> get _diasSemanaTexto {
    if (_espanol) {
      return const ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    }

    return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  }

  String _nombreDiaCompleto(int weekday) {
    if (_espanol) {
      switch (weekday) {
        case DateTime.monday:
          return 'Lunes';
        case DateTime.tuesday:
          return 'Martes';
        case DateTime.wednesday:
          return 'Miércoles';
        case DateTime.thursday:
          return 'Jueves';
        case DateTime.friday:
          return 'Viernes';
        case DateTime.saturday:
          return 'Sábado';
        case DateTime.sunday:
          return 'Domingo';
      }
    }

    switch (weekday) {
      case DateTime.monday:
        return 'Monday';
      case DateTime.tuesday:
        return 'Tuesday';
      case DateTime.wednesday:
        return 'Wednesday';
      case DateTime.thursday:
        return 'Thursday';
      case DateTime.friday:
        return 'Friday';
      case DateTime.saturday:
        return 'Saturday';
      case DateTime.sunday:
        return 'Sunday';
    }

    return '';
  }

  String _nombreMesFecha(int month) {
    const List<String> es = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];

    const List<String> en = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return (_espanol ? es : en)[month - 1];
  }

  String get _fechaSeleccionadaTexto {
    final DateTime fecha = _fechaSeleccionada;

    if (_espanol) {
      return '${_nombreDiaCompleto(fecha.weekday)} '
          '${fecha.day} de '
          '${_nombreMesFecha(fecha.month)}';
    }

    return '${_nombreDiaCompleto(fecha.weekday)}, '
        '${_nombreMesFecha(fecha.month)} '
        '${fecha.day}';
  }

  // =========================================================
  // CLASES / TAREAS DEL DÍA
  // =========================================================

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

  List<_CalendarItem> _elementosFecha(DateTime fecha) {
    final List<_CalendarItem> items = [];

    final DiaSemana? dia = _diaSemanaModelo(fecha.weekday);

    if (dia != null) {
      for (final Asignatura asignatura in _asignaturas) {
        for (
          int blockIndex = 0;
          blockIndex < asignatura.horario.length;
          blockIndex++
        ) {
          final BloqueHorario bloque = asignatura.horario[blockIndex];

          if (bloque.dia != dia) {
            continue;
          }

          final String salaBloque = bloque.sala?.trim() ?? '';

          final String salaAsignatura = asignatura.sala?.trim() ?? '';

          final String sala = salaBloque.isNotEmpty
              ? salaBloque
              : salaAsignatura;

          final String profesor = asignatura.profesor?.trim() ?? '';

          final List<String> detalles = [];

          if (profesor.isNotEmpty) {
            detalles.add(profesor);
          }

          if (sala.isNotEmpty) {
            detalles.add(sala);
          }

          items.add(
            _CalendarItem.clase(
              asignatura: asignatura,
              bloque: bloque,
              blockIndex: blockIndex,
              detalles: detalles.join(' · '),
            ),
          );
        }
      }
    }

    for (final Tarea tarea in _tareas) {
      final DateTime? entrega = tarea.fechaEntrega;

      if (entrega == null || !_mismaFecha(entrega, fecha)) {
        continue;
      }

      items.add(
        _CalendarItem.tarea(
          tarea: tarea,
          asignaturaNombre: _nombreAsignaturaTarea(tarea),
        ),
      );
    }

    for (final Evaluacion evaluacion in _evaluaciones) {
      if (!_mismaFecha(evaluacion.fecha, fecha)) {
        continue;
      }

      items.add(
        _CalendarItem.evaluacion(
          evaluacion: evaluacion,
          asignaturaNombre: _nombreAsignaturaEvaluacion(evaluacion),
        ),
      );
    }

    items.sort((a, b) => a.horaOrden.compareTo(b.horaOrden));

    return items;
  }

  String _nombreAsignaturaTarea(Tarea tarea) {
    final String? id = tarea.asignaturaId;

    if (id == null || id.trim().isEmpty) {
      return _espanol ? 'Tarea general' : 'General task';
    }

    for (final Asignatura asignatura in _asignaturas) {
      if (asignatura.id == id) {
        return asignatura.nombre;
      }
    }

    return _espanol ? 'Asignatura no disponible' : 'Subject unavailable';
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

  Color _colorPrioridad(PrioridadTarea prioridad) {
    switch (prioridad) {
      case PrioridadTarea.baja:
        return const Color(0xFF059669);

      case PrioridadTarea.media:
        return const Color(0xFFF59E0B);

      case PrioridadTarea.alta:
        return const Color(0xFFEF4444);
    }
  }

  String _nombrePrioridad(PrioridadTarea prioridad) {
    switch (prioridad) {
      case PrioridadTarea.baja:
        return _espanol ? 'Prioridad baja' : 'Low priority';

      case PrioridadTarea.media:
        return _espanol ? 'Prioridad media' : 'Medium priority';

      case PrioridadTarea.alta:
        return _espanol ? 'Prioridad alta' : 'High priority';
    }
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

  bool _tareaVencida(Tarea tarea) {
    if (tarea.completada) {
      return false;
    }

    final DateTime? fecha = tarea.fechaEntrega;

    if (fecha == null) {
      return false;
    }

    final DateTime ahora = DateTime.now();

    final DateTime hoy = DateTime(ahora.year, ahora.month, ahora.day);

    final DateTime entrega = DateTime(fecha.year, fecha.month, fecha.day);

    if (entrega.isBefore(hoy)) {
      return true;
    }

    if (entrega.isAfter(hoy)) {
      return false;
    }

    final String hora = tarea.horaEntrega?.trim() ?? '';

    if (hora.isEmpty) {
      return false;
    }

    final List<String> partes = hora.split(':');

    if (partes.length != 2) {
      return false;
    }

    final int? horaLimite = int.tryParse(partes[0]);

    final int? minutoLimite = int.tryParse(partes[1]);

    if (horaLimite == null || minutoLimite == null) {
      return false;
    }

    final DateTime limite = DateTime(
      ahora.year,
      ahora.month,
      ahora.day,
      horaLimite,
      minutoLimite,
    );

    // Se considera vencida recién
    // cuando termina el minuto indicado.
    final DateTime finDelMinuto = limite.add(const Duration(minutes: 1));

    return !ahora.isBefore(finDelMinuto);
  }

  String _estadoTemporalTarea(Tarea tarea) {
    if (tarea.completada) {
      return _espanol ? 'COMPLETADA' : 'COMPLETED';
    }

    if (_tareaVencida(tarea)) {
      return _espanol ? 'VENCIDA' : 'OVERDUE';
    }

    final DateTime? fecha = tarea.fechaEntrega;

    if (fecha == null) {
      return _espanol ? 'PENDIENTE' : 'PENDING';
    }

    final DateTime ahora = DateTime.now();

    final DateTime hoy = DateTime(ahora.year, ahora.month, ahora.day);

    final DateTime entrega = DateTime(fecha.year, fecha.month, fecha.day);

    final int diferencia = entrega.difference(hoy).inDays;

    if (diferencia == 0) {
      return _espanol ? 'VENCE HOY' : 'DUE TODAY';
    }

    if (diferencia == 1) {
      return _espanol ? 'VENCE MAÑANA' : 'DUE TOMORROW';
    }

    return _espanol ? 'PRÓXIMA' : 'UPCOMING';
  }

  Color _colorEstadoTemporalTarea(Tarea tarea) {
    if (tarea.completada) {
      return const Color(0xFF059669);
    }

    if (_tareaVencida(tarea)) {
      return const Color(0xFFEF4444);
    }

    final DateTime? fecha = tarea.fechaEntrega;

    if (fecha == null) {
      return _primaryColor;
    }

    final DateTime ahora = DateTime.now();

    final DateTime hoy = DateTime(ahora.year, ahora.month, ahora.day);

    final DateTime entrega = DateTime(fecha.year, fecha.month, fecha.day);

    final int diferencia = entrega.difference(hoy).inDays;

    if (diferencia == 0) {
      return const Color(0xFFF59E0B);
    }

    if (diferencia == 1) {
      return const Color(0xFF3B82F6);
    }

    return _primaryColor;
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
  // EDICIÓN DE CLASE DESDE CALENDARIO
  // =========================================================

  String _nombreDiaHorario(DiaSemana dia) {
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

  int _ordenDiaHorario(DiaSemana dia) {
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

  Future<bool> _confirmarConflictoCalendario({
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
              const SizedBox(height: 15),
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
                        '${_nombreDiaHorario(bloque.dia)} · '
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
              const SizedBox(height: 12),
              for (final ConflictoHorario conflicto in conflictos) ...[
                Container(
                  width: double.infinity,
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

  Future<void> _editarClaseCalendario(_CalendarItem item) async {
    final Asignatura? asignatura = item.asignatura;
    final BloqueHorario? bloque = item.bloque;
    final int? blockIndex = item.blockIndex;

    if (asignatura == null || bloque == null || blockIndex == null) {
      return;
    }

    final BloqueHorario? editado = await showScheduleClassEditSheet(
      context: context,
      block: bloque,
      spanish: _espanol,
      school: _esEscolar,
    );

    if (!mounted || editado == null) {
      return;
    }

    final List<ConflictoHorario> conflictos = _horarioConflictService
        .buscarConflictos(
          asignaturas: _asignaturas,
          asignaturaId: asignatura.id,
          bloquePropuesto: editado,
          bloqueIndexIgnorar: blockIndex,
        );

    if (conflictos.isNotEmpty) {
      final bool guardar = await _confirmarConflictoCalendario(
        asignatura: asignatura,
        bloque: editado,
        conflictos: conflictos,
      );

      if (!mounted || !guardar) {
        return;
      }
    }

    if (blockIndex < 0 || blockIndex >= asignatura.horario.length) {
      return;
    }

    final List<BloqueHorario> horario = [...asignatura.horario];
    horario[blockIndex] = editado;

    horario.sort((a, b) {
      final int diferenciaDia =
          _ordenDiaHorario(a.dia) - _ordenDiaHorario(b.dia);

      if (diferenciaDia != 0) {
        return diferenciaDia;
      }

      return a.horaInicio.compareTo(b.horaInicio);
    });

    final Asignatura actualizada = Asignatura(
      id: asignatura.id,
      nombre: asignatura.nombre,
      profesor: asignatura.profesor,
      correoProfesor: asignatura.correoProfesor,
      sala: asignatura.sala,
      periodo: asignatura.periodo,
      horario: horario,
      estado: asignatura.estado,
      origen: asignatura.origen,
      sigla: asignatura.sigla,
      seccion: asignatura.seccion,
      creditos: asignatura.creditos,
      semestreMalla: asignatura.semestreMalla,
      cursoNivel: asignatura.cursoNivel,
      anioAcademico: asignatura.anioAcademico,
      modalidad: asignatura.modalidad,
      lugar: asignatura.lugar,
      institucion: asignatura.institucion,
      prerrequisitosIds: [...asignatura.prerrequisitosIds],
      asignaturasSiguientesIds: [...asignatura.asignaturasSiguientesIds],
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

      // Mantiene al usuario dentro de la misma semana visual y
      // selecciona el nuevo día del bloque si fue modificado.
      final DateTime lunes = _inicioSemana(_fechaSeleccionada);
      final DateTime nuevaFecha = lunes.add(
        Duration(days: _ordenDiaHorario(editado.dia) - 1),
      );

      setState(() {
        _fechaSeleccionada = _normalizarFecha(nuevaFecha);
        _mesVisible = DateTime(nuevaFecha.year, nuevaFecha.month, 1);
      });

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

  // =========================================================
  // NAVEGACIÓN INFERIOR
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

  void _abrirNotificaciones() {
    HapticFeedback.selectionClick();
    MainNavigation.goTo(context, SeccionPrincipal.notificaciones);
  }

  Future<void> _abrirClaseCalendario(_CalendarItem item) async {
    final Asignatura? asignatura = item.asignatura;

    final BloqueHorario? bloque = item.bloque;

    if (asignatura == null || bloque == null) {
      return;
    }

    HapticFeedback.selectionClick();

    final CalendarClassDetailAction? action =
        await showCalendarClassDetailSheet(
          context: context,
          subject: asignatura,
          block: bloque,
          spanish: _espanol,
        );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case CalendarClassDetailAction.edit:
        await _editarClaseCalendario(item);
        break;

      case CalendarClassDetailAction.viewSubject:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SubjectDetailPage(subjectId: asignatura.id),
          ),
        );

        if (!mounted) {
          return;
        }

        await _cargarDatos(silencioso: true);
        break;
    }
  }

  Future<void> _agregarActividad() async {
    HapticFeedback.selectionClick();

    final CalendarAddAction? action = await showCalendarAddSheet(
      context: context,
      spanish: _espanol,
      selectedDate: _fechaSeleccionada,
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case CalendarAddAction.task:
        await _crearTareaEnFecha();
        break;

      case CalendarAddAction.evaluation:
        await _crearEvaluacionEnFecha();
        break;
    }
  }

  Future<void> _crearEvaluacionEnFecha() async {
    if (_asignaturas.isEmpty) {
      _mostrarEstado(
        mensaje: _espanol
            ? 'Primero debes tener al menos una asignatura registrada.'
            : 'You need at least one registered subject first.',
        tipo: AppStatusType.info,
      );

      return;
    }

    final EvaluationEditResult? result = await showEvaluationEditSheet(
      context: context,
      subjects: _asignaturas,
      spanish: _espanol,
      initialDate: _fechaSeleccionada,
    );

    if (!mounted || result == null) {
      return;
    }

    try {
      await _evaluacionesService.crear(
        titulo: result.title,
        asignaturaId: result.subjectId,
        fecha: result.date,
        tipo: result.type,
        descripcion: result.description,
        hora: result.time,
        ponderacion: result.weight,
      );

      if (!mounted) {
        return;
      }

      await _cargarDatos(silencioso: true);

      if (!mounted) {
        return;
      }

      setState(() {
        _fechaSeleccionada = _normalizarFecha(result.date);
        _mesVisible = DateTime(result.date.year, result.date.month, 1);
      });

      HapticFeedback.mediumImpact();

      _mostrarEstado(
        mensaje: _espanol
            ? 'Evaluación agregada al calendario.'
            : 'Evaluation added to calendar.',
        tipo: AppStatusType.success,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      HapticFeedback.heavyImpact();

      _mostrarEstado(
        mensaje: _espanol
            ? 'No pudimos crear la evaluación.'
            : 'We could not create the evaluation.',
        tipo: AppStatusType.error,
      );
    }
  }

  Future<void> _abrirEvaluacionCalendario(Evaluacion evaluacion) async {
    HapticFeedback.selectionClick();

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
        await _editarEvaluacionCalendario(evaluacion);
        break;

      case EvaluationDetailAction.delete:
        await _eliminarEvaluacionCalendario(evaluacion);
        break;
    }
  }

  Future<void> _editarEvaluacionCalendario(Evaluacion evaluacion) async {
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

      setState(() {
        _fechaSeleccionada = _normalizarFecha(result.date);
        _mesVisible = DateTime(result.date.year, result.date.month, 1);
      });

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

  Future<void> _eliminarEvaluacionCalendario(Evaluacion evaluacion) async {
    HapticFeedback.mediumImpact();

    final bool? confirmar = await showDialog<bool>(
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
          title: Text(
            _espanol ? '¿Eliminar evaluación?' : 'Delete evaluation?',
          ),
          content: Text(
            _espanol
                ? '¿Seguro que quieres eliminar "${evaluacion.titulo}"?\n\nEsta acción no se puede deshacer.'
                : 'Are you sure you want to delete "${evaluacion.titulo}"?\n\nThis action cannot be undone.',
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
              child: Text(_espanol ? 'Eliminar' : 'Delete'),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !mounted) {
      return;
    }

    try {
      await _evaluacionesService.eliminar(evaluacion.id);

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

  Future<void> _abrirTareaCalendario(Tarea tarea) async {
    HapticFeedback.selectionClick();

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
        await _editarTareaCalendario(tarea);
        break;

      case TaskDetailAction.delete:
        await _eliminarTareaCalendario(tarea);
        break;
    }
  }

  Future<void> _editarTareaCalendario(Tarea tarea) async {
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

      final DateTime? nuevaFecha = result.dueDate;

      if (nuevaFecha != null) {
        setState(() {
          _fechaSeleccionada = _normalizarFecha(nuevaFecha);

          _mesVisible = DateTime(nuevaFecha.year, nuevaFecha.month, 1);
        });
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

  Future<void> _eliminarTareaCalendario(Tarea tarea) async {
    HapticFeedback.mediumImpact();

    final bool? confirmar = await showDialog<bool>(
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
          title: Text(_espanol ? '¿Eliminar tarea?' : 'Delete task?'),
          content: Text(
            _espanol
                ? '¿Seguro que quieres eliminar "${tarea.titulo}"?\n\nEsta acción no se puede deshacer.'
                : 'Are you sure you want to delete "${tarea.titulo}"?\n\nThis action cannot be undone.',
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
              child: Text(_espanol ? 'Eliminar' : 'Delete'),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !mounted) {
      return;
    }

    try {
      await _tareasService.eliminar(tarea.id);

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

      _mostrarEstado(
        mensaje: _espanol
            ? 'No pudimos eliminar la tarea.'
            : 'We could not delete the task.',
        tipo: AppStatusType.error,
      );
    }
  }

  Future<void> _crearTareaEnFecha() async {
    final TaskEditResult? result = await showTaskEditSheet(
      context: context,
      subjects: _asignaturas,
      spanish: _espanol,

      // Aquí está la gracia:
      // el día seleccionado se carga solo.
      initialDueDate: _fechaSeleccionada,
    );

    if (!mounted || result == null) {
      return;
    }

    try {
      await _tareasService.crear(
        titulo: result.title,
        descripcion: result.description,
        asignaturaId: result.subjectId,
        prioridad: result.priority,
        fechaEntrega: result.dueDate,
        horaEntrega: result.dueTime,
      );

      if (!mounted) {
        return;
      }

      await _cargarDatos(silencioso: true);

      if (!mounted) {
        return;
      }

      // Si el usuario cambió la fecha dentro
      // del formulario, llevamos el calendario
      // directamente a esa nueva fecha.
      final DateTime? fechaCreada = result.dueDate;

      if (fechaCreada != null) {
        setState(() {
          _fechaSeleccionada = _normalizarFecha(fechaCreada);

          _mesVisible = DateTime(fechaCreada.year, fechaCreada.month, 1);
        });
      }

      HapticFeedback.mediumImpact();

      _mostrarEstado(
        mensaje: _espanol
            ? 'Tarea agregada al calendario.'
            : 'Task added to calendar.',
        tipo: AppStatusType.success,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      HapticFeedback.heavyImpact();

      _mostrarEstado(
        mensaje: _espanol
            ? 'No pudimos crear la tarea.'
            : 'We could not create the task.',
        tipo: AppStatusType.error,
      );
    }
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
                              child: AppReveal(
                                child: _buildContent(oscuro, ancho),
                              ),
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
              title: _espanol ? 'Calendario' : 'Calendar',
              trailing: _buildCompactAddButton(oscuro),
            ),
          ),

          MainBottomNav(
            currentIndex: 3,
            onHome: _volverInicio,
            onSchedule: _abrirHorario,
            onAi: _abrirIA,
            onCalendar: _volverArriba,
            onNotifications: _abrirNotificaciones,
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
                    _espanol ? 'Calendario' : 'Calendar',
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
                        ? 'Revisa tus clases y entregas en un solo lugar.'
                        : 'See your classes and assignments in one place.',
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

            AppPressable(
              scale: 0.88,
              child: GestureDetector(
                onTap: _agregarActividad,
                child: Container(
                  width: 50,
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _primaryColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: oscuro
                        ? const []
                        : const [
                            BoxShadow(
                              color: Color(0x385B5FEF),
                              blurRadius: 18,
                              offset: Offset(0, 7),
                            ),
                          ],
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: Colors.white,
                    size: 27,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactAddButton(bool oscuro) {
    return AppPressable(
      scale: 0.86,
      child: GestureDetector(
        onTap: _agregarActividad,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _primaryColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 21),
        ),
      ),
    );
  }

  Widget _buildContent(bool oscuro, double ancho) {
    final bool escritorio = ancho >= 900;

    if (escritorio) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 13, child: _buildCalendarCard(oscuro)),

          const SizedBox(width: 18),

          Expanded(flex: 8, child: _buildDayPanel(oscuro)),
        ],
      );
    }

    return Column(
      children: [
        _buildCalendarCard(oscuro),

        const SizedBox(height: 16),

        _buildDayPanel(oscuro),
      ],
    );
  }

  // =========================================================
  // CALENDARIO
  // =========================================================

  Widget _buildCalendarCard(bool oscuro) {
    final List<DateTime> dias = _calendarioExpandido
        ? _diasMesVisible
        : _diasSemanaVisible;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: _panelDecoration(oscuro),
      child: Column(
        children: [
          _buildMonthNavigation(oscuro),

          const SizedBox(height: 14),

          _buildWeekHeader(oscuro),

          const SizedBox(height: 5),

          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: GridView.builder(
                key: ValueKey(_calendarioExpandido),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: dias.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  crossAxisSpacing: 3,
                  mainAxisSpacing: 3,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  return _buildDay(dias[index], oscuro);
                },
              ),
            ),
          ),

          const SizedBox(height: 10),

          _buildExpandButton(oscuro),

          const SizedBox(height: 12),

          Divider(
            height: 1,
            color: oscuro ? const Color(0xFF303038) : const Color(0xFFE7EAF0),
          ),

          const SizedBox(height: 12),

          _buildLegend(oscuro),
        ],
      ),
    );
  }

  Widget _buildMonthNavigation(bool oscuro) {
    return Row(
      children: [
        _buildMonthArrow(
          oscuro: oscuro,
          icon: Icons.chevron_left_rounded,
          onTap: () {
            _cambiarMes(-1);
          },
        ),

        const SizedBox(width: 8),

        Expanded(
          child: Column(
            children: [
              Text(
                '$_nombreMes '
                '${_mesVisible.year}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: oscuro
                      ? const Color(0xFFF8FAFC)
                      : const Color(0xFF111827),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 6),

              GestureDetector(
                onTap: _irAHoy,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: oscuro
                        ? const Color(0xFF292936)
                        : const Color(0xFFEEF0FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _espanol ? 'Hoy' : 'Today',
                    style: const TextStyle(
                      color: _primaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 8),

        _buildMonthArrow(
          oscuro: oscuro,
          icon: Icons.chevron_right_rounded,
          onTap: () {
            _cambiarMes(1);
          },
        ),
      ],
    );
  }

  Widget _buildMonthArrow({
    required bool oscuro,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return AppPressable(
      scale: 0.86,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: oscuro ? const Color(0xFF222229) : const Color(0xFFFAFBFC),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: oscuro ? const Color(0xFF303038) : const Color(0xFFE7EAF0),
            ),
          ),
          child: Icon(
            icon,
            color: oscuro ? const Color(0xFFC4CAD4) : const Color(0xFF4B5563),
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildWeekHeader(bool oscuro) {
    return Row(
      children: [
        for (final String dia in _diasSemanaTexto)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text(
                dia.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: oscuro
                      ? const Color(0xFF7F899A)
                      : const Color(0xFF9CA3AF),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDay(DateTime fecha, bool oscuro) {
    final bool seleccionada = _mismaFecha(fecha, _fechaSeleccionada);

    final bool hoy = _mismaFecha(fecha, _hoy);

    final bool otroMes = fecha.month != _mesVisible.month;

    final List<_CalendarItem> items = _elementosFecha(fecha);

    return AppPressable(
      scale: 0.88,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _seleccionarFecha(fecha);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: seleccionada
                ? _primaryColor
                : otroMes
                ? Colors.transparent
                : oscuro
                ? const Color(0xFF222229)
                : const Color(0xFFFAFBFC),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: seleccionada
                  ? _primaryColor
                  : hoy
                  ? const Color(0xFF8B8FFF)
                  : Colors.transparent,
            ),
            boxShadow: seleccionada && !oscuro
                ? const [
                    BoxShadow(
                      color: Color(0x305B5FEF),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ]
                : const [],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${fecha.day}',
                  style: TextStyle(
                    color: seleccionada
                        ? Colors.white
                        : otroMes
                        ? (oscuro
                              ? const Color(0xFF505762)
                              : const Color(0xFFC4C8D0))
                        : hoy
                        ? _primaryColor
                        : (oscuro
                              ? const Color(0xFFE7EAF0)
                              : const Color(0xFF374151)),
                    fontSize: 12.5,
                    fontWeight: hoy || seleccionada
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                ),
              ),

              if (items.isNotEmpty)
                Positioned(
                  bottom: 5,
                  child: _buildDayDots(items, seleccionada),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayDots(List<_CalendarItem> items, bool selected) {
    final List<_CalendarItem> visibles = items.take(3).toList();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int index = 0; index < visibles.length; index++) ...[
          Container(
            width: 4.5,
            height: 4.5,
            decoration: BoxDecoration(
              color: _colorItem(visibles[index]),
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(color: Colors.white, width: 0.7)
                  : null,
            ),
          ),

          if (index != visibles.length - 1) const SizedBox(width: 2.5),
        ],
      ],
    );
  }

  Color _colorItem(_CalendarItem item) {
    switch (item.tipo) {
      case _CalendarItemType.clase:
        return _classColor;

      case _CalendarItemType.tarea:
        return _colorPrioridad(item.tarea!.prioridad);

      case _CalendarItemType.evaluacion:
        return _evaluationColor;
    }
  }

  Widget _buildExpandButton(bool oscuro) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _alternarExpansion,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _calendarioExpandido
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: _primaryColor,
              size: 20,
            ),

            const SizedBox(width: 5),

            Text(
              _calendarioExpandido
                  ? (_espanol ? 'Mostrar solo semana' : 'Show week only')
                  : (_espanol ? 'Ver mes completo' : 'View full month'),
              style: const TextStyle(
                color: _primaryColor,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend(bool oscuro) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        _legendItem(
          color: _classColor,
          text: _espanol ? 'Clase' : 'Class',
          oscuro: oscuro,
        ),
        _legendItem(
          color: _evaluationColor,
          text: _espanol ? 'Evaluación' : 'Evaluation',
          oscuro: oscuro,
        ),
        _legendItem(
          color: const Color(0xFF059669),
          text: _espanol ? 'Tarea baja' : 'Low',
          oscuro: oscuro,
        ),
        _legendItem(
          color: const Color(0xFFF59E0B),
          text: _espanol ? 'Tarea media' : 'Medium',
          oscuro: oscuro,
        ),
        _legendItem(
          color: const Color(0xFFEF4444),
          text: _espanol ? 'Tarea alta' : 'High',
          oscuro: oscuro,
        ),
      ],
    );
  }

  Widget _legendItem({
    required Color color,
    required String text,
    required bool oscuro,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),

        const SizedBox(width: 5),

        Text(
          text,
          style: TextStyle(
            color: oscuro ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }

  // =========================================================
  // PANEL DEL DÍA
  // =========================================================

  Widget _buildDayPanel(bool oscuro) {
    final List<_CalendarItem> items = _elementosFecha(_fechaSeleccionada);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: _panelDecoration(oscuro),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FECHA SELECCIONADA',
            style: TextStyle(
              color: _primaryColor,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            _fechaSeleccionadaTexto,
            style: TextStyle(
              color: oscuro ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 5),

          Text(
            items.length == 1
                ? (_espanol ? '1 actividad' : '1 activity')
                : (_espanol
                      ? '${items.length} actividades'
                      : '${items.length} activities'),
            style: TextStyle(
              color: oscuro ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
              fontSize: 12,
            ),
          ),

          const SizedBox(height: 18),

          if (items.isEmpty)
            _buildEmptyDay(oscuro)
          else
            Column(
              children: [
                for (int index = 0; index < items.length; index++) ...[
                  _buildEventCard(items[index], oscuro),

                  if (index != items.length - 1) const SizedBox(height: 9),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildEventCard(_CalendarItem item, bool oscuro) {
    final bool esClase = item.tipo == _CalendarItemType.clase;
    final bool esTarea = item.tipo == _CalendarItemType.tarea;
    final bool esEvaluacion = item.tipo == _CalendarItemType.evaluacion;

    final Color color = _colorItem(item);

    final String horaPrincipal = item.horaInicio == null
        ? (_espanol ? 'Todo el día' : 'All day')
        : _timeFormatService.formatStoredTime(context, item.horaInicio!);

    String? horaFin;

    if (item.horaFin != null) {
      horaFin = _timeFormatService.formatStoredTime(context, item.horaFin!);
    }

    final bool completada = item.tarea?.completada ?? false;

    return AppPressable(
      scale: 0.985,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (esClase) {
            _abrirClaseCalendario(item);
            return;
          }

          if (esEvaluacion) {
            _abrirEvaluacionCalendario(item.evaluacion!);
            return;
          }

          _abrirTareaCalendario(item.tarea!);
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: oscuro ? const Color(0xFF222229) : const Color(0xFFFAFBFC),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: oscuro ? const Color(0xFF303038) : const Color(0xFFE7EAF0),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 57,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      horaPrincipal,
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF1F2937),
                        fontSize: item.horaInicio == null ? 9.5 : 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    if (horaFin != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        horaFin,
                        style: TextStyle(
                          color: oscuro
                              ? const Color(0xFF8993A2)
                              : const Color(0xFF6B7280),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: oscuro ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  esClase
                      ? Ionicons.bookOutline
                      : esEvaluacion
                      ? Icons.school_outlined
                      : completada
                      ? Icons.task_alt_rounded
                      : Icons.description_outlined,
                  color: completada && esTarea
                      ? const Color(0xFF059669)
                      : color,
                  size: 20,
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (esClase)
                      Text(
                        _espanol ? 'CLASE' : 'CLASS',
                        style: const TextStyle(
                          color: _classColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                        ),
                      )
                    else if (esEvaluacion)
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 5,
                        runSpacing: 3,
                        children: [
                          Text(
                            _espanol ? 'EVALUACIÓN' : 'EVALUATION',
                            style: const TextStyle(
                              color: _evaluationColor,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                            ),
                          ),
                          Text(
                            '•',
                            style: TextStyle(
                              color: oscuro
                                  ? const Color(0xFF667080)
                                  : const Color(0xFF9CA3AF),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            _nombreTipoEvaluacion(item.evaluacion!.tipo)
                                .toUpperCase(),
                            style: const TextStyle(
                              color: _evaluationColor,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      )
                    else
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 5,
                        runSpacing: 3,
                        children: [
                          const Text(
                            'TAREA',
                            style: TextStyle(
                              color: _primaryColor,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                            ),
                          ),

                          Text(
                            '•',
                            style: TextStyle(
                              color: oscuro
                                  ? const Color(0xFF667080)
                                  : const Color(0xFF9CA3AF),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),

                          Text(
                            _estadoTemporalTarea(item.tarea!),
                            style: TextStyle(
                              color: _colorEstadoTemporalTarea(item.tarea!),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),

                    const SizedBox(height: 3),

                    Text(
                      item.titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF1F2937),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        decoration: completada
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),

                    if (item.detalles.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.detalles,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: oscuro
                              ? const Color(0xFFA9B1BF)
                              : const Color(0xFF6B7280),
                          fontSize: 10.5,
                        ),
                      ),
                    ],

                    if (esTarea) ...[
                      const SizedBox(height: 5),
                      Text(
                        completada
                            ? (_espanol ? 'Completada' : 'Completed')
                            : _nombrePrioridad(item.tarea!.prioridad),
                        style: TextStyle(
                          color: completada ? const Color(0xFF059669) : color,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ] else if (esEvaluacion) ...[
                      const SizedBox(height: 5),
                      Text(
                        item.evaluacion!.ponderacion == null
                            ? (_espanol
                                  ? 'Evaluación programada'
                                  : 'Scheduled evaluation')
                            : (_espanol
                                  ? 'Ponderación ${item.evaluacion!.ponderacion!.toStringAsFixed(item.evaluacion!.ponderacion! % 1 == 0 ? 0 : 1)}%'
                                  : 'Weight ${item.evaluacion!.ponderacion!.toStringAsFixed(item.evaluacion!.ponderacion! % 1 == 0 ? 0 : 1)}%'),
                        style: const TextStyle(
                          color: _evaluationColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyDay(bool oscuro) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: oscuro ? const Color(0xFF292936) : const Color(0xFFEEF0FF),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Ionicons.calendarClearOutline,
              color: _primaryColor,
              size: 27,
            ),
          ),

          const SizedBox(height: 14),

          Text(
            _espanol ? 'No hay actividades' : 'No activities',
            style: TextStyle(
              color: oscuro ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            _espanol
                ? 'Este día está libre por ahora.'
                : 'This day is free for now.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: oscuro ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
              fontSize: 12,
            ),
          ),

          const SizedBox(height: 16),

          FilledButton.icon(
            onPressed: _agregarActividad,
            style: FilledButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.add_rounded, size: 19),
            label: Text(_espanol ? 'Agregar' : 'Add'),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // ESTADOS
  // =========================================================

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
                      ? 'No pudimos cargar el calendario. Desliza hacia abajo para intentarlo nuevamente.'
                      : 'We could not load the calendar. Pull down to try again.',
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

  BoxDecoration _panelDecoration(bool oscuro) {
    return BoxDecoration(
      color: oscuro ? const Color(0xFF18181D) : Colors.white,
      borderRadius: BorderRadius.circular(19),
      border: Border.all(
        color: oscuro ? const Color(0xFF303038) : const Color(0xFFE7EAF0),
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

Evaluacion? findEvaluationForInitialDetail(
  List<Evaluacion> evaluations,
  String? evaluationId,
) {
  final String cleanId = evaluationId?.trim() ?? '';
  if (cleanId.isEmpty) return null;
  for (final Evaluacion evaluation in evaluations) {
    if (evaluation.id == cleanId) return evaluation;
  }
  return null;
}

// ===========================================================
// ITEM INTERNO DEL CALENDARIO
// ===========================================================

enum _CalendarItemType { clase, tarea, evaluacion }

class _CalendarItem {
  const _CalendarItem._({
    required this.tipo,
    required this.titulo,
    required this.detalles,
    required this.horaInicio,
    required this.horaFin,
    required this.horaOrden,
    this.asignatura,
    this.bloque,
    this.blockIndex,
    this.tarea,
    this.evaluacion,
  });

  factory _CalendarItem.clase({
    required Asignatura asignatura,
    required BloqueHorario bloque,
    required int blockIndex,
    required String detalles,
  }) {
    return _CalendarItem._(
      tipo: _CalendarItemType.clase,
      titulo: asignatura.nombre,
      detalles: detalles,
      horaInicio: bloque.horaInicio,
      horaFin: bloque.horaFin,
      horaOrden: bloque.horaInicio,
      asignatura: asignatura,
      bloque: bloque,
      blockIndex: blockIndex,
    );
  }

  factory _CalendarItem.tarea({
    required Tarea tarea,
    required String asignaturaNombre,
  }) {
    final String hora = tarea.horaEntrega?.trim() ?? '';

    return _CalendarItem._(
      tipo: _CalendarItemType.tarea,
      titulo: tarea.titulo,
      detalles: asignaturaNombre,
      horaInicio: hora.isEmpty ? null : hora,
      horaFin: null,

      // Las tareas sin hora quedan después
      // de los elementos con hora.
      horaOrden: hora.isEmpty ? '99:99' : hora,
      tarea: tarea,
    );
  }

  factory _CalendarItem.evaluacion({
    required Evaluacion evaluacion,
    required String asignaturaNombre,
  }) {
    final String hora = evaluacion.hora?.trim() ?? '';

    return _CalendarItem._(
      tipo: _CalendarItemType.evaluacion,
      titulo: evaluacion.titulo,
      detalles: asignaturaNombre,
      horaInicio: hora.isEmpty ? null : hora,
      horaFin: null,
      horaOrden: hora.isEmpty ? '99:98' : hora,
      evaluacion: evaluacion,
    );
  }

  final _CalendarItemType tipo;

  final String titulo;
  final String detalles;

  final String? horaInicio;
  final String? horaFin;

  final String horaOrden;

  final Asignatura? asignatura;
  final BloqueHorario? bloque;
  final int? blockIndex;
  final Tarea? tarea;
  final Evaluacion? evaluacion;
}
