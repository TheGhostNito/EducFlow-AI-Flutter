import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import '../../models/asignatura.dart';
import '../../models/evaluacion.dart';
import '../../models/nota.dart';
import '../../services/asignaturas_service.dart';
import '../../services/calculo_notas_service.dart';
import '../../services/evaluaciones_service.dart';
import '../../services/notas_service.dart';
import '../../services/time_format_service.dart';
import '../../services/translation_service.dart';
import '../../widgets/app_pressable.dart';
import '../../widgets/app_reveal.dart';
import '../../widgets/app_scroll_header.dart';
import '../../widgets/app_status_snackbar.dart';
import '../calendar/widgets/evaluation_detail_sheet.dart';
import '../calendar/widgets/evaluation_edit_sheet.dart';

enum EstadoTemporalEvaluacion { proxima, hoy, anterior }

EstadoTemporalEvaluacion estadoTemporalEvaluacion(
  Evaluacion evaluacion, {
  DateTime? ahora,
}) {
  final DateTime referencia = ahora ?? DateTime.now();
  final DateTime hoy = DateTime(
    referencia.year,
    referencia.month,
    referencia.day,
  );
  final DateTime fecha = DateTime(
    evaluacion.fecha.year,
    evaluacion.fecha.month,
    evaluacion.fecha.day,
  );

  if (fecha.isBefore(hoy)) return EstadoTemporalEvaluacion.anterior;
  if (fecha.isAtSameMomentAs(hoy)) return EstadoTemporalEvaluacion.hoy;
  return EstadoTemporalEvaluacion.proxima;
}

Evaluacion? findEvaluationForDetail(
  Iterable<Evaluacion> evaluaciones,
  String? evaluationId,
) {
  final String id = evaluationId?.trim() ?? '';
  if (id.isEmpty) return null;

  for (final Evaluacion evaluacion in evaluaciones) {
    if (evaluacion.id == id) return evaluacion;
  }
  return null;
}

List<Evaluacion> filterEvaluationsForSubject(
  Iterable<Evaluacion> evaluations,
  String? subjectId,
) {
  final String id = subjectId?.trim() ?? '';
  if (id.isEmpty) return List<Evaluacion>.of(evaluations);
  return evaluations.where((item) => item.asignaturaId == id).toList();
}

typedef EvaluationGradesLoader =
    Future<DatosCalificacionesEvaluaciones> Function();
typedef EvaluationGradeChanges = Stream<void> Function();

class EvaluationsPage extends StatefulWidget {
  const EvaluationsPage({
    this.initialEvaluationId,
    this.initialSubjectId,
    this.onBack,
    this.evaluacionesService,
    this.asignaturasService,
    this.gradesLoader,
    this.gradeChanges,
    super.key,
  });

  final String? initialEvaluationId;
  final String? initialSubjectId;
  final VoidCallback? onBack;
  final EvaluacionesService? evaluacionesService;
  final AsignaturasService? asignaturasService;
  final EvaluationGradesLoader? gradesLoader;
  final EvaluationGradeChanges? gradeChanges;

  @override
  State<EvaluationsPage> createState() => _EvaluationsPageState();
}

class _EvaluationsPageState extends State<EvaluationsPage> {
  static const Color _primaryColor = Color(0xFF8B5CF6);

  late final EvaluacionesService _evaluacionesService;
  late final AsignaturasService _asignaturasService;
  late final EvaluationGradesLoader _gradesLoader;
  late final EvaluationGradeChanges _gradeChanges;
  final CalculoNotasService _calculoNotasService = const CalculoNotasService();
  final TranslationService _translationService = TranslationService.instance;
  final TimeFormatService _timeFormatService = TimeFormatService.instance;
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<void>? _changesSubscription;
  StreamSubscription<void>? _gradeChangesSubscription;
  List<Evaluacion> _evaluaciones = const [];
  List<Asignatura> _asignaturas = const [];
  Map<String, CalificacionEvaluacion> _calificaciones = const {};
  ConfiguracionNotas _configuracionNotas = ConfiguracionNotas.predeterminada;
  bool _cargando = true;
  bool _error = false;
  bool _procesando = false;
  bool _initialDetailHandled = false;
  double _progresoHeader = 0;

  bool get _espanol => _translationService.isSpanish;

  String? get _subjectId {
    final String value = widget.initialSubjectId?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  List<Evaluacion> get _evaluacionesVisibles {
    return filterEvaluationsForSubject(_evaluaciones, _subjectId);
  }

  String? get _nombreAsignaturaContexto {
    final String? subjectId = _subjectId;
    if (subjectId == null) return null;
    for (final Asignatura subject in _asignaturas) {
      if (subject.id == subjectId) return subject.nombre;
    }
    return null;
  }

  List<Evaluacion> get _proximas => _evaluacionesVisibles
      .where(
        (item) =>
            estadoTemporalEvaluacion(item) == EstadoTemporalEvaluacion.proxima,
      )
      .toList();

  List<Evaluacion> get _deHoy => _evaluacionesVisibles
      .where(
        (item) =>
            estadoTemporalEvaluacion(item) == EstadoTemporalEvaluacion.hoy,
      )
      .toList();

  List<Evaluacion> get _anteriores => _evaluacionesVisibles
      .where(
        (item) =>
            estadoTemporalEvaluacion(item) == EstadoTemporalEvaluacion.anterior,
      )
      .toList()
      .reversed
      .toList();

  @override
  void initState() {
    super.initState();
    _evaluacionesService =
        widget.evaluacionesService ?? EvaluacionesService.instance;
    _asignaturasService =
        widget.asignaturasService ?? AsignaturasService.instance;
    _gradesLoader =
        widget.gradesLoader ??
        NotasService.instance.obtenerCalificacionesEvaluaciones;
    _gradeChanges =
        widget.gradeChanges ??
        (widget.gradesLoader == null
            ? NotasService.instance.observarCambiosCalificaciones
            : () => const Stream<void>.empty());
    _translationService.addListener(_actualizarPantalla);
    _timeFormatService.addListener(_actualizarPantalla);
    _scrollController.addListener(_escucharScroll);
    _cargarDatos();
    _observarCambios();
    _observarCambiosCalificaciones();
  }

  @override
  void dispose() {
    unawaited(_changesSubscription?.cancel());
    unawaited(_gradeChangesSubscription?.cancel());
    _translationService.removeListener(_actualizarPantalla);
    _timeFormatService.removeListener(_actualizarPantalla);
    _scrollController.removeListener(_escucharScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _actualizarPantalla() {
    if (mounted) setState(() {});
  }

  void _escucharScroll() {
    if (!_scrollController.hasClients) return;
    final double progreso = ((_scrollController.offset - 45) / 100).clamp(
      0.0,
      1.0,
    );
    if ((progreso - _progresoHeader).abs() < 0.01) return;
    setState(() => _progresoHeader = progreso);
  }

  void _observarCambios() {
    try {
      _changesSubscription = _evaluacionesService.observarCambios().listen(
        (_) => _cargarDatos(silencioso: true),
        onError: (_) {},
      );
    } catch (_) {
      // La carga manual sigue disponible si Realtime no puede iniciar.
    }
  }

  void _observarCambiosCalificaciones() {
    try {
      _gradeChangesSubscription = _gradeChanges().listen(
        (_) => _cargarDatos(silencioso: true),
        onError: (_) {},
      );
    } catch (_) {
      // El refresco manual sigue disponible si Realtime no puede iniciar.
    }
  }

  Future<void> _cargarDatos({bool silencioso = false}) async {
    if (!silencioso && mounted) {
      setState(() {
        _cargando = true;
        _error = false;
      });
    }

    try {
      final List<dynamic> resultados = await Future.wait([
        _evaluacionesService.obtenerTodas(),
        _asignaturasService.obtenerTodas(),
        _loadGradesSafely(),
      ]);
      if (!mounted) return;

      setState(() {
        _evaluaciones = resultados[0] as List<Evaluacion>;
        _asignaturas = resultados[1] as List<Asignatura>;
        final DatosCalificacionesEvaluaciones? grades =
            resultados[2] as DatosCalificacionesEvaluaciones?;
        _calificaciones = grades?.calificaciones ?? const {};
        _configuracionNotas =
            grades?.configuracion ?? ConfiguracionNotas.predeterminada;
        _error = false;
      });
      _programarDetalleInicial();
    } catch (_) {
      if (!mounted || silencioso) return;
      setState(() => _error = true);
    } finally {
      if (mounted && !silencioso) setState(() => _cargando = false);
    }
  }

  Future<DatosCalificacionesEvaluaciones?> _loadGradesSafely() async {
    try {
      return await _gradesLoader();
    } catch (_) {
      return null;
    }
  }

  void _programarDetalleInicial() {
    if (_initialDetailHandled) return;
    _initialDetailHandled = true;
    final Evaluacion? evaluacion = findEvaluationForDetail(
      _evaluaciones,
      widget.initialEvaluationId,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (evaluacion != null) {
        _abrirDetalle(evaluacion);
      } else if ((widget.initialEvaluationId?.trim() ?? '').isNotEmpty) {
        showAppStatusSnackBar(
          context,
          message: _espanol
              ? 'La evaluación seleccionada ya no está disponible.'
              : 'The selected evaluation is no longer available.',
          type: AppStatusType.info,
        );
      }
    });
  }

  Future<void> _refrescar() => _cargarDatos(silencioso: true);

  void _volver() {
    HapticFeedback.selectionClick();
    final VoidCallback? onBack = widget.onBack;
    if (onBack != null) {
      onBack();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _nuevaEvaluacion() async {
    if (_asignaturas.isEmpty) {
      showAppStatusSnackBar(
        context,
        message: _espanol
            ? 'Primero debes registrar al menos una asignatura.'
            : 'Register at least one subject first.',
        type: AppStatusType.info,
      );
      return;
    }

    HapticFeedback.selectionClick();
    final EvaluationEditResult? result = await showEvaluationEditSheet(
      context: context,
      subjects: _asignaturas,
      spanish: _espanol,
      initialDate: DateTime.now(),
      initialSubjectId: _subjectId,
    );
    if (!mounted || result == null) return;

    await _ejecutarOperacion(
      operacion: () => _evaluacionesService.crear(
        titulo: result.title,
        asignaturaId: result.subjectId,
        fecha: result.date,
        tipo: result.type,
        descripcion: result.description,
        hora: result.time,
        ponderacion: result.weight,
      ),
      exito: _espanol
          ? 'Evaluación creada correctamente.'
          : 'Evaluation created successfully.',
      error: _espanol
          ? 'No pudimos crear la evaluación.'
          : 'We could not create the evaluation.',
    );
  }

  Future<void> _abrirDetalle(Evaluacion evaluacion) async {
    HapticFeedback.selectionClick();
    final EvaluationDetailAction? action = await showEvaluationDetailSheet(
      context: context,
      evaluation: evaluacion,
      subjectName: _nombreAsignatura(evaluacion),
      typeName: _nombreTipo(evaluacion.tipo),
      spanish: _espanol,
      grade: _formattedGrade(evaluacion),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case EvaluationDetailAction.edit:
        await _editarEvaluacion(evaluacion);
      case EvaluationDetailAction.delete:
        await _solicitarEliminar(evaluacion);
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
    if (!mounted || result == null) return;

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

    await _ejecutarOperacion(
      operacion: () => _evaluacionesService.actualizar(actualizada),
      exito: _espanol
          ? 'Evaluación actualizada correctamente.'
          : 'Evaluation updated successfully.',
      error: _espanol
          ? 'No pudimos actualizar la evaluación.'
          : 'We could not update the evaluation.',
    );
  }

  Future<void> _solicitarEliminar(Evaluacion evaluacion) async {
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
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_espanol ? 'Cancelar' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
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
    if (!mounted || confirmar != true) return;

    setState(() => _procesando = true);
    try {
      await _evaluacionesService.eliminar(evaluacion.id);
      if (!mounted) return;
      await _cargarDatos(silencioso: true);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showAppStatusSnackBar(
        context,
        message: _espanol ? 'Evaluación eliminada.' : 'Evaluation deleted.',
      );
    } on EvaluacionConNotaException {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      showAppStatusSnackBar(
        context,
        message: _espanol
            ? 'No puedes eliminar esta evaluación porque tiene una nota asociada.'
            : 'This evaluation cannot be deleted because it has an associated grade.',
        type: AppStatusType.error,
      );
    } catch (_) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      showAppStatusSnackBar(
        context,
        message: _espanol
            ? 'No pudimos eliminar la evaluación.'
            : 'We could not delete the evaluation.',
        type: AppStatusType.error,
      );
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _ejecutarOperacion({
    required Future<Object?> Function() operacion,
    required String exito,
    required String error,
  }) async {
    setState(() => _procesando = true);
    try {
      await operacion();
      if (!mounted) return;
      await _cargarDatos(silencioso: true);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showAppStatusSnackBar(context, message: exito);
    } catch (_) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      showAppStatusSnackBar(context, message: error, type: AppStatusType.error);
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  String _nombreAsignatura(Evaluacion evaluacion) {
    for (final Asignatura asignatura in _asignaturas) {
      if (asignatura.id == evaluacion.asignaturaId) return asignatura.nombre;
    }
    return _espanol ? 'Asignatura no disponible' : 'Subject unavailable';
  }

  String _nombreTipo(TipoEvaluacion tipo) {
    return switch (tipo) {
      TipoEvaluacion.prueba => _espanol ? 'Prueba' : 'Test',
      TipoEvaluacion.examen => _espanol ? 'Examen' : 'Exam',
      TipoEvaluacion.control => _espanol ? 'Control' : 'Assessment',
      TipoEvaluacion.quiz => 'Quiz',
      TipoEvaluacion.presentacion => _espanol ? 'Presentación' : 'Presentation',
      TipoEvaluacion.otro => _espanol ? 'Otro' : 'Other',
    };
  }

  CalificacionEvaluacion? _gradeFor(Evaluacion evaluation) {
    return _calificaciones[evaluation.id];
  }

  String? _formattedGrade(Evaluacion evaluation) {
    final CalificacionEvaluacion? grade = _gradeFor(evaluation);
    if (grade == null) return null;
    return _calculoNotasService
        .redondear(grade.nota, _configuracionNotas)
        .toStringAsFixed(_configuracionNotas.decimales)
        .replaceAll('.', _espanol ? ',' : '.');
  }

  String _fecha(Evaluacion evaluacion) {
    final DateTime fecha = evaluacion.fecha;
    final String dia = fecha.day.toString().padLeft(2, '0');
    final String mes = fecha.month.toString().padLeft(2, '0');
    final String fechaTexto = _espanol
        ? '$dia/$mes/${fecha.year}'
        : '$mes/$dia/${fecha.year}';
    final String? hora = evaluacion.hora;
    if (hora == null || hora.trim().isEmpty) return fechaTexto;
    return '$fechaTexto · ${_timeFormatService.formatStoredTime(context, hora)}';
  }

  String _estado(EstadoTemporalEvaluacion estado) {
    return switch (estado) {
      EstadoTemporalEvaluacion.proxima => _espanol ? 'Próxima' : 'Upcoming',
      EstadoTemporalEvaluacion.hoy => _espanol ? 'Hoy' : 'Today',
      EstadoTemporalEvaluacion.anterior => _espanol ? 'Anterior' : 'Past',
    };
  }

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
                child: ListView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(10, 24, 10, 104),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: _buildHeader(oscuro),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: _buildContent(oscuro),
                      ),
                    ),
                  ],
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
              title: _espanol ? 'Evaluaciones' : 'Assessments',
              leading: _buildCompactBackButton(oscuro),
            ),
          ),
          if (_procesando)
            const Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Color(0x29000000),
                  child: Center(
                    child: CircularProgressIndicator(color: _primaryColor),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _cargando || _error || _procesando
          ? null
          : FloatingActionButton.extended(
              key: const Key('new-evaluation-button'),
              onPressed: _nuevaEvaluacion,
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                _espanol ? 'Nueva evaluación' : 'New assessment',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
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
            AppPressable(scale: 0.86, child: _buildBackButton(oscuro)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'EDUCFLOW AI',
                    style: TextStyle(
                      color: _primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _nombreAsignaturaContexto == null
                        ? (_espanol ? 'Mis evaluaciones' : 'My assessments')
                        : (_espanol
                              ? 'Evaluaciones de ${_nombreAsignaturaContexto!}'
                              : '${_nombreAsignaturaContexto!} assessments'),
                    style: TextStyle(
                      color: oscuro
                          ? const Color(0xFFF8FAFC)
                          : const Color(0xFF111827),
                      fontSize: 31,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _nombreAsignaturaContexto == null
                        ? (_espanol
                              ? 'Consulta y organiza las evaluaciones de tus asignaturas.'
                              : 'Review and organize assessments for your subjects.')
                        : (_espanol
                              ? 'Consulta y organiza las evaluaciones de esta asignatura.'
                              : 'Review and organize assessments for this subject.'),
                    style: TextStyle(
                      color: oscuro
                          ? const Color(0xFFA9B1BF)
                          : const Color(0xFF6B7280),
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackButton(bool oscuro) {
    return GestureDetector(
      onTap: _volver,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: oscuro ? const Color(0xFF18181D) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: oscuro ? const Color(0xFF303038) : const Color(0xFFE2E6ED),
          ),
        ),
        child: Icon(
          Ionicons.chevronBackOutline,
          color: oscuro ? const Color(0xFFE7EAF0) : const Color(0xFF374151),
          size: 21,
        ),
      ),
    );
  }

  Widget _buildCompactBackButton(bool oscuro) {
    return AppPressable(
      scale: 0.86,
      child: GestureDetector(
        onTap: _volver,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: oscuro ? const Color(0xFF222229) : const Color(0xFFF4F5F8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Ionicons.chevronBackOutline,
            color: oscuro ? const Color(0xFFE7EAF0) : const Color(0xFF374151),
            size: 19,
          ),
        ),
      ),
    );
  }

  Widget _buildContent(bool oscuro) {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Center(child: CircularProgressIndicator(color: _primaryColor)),
      );
    }
    if (_error) return _buildError(oscuro);
    if (_evaluacionesVisibles.isEmpty) return _buildEmpty(oscuro);

    return Column(
      children: [
        AppReveal(child: _buildSummary(oscuro)),
        const SizedBox(height: 20),
        if (_deHoy.isNotEmpty)
          AppReveal(
            delay: const Duration(milliseconds: 50),
            child: _buildGroup(
              oscuro: oscuro,
              title: _espanol ? 'Hoy' : 'Today',
              description: _espanol
                  ? 'Evaluaciones programadas para hoy'
                  : 'Assessments scheduled for today',
              evaluations: _deHoy,
            ),
          ),
        if (_deHoy.isNotEmpty && _proximas.isNotEmpty)
          const SizedBox(height: 20),
        if (_proximas.isNotEmpty)
          AppReveal(
            delay: const Duration(milliseconds: 90),
            child: _buildGroup(
              oscuro: oscuro,
              title: _espanol ? 'Próximas' : 'Upcoming',
              description: _espanol
                  ? 'Lo que viene en tu calendario'
                  : 'What is next on your calendar',
              evaluations: _proximas,
            ),
          ),
        if ((_deHoy.isNotEmpty || _proximas.isNotEmpty) &&
            _anteriores.isNotEmpty)
          const SizedBox(height: 20),
        if (_anteriores.isNotEmpty)
          AppReveal(
            delay: const Duration(milliseconds: 130),
            child: _buildGroup(
              oscuro: oscuro,
              title: _espanol ? 'Anteriores' : 'Past',
              description: _espanol
                  ? 'Historial de evaluaciones registradas'
                  : 'Previously registered assessments',
              evaluations: _anteriores,
            ),
          ),
      ],
    );
  }

  Widget _buildSummary(bool oscuro) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(oscuro),
      child: Row(
        children: [
          _summaryItem(
            oscuro: oscuro,
            value: '${_deHoy.length}',
            label: _espanol ? 'Hoy' : 'Today',
            icon: Icons.today_outlined,
          ),
          _divider(oscuro),
          _summaryItem(
            oscuro: oscuro,
            value: '${_proximas.length}',
            label: _espanol ? 'Próximas' : 'Upcoming',
            icon: Icons.upcoming_outlined,
          ),
          _divider(oscuro),
          _summaryItem(
            oscuro: oscuro,
            value: '${_anteriores.length}',
            label: _espanol ? 'Anteriores' : 'Past',
            icon: Icons.history_rounded,
          ),
        ],
      ),
    );
  }

  Widget _summaryItem({
    required bool oscuro,
    required String value,
    required String label,
    required IconData icon,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: _primaryColor, size: 21),
          const SizedBox(height: 7),
          Text(
            value,
            style: TextStyle(
              color: oscuro ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: oscuro ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(bool oscuro) => Container(
    width: 1,
    height: 52,
    color: oscuro ? const Color(0xFF303038) : const Color(0xFFE7EAF0),
  );

  Widget _buildGroup({
    required bool oscuro,
    required String title,
    required String description,
    required List<Evaluacion> evaluations,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFF8993A2)
                            : const Color(0xFF6B7280),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha: oscuro ? 0.18 : 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${evaluations.length}',
                  style: const TextStyle(
                    color: _primaryColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 11),
        for (int index = 0; index < evaluations.length; index++) ...[
          _buildEvaluationCard(evaluations[index], oscuro),
          if (index != evaluations.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildEvaluationCard(Evaluacion evaluacion, bool oscuro) {
    final EstadoTemporalEvaluacion estado = estadoTemporalEvaluacion(
      evaluacion,
    );
    final bool anterior = estado == EstadoTemporalEvaluacion.anterior;
    final String? grade = _formattedGrade(evaluacion);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('evaluation-card-${evaluacion.id}'),
        onTap: _procesando ? null : () => _abrirDetalle(evaluacion),
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(15),
          decoration: _panelDecoration(oscuro),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha: oscuro ? 0.18 : 0.1),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  anterior ? Icons.history_rounded : Icons.school_outlined,
                  color: _primaryColor,
                  size: 23,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            evaluacion.titulo,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: oscuro
                                  ? const Color(0xFFF8FAFC)
                                  : const Color(0xFF111827),
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _nombreAsignatura(evaluacion),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _primaryColor,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (grade != null) ...[
                      const SizedBox(height: 9),
                      Text(
                        '${_espanol ? 'Nota' : 'Grade'}: $grade',
                        key: ValueKey('evaluation-grade-${evaluacion.id}'),
                        style: TextStyle(
                          color: oscuro
                              ? const Color(0xFFF8FAFC)
                              : const Color(0xFF111827),
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 7,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _statusChip(estado, oscuro),
                        if (grade != null) _evaluatedChip(oscuro),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        _metadata(
                          oscuro,
                          Icons.calendar_today_outlined,
                          _fecha(evaluacion),
                        ),
                        _metadata(
                          oscuro,
                          Icons.category_outlined,
                          _nombreTipo(evaluacion.tipo),
                        ),
                        if (evaluacion.ponderacion != null)
                          _metadata(
                            oscuro,
                            Icons.percent_rounded,
                            _ponderacion(evaluacion.ponderacion!),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                color: oscuro
                    ? const Color(0xFF8993A2)
                    : const Color(0xFF9CA3AF),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(EstadoTemporalEvaluacion estado, bool oscuro) {
    final Color color = switch (estado) {
      EstadoTemporalEvaluacion.proxima => _primaryColor,
      EstadoTemporalEvaluacion.hoy => const Color(0xFF059669),
      EstadoTemporalEvaluacion.anterior => const Color(0xFF6B7280),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: oscuro ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _estado(estado),
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _evaluatedChip(bool oscuro) {
    const Color color = Color(0xFF059669);
    return Container(
      key: const ValueKey('evaluated-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: oscuro ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _espanol ? 'Evaluada' : 'Graded',
        style: const TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _metadata(bool oscuro, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: oscuro ? const Color(0xFF8993A2) : const Color(0xFF6B7280),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            color: oscuro ? const Color(0xFFB8BEC9) : const Color(0xFF6B7280),
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _ponderacion(double value) {
    final String formatted = value % 1 == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$formatted%';
  }

  Widget _buildEmpty(bool oscuro) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 44, 24, 42),
      decoration: _panelDecoration(oscuro),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _primaryColor.withValues(alpha: oscuro ? 0.18 : 0.1),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.school_outlined,
              color: _primaryColor,
              size: 34,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _espanol ? 'Aún no hay evaluaciones' : 'No assessments yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: oscuro ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _espanol
                ? 'Crea una evaluación aquí o desde el Calendario. Aparecerá en ambos lugares.'
                : 'Create an assessment here or from Calendar. It will appear in both places.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: oscuro ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _nuevaEvaluacion,
            style: FilledButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.add_rounded),
            label: Text(_espanol ? 'Crear evaluación' : 'Create assessment'),
          ),
        ],
      ),
    );
  }

  Widget _buildError(bool oscuro) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: _panelDecoration(oscuro),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            color: Color(0xFFEF4444),
            size: 38,
          ),
          const SizedBox(height: 13),
          Text(
            _espanol
                ? 'No pudimos cargar tus evaluaciones.'
                : 'We could not load your assessments.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: oscuro ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _cargarDatos,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(_espanol ? 'Reintentar' : 'Try again'),
          ),
        ],
      ),
    );
  }

  BoxDecoration _panelDecoration(bool oscuro) {
    return BoxDecoration(
      color: oscuro ? const Color(0xFF18181D) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: oscuro ? const Color(0xFF303038) : const Color(0xFFE7EAF0),
      ),
      boxShadow: oscuro
          ? const []
          : const [
              BoxShadow(
                color: Color(0x0D111827),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
    );
  }
}
