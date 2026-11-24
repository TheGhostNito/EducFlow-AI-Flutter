import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';

import '../../models/asignatura.dart';
import '../../models/evaluacion.dart';
import '../../models/nota.dart';
import '../../services/calculo_notas_service.dart';
import '../../services/notas_service.dart';
import '../../services/translation_service.dart';
import '../../widgets/app_pressable.dart';
import '../../widgets/app_reveal.dart';
import '../../widgets/app_scroll_header.dart';
import '../../widgets/app_status_snackbar.dart';
import 'subject_grades_page.dart';
import 'widgets/grade_input_dialogs.dart';

class GradesPage extends StatefulWidget {
  const GradesPage({this.notasService, super.key});

  final NotasService? notasService;

  @override
  State<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends State<GradesPage> {
  static const Color _primaryColor = Color(0xFF5B5FEF);

  late final NotasService _notasService;
  final _calculoService = const CalculoNotasService();
  final _translationService = TranslationService.instance;
  final _scrollController = ScrollController();

  List<Asignatura> _asignaturas = const [];
  List<Evaluacion> _evaluaciones = const [];
  DatosNotasUsuario? _datosNotas;
  bool _cargando = true;
  bool _error = false;
  double _progresoHeader = 0;

  bool get _espanol => _translationService.isSpanish;

  @override
  void initState() {
    super.initState();
    _notasService = widget.notasService ?? NotasService.instance;
    _translationService.addListener(_actualizarIdioma);
    _scrollController.addListener(_escucharScroll);
    _cargar();
  }

  @override
  void dispose() {
    _translationService.removeListener(_actualizarIdioma);
    _scrollController
      ..removeListener(_escucharScroll)
      ..dispose();
    super.dispose();
  }

  void _actualizarIdioma() {
    if (mounted) setState(() {});
  }

  void _escucharScroll() {
    if (!_scrollController.hasClients) return;
    final progreso = ((_scrollController.offset - 45) / 100).clamp(0.0, 1.0);
    if ((progreso - _progresoHeader).abs() < 0.01) return;
    setState(() => _progresoHeader = progreso);
  }

  Future<void> _cargar({bool mostrarCarga = true}) async {
    if (mounted && mostrarCarga) {
      setState(() {
        _cargando = true;
        _error = false;
      });
    }
    try {
      final datos = await _notasService.obtenerDatos();
      if (!mounted) return;
      setState(() {
        _asignaturas = datos.asignaturas;
        _evaluaciones = datos.evaluaciones;
        _datosNotas = datos;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = _datosNotas == null;
      });
    }
  }

  List<Evaluacion> _evaluacionesDe(String asignaturaId) {
    return _evaluaciones
        .where((item) => item.asignaturaId == asignaturaId)
        .toList();
  }

  ResultadoCalculoNotas _resultado(Asignatura asignatura) {
    final datos = _datosNotas!;
    return _calculoService.calcular(
      evaluaciones: _evaluacionesDe(asignatura.id).map((evaluacion) {
        return EntradaCalculoNota(
          id: evaluacion.id,
          nombre: evaluacion.titulo,
          ponderacion: evaluacion.ponderacion,
          notaReal: datos.calificaciones[evaluacion.id]?.nota,
        );
      }).toList(),
      configuracion: datos.configuracion,
      objetivo:
          datos.objetivos[asignatura.id]?.notaObjetivo ??
          datos.configuracion.notaAprobacion,
      configuracionAsignatura:
          datos.configuracionesCalculo[asignatura.id] ??
          ConfiguracionCalculoAsignatura.directa(asignatura.id),
    );
  }

  String _numero(double? valor) {
    if (valor == null) return '—';
    final config = _datosNotas!.configuracion;
    return _calculoService
        .redondear(valor, config)
        .toStringAsFixed(config.decimales)
        .replaceAll('.', _espanol ? ',' : '.');
  }

  String _estado(ResultadoCalculoNotas resultado) {
    if (resultado.estadoPonderaciones != EstadoPonderacionesNotas.validas) {
      return _espanol ? 'Configuración incompleta' : 'Incomplete setup';
    }
    if (resultado.estaFinalizada) {
      return _espanol ? 'Evaluado' : 'Assessed';
    }
    return switch (resultado.alerta) {
      AlertaAcademicaNota.sinCalificaciones =>
        _espanol ? 'Aún sin notas' : 'No grades yet',
      AlertaAcademicaNota.objetivoAsegurado =>
        _espanol ? 'Objetivo asegurado' : 'Goal secured',
      AlertaAcademicaNota.objetivoImposible =>
        _espanol ? 'Objetivo no alcanzable' : 'Goal unreachable',
      AlertaAcademicaNota.objetivoExigente =>
        _espanol ? 'Objetivo exigente' : 'Demanding goal',
      AlertaAcademicaNota.necesitaMejorar =>
        _espanol ? 'Necesita mejorar' : 'Needs improvement',
      _ => _espanol ? 'Rendimiento estable' : 'Stable performance',
    };
  }

  Color _colorEstado(ResultadoCalculoNotas resultado) {
    if (resultado.estaFinalizada) {
      return resultado.estaAprobada
          ? const Color(0xFF059669)
          : const Color(0xFFDC2626);
    }
    return switch (resultado.alerta) {
      AlertaAcademicaNota.objetivoImposible => const Color(0xFFDC2626),
      AlertaAcademicaNota.objetivoExigente ||
      AlertaAcademicaNota.necesitaMejorar => const Color(0xFFD97706),
      AlertaAcademicaNota.objetivoAsegurado ||
      AlertaAcademicaNota.estable => const Color(0xFF059669),
      _ => _primaryColor,
    };
  }

  Future<void> _abrirDetalle(Asignatura asignatura) async {
    final datos = _datosNotas;
    if (datos == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SubjectGradesPage(
          asignatura: asignatura,
          evaluaciones: _evaluacionesDe(asignatura.id),
          datosNotas: datos,
          notasService: _notasService,
        ),
      ),
    );
    if (mounted) await _cargar(mostrarCarga: false);
  }

  Future<void> _editarConfiguracion() async {
    final actual = _datosNotas?.configuracion;
    if (actual == null) return;
    final nueva = await showGradeSettingsDialog(
      context: context,
      initial: actual,
      spanish: _espanol,
      onSave: _notasService.guardarConfiguracion,
    );
    if (nueva == null || !mounted) return;
    showAppStatusSnackBar(
      context,
      message: _espanol
          ? 'Configuración de notas guardada.'
          : 'Grade settings saved.',
    );
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: RefreshIndicator(
                color: _primaryColor,
                onRefresh: _cargar,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontal = constraints.maxWidth <= 600
                        ? 12.0
                        : constraints.maxWidth <= 900
                        ? 24.0
                        : 40.0;
                    return ListView(
                      key: const ValueKey('grades-subject-list'),
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        24,
                        horizontal,
                        60,
                      ),
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 820),
                            child: _header(oscuro),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 820),
                            child: _contenido(oscuro),
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
              title: _espanol ? 'Notas' : 'Grades',
              leading: _backButton(oscuro, compact: true),
              trailing: IconButton(
                tooltip: _espanol ? 'Configurar escala' : 'Configure scale',
                onPressed: _datosNotas == null ? null : _editarConfiguracion,
                icon: const Icon(Icons.tune_rounded),
              ),
            ),
          ),
        ],
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
                  _espanol ? 'Notas' : 'Grades',
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF111827),
                    fontSize: 32,
                    height: 1.08,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _espanol
                      ? 'Sigue tu rendimiento, proyecta escenarios y descubre qué necesitas para alcanzar tus objetivos.'
                      : 'Track performance, explore scenarios, and see what you need to reach your goals.',
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFA9B1BF)
                        : const Color(0xFF6B7280),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _espanol ? 'Configurar escala' : 'Configure scale',
            onPressed: _datosNotas == null ? null : _editarConfiguracion,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
    );
  }

  Widget _contenido(bool oscuro) {
    if (_cargando) {
      return const SizedBox(
        height: 320,
        child: Center(child: CircularProgressIndicator(color: _primaryColor)),
      );
    }
    if (_error) return _errorCard(oscuro);
    if (_asignaturas.isEmpty) return _emptyCard(oscuro);
    return Column(
      children: [
        for (int i = 0; i < _asignaturas.length; i++) ...[
          AppReveal(child: _subjectCard(_asignaturas[i], oscuro)),
          if (i != _asignaturas.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _subjectCard(Asignatura asignatura, bool oscuro) {
    final resultado = _resultado(asignatura);
    final evaluaciones = _evaluacionesDe(asignatura.id);
    final color = _colorEstado(resultado);
    final necesario = resultado.promedioNecesarioRestante;
    final objetivo =
        _datosNotas!.objetivos[asignatura.id]?.notaObjetivo ??
        _datosNotas!.configuracion.notaAprobacion;
    final notaFinal = resultado.resultadoFinalProyectado;
    final objetivoAlcanzado =
        notaFinal != null &&
        notaFinal >= objetivo - CalculoNotasService.tolerancia;
    return AppPressable(
      child: InkWell(
        key: ValueKey('grades-subject-card-${asignatura.id}'),
        onTap: () => _abrirDetalle(asignatura),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: _panelDecoration(oscuro),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      asignatura.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF111827),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _estado(resultado),
                      style: TextStyle(
                        color: color,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (resultado.estaFinalizada)
                Row(
                  key: ValueKey('grades-final-state-${asignatura.id}'),
                  children: [
                    _metric(
                      label: _espanol ? 'NOTA FINAL' : 'FINAL GRADE',
                      value: _numero(notaFinal),
                      oscuro: oscuro,
                    ),
                    _metric(
                      label: _espanol ? 'RESULTADO' : 'RESULT',
                      value: resultado.estaAprobada
                          ? (_espanol ? 'APROBADO' : 'PASSED')
                          : (_espanol ? 'REPROBADO' : 'FAILED'),
                      oscuro: oscuro,
                    ),
                    _metric(
                      label: _espanol ? 'OBJETIVO' : 'GOAL',
                      value: _numero(objetivo),
                      oscuro: oscuro,
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    _metric(
                      label: _espanol ? 'PROMEDIO' : 'AVERAGE',
                      value: _numero(resultado.promedioParcial),
                      oscuro: oscuro,
                    ),
                    _metric(
                      label: _espanol ? 'EVALUADO' : 'ASSESSED',
                      value: '${resultado.pesoEvaluado.toStringAsFixed(0)} %',
                      oscuro: oscuro,
                    ),
                    _metric(
                      label: _espanol ? 'PENDIENTE' : 'REMAINING',
                      value: '${resultado.pesoPendiente.toStringAsFixed(0)} %',
                      oscuro: oscuro,
                    ),
                  ],
                ),
              const SizedBox(height: 14),
              Text(
                resultado.estaFinalizada
                    ? objetivoAlcanzado
                          ? (_espanol
                                ? 'Objetivo personal alcanzado.'
                                : 'Personal goal reached.')
                          : (_espanol
                                ? 'Objetivo personal no alcanzado.'
                                : 'Personal goal not reached.')
                    : evaluaciones.isEmpty
                    ? (_espanol
                          ? 'Esta asignatura todavía no tiene evaluaciones.'
                          : 'This subject has no assessments yet.')
                    : necesario == null
                    ? (_espanol
                          ? '${evaluaciones.length} evaluaciones registradas.'
                          : '${evaluaciones.length} assessments registered.')
                    : resultado.notaNecesariaUnica != null
                    ? (_espanol
                          ? 'Necesitas ${_numero(resultado.notaNecesariaUnica)} en la evaluación restante.'
                          : 'You need ${_numero(resultado.notaNecesariaUnica)} in the remaining assessment.')
                    : (_espanol
                          ? 'Necesitas promediar ${_numero(necesario)} en el peso restante.'
                          : 'You need a ${_numero(necesario)} average across the remaining weight.'),
                style: TextStyle(
                  color: oscuro
                      ? const Color(0xFFA9B1BF)
                      : const Color(0xFF6B7280),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric({
    required String label,
    required String value,
    required bool oscuro,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: oscuro ? const Color(0xFF7F899A) : const Color(0xFF9CA3AF),
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: oscuro ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(bool oscuro) {
    return _stateCard(
      oscuro: oscuro,
      icon: Ionicons.schoolOutline,
      title: _espanol ? 'Aún no hay asignaturas' : 'No subjects yet',
      message: _espanol
          ? 'Crea una asignatura primero. Luego podrás gestionar aquí sus evaluaciones y notas.'
          : 'Create a subject first. Then you can manage its assessments and grades here.',
    );
  }

  Widget _errorCard(bool oscuro) {
    return _stateCard(
      oscuro: oscuro,
      icon: Icons.cloud_off_rounded,
      title: _espanol ? 'No pudimos cargar tus notas' : 'Could not load grades',
      message: _espanol
          ? 'Revisa tu conexión y confirma que la migración del módulo Notas esté aplicada en Supabase.'
          : 'Check your connection and confirm that the Grades migration has been applied in Supabase.',
      action: FilledButton.icon(
        onPressed: _cargar,
        icon: const Icon(Icons.refresh_rounded),
        label: Text(_espanol ? 'Reintentar' : 'Retry'),
      ),
    );
  }

  Widget _stateCard({
    required bool oscuro,
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: _panelDecoration(oscuro),
      child: Column(
        children: [
          Icon(icon, size: 42, color: _primaryColor),
          const SizedBox(height: 15),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: oscuro ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: oscuro ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
              height: 1.45,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 18), action],
        ],
      ),
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

  BoxDecoration _panelDecoration(bool oscuro) {
    return BoxDecoration(
      color: oscuro ? const Color(0xFF191F29) : Colors.white,
      borderRadius: BorderRadius.circular(20),
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
