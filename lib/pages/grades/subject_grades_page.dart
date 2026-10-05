import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';

import '../../models/asignatura.dart';
import '../../models/evaluacion.dart';
import '../../models/nota.dart';
import '../../models/perfil_usuario.dart';
import '../../services/calculo_notas_service.dart';
import '../../services/grade_input_interpreter.dart';
import '../../services/notas_service.dart';
import '../../services/translation_service.dart';
import '../../widgets/app_pressable.dart';
import '../../widgets/app_scroll_header.dart';
import '../../widgets/app_status_snackbar.dart';
import 'widgets/grade_input_dialogs.dart';
import 'widgets/evaluation_grade_detail_sheet.dart';
import 'widgets/grade_scheme_dialog.dart';

class SubjectGradesPage extends StatefulWidget {
  const SubjectGradesPage({
    required this.asignatura,
    required this.evaluaciones,
    required this.datosNotas,
    this.notasService,
    super.key,
  });

  final Asignatura asignatura;
  final List<Evaluacion> evaluaciones;
  final DatosNotasUsuario datosNotas;
  final NotasService? notasService;

  @override
  State<SubjectGradesPage> createState() => _SubjectGradesPageState();
}

class _SubjectGradesPageState extends State<SubjectGradesPage> {
  static const Color _primaryColor = Color(0xFF5B5FEF);
  late final NotasService _notasService;
  final _calculoService = const CalculoNotasService();
  final _inputInterpreter = const GradeInputInterpreter();
  final _translationService = TranslationService.instance;
  final _scrollController = ScrollController();

  late List<Evaluacion> _evaluaciones;
  late Map<String, CalificacionEvaluacion> _calificaciones;
  late ConfiguracionNotas _configuracion;
  late ConfiguracionCalculoAsignatura _configuracionCalculo;
  late double _objetivo;
  final Map<String, double> _escenario = {};
  final Map<String, TextEditingController> _scenarioControllers = {};
  final Set<String> _guardando = {};
  double _progresoHeader = 0;

  bool get _espanol => _translationService.isSpanish;

  bool get _permiteEsquemaAvanzado =>
      widget.datosNotas.nivelEducativo == NivelEducativoPerfil.superior ||
      widget.datosNotas.nivelEducativo == NivelEducativoPerfil.tecnico;

  bool _esExamenFinal(Evaluacion evaluacion) =>
      _configuracionCalculo.usaExamenFinal &&
      _configuracionCalculo.evaluacionExamenId == evaluacion.id;

  @override
  void initState() {
    super.initState();
    _notasService = widget.notasService ?? NotasService.instance;
    _evaluaciones = List.of(widget.evaluaciones);
    _calificaciones = Map.of(widget.datosNotas.calificaciones);
    _configuracion = widget.datosNotas.configuracion;
    _configuracionCalculo =
        widget.datosNotas.configuracionesCalculo[widget.asignatura.id] ??
        ConfiguracionCalculoAsignatura.directa(widget.asignatura.id);
    _objetivo =
        widget.datosNotas.objetivos[widget.asignatura.id]?.notaObjetivo ??
        _configuracion.notaAprobacion;
    _translationService.addListener(_refrescarIdioma);
    _scrollController.addListener(_escucharScroll);
  }

  @override
  void dispose() {
    _translationService.removeListener(_refrescarIdioma);
    for (final controller in _scenarioControllers.values) {
      controller.dispose();
    }
    _scrollController
      ..removeListener(_escucharScroll)
      ..dispose();
    super.dispose();
  }

  void _refrescarIdioma() {
    if (mounted) setState(() {});
  }

  void _escucharScroll() {
    if (!_scrollController.hasClients) return;
    final progreso = ((_scrollController.offset - 45) / 100).clamp(0.0, 1.0);
    if ((progreso - _progresoHeader).abs() < 0.01) return;
    setState(() => _progresoHeader = progreso);
  }

  List<EntradaCalculoNota> _entradas({bool conEscenario = false}) {
    return _evaluaciones.map((evaluacion) {
      return EntradaCalculoNota(
        id: evaluacion.id,
        nombre: evaluacion.titulo,
        ponderacion: evaluacion.ponderacion,
        notaReal: _calificaciones[evaluacion.id]?.nota,
        notaHipotetica: conEscenario ? _escenario[evaluacion.id] : null,
      );
    }).toList();
  }

  ResultadoCalculoNotas get _resultado => _calculoService.calcular(
    evaluaciones: _entradas(),
    configuracion: _configuracion,
    objetivo: _objetivo,
    configuracionAsignatura: _configuracionCalculo,
  );

  ResultadoCalculoNotas get _resultadoEscenario => _calculoService.calcular(
    evaluaciones: _entradas(conEscenario: true),
    configuracion: _configuracion,
    objetivo: _objetivo,
    configuracionAsignatura: _configuracionCalculo,
  );

  String _numero(double? valor) {
    if (valor == null || !valor.isFinite) return '—';
    return _calculoService
        .redondear(valor, _configuracion)
        .toStringAsFixed(_configuracion.decimales)
        .replaceAll('.', _espanol ? ',' : '.');
  }

  String _porcentaje(double valor) {
    final decimales = valor % 1 == 0 ? 0 : 1;
    return '${valor.toStringAsFixed(decimales).replaceAll('.', _espanol ? ',' : '.')} %';
  }

  Future<void> _editarObjetivo() async {
    final nuevo = await showTargetGradeDialog(
      context: context,
      initialValue: _objetivo,
      configuration: _configuracion,
      spanish: _espanol,
      onSave: (value) async {
        await _notasService.guardarObjetivo(
          ObjetivoNotaAsignatura(
            asignaturaId: widget.asignatura.id,
            notaObjetivo: value,
          ),
          _configuracion,
        );
        if (mounted) setState(() => _objetivo = value);
      },
    );
    if (nuevo == null || !mounted) return;
    showAppStatusSnackBar(
      context,
      message: _espanol ? 'Objetivo actualizado.' : 'Goal updated.',
    );
  }

  Future<void> _editarEvaluacion(Evaluacion evaluacion) async {
    final grade = _calificaciones[evaluacion.id]?.nota;
    final otherWeight = _evaluaciones
        .where(
          (item) =>
              item.id != evaluacion.id &&
              (!_configuracionCalculo.usaExamenFinal || !_esExamenFinal(item)),
        )
        .fold<double>(0, (sum, item) => sum + (item.ponderacion ?? 0));
    final resultado = await showEvaluationGradeDialog(
      context: context,
      title: evaluacion.titulo,
      initialGrade: grade,
      initialWeight: evaluacion.ponderacion,
      otherWeight: otherWeight,
      configuration: _configuracion,
      spanish: _espanol,
      editWeight: !_esExamenFinal(evaluacion),
      onSave: (edicion) => _guardarEvaluacion(evaluacion, edicion),
    );
    if (resultado == null || !mounted) return;
    showAppStatusSnackBar(
      context,
      message: _espanol ? 'Evaluación actualizada.' : 'Assessment updated.',
    );
  }

  Future<void> _mostrarDetalleEvaluacion(Evaluacion evaluacion) async {
    final grade = _calificaciones[evaluacion.id]?.nota;
    final isExam = _esExamenFinal(evaluacion);
    final double? weight = isExam
        ? _configuracionCalculo.pesoExamen
        : evaluacion.ponderacion;
    final contribution = grade != null && weight != null
        ? grade * weight / 100
        : null;
    final edit = await showEvaluationGradeDetails(
      context: context,
      evaluacion: evaluacion,
      grade: grade == null
          ? (_espanol ? 'Pendiente' : 'Pending')
          : _numero(grade),
      weight: weight == null ? '—' : _porcentaje(weight),
      contribution: _numero(contribution),
      spanish: _espanol,
      isFinalExam: isExam,
    );
    if (edit && mounted) await _editarEvaluacion(evaluacion);
  }

  Future<void> _editarEsquemaCalculo() async {
    final result = await showGradeSchemeDialog(
      context: context,
      initial: _configuracionCalculo,
      evaluaciones: _evaluaciones,
      spanish: _espanol,
      onSave: _notasService.guardarConfiguracionCalculo,
    );
    if (result == null || !mounted) return;
    setState(() => _configuracionCalculo = result);
    showAppStatusSnackBar(
      context,
      message: _espanol
          ? 'Esquema académico actualizado.'
          : 'Academic scheme updated.',
    );
  }

  Future<void> _guardarEvaluacion(
    Evaluacion evaluacion,
    GradeEvaluationEdit edicion,
  ) async {
    setState(() => _guardando.add(evaluacion.id));
    try {
      final actualizada = evaluacion.copyWith(
        ponderacion: edicion.ponderacion,
        limpiarPonderacion: edicion.ponderacion == null,
      );
      if (edicion.ponderacion != evaluacion.ponderacion) {
        await _notasService.guardarPonderacion(
          evaluacion.id,
          edicion.ponderacion,
        );
      }
      if (edicion.nota == null) {
        await _notasService.eliminarCalificacion(evaluacion.id);
      } else {
        await _notasService.guardarCalificacion(
          CalificacionEvaluacion(
            evaluacionId: evaluacion.id,
            nota: edicion.nota!,
          ),
          _configuracion,
        );
      }
      if (!mounted) return;
      setState(() {
        final index = _evaluaciones.indexWhere(
          (item) => item.id == evaluacion.id,
        );
        if (index >= 0) _evaluaciones[index] = actualizada;
        if (edicion.nota == null) {
          _calificaciones.remove(evaluacion.id);
        } else {
          _calificaciones[evaluacion.id] = CalificacionEvaluacion(
            evaluacionId: evaluacion.id,
            nota: edicion.nota!,
          );
        }
        _escenario.remove(evaluacion.id);
        _scenarioControllers[evaluacion.id]?.clear();
      });
    } finally {
      if (mounted) setState(() => _guardando.remove(evaluacion.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                bottom: false,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontal = constraints.maxWidth <= 600
                        ? 12.0
                        : constraints.maxWidth <= 900
                        ? 24.0
                        : 40.0;
                    return ListView(
                      controller: _scrollController,
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        24,
                        horizontal,
                        60,
                      ),
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 860),
                            child: _header(oscuro),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 860),
                            child: Column(
                              children: [
                                _summary(oscuro),
                                const SizedBox(height: 14),
                                _alert(oscuro),
                                const SizedBox(height: 18),
                                _evaluations(oscuro),
                                const SizedBox(height: 18),
                                _scenario(oscuro),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AppScrollHeader(
                progress: _progresoHeader,
                title: widget.asignatura.nombre,
                leading: _backButton(oscuro, compact: true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(bool oscuro) {
    return Opacity(
      opacity: 1 - _progresoHeader,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppPressable(child: _backButton(oscuro)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _espanol ? 'DETALLE DE NOTAS' : 'GRADE DETAILS',
                  style: const TextStyle(
                    color: _primaryColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  widget.asignatura.nombre,
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF111827),
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  _espanol
                      ? 'Distingue notas reales, pendientes y escenarios antes de tomar decisiones.'
                      : 'Keep real grades, pending work, and scenarios clearly separated.',
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFA9B1BF)
                        : const Color(0xFF6B7280),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary(bool oscuro) {
    final resultado = _resultado;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(19),
      decoration: _panelDecoration(oscuro),
      child: Column(
        children: [
          if (_permiteEsquemaAvanzado) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    _configuracionCalculo.usaExamenFinal
                        ? (_espanol
                              ? 'Presentación + examen final'
                              : 'Coursework + final exam')
                        : (_espanol ? 'Cálculo directo' : 'Direct calculation'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('configure-grade-scheme'),
                  onPressed: _editarEsquemaCalculo,
                  icon: const Icon(Icons.account_tree_outlined, size: 18),
                  label: Text(_espanol ? 'Configurar' : 'Configure'),
                ),
              ],
            ),
            const Divider(height: 24),
          ],
          if (resultado.estaFinalizada) ...[
            _finalGradeSummary(oscuro, resultado),
            if (resultado.esquema ==
                EsquemaCalculoNotas.presentacionExamen) ...[
              const Divider(height: 28),
              Wrap(
                spacing: 28,
                runSpacing: 16,
                children: [
                  _summaryMetric(
                    oscuro,
                    _espanol
                        ? 'Presentación (${_porcentaje(resultado.pesoPresentacion)})'
                        : 'Coursework (${_porcentaje(resultado.pesoPresentacion)})',
                    _numero(resultado.notaPresentacion),
                  ),
                  _summaryMetric(
                    oscuro,
                    _espanol
                        ? 'Examen (${_porcentaje(resultado.pesoExamen)})'
                        : 'Exam (${_porcentaje(resultado.pesoExamen)})',
                    _numero(resultado.notaExamen),
                  ),
                  _summaryMetric(
                    oscuro,
                    _espanol
                        ? 'Aporte presentación'
                        : 'Coursework contribution',
                    _numero(resultado.aportePresentacion),
                  ),
                  _summaryMetric(
                    oscuro,
                    _espanol ? 'Aporte examen' : 'Exam contribution',
                    _numero(resultado.aporteExamen),
                  ),
                ],
              ),
            ],
          ] else if (resultado.esquema ==
              EsquemaCalculoNotas.presentacionExamen)
            Wrap(
              spacing: 28,
              runSpacing: 16,
              children: [
                _summaryMetric(
                  oscuro,
                  _espanol ? 'Promedio parcial' : 'Current average',
                  _numero(resultado.promedioParcial),
                ),
                _summaryMetric(
                  oscuro,
                  _espanol
                      ? 'Presentación (${_porcentaje(resultado.pesoPresentacion)})'
                      : 'Coursework (${_porcentaje(resultado.pesoPresentacion)})',
                  _numero(resultado.notaPresentacion),
                ),
                _summaryMetric(
                  oscuro,
                  _espanol
                      ? 'Examen (${_porcentaje(resultado.pesoExamen)})'
                      : 'Exam (${_porcentaje(resultado.pesoExamen)})',
                  _numero(resultado.notaExamen),
                ),
                _summaryMetric(
                  oscuro,
                  _espanol ? 'Nota final' : 'Final grade',
                  _numero(resultado.resultadoFinalProyectado),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: _summaryMetric(
                    oscuro,
                    _espanol ? 'Promedio parcial' : 'Current average',
                    _numero(resultado.promedioParcial),
                  ),
                ),
                Expanded(
                  child: _summaryMetric(
                    oscuro,
                    _espanol ? 'Aporte final' : 'Final contribution',
                    _numero(resultado.aporteAcumulado),
                  ),
                ),
                Expanded(
                  child: _summaryMetric(
                    oscuro,
                    _espanol ? 'Evaluado' : 'Assessed',
                    _porcentaje(resultado.pesoEvaluado),
                  ),
                ),
              ],
            ),
          const Divider(height: 30),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _espanol ? 'NOTA OBJETIVO' : 'TARGET GRADE',
                      style: const TextStyle(
                        color: _primaryColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _numero(_objetivo),
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF111827),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _editarObjetivo,
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: Text(_espanol ? 'Cambiar' : 'Change'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryMetric(bool oscuro, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: oscuro ? const Color(0xFF8993A2) : const Color(0xFF6B7280),
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: TextStyle(
            color: oscuro ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _finalGradeSummary(bool oscuro, ResultadoCalculoNotas resultado) {
    final color = resultado.estaAprobada
        ? const Color(0xFF059669)
        : const Color(0xFFDC2626);
    return Container(
      key: const ValueKey('subject-final-grade-summary'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: oscuro ? 0.13 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _espanol ? 'NOTA FINAL' : 'FINAL GRADE',
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _numero(resultado.resultadoFinalProyectado),
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF111827),
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              resultado.estaAprobada
                  ? (_espanol ? 'EVALUADO · APROBADO' : 'ASSESSED · PASSED')
                  : (_espanol ? 'EVALUADO · REPROBADO' : 'ASSESSED · FAILED'),
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _alert(bool oscuro) {
    final resultado = _resultado;
    final (icon, color, title, message) = _alertContent(resultado);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: color.withValues(alpha: oscuro ? 0.13 : 0.08),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 23),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFD7DCE4)
                        : const Color(0xFF4B5563),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color, String, String) _alertContent(
    ResultadoCalculoNotas resultado,
  ) {
    if (resultado.estadoPonderaciones != EstadoPonderacionesNotas.validas) {
      final restante = resultado.pesoSinDistribuir;
      return (
        Icons.tune_rounded,
        const Color(0xFFD97706),
        _espanol ? 'Completa las ponderaciones' : 'Complete the weights',
        resultado.estadoPonderaciones == EstadoPonderacionesNotas.excedidas
            ? (_espanol
                  ? 'Las ponderaciones superan el 100 %. Corrígelas antes de usar proyecciones.'
                  : 'Weights exceed 100%. Fix them before using projections.')
            : (_espanol
                  ? 'Falta distribuir ${_porcentaje(restante)}. El promedio parcial es informativo, pero una proyección final aún no es confiable.'
                  : '${_porcentaje(restante)} is still undistributed. The current average is informative, but the final projection is not reliable yet.'),
      );
    }
    if (resultado.estaFinalizada) {
      final objetivoAlcanzado =
          resultado.resultadoFinalProyectado! >=
          _objetivo - CalculoNotasService.tolerancia;
      final aprobado = resultado.estaAprobada;
      final color = aprobado
          ? const Color(0xFF059669)
          : const Color(0xFFDC2626);
      final estado = aprobado
          ? (_espanol ? 'Aprobado' : 'Passed')
          : (_espanol ? 'Reprobado' : 'Failed');
      final objetivo = objetivoAlcanzado
          ? (_espanol
                ? 'Objetivo personal alcanzado.'
                : 'Personal goal reached.')
          : (_espanol
                ? 'Objetivo personal no alcanzado.'
                : 'Personal goal not reached.');
      return (
        aprobado ? Icons.verified_rounded : Icons.cancel_rounded,
        color,
        _espanol ? 'Evaluado · $estado' : 'Assessed · $estado',
        _espanol
            ? 'Nota final ${_numero(resultado.resultadoFinalProyectado)}. $objetivo'
            : 'Final grade ${_numero(resultado.resultadoFinalProyectado)}. $objetivo',
      );
    }
    return switch (resultado.alerta) {
      AlertaAcademicaNota.objetivoAsegurado => (
        Icons.verified_rounded,
        const Color(0xFF059669),
        _espanol ? 'Objetivo asegurado' : 'Goal secured',
        _espanol
            ? 'Incluso con la nota mínima en lo restante, terminas con al menos ${_numero(resultado.minimoFinalPosible)}.'
            : 'Even with the minimum grade in the remaining work, you finish with at least ${_numero(resultado.minimoFinalPosible)}.',
      ),
      AlertaAcademicaNota.objetivoImposible => (
        Icons.block_rounded,
        const Color(0xFFDC2626),
        _espanol
            ? 'Objetivo matemáticamente imposible'
            : 'Goal is mathematically impossible',
        _espanol
            ? 'El mejor resultado final posible es ${_numero(resultado.maximoFinalPosible)}.'
            : 'The best possible final result is ${_numero(resultado.maximoFinalPosible)}.',
      ),
      AlertaAcademicaNota.objetivoExigente => (
        Icons.trending_up_rounded,
        const Color(0xFFD97706),
        _espanol
            ? 'Objetivo exigente, pero posible'
            : 'Demanding but possible goal',
        _requiredMessage(resultado),
      ),
      AlertaAcademicaNota.necesitaMejorar => (
        Icons.insights_rounded,
        const Color(0xFFD97706),
        _espanol ? 'Necesitas mejorar' : 'Improvement needed',
        _requiredMessage(resultado),
      ),
      AlertaAcademicaNota.sinCalificaciones => (
        Icons.hourglass_empty_rounded,
        _primaryColor,
        _espanol ? 'Aún no hay notas reales' : 'No real grades yet',
        _espanol
            ? 'Registra la primera calificación para comenzar el seguimiento.'
            : 'Add the first grade to start tracking performance.',
      ),
      _ => (
        Icons.check_circle_outline_rounded,
        const Color(0xFF059669),
        _espanol ? 'Rendimiento estable' : 'Stable performance',
        _requiredMessage(resultado),
      ),
    };
  }

  String _requiredMessage(ResultadoCalculoNotas resultado) {
    if (resultado.esquema == EsquemaCalculoNotas.presentacionExamen &&
        resultado.notaNecesariaExamen != null) {
      return _espanol
          ? 'Con presentación ${_numero(resultado.notaPresentacion)}, necesitas ${_numero(resultado.notaNecesariaExamen)} en el examen para llegar a ${_numero(_objetivo)}.'
          : 'With a ${_numero(resultado.notaPresentacion)} coursework grade, you need ${_numero(resultado.notaNecesariaExamen)} on the exam to reach ${_numero(_objetivo)}.';
    }
    if (resultado.esquema == EsquemaCalculoNotas.presentacionExamen &&
        resultado.promedioNecesarioPresentacion != null) {
      return _espanol
          ? 'Necesitas promediar ${_numero(resultado.promedioNecesarioPresentacion)} en las evaluaciones restantes para llegar al examen con presentación ${_numero(resultado.objetivoPresentacion)}.'
          : 'You need a ${_numero(resultado.promedioNecesarioPresentacion)} average in the remaining coursework to reach a ${_numero(resultado.objetivoPresentacion)} coursework grade.';
    }
    if (resultado.notaNecesariaUnica != null) {
      return _espanol
          ? 'Necesitas ${_numero(resultado.notaNecesariaUnica)} en la única evaluación pendiente para llegar a ${_numero(_objetivo)}.'
          : 'You need ${_numero(resultado.notaNecesariaUnica)} in the only pending assessment to reach ${_numero(_objetivo)}.';
    }
    final requerido = resultado.promedioNecesarioRestante;
    if (requerido != null) {
      return _espanol
          ? 'Necesitas promediar ${_numero(requerido)} en todo el peso restante para llegar a ${_numero(_objetivo)}.'
          : 'You need a ${_numero(requerido)} average across all remaining weight to reach ${_numero(_objetivo)}.';
    }
    return _espanol
        ? 'El cálculo se actualizará al completar las ponderaciones.'
        : 'The calculation will update when weights are complete.';
  }

  Widget _evaluations(bool oscuro) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _espanol ? 'EVALUACIONES' : 'ASSESSMENTS',
          style: const TextStyle(
            color: _primaryColor,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        if (_evaluaciones.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: _panelDecoration(oscuro),
            child: Column(
              children: [
                const Icon(
                  Ionicons.calendarOutline,
                  color: _primaryColor,
                  size: 34,
                ),
                const SizedBox(height: 10),
                Text(
                  _espanol
                      ? 'Crea evaluaciones desde Calendario para registrarlas aquí.'
                      : 'Create assessments in Calendar to track them here.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          for (int i = 0; i < _evaluaciones.length; i++) ...[
            _evaluationCard(_evaluaciones[i], oscuro),
            if (i != _evaluaciones.length - 1) const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _evaluationCard(Evaluacion evaluacion, bool oscuro) {
    final grade = _calificaciones[evaluacion.id]?.nota;
    final isExam = _esExamenFinal(evaluacion);
    final double? weight = isExam
        ? _configuracionCalculo.pesoExamen
        : evaluacion.ponderacion;
    final contribution = grade != null && weight != null
        ? grade * weight / 100
        : null;
    final saving = _guardando.contains(evaluacion.id);
    return AppPressable(
      child: InkWell(
        key: ValueKey('evaluation-grade-card-${evaluacion.id}'),
        onTap: saving ? null : () => _mostrarDetalleEvaluacion(evaluacion),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: _panelDecoration(oscuro, radius: 18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      evaluacion.titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF111827),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      children: [
                        _chip(
                          isExam
                              ? (_espanol ? 'Examen final' : 'Final exam')
                              : (_espanol
                                    ? 'Evaluación interna'
                                    : 'Coursework'),
                          isExam ? const Color(0xFFD97706) : _primaryColor,
                        ),
                        _chip(
                          weight == null
                              ? (_espanol ? 'Sin ponderación' : 'No weight')
                              : _porcentaje(weight),
                          const Color(0xFF7C3AED),
                        ),
                        if (contribution != null)
                          _chip(
                            '${_espanol ? 'Aporte' : 'Contribution'} ${_numero(contribution)}',
                            const Color(0xFF2563EB),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              if (saving)
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      grade == null ? '—' : _numero(grade),
                      key: ValueKey('evaluation-grade-value-${evaluacion.id}'),
                      style: TextStyle(
                        color: grade == null
                            ? (oscuro
                                  ? const Color(0xFF8993A2)
                                  : const Color(0xFF9CA3AF))
                            : _primaryColor,
                        fontSize: 30,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      grade == null
                          ? (_espanol ? 'Pendiente' : 'Pending')
                          : (_espanol ? 'Nota' : 'Grade'),
                      style: const TextStyle(fontSize: 10.5),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _scenario(bool oscuro) {
    final pending = _evaluaciones
        .where((item) => _calificaciones[item.id] == null)
        .toList();
    if (pending.isEmpty) return const SizedBox.shrink();
    final result = _resultadoEscenario;
    return Container(
      key: const ValueKey('grades-scenario-panel'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(oscuro),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.science_outlined, color: _primaryColor),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _espanol ? 'Escenario hipotético' : 'What-if scenario',
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF111827),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_escenario.isNotEmpty)
                TextButton(
                  onPressed: _descartarEscenario,
                  child: Text(_espanol ? 'Descartar' : 'Clear'),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            _espanol
                ? 'Estas notas no se guardan ni modifican tus datos oficiales.'
                : 'These grades are not saved and never change official data.',
            style: TextStyle(
              color: oscuro ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 15),
          for (final evaluation in pending) ...[
            _scenarioField(evaluation),
            const SizedBox(height: 9),
          ],
          if (_escenario.isNotEmpty) ...[
            const Divider(height: 25),
            Wrap(
              spacing: 22,
              runSpacing: 12,
              children: [
                _scenarioResult(
                  _espanol ? 'Promedio proyectado' : 'Projected average',
                  _numero(result.promedioParcial),
                  oscuro,
                ),
                _scenarioResult(
                  _espanol ? 'Aporte acumulado' : 'Accumulated contribution',
                  _numero(result.aporteAcumulado),
                  oscuro,
                ),
                _scenarioResult(
                  result.resultadoFinalProyectado != null
                      ? (_espanol ? 'Resultado final' : 'Final result')
                      : (_espanol
                            ? 'Mejor final posible'
                            : 'Best possible final'),
                  _numero(
                    result.resultadoFinalProyectado ??
                        result.maximoFinalPosible,
                  ),
                  oscuro,
                ),
                if (result.promedioNecesarioRestante != null)
                  _scenarioResult(
                    result.notaNecesariaUnica != null
                        ? (_espanol
                              ? 'Nota exacta restante'
                              : 'Exact remaining grade')
                        : (_espanol
                              ? 'Promedio aún necesario'
                              : 'Still-needed average'),
                    _numero(
                      result.notaNecesariaUnica ??
                          result.promedioNecesarioRestante,
                    ),
                    oscuro,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _scenarioField(Evaluacion evaluacion) {
    return Row(
      children: [
        Expanded(
          child: Text(
            evaluacion.titulo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 105,
          child: TextFormField(
            key: ValueKey('grade-scenario-input-${evaluacion.id}'),
            controller: _scenarioControllers.putIfAbsent(
              evaluacion.id,
              TextEditingController.new,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [DecimalTextInputFormatter(3)],
            onTapOutside: (_) {
              FocusManager.instance.primaryFocus?.unfocus();
            },
            decoration: InputDecoration(
              isDense: true,
              labelText: _espanol ? 'Hipótesis' : 'What if',
            ),
            onChanged: (text) {
              final interpretation = _inputInterpreter.interpretar(
                text,
                _configuracion,
              );
              final value = interpretation.valor;
              setState(() {
                if (!interpretation.esValida || value == null) {
                  _escenario.remove(evaluacion.id);
                } else {
                  _escenario[evaluacion.id] = value;
                }
              });
            },
          ),
        ),
      ],
    );
  }

  void _descartarEscenario() {
    FocusManager.instance.primaryFocus?.unfocus();
    for (final controller in _scenarioControllers.values) {
      controller.clear();
    }
    setState(_escenario.clear);
  }

  Widget _scenarioResult(String label, String value, bool oscuro) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: oscuro ? const Color(0xFF8993A2) : const Color(0xFF6B7280),
            fontSize: 10.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  Widget _backButton(bool oscuro, {bool compact = false}) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        width: compact ? 38 : 46,
        height: compact ? 38 : 46,
        decoration: BoxDecoration(
          color: oscuro ? const Color(0xFF191F29) : Colors.white,
          borderRadius: BorderRadius.circular(compact ? 12 : 15),
          border: Border.all(
            color: oscuro ? const Color(0xFF2B323E) : const Color(0xFFE2E6ED),
          ),
        ),
        child: Icon(Ionicons.chevronBackOutline, size: compact ? 19 : 21),
      ),
    );
  }

  BoxDecoration _panelDecoration(bool oscuro, {double radius = 20}) {
    return BoxDecoration(
      color: oscuro ? const Color(0xFF191F29) : Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: oscuro ? const Color(0xFF2B323E) : const Color(0xFFE7EAF0),
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
