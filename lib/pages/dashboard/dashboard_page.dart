import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/navigation/main_navigation.dart';
import '../../core/auth/auth_service.dart';
import '../../models/asignatura.dart';
import '../../models/evaluacion.dart';
import '../../models/perfil_usuario.dart';
import '../../models/tarea.dart';
import '../../services/academic_home_priority_service.dart';
import '../../services/asignaturas_service.dart';
import '../../services/beta_notice_service.dart';
import '../../services/evaluaciones_service.dart';
import '../../services/home_preferences_service.dart';
import '../../services/home_class_status_service.dart';
import '../../services/perfil_service.dart';
import '../../services/tareas_service.dart';
import '../../services/translation_service.dart';
import '../login/login_page.dart';
import '../../widgets/main_bottom_nav.dart';
import '../../widgets/main_section_scroll.dart';
import '../../widgets/app_reveal.dart';
import '../../widgets/app_scroll_header.dart';
import '../../widgets/app_status_snackbar.dart';
import '../profile/profile_page.dart';
import '../settings/settings_page.dart';
import '../settings/home_customization_page.dart';
import '../subjects/subjects_page.dart';
import '../../services/time_format_service.dart';
import '../tasks/tasks_page.dart';
import 'widgets/home_content_sections.dart';

import 'package:flutter/services.dart';

import '../../widgets/app_pressable.dart';
import '../../widgets/beta_notice_dialog.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  final AuthService _authService = AuthService();

  final PerfilService _perfilService = PerfilService();

  final AsignaturasService _asignaturasService = AsignaturasService.instance;

  final TareasService _tareasService = TareasService.instance;

  final EvaluacionesService _evaluacionesService = EvaluacionesService.instance;

  final AcademicHomePriorityService _academicPriorityService =
      const AcademicHomePriorityService();

  final TranslationService _translationService = TranslationService.instance;

  final TimeFormatService _timeFormatService = TimeFormatService.instance;

  final BetaNoticeService _betaNoticeService = BetaNoticeService.instance;

  final HomePreferencesService _homePreferencesService =
      HomePreferencesService.instance;

  final HomeClassStatusService _homeClassStatusService =
      const HomeClassStatusService();

  final ScrollController _scrollController = ScrollController();

  double _progresoHeader = 0.0;

  PerfilUsuario? _perfil;

  List<Asignatura> _asignaturas = [];
  List<HomeClassEntry> _clasesHoy = [];
  List<Tarea> _tareas = [];
  List<Evaluacion> _evaluaciones = [];
  AcademicInsight? _smartInsight;

  bool _cargandoPerfil = true;
  bool _errorPerfil = false;

  bool _cargandoContenido = true;
  bool _errorContenido = false;

  bool _cerrandoSesion = false;

  HomePreferences _homePreferences = HomePreferences.defaults;

  int _versionAsignaturasCargada = -1;

  Timer? _classStatusTimer;

  static const Color _primaryColor = Color(0xFF5B5FEF);

  // Ancho común para las traducciones de ambos menús del avatar.
  static const BoxConstraints _profileMenuConstraints = BoxConstraints.tightFor(
    width: 200,
  );

  bool get _espanol => _translationService.isSpanish;

  // =========================================================
  // DATOS DERIVADOS
  // =========================================================

  bool get _tieneContenido => _asignaturas.isNotEmpty;

  bool get _tieneHorarioConfigurado {
    return _asignaturas.any((asignatura) => asignatura.horario.isNotEmpty);
  }

  int get _totalAsignaturas => _asignaturas.length;

  int get _totalClasesHoy => _clasesHoy.length;

  Tarea? get _proximaTarea =>
      _academicPriorityService.selectNextTask(_tareas, now: DateTime.now());

  Evaluacion? get _proximaEvaluacion => _academicPriorityService
      .selectNextEvaluation(_evaluaciones, now: DateTime.now());

  String get _nombreUsuario {
    final String nombrePerfil = _perfil?.nombre.trim() ?? '';

    if (nombrePerfil.isNotEmpty) {
      return nombrePerfil;
    }

    final String nombreAuth =
        _authService.usuarioActual?.displayName?.trim() ?? '';

    if (nombreAuth.isNotEmpty) {
      return nombreAuth;
    }

    return _espanol ? 'Estudiante' : 'Student';
  }

  String get _primerNombre {
    final List<String> partes = _nombreUsuario
        .split(RegExp(r'\s+'))
        .where((parte) => parte.trim().isNotEmpty)
        .toList();

    if (partes.isEmpty) {
      return _espanol ? 'Estudiante' : 'Student';
    }

    return partes.first;
  }

  String get _inicialesUsuario {
    final List<String> partes = _nombreUsuario
        .split(RegExp(r'\s+'))
        .where((parte) => parte.trim().isNotEmpty)
        .toList();

    if (partes.isEmpty) {
      return 'EF';
    }

    if (partes.length == 1) {
      final String nombre = partes.first;

      if (nombre.length == 1) {
        return nombre.toUpperCase();
      }

      return nombre.substring(0, 2).toUpperCase();
    }

    return '${partes.first[0]}${partes.last[0]}'.toUpperCase();
  }

  bool get _perfilIncompleto {
    return _perfil != null && !_perfil!.perfilCompleto;
  }

  bool get _esNivelEscolar {
    final NivelEducativoPerfil nivel =
        _perfil?.nivelEducativo ?? NivelEducativoPerfil.vacio;

    return nivel == NivelEducativoPerfil.basica ||
        nivel == NivelEducativoPerfil.media;
  }

  bool get _esNivelSuperior {
    final NivelEducativoPerfil nivel =
        _perfil?.nivelEducativo ?? NivelEducativoPerfil.vacio;

    return nivel == NivelEducativoPerfil.tecnico ||
        nivel == NivelEducativoPerfil.superior;
  }

  String get _descripcionAgregarAsignaturas {
    if (_espanol) {
      if (_esNivelEscolar) {
        return 'Registra las asignaturas que tienes este año para organizar tus clases, tareas y horario escolar.';
      }

      if (_esNivelSuperior) {
        return 'Registra los ramos que cursas actualmente para organizar tus clases, profesores y horario.';
      }

      return 'Registra las materias o módulos que estudias actualmente para organizar toda tu información académica.';
    }

    if (_esNivelEscolar) {
      return 'Add the subjects you have this year to organize your classes, tasks and school schedule.';
    }

    if (_esNivelSuperior) {
      return 'Add the courses you are currently taking to organize your classes, teachers and schedule.';
    }

    return 'Add the subjects or modules you are currently studying to organize your academic information.';
  }

  String get _descripcionConfigurarHorario {
    if (_espanol) {
      if (_esNivelEscolar) {
        return 'Agrega los días y horas de tus clases para que EduFlow AI pueda organizar tu semana escolar y mostrarte qué tienes hoy.';
      }

      if (_esNivelSuperior) {
        return 'Configura los bloques de tus ramos para ver tus clases del día, salas y próximas clases desde el inicio.';
      }

      return 'Agrega los días y horarios de tus materias para organizar tu semana académica.';
    }

    if (_esNivelEscolar) {
      return 'Add the days and times of your classes so EduFlow AI can organize your school week and show what you have today.';
    }

    if (_esNivelSuperior) {
      return 'Set up your course blocks to see today\'s classes, rooms and upcoming classes from the home screen.';
    }

    return 'Add the days and times of your subjects to organize your academic week.';
  }

  HomeClassStatus get _classStatus =>
      _homeClassStatusService.resolve(_clasesHoy, now: DateTime.now());

  // =========================================================
  // CICLO DE VIDA
  // =========================================================

  void _feedbackSuave() {
    HapticFeedback.selectionClick();
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _translationService.addListener(_actualizarIdioma);
    _timeFormatService.addListener(_actualizarFormatoHora);
    _homePreferencesService.addListener(_actualizarPreferenciasInicio);

    _scrollController.addListener(_escucharScroll);

    _cargarDashboard();
    _cargarPreferenciasInicio();
    _scheduleClassStatusRefresh();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mostrarBienvenidaBeta();
    });
  }

  @override
  void dispose() {
    _classStatusTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _translationService.removeListener(_actualizarIdioma);
    _timeFormatService.removeListener(_actualizarFormatoHora);
    _homePreferencesService.removeListener(_actualizarPreferenciasInicio);
    _scrollController.removeListener(_escucharScroll);

    _scrollController.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleClassStatusRefresh();
      _cargarContenido(forzar: true, silencioso: true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _classStatusTimer?.cancel();
    }
  }

  void _scheduleClassStatusRefresh() {
    _classStatusTimer?.cancel();
    final DateTime now = DateTime.now();
    final int millisecondsUntilNextMinute =
        60000 - (now.second * 1000 + now.millisecond);
    _classStatusTimer = Timer(
      Duration(milliseconds: millisecondsUntilNextMinute),
      () {
        if (!mounted) return;
        setState(_generarClasesDeHoy);
        _scheduleClassStatusRefresh();
      },
    );
  }

  Future<void> _mostrarBienvenidaBeta() async {
    final bool mostrar = await _betaNoticeService.shouldShow(
      BetaNoticeKind.welcome,
    );

    if (!mounted || !mostrar) {
      return;
    }

    await showBetaNoticeDialog(
      context,
      spanish: _espanol,
      kind: BetaNoticeKind.welcome,
    );

    await _betaNoticeService.markShown(BetaNoticeKind.welcome);
  }

  void _actualizarIdioma() {
    if (mounted) {
      setState(_generarClasesDeHoy);
    }
  }

  void _actualizarFormatoHora() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<void> _cargarPreferenciasInicio() async {
    final HomePreferences preferences = await _homePreferencesService
        .loadCurrent();
    if (!mounted) return;
    setState(() => _homePreferences = preferences);
    await _actualizarResumenInteligente();
  }

  void _actualizarPreferenciasInicio() async {
    if (!mounted) return;
    setState(() => _homePreferences = _homePreferencesService.current);
    await _actualizarResumenInteligente();
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

  Future<void> _cargarDashboard() async {
    await Future.wait([_cargarPerfil(), _cargarContenido()]);
  }

  Future<void> _cargarPerfil({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _cargandoPerfil = true;
        _errorPerfil = false;
      });
    }

    try {
      final usuario = _authService.usuarioActual;

      if (usuario == null) {
        if (!mounted) {
          return;
        }

        await _volverAlLogin();

        return;
      }

      final PerfilUsuario? perfil = await _perfilService.obtenerPerfil(
        usuario.uid,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _perfil = perfil;
        _errorPerfil = perfil == null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      if (!silencioso) {
        setState(() {
          _errorPerfil = true;
        });
      }
    } finally {
      if (mounted && !silencioso) {
        setState(() {
          _cargandoPerfil = false;
        });
      }
    }
  }

  Future<void> _cargarContenido({
    bool forzar = false,
    bool silencioso = false,
  }) async {
    if (!forzar &&
        _versionAsignaturasCargada == _asignaturasService.versionDatos &&
        _versionAsignaturasCargada != -1) {
      return;
    }

    if (!silencioso) {
      setState(() {
        _cargandoContenido = true;
        _errorContenido = false;
      });
    }

    try {
      final List<Object> results = await Future.wait<Object>([
        _asignaturasService.obtenerTodas(),
        _tareasService.obtenerTodas(),
        _evaluacionesService.obtenerTodas(),
      ]);
      final List<Asignatura> asignaturas = results[0] as List<Asignatura>;
      final List<Tarea> tareas = results[1] as List<Tarea>;
      final List<Evaluacion> evaluaciones = results[2] as List<Evaluacion>;

      if (!mounted) {
        return;
      }

      setState(() {
        _asignaturas = asignaturas;
        _tareas = tareas;
        _evaluaciones = evaluaciones;

        _generarClasesDeHoy();

        _versionAsignaturasCargada = _asignaturasService.versionDatos;

        _errorContenido = false;
      });
      await _actualizarResumenInteligente();
    } catch (_) {
      if (!mounted) {
        return;
      }

      // Si ya había contenido visible durante
      // un refresh, no lo borramos por un
      // problema temporal de conexión.
      if (!silencioso) {
        setState(() {
          _asignaturas = [];
          _clasesHoy = [];
          _tareas = [];
          _evaluaciones = [];
          _smartInsight = null;
          _errorContenido = true;
        });
      }
    } finally {
      if (mounted && !silencioso) {
        setState(() {
          _cargandoContenido = false;
        });
      }
    }
  }

  Future<void> _actualizarResumenInteligente() async {
    final AcademicInsight? insight = _academicPriorityService.selectPriority(
      tasks: _tareas,
      evaluations: _evaluaciones,
      todayClassCount: _clasesHoy.length,
      now: DateTime.now(),
      nextTaskVisible: _homePreferences.nextTaskVisible,
      nextEvaluationVisible: _homePreferences.nextEvaluationVisible,
    );
    final bool dismissed =
        insight != null &&
        await _homePreferencesService.isInsightDismissed(insight.id);
    if (!mounted) return;
    setState(() => _smartInsight = dismissed ? null : insight);
  }

  Future<void> _refrescar() async {
    await Future.wait([
      _cargarPerfil(silencioso: true),
      _cargarContenido(forzar: true, silencioso: true),
    ]);
  }

  // =========================================================
  // CLASES DE HOY
  // =========================================================

  void _generarClasesDeHoy() {
    _clasesHoy = _homeClassStatusService.classesForDay(
      _asignaturas,
      date: DateTime.now(),
      missingRoomLabel: _espanol ? 'Sin sala' : 'No room',
      missingTeacherLabel: _espanol ? 'Sin profesor' : 'No teacher',
    );
  }

  String _mostrarHora(String hora) {
    return _timeFormatService.formatStoredTime(context, hora);
  }

  // =========================================================
  // LOGOUT
  // =========================================================

  Future<void> _cerrarSesion() async {
    if (_cerrandoSesion) {
      return;
    }

    setState(() {
      _cerrandoSesion = true;
    });

    try {
      await _authService.cerrarSesion();

      if (!mounted) {
        return;
      }

      await _volverAlLogin();
    } finally {
      if (mounted) {
        setState(() {
          _cerrandoSesion = false;
        });
      }
    }
  }

  Future<void> _volverAlLogin() async {
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  Future<void> _abrirPerfil({bool completar = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfilePage(startInEditMode: completar),
      ),
    );

    if (!mounted) {
      return;
    }

    await _cargarPerfil();
  }

  Future<void> _abrirAjustes() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsPage()));
  }

  Future<void> _abrirAsignaturas() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SubjectsPage()));

    if (!mounted) {
      return;
    }

    await _cargarContenido(forzar: true, silencioso: true);
  }

  Future<void> _abrirTareas() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const TasksPage()));

    if (!mounted) return;
    await _cargarContenido(forzar: true, silencioso: true);
  }

  Future<void> _abrirTareaEspecifica(Tarea tarea) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TasksPage(initialTaskId: tarea.id)),
    );
    if (!mounted) return;
    await _cargarContenido(forzar: true, silencioso: true);
  }

  Future<void> _abrirPersonalizarInicio() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const HomeCustomizationPage()));
  }

  void _abrirHorario() {
    MainNavigation.goTo(context, SeccionPrincipal.horario);
  }

  void _volverArriba() {
    scrollMainSectionToTop(context, _scrollController);
  }

  void _abrirCalendario() {
    MainNavigation.goTo(context, SeccionPrincipal.calendario);
  }

  void _abrirEvaluacionEspecifica(Evaluacion evaluacion) {
    MainNavigation.openEvaluation(context, evaluacion.id);
  }

  void _abrirNotificaciones() {
    HapticFeedback.selectionClick();
    MainNavigation.goTo(context, SeccionPrincipal.notificaciones);
  }

  // =========================================================
  // EDUCFLOW AI
  // =========================================================

  void _abrirIA() {
    HapticFeedback.selectionClick();
    MainNavigation.goTo(context, SeccionPrincipal.ia);
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

                    final double paddingInferior = ancho <= 480 ? 110 : 145;

                    return ListView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        22,
                        horizontal,
                        paddingInferior,
                      ),
                      children: [
                        Transform.translate(
                          offset: Offset(0, -10 * _progresoHeader),
                          child: Transform.scale(
                            alignment: Alignment.topLeft,
                            scale: 1 - (0.015 * _progresoHeader),
                            child: Opacity(
                              opacity: 1 - _progresoHeader,
                              child: _buildTopbar(oscuro),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        if (_cargandoPerfil)
                          _buildLoading(oscuro)
                        else if (_errorPerfil)
                          _buildProfileError(oscuro)
                        else if (_perfilIncompleto)
                          _buildWelcomeCard(oscuro)
                        else if (_cargandoContenido)
                          _buildContentLoading(oscuro)
                        else if (_errorContenido)
                          _buildContentError(oscuro)
                        else
                          _buildAvailableContent(oscuro, ancho),
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
              title: _espanol ? 'Inicio' : 'Home',
              trailing: _buildCompactProfileButton(oscuro),
            ),
          ),

          MainBottomNav(
            currentIndex: 0,

            onHome: _volverArriba,

            onSchedule: _abrirHorario,

            onAi: _abrirIA,

            onCalendar: _abrirCalendario,

            onNotifications: _abrirNotificaciones,
          ),
        ],
      ),
    );
  }

  // =========================================================
  // CONTENIDO DISPONIBLE
  // =========================================================

  Widget _buildAvailableContent(bool oscuro, double ancho) {
    final Widget? setup = !_tieneContenido
        ? _buildSubjectsSetupCard(oscuro)
        : !_tieneHorarioConfigurado
        ? _buildScheduleSetupCard(oscuro)
        : null;
    final bool hasConfiguredContent =
        (_tieneHorarioConfigurado &&
            (_homePreferences.summaryVisible ||
                _homePreferences.todayClassesVisible ||
                _homePreferences.subjectsVisible)) ||
        (_homePreferences.nextTaskVisible && _proximaTarea != null) ||
        (_homePreferences.nextEvaluationVisible &&
            _proximaEvaluacion != null) ||
        (_homePreferences.smartSummaryVisible && _smartInsight != null);

    final List<Widget> children = [];
    if (setup != null) children.add(setup);
    if (setup != null && hasConfiguredContent) {
      children.add(const SizedBox(height: 18));
    }
    children.add(
      HomeContentSections(
        preferences: _homePreferences,
        summary: _tieneHorarioConfigurado
            ? _buildSummarySection(oscuro, ancho)
            : null,
        smartSummary: _smartInsight == null
            ? null
            : AppReveal(child: _buildSmartSummaryCard(oscuro)),
        nextTask: _proximaTarea == null
            ? null
            : AppReveal(child: _buildNextTaskCard(oscuro, _proximaTarea!)),
        nextEvaluation: _proximaEvaluacion == null
            ? null
            : AppReveal(
                child: _buildNextEvaluationCard(oscuro, _proximaEvaluacion!),
              ),
        // Todavía no existe una fuente real de recordatorios de estudio.
        studyReminder: null,
        emptyState: setup == null ? _buildEmptyHomeState(oscuro) : null,
        todayClasses: _tieneHorarioConfigurado
            ? AppReveal(
                delay: const Duration(milliseconds: 180),
                child: _buildClassesPanel(oscuro),
              )
            : null,
        subjects: _tieneHorarioConfigurado
            ? AppReveal(
                delay: const Duration(milliseconds: 230),
                child: _buildSubjectsPanel(oscuro),
              )
            : null,
      ),
    );
    return Column(children: children);
  }

  Widget _buildEmptyHomeState(bool oscuro) {
    return AppReveal(
      child: _buildSimpleCard(
        key: const Key('home-empty-state'),
        oscuro: oscuro,
        radius: 22,
        borderColor: oscuro ? const Color(0xFF363964) : const Color(0xFFDFE2FF),
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: oscuro
                    ? const Color(0xFF252747)
                    : const Color(0xFFEEF0FF),
                borderRadius: BorderRadius.circular(19),
              ),
              child: const Icon(
                Icons.space_dashboard_outlined,
                color: _primaryColor,
                size: 29,
              ),
            ),
            const SizedBox(height: 17),
            Text(
              _espanol ? 'Tienes tu Inicio despejado' : 'Your Home is clear',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: oscuro
                    ? const Color(0xFFF8FAFC)
                    : const Color(0xFF111827),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _espanol
                  ? 'Has ocultado las secciones de Inicio. Puedes volver a mostrar las que quieras.'
                  : 'You have hidden the Home sections. You can show any of them again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: oscuro
                    ? const Color(0xFFA9B1BF)
                    : const Color(0xFF6B7280),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                key: const Key('empty-home-customize'),
                onPressed: _abrirPersonalizarInicio,
                style: FilledButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.tune_rounded, size: 20),
                label: Text(
                  _espanol ? 'Personalizar Inicio' : 'Customize Home',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // TOPBAR
  // =========================================================

  Widget _buildTopbar(bool oscuro) {
    return Row(
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
                _cargandoPerfil
                    ? (_espanol ? 'Cargando...' : 'Loading...')
                    : (_espanol
                          ? 'Hola, $_primerNombre 👋'
                          : 'Hi, $_primerNombre 👋'),
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
                    ? 'Tu espacio académico personal.'
                    : 'Your personal academic space.',
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

        _buildProfileMenu(oscuro),
      ],
    );
  }

  // =========================================================
  // MENÚ PERFIL
  // =========================================================

  Widget _buildProfileMenu(bool oscuro) {
    return AppPressable(
      scale: 0.92,
      child: PopupMenuButton<_ProfileAction>(
        constraints: _profileMenuConstraints,
        tooltip: '',
        onOpened: _feedbackSuave,
        color: oscuro ? const Color(0xFF191F29) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black26,
        elevation: 12,
        offset: const Offset(0, 8),
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: BorderSide(
            color: oscuro ? const Color(0xFF2B323E) : const Color(0xFFE7EAF0),
          ),
        ),
        onSelected: (_ProfileAction action) {
          switch (action) {
            case _ProfileAction.perfil:
              _abrirPerfil();
              break;

            case _ProfileAction.asignaturas:
              _abrirAsignaturas();
              break;

            case _ProfileAction.tareas:
              _abrirTareas();
              break;

            case _ProfileAction.ajustes:
              _abrirAjustes();

            case _ProfileAction.logout:
              _cerrarSesion();
          }
        },
        itemBuilder: (context) {
          return [
            _profileMenuItem(
              action: _ProfileAction.perfil,
              icon: Icons.person_outline,
              label: _espanol ? 'Perfil' : 'Profile',
              oscuro: oscuro,
            ),

            _profileMenuItem(
              action: _ProfileAction.asignaturas,
              icon: Icons.menu_book_outlined,
              label: _espanol ? 'Asignaturas' : 'Subjects',
              oscuro: oscuro,
            ),

            _profileMenuItem(
              action: _ProfileAction.tareas,
              icon: Icons.checklist_rounded,
              label: _espanol ? 'Tareas' : 'Tasks',
              oscuro: oscuro,
            ),

            _profileMenuItem(
              action: _ProfileAction.ajustes,
              icon: Icons.settings_outlined,
              label: _espanol ? 'Ajustes' : 'Settings',
              oscuro: oscuro,
            ),

            const PopupMenuDivider(),

            PopupMenuItem<_ProfileAction>(
              value: _ProfileAction.logout,
              height: 49,
              child: Row(
                children: [
                  const Icon(
                    Icons.logout_outlined,
                    size: 20,
                    color: Color(0xFFDC2626),
                  ),

                  const SizedBox(width: 13),

                  Text(
                    _cerrandoSesion
                        ? (_espanol ? 'Cerrando...' : 'Signing out...')
                        : (_espanol ? 'Cerrar sesión' : 'Sign out'),
                    style: const TextStyle(
                      color: Color(0xFFDC2626),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ];
        },
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _primaryColor,
            borderRadius: BorderRadius.circular(15),
            boxShadow: oscuro
                ? const []
                : const [
                    BoxShadow(
                      color: Color(0x385B5FEF),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
          ),
          child: Text(
            _inicialesUsuario,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactProfileButton(bool oscuro) {
    return AppPressable(
      scale: 0.92,
      child: PopupMenuButton<_ProfileAction>(
        constraints: _profileMenuConstraints,
        tooltip: '',
        onOpened: _feedbackSuave,
        color: oscuro ? const Color(0xFF1A1F29) : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        offset: const Offset(0, 7),
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: BorderSide(
            color: oscuro ? const Color(0xFF313946) : const Color(0xFFE7EAF0),
          ),
        ),
        onSelected: (_ProfileAction action) {
          switch (action) {
            case _ProfileAction.perfil:
              _abrirPerfil();
              break;

            case _ProfileAction.asignaturas:
              _abrirAsignaturas();
              break;

            case _ProfileAction.tareas:
              _abrirTareas();
              break;

            case _ProfileAction.ajustes:
              _abrirAjustes();
              break;

            case _ProfileAction.logout:
              _cerrarSesion();
              break;
          }
        },
        itemBuilder: (context) {
          return [
            _profileMenuItem(
              action: _ProfileAction.perfil,
              icon: Icons.person_outline,
              label: _espanol ? 'Perfil' : 'Profile',
              oscuro: oscuro,
            ),

            _profileMenuItem(
              action: _ProfileAction.asignaturas,
              icon: Icons.menu_book_outlined,
              label: _espanol ? 'Asignaturas' : 'Subjects',
              oscuro: oscuro,
            ),

            _profileMenuItem(
              action: _ProfileAction.tareas,
              icon: Icons.checklist_rounded,
              label: _espanol ? 'Tareas' : 'Tasks',
              oscuro: oscuro,
            ),

            _profileMenuItem(
              action: _ProfileAction.ajustes,
              icon: Icons.settings_outlined,
              label: _espanol ? 'Ajustes' : 'Settings',
              oscuro: oscuro,
            ),

            const PopupMenuDivider(),

            PopupMenuItem<_ProfileAction>(
              value: _ProfileAction.logout,
              height: 49,
              child: Row(
                children: [
                  const Icon(
                    Icons.logout_outlined,
                    size: 20,
                    color: Color(0xFFFF6B6B),
                  ),

                  const SizedBox(width: 13),

                  Text(
                    _espanol ? 'Cerrar sesión' : 'Sign out',
                    style: const TextStyle(
                      color: Color(0xFFFF6B6B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ];
        },
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _primaryColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _inicialesUsuario,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<_ProfileAction> _profileMenuItem({
    required _ProfileAction action,
    required IconData icon,
    required String label,
    required bool oscuro,
  }) {
    return PopupMenuItem<_ProfileAction>(
      value: action,
      height: 49,
      child: Row(
        children: [
          Icon(icon, size: 20, color: _primaryColor),

          const SizedBox(width: 13),

          Text(
            label,
            style: TextStyle(
              color: oscuro ? const Color(0xFFEDF1F7) : const Color(0xFF374151),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // CARGA
  // =========================================================

  Widget _buildLoading(bool oscuro) {
    return SizedBox(
      height: 330,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: _primaryColor,
              ),
            ),

            const SizedBox(height: 14),

            Text(
              _espanol ? 'Cargando tu espacio...' : 'Loading your space...',
              style: TextStyle(
                color: oscuro
                    ? const Color(0xFFA9B1BF)
                    : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentLoading(bool oscuro) {
    return _buildSimpleCard(
      oscuro: oscuro,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 42),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  strokeWidth: 2.7,
                  color: _primaryColor,
                ),
              ),

              const SizedBox(height: 14),

              Text(
                _espanol
                    ? 'Cargando contenido académico...'
                    : 'Loading academic content...',
                style: TextStyle(
                  color: oscuro
                      ? const Color(0xFFA9B1BF)
                      : const Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================
  // ERRORES
  // =========================================================

  Widget _buildProfileError(bool oscuro) {
    return _buildErrorCard(
      titulo: _espanol
          ? 'No pudimos cargar tu perfil'
          : 'We could not load your profile',
      descripcion: _espanol
          ? 'Intenta actualizar la pantalla para volver a cargar tus datos.'
          : 'Refresh the screen to try loading your data again.',
    );
  }

  Widget _buildContentError(bool oscuro) {
    return _buildErrorCard(
      titulo: _espanol
          ? 'No pudimos cargar tus asignaturas'
          : 'We could not load your subjects',
      descripcion: _espanol
          ? 'Desliza hacia abajo para intentarlo nuevamente.'
          : 'Pull down to try again.',
    );
  }

  Widget _buildErrorCard({
    required String titulo,
    required String descripcion,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF321D22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF5F2B31)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFFCA5A5),
            size: 27,
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Color(0xFFFCA5A5),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  descripcion,
                  style: const TextStyle(
                    color: Color(0xFFFCA5A5),
                    fontSize: 14,
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

  // =========================================================
  // PERFIL INCOMPLETO
  // =========================================================

  Widget _buildWelcomeCard(bool oscuro) {
    return _buildSimpleCard(
      oscuro: oscuro,
      borderColor: oscuro ? const Color(0xFF363964) : const Color(0xFFDFE2FF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: oscuro
                      ? const Color(0xFF252747)
                      : const Color(0xFFEEF0FF),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.person_add_alt_1_outlined,
                  color: _primaryColor,
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _espanol ? 'PRIMEROS PASOS' : 'GET STARTED',
                      style: const TextStyle(
                        color: _primaryColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      _espanol ? 'Completa tu perfil' : 'Complete your profile',
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF111827),
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      _espanol
                          ? 'Cuéntanos un poco sobre tus estudios para personalizar mejor EduFlow AI.'
                          : 'Tell us a little about your studies so EduFlow AI can personalize your experience.',
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
            ],
          ),

          const SizedBox(height: 18),

          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                _abrirPerfil(completar: true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                _espanol ? 'Completar perfil' : 'Complete profile',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // ESTADO VACÍO
  // =========================================================
  Widget _buildSubjectsSetupCard(bool oscuro) {
    return AppReveal(
      child: _buildSimpleCard(
        oscuro: oscuro,
        radius: 22,
        borderColor: oscuro ? const Color(0xFF363964) : const Color(0xFFDFE2FF),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Column(
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: oscuro
                      ? const Color(0xFF252747)
                      : const Color(0xFFEEF0FF),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.menu_book_outlined,
                  color: _primaryColor,
                  size: 34,
                ),
              ),

              const SizedBox(height: 19),

              Text(
                _espanol ? 'SIGUIENTE PASO' : 'NEXT STEP',
                style: const TextStyle(
                  color: _primaryColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                _espanol ? 'Agrega tus asignaturas' : 'Add your subjects',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: oscuro
                      ? const Color(0xFFF8FAFC)
                      : const Color(0xFF111827),
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 8),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  _descripcionAgregarAsignaturas,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFA9B1BF)
                        : const Color(0xFF6B7280),
                    height: 1.5,
                  ),
                ),
              ),

              const SizedBox(height: 25),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _abrirAsignaturas,
                  icon: const Icon(Icons.add_rounded, size: 21),
                  label: Text(
                    _espanol ? 'Agregar asignaturas' : 'Add subjects',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleSetupCard(bool oscuro) {
    return AppReveal(
      child: _buildSimpleCard(
        oscuro: oscuro,
        radius: 22,
        borderColor: oscuro ? const Color(0xFF363964) : const Color(0xFFDFE2FF),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Column(
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: oscuro
                      ? const Color(0xFF252747)
                      : const Color(0xFFEEF0FF),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.calendar_month_outlined,
                  color: _primaryColor,
                  size: 34,
                ),
              ),

              const SizedBox(height: 19),

              Text(
                _espanol ? 'SIGUIENTE PASO' : 'NEXT STEP',
                style: const TextStyle(
                  color: _primaryColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                _espanol ? 'Configura tu horario' : 'Set up your schedule',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: oscuro
                      ? const Color(0xFFF8FAFC)
                      : const Color(0xFF111827),
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 8),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  _descripcionConfigurarHorario,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFA9B1BF)
                        : const Color(0xFF6B7280),
                    height: 1.5,
                  ),
                ),
              ),

              const SizedBox(height: 25),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _abrirHorario,
                  icon: const Icon(Icons.calendar_month_outlined, size: 21),
                  label: Text(
                    _espanol ? 'Configurar horario' : 'Set up schedule',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================
  // RESUMEN
  // =========================================================

  Widget _buildSummarySection(bool oscuro, double ancho) {
    final HomeClassStatus classStatus = _classStatus;

    final List<Widget> tarjetas = [
      AppReveal(
        child: _buildSummaryCard(
          oscuro: oscuro,
          icon: Icons.menu_book_outlined,
          iconColor: const Color(0xFF2563EB),
          label: _espanol ? 'ASIGNATURAS' : 'SUBJECTS',
          value: '$_totalAsignaturas',
          description: _espanol
              ? 'Registradas actualmente'
              : 'Currently registered',
        ),
      ),

      AppReveal(
        delay: const Duration(milliseconds: 50),
        child: _buildSummaryCard(
          oscuro: oscuro,
          icon: Icons.access_time_rounded,
          iconColor: const Color(0xFF7C3AED),
          label: _espanol ? 'CLASES HOY' : 'CLASSES TODAY',
          value: '$_totalClasesHoy',
          description: _totalClasesHoy == 0
              ? (_espanol ? 'Sin clases hoy' : 'No classes today')
              : _totalClasesHoy == 1
              ? (_espanol ? 'clase programada' : 'scheduled class')
              : (_espanol ? 'clases programadas' : 'scheduled classes'),
        ),
      ),

      if (classStatus.currentClass != null)
        AppReveal(
          delay: const Duration(milliseconds: 100),
          child: _buildClassStatusCard(
            key: const Key('current-class-card'),
            oscuro: oscuro,
            label: _espanol ? 'CLASE EN CURSO' : 'CURRENT CLASS',
            clase: classStatus.currentClass!,
            icon: Icons.play_circle_outline_rounded,
            iconColor: const Color(0xFFDC2626),
          ),
        ),
      if (classStatus.nextClass != null)
        AppReveal(
          delay: const Duration(milliseconds: 150),
          child: _buildClassStatusCard(
            key: const Key('next-class-card'),
            oscuro: oscuro,
            label: _espanol ? 'PRÓXIMA CLASE' : 'NEXT CLASS',
            clase: classStatus.nextClass!,
            icon: Icons.alarm_outlined,
            iconColor: const Color(0xFF059669),
          ),
        ),
      if (classStatus.currentClass == null && classStatus.nextClass == null)
        AppReveal(
          delay: const Duration(milliseconds: 100),
          child: _buildSummaryCard(
            oscuro: oscuro,
            icon: Icons.alarm_outlined,
            iconColor: const Color(0xFF059669),
            label: _espanol ? 'PRÓXIMA CLASE' : 'NEXT CLASS',
            value: '—',
            description: _espanol
                ? 'Sin clases pendientes hoy'
                : 'No remaining classes today',
          ),
        ),
    ];

    if (ancho > 960) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int index = 0; index < tarjetas.length; index++) ...[
            if (index > 0) const SizedBox(width: 18),
            Expanded(child: tarjetas[index]),
          ],
        ],
      );
    }

    return Column(
      children: [
        for (int index = 0; index < tarjetas.length; index++) ...[
          if (index > 0) const SizedBox(height: 13),
          tarjetas[index],
        ],
      ],
    );
  }

  Widget _buildClassStatusCard({
    required Key key,
    required bool oscuro,
    required String label,
    required HomeClassEntry clase,
    required IconData icon,
    required Color iconColor,
  }) {
    return _buildSimpleCard(
      key: key,
      oscuro: oscuro,
      radius: 18,
      padding: 18,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: oscuro ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: iconColor, size: 23),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFF8993A2)
                        : const Color(0xFF6B7280),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  clase.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                  '${_mostrarHora(clase.horaInicio)}–${_mostrarHora(clase.horaFin)} · ${clase.sala}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFA9B1BF)
                        : const Color(0xFF6B7280),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required bool oscuro,
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String description,
  }) {
    return _buildSimpleCard(
      oscuro: oscuro,
      radius: 18,
      padding: 18,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: oscuro ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: iconColor, size: 23),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFF8993A2)
                        : const Color(0xFF6B7280),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),

                const SizedBox(height: 6),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: const Cubic(0.22, 1, 0.36, 1),
                  switchOutCurve: Curves.easeOut,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.82,
                          end: 1,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: Text(
                    value,
                    key: ValueKey(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: oscuro
                          ? const Color(0xFFF8FAFC)
                          : const Color(0xFF111827),
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFA9B1BF)
                        : const Color(0xFF6B7280),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // CONTEXTO ACADÉMICO
  // =========================================================

  Widget _buildNextTaskCard(bool oscuro, Tarea tarea) {
    return _buildContextCard(
      key: const Key('home-next-task-card'),
      oscuro: oscuro,
      icon: Icons.assignment_outlined,
      accent: const Color(0xFF2563EB),
      label: _espanol ? 'PRÓXIMA TAREA' : 'NEXT TASK',
      title: tarea.titulo,
      subject: _nombreAsignaturaPorId(
        tarea.asignaturaId,
        generalTaskIfEmpty: true,
      ),
      date: _taskDateText(tarea),
      action: _espanol ? 'Ver tarea' : 'View task',
      onPressed: () => _abrirTareaEspecifica(tarea),
    );
  }

  Widget _buildNextEvaluationCard(bool oscuro, Evaluacion evaluacion) {
    return _buildContextCard(
      key: const Key('home-next-evaluation-card'),
      oscuro: oscuro,
      icon: Icons.school_outlined,
      accent: const Color(0xFF8B5CF6),
      label:
          '${_espanol ? 'PRÓXIMA EVALUACIÓN' : 'NEXT EVALUATION'} · '
          '${_evaluationTypeName(evaluacion.tipo).toUpperCase()}',
      title: evaluacion.titulo,
      subject: _nombreAsignaturaPorId(evaluacion.asignaturaId),
      date: _evaluationDateText(evaluacion),
      action: _espanol ? 'Ver evaluación' : 'View evaluation',
      onPressed: () => _abrirEvaluacionEspecifica(evaluacion),
    );
  }

  Widget _buildContextCard({
    required Key key,
    required bool oscuro,
    required IconData icon,
    required Color accent,
    required String label,
    required String title,
    required String subject,
    required String date,
    required String action,
    required VoidCallback onPressed,
  }) {
    return _buildSimpleCard(
      key: key,
      oscuro: oscuro,
      radius: 20,
      padding: 18,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: oscuro ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: accent, size: 23),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: accent,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  title,
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
                const SizedBox(height: 5),
                Text(
                  subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFA9B1BF)
                        : const Color(0xFF6B7280),
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        date,
                        style: TextStyle(
                          color: accent,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    AppPressable(
                      child: TextButton(
                        onPressed: onPressed,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          action,
                          style: const TextStyle(
                            color: _primaryColor,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartSummaryCard(bool oscuro) {
    final AcademicInsight insight = _smartInsight!;
    final Tarea? mentionedTask = insight.task ?? insight.secondaryTask;
    final Evaluacion? mentionedEvaluation =
        insight.evaluation ?? insight.secondaryEvaluation;

    return _buildSimpleCard(
      key: const Key('home-smart-summary-card'),
      oscuro: oscuro,
      radius: 20,
      padding: 18,
      borderColor: oscuro ? const Color(0xFF42496D) : const Color(0xFFD7DAFF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: oscuro
                      ? const Color(0xFF292936)
                      : const Color(0xFFEEF0FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: _primaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _espanol ? 'RESUMEN INTELIGENTE' : 'SMART SUMMARY',
                      style: const TextStyle(
                        color: _primaryColor,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _smartInsightText(insight),
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF1F2937),
                        fontSize: 15,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              if (mentionedTask != null)
                FilledButton.tonal(
                  key: const Key('smart-summary-view-task'),
                  onPressed: () => _abrirTareaEspecifica(mentionedTask),
                  child: Text(_espanol ? 'Ver tarea' : 'View task'),
                ),
              if (mentionedEvaluation != null)
                FilledButton.tonal(
                  key: const Key('smart-summary-view-evaluation'),
                  onPressed: () =>
                      _abrirEvaluacionEspecifica(mentionedEvaluation),
                  child: Text(_espanol ? 'Ver evaluación' : 'View evaluation'),
                ),
              TextButton(
                key: const Key('dismiss-smart-summary'),
                onPressed: _remindSmartSummaryLater,
                child: Text(
                  _espanol ? 'Recordarme después' : 'Remind me later',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _remindSmartSummaryLater() async {
    final AcademicInsight? insight = _smartInsight;
    if (insight == null) return;
    HapticFeedback.selectionClick();
    await _homePreferencesService.dismissInsightUntilTomorrow(insight.id);
    if (!mounted) return;
    setState(() => _smartInsight = null);
    showAppStatusSnackBar(
      context,
      message: _espanol
          ? 'Ocultaremos esta recomendación hasta mañana.'
          : 'We will hide this recommendation until tomorrow.',
      type: AppStatusType.info,
      bottomMargin: 104,
    );
  }

  String _smartInsightText(AcademicInsight insight) {
    final AcademicInsightItem? secondary = insight.secondary;
    if (secondary == null) return _primaryInsightText(insight.primary);
    return '${_primaryInsightText(insight.primary)} '
        '${_secondaryInsightText(secondary)}';
  }

  String _primaryInsightText(AcademicInsightItem item) {
    final String? taskTitle = item.task?.titulo;
    final String? evaluationTitle = item.evaluation?.titulo;
    switch (item.kind) {
      case AcademicInsightKind.overdueOrTodayTask:
        final bool overdue = _academicPriorityService
            .taskDeadline(item.task!)!
            .isBefore(DateTime.now());
        return overdue
            ? (_espanol
                  ? 'Prioriza la tarea “$taskTitle”: está vencida.'
                  : 'Prioritize “$taskTitle”: this task is overdue.')
            : (_espanol
                  ? 'Prioriza la tarea “$taskTitle”: vence hoy.'
                  : 'Prioritize “$taskTitle”: this task is due today.');
      case AcademicInsightKind.imminentEvaluation:
        return item.daysUntil == 0
            ? (_espanol
                  ? 'Prioriza la evaluación “$evaluationTitle”: es hoy.'
                  : 'Prioritize “$evaluationTitle”: it is today.')
            : (_espanol
                  ? 'Prepara la evaluación “$evaluationTitle”: es mañana.'
                  : 'Prepare for “$evaluationTitle”: it is tomorrow.');
      case AcademicInsightKind.tomorrowTask:
        return _espanol
            ? 'Prioriza la tarea “$taskTitle”: vence mañana.'
            : 'Prioritize “$taskTitle”: this task is due tomorrow.';
      case AcademicInsightKind.upcomingEvaluation:
        return _espanol
            ? 'Empieza por preparar “$evaluationTitle”, que es en ${item.daysUntil} días.'
            : 'Start preparing for “$evaluationTitle”, which is in ${item.daysUntil} days.';
      case AcademicInsightKind.upcomingTask:
        return _espanol
            ? 'Empieza por la tarea “$taskTitle”, que vence en ${item.daysUntil} días.'
            : 'Start with “$taskTitle”, which is due in ${item.daysUntil} days.';
      case AcademicInsightKind.busyAcademicDay:
        return _espanol
            ? 'Hoy tienes ${item.todayClassCount} clases programadas.'
            : 'You have ${item.todayClassCount} scheduled classes today.';
    }
  }

  String _secondaryInsightText(AcademicInsightItem item) {
    final Tarea? task = item.task;
    if (task != null) {
      final String timing = item.daysUntil <= 0
          ? (_espanol
                ? 'también requiere atención hoy'
                : 'also needs attention today')
          : item.daysUntil == 1
          ? (_espanol ? 'vence mañana' : 'is due tomorrow')
          : (_espanol
                ? 'vence en ${item.daysUntil} días'
                : 'is due in ${item.daysUntil} days');
      return _espanol
          ? 'Después, la tarea “${task.titulo}” $timing.'
          : 'After that, the task “${task.titulo}” $timing.';
    }
    final Evaluacion? evaluation = item.evaluation;
    if (evaluation != null) {
      final String timing = item.daysUntil == 0
          ? (_espanol ? 'es hoy' : 'is today')
          : item.daysUntil == 1
          ? (_espanol ? 'es mañana' : 'is tomorrow')
          : (_espanol
                ? 'es en ${item.daysUntil} días'
                : 'is in ${item.daysUntil} days');
      final String subject = _nombreAsignaturaPorId(evaluation.asignaturaId);
      return _espanol
          ? 'Después tienes ${_evaluationTypeName(evaluation.tipo).toLowerCase()} “${evaluation.titulo}” de $subject: $timing.'
          : 'After that, you have the ${_evaluationTypeName(evaluation.tipo).toLowerCase()} “${evaluation.titulo}” for $subject: it $timing.';
    }
    return _espanol
        ? 'Además, hoy tienes ${item.todayClassCount} clases programadas.'
        : 'You also have ${item.todayClassCount} scheduled classes today.';
  }

  String _nombreAsignaturaPorId(String? id, {bool generalTaskIfEmpty = false}) {
    final String cleanId = id?.trim() ?? '';
    if (cleanId.isEmpty && generalTaskIfEmpty) {
      return _espanol ? 'Tarea general' : 'General task';
    }
    for (final Asignatura subject in _asignaturas) {
      if (subject.id == cleanId) return subject.nombre;
    }
    return _espanol ? 'Asignatura no disponible' : 'Subject unavailable';
  }

  String _taskDateText(Tarea task) {
    final DateTime date = task.fechaEntrega!;
    final int days = _academicPriorityService.calendarDaysUntil(
      date,
      DateTime.now(),
    );
    final bool overdue = _academicPriorityService
        .taskDeadline(task)!
        .isBefore(DateTime.now());
    final String relative = overdue
        ? (days == 0
              ? (_espanol ? 'Vencida hoy' : 'Overdue today')
              : (_espanol
                    ? 'Vencida hace ${days.abs()} días'
                    : 'Overdue by ${days.abs()} days'))
        : days == 0
        ? (_espanol ? 'Entrega hoy' : 'Due today')
        : days == 1
        ? (_espanol ? 'Entrega mañana' : 'Due tomorrow')
        : (_espanol ? 'Faltan $days días' : '$days days left');
    final String? time = task.horaEntrega?.trim();
    final String formattedTime = time?.isNotEmpty == true
        ? ' · ${_timeFormatService.formatStoredTime(context, time!)}'
        : '';
    return '${MaterialLocalizations.of(context).formatMediumDate(date)}'
        '$formattedTime · $relative';
  }

  String _evaluationDateText(Evaluacion evaluation) {
    final int days = _academicPriorityService.calendarDaysUntil(
      evaluation.fecha,
      DateTime.now(),
    );
    final String relative = days == 0
        ? (_espanol ? 'Hoy' : 'Today')
        : days == 1
        ? (_espanol ? 'Mañana' : 'Tomorrow')
        : (_espanol ? 'Faltan $days días' : '$days days left');
    final String? time = evaluation.hora?.trim();
    final String formattedTime = time?.isNotEmpty == true
        ? ' · ${_timeFormatService.formatStoredTime(context, time!)}'
        : '';
    return '${MaterialLocalizations.of(context).formatMediumDate(evaluation.fecha)}'
        '$formattedTime · $relative';
  }

  String _evaluationTypeName(TipoEvaluacion type) {
    return switch (type) {
      TipoEvaluacion.prueba => _espanol ? 'Prueba' : 'Test',
      TipoEvaluacion.examen => _espanol ? 'Examen' : 'Exam',
      TipoEvaluacion.control => _espanol ? 'Control' : 'Assessment',
      TipoEvaluacion.quiz => 'Quiz',
      TipoEvaluacion.presentacion => _espanol ? 'Presentación' : 'Presentation',
      TipoEvaluacion.otro => _espanol ? 'Evaluación' : 'Evaluation',
    };
  }

  // =========================================================
  // PANELES PRINCIPALES
  // =========================================================

  Widget _buildClassesPanel(bool oscuro) {
    return _buildSimpleCard(
      oscuro: oscuro,
      radius: 20,
      padding: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPanelHeader(
            oscuro: oscuro,
            label: _espanol ? 'HOY' : 'TODAY',
            title: _espanol ? 'Clases de hoy' : 'Today\'s classes',
            action: _espanol ? 'Ver horario' : 'View schedule',
            onPressed: _abrirHorario,
          ),

          const SizedBox(height: 8),

          if (_clasesHoy.isEmpty)
            _buildNoClasses(oscuro)
          else
            ..._clasesHoy.map((clase) => _buildClassItem(clase, oscuro)),
        ],
      ),
    );
  }

  Widget _buildClassItem(HomeClassEntry clase, bool oscuro) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: oscuro ? const Color(0xFF303844) : const Color(0xFFEDF0F5),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 76,
            height: 56,
            decoration: BoxDecoration(
              color: oscuro ? const Color(0xFF252747) : const Color(0xFFEEF0FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _mostrarHora(clase.horaInicio),
                  style: const TextStyle(
                    color: _primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  _mostrarHora(clase.horaFin),
                  style: const TextStyle(
                    color: _primaryColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clase.nombre,
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF1F2937),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  '${clase.sala} · ${clase.profesor}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFA9B1BF)
                        : const Color(0xFF6B7280),
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoClasses(bool oscuro) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 23),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            color: _primaryColor,
            size: 30,
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _espanol ? 'Sin clases por hoy' : 'No classes today',
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF1F2937),
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  _espanol
                      ? 'No tienes bloques programados para hoy.'
                      : 'You have no scheduled blocks today.',
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFA9B1BF)
                        : const Color(0xFF6B7280),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectsPanel(bool oscuro) {
    final List<Asignatura> primeras = _asignaturas.take(4).toList();

    return _buildSimpleCard(
      oscuro: oscuro,
      radius: 20,
      padding: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPanelHeader(
            oscuro: oscuro,
            label: _espanol ? 'ACADÉMICO' : 'ACADEMIC',
            title: _espanol ? 'Mis asignaturas' : 'My subjects',
            action: _espanol ? 'Ver todas' : 'View all',
            onPressed: _abrirAsignaturas,
          ),

          const SizedBox(height: 8),

          ...primeras.map(
            (asignatura) => _buildSubjectItem(asignatura, oscuro),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectItem(Asignatura asignatura, bool oscuro) {
    final String codigo = asignatura.sigla?.trim().isNotEmpty == true
        ? asignatura.sigla!.trim()
        : (_espanol ? 'ASIG.' : 'SUBJ.');

    final String profesor = asignatura.profesor?.trim().isNotEmpty == true
        ? asignatura.profesor!.trim()
        : (_espanol ? 'Sin profesor' : 'No teacher');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: oscuro ? const Color(0xFF303844) : const Color(0xFFEDF0F5),
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(
              codigo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _primaryColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asignatura.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF1F2937),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  profesor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFA9B1BF)
                        : const Color(0xFF6B7280),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelHeader({
    required bool oscuro,
    required String label,
    required String title,
    required String action,
    required VoidCallback onPressed,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: oscuro
                      ? const Color(0xFF8993A2)
                      : const Color(0xFF6B7280),
                  fontSize: 10.5,
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
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),

        AppPressable(
          child: TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              action,
              style: const TextStyle(
                color: _primaryColor,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================
  // TARJETA BASE
  // =========================================================

  Widget _buildSimpleCard({
    Key? key,
    required bool oscuro,
    required Widget child,
    double radius = 20,
    double padding = 20,
    Color? borderColor,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: oscuro ? const Color(0xFF191F29) : Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color:
              borderColor ??
              (oscuro ? const Color(0xFF2B323E) : const Color(0xFFE7EAF0)),
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
      ),
      child: child,
    );
  }
}

// ===========================================================
// ACCIONES MENÚ PERFIL
// ===========================================================

enum _ProfileAction { perfil, asignaturas, tareas, ajustes, logout }
