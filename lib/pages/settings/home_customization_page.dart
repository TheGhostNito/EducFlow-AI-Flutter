import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/home_preferences_service.dart';
import '../../services/translation_service.dart';
import '../../widgets/app_pressable.dart';
import '../../widgets/app_reveal.dart';
import '../../widgets/app_scroll_header.dart';
import '../../widgets/app_status_snackbar.dart';

class HomeCustomizationPage extends StatefulWidget {
  const HomeCustomizationPage({super.key});

  @override
  State<HomeCustomizationPage> createState() => _HomeCustomizationPageState();
}

class _HomeCustomizationPageState extends State<HomeCustomizationPage> {
  static const Color _primaryColor = Color(0xFF5B5FEF);

  final HomePreferencesService _preferencesService =
      HomePreferencesService.instance;
  final TranslationService _translationService = TranslationService.instance;
  final ScrollController _scrollController = ScrollController();

  HomePreferences _preferences = HomePreferences.defaults;
  bool _loading = true;
  bool _saving = false;
  double _headerProgress = 0;

  bool get _spanish => _translationService.isSpanish;

  @override
  void initState() {
    super.initState();
    _translationService.addListener(_refresh);
    _scrollController.addListener(_listenScroll);
    _load();
  }

  @override
  void dispose() {
    _translationService.removeListener(_refresh);
    _scrollController.removeListener(_listenScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _listenScroll() {
    if (!_scrollController.hasClients) return;
    final double progress = ((_scrollController.offset - 45) / 100).clamp(
      0.0,
      1.0,
    );
    if ((progress - _headerProgress).abs() < 0.01) return;
    setState(() => _headerProgress = progress);
  }

  Future<void> _load() async {
    final HomePreferences preferences = await _preferencesService.loadCurrent(
      forceRefresh: true,
    );
    if (!mounted) return;
    setState(() {
      _preferences = preferences;
      _loading = false;
    });
  }

  Future<void> _save(HomePreferences next) async {
    if (_saving) return;
    final HomePreferences previous = _preferences;
    setState(() {
      _preferences = next;
      _saving = true;
    });

    try {
      await _preferencesService.saveCurrent(next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _preferences = previous);
      showAppStatusSnackBar(
        context,
        message: _spanish
            ? 'No pudimos guardar la configuración del Inicio.'
            : 'We could not save your Home settings.',
        type: AppStatusType.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    HapticFeedback.selectionClick();
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            final bool dark =
                Theme.of(dialogContext).brightness == Brightness.dark;
            return AlertDialog(
              backgroundColor: dark ? const Color(0xFF191E27) : Colors.white,
              title: Text(_spanish ? '¿Restablecer Inicio?' : 'Reset Home?'),
              content: Text(
                _spanish
                    ? 'Todas las secciones volverán a mostrarse.'
                    : 'All sections will be shown again.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(_spanish ? 'Cancelar' : 'Cancel'),
                ),
                FilledButton(
                  key: const Key('confirm-reset-home'),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  style: FilledButton.styleFrom(backgroundColor: _primaryColor),
                  child: Text(_spanish ? 'Restablecer' : 'Reset'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed || !mounted) return;
    await _save(HomePreferences.defaults);
  }

  void _back() {
    HapticFeedback.selectionClick();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double horizontal = constraints.maxWidth <= 560
                      ? 10
                      : constraints.maxWidth <= 800
                      ? 24
                      : 40;
                  return ListView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      constraints.maxWidth <= 560 ? 24 : 32,
                      horizontal,
                      60,
                    ),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 800),
                          child: _buildHeader(dark),
                        ),
                      ),
                      const SizedBox(height: 30),
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 800),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppReveal(child: _buildExplanationCard(dark)),
                              const SizedBox(height: 26),
                              AppReveal(
                                delay: const Duration(milliseconds: 70),
                                child: _buildOptions(dark),
                              ),
                              const SizedBox(height: 22),
                              AppReveal(
                                delay: const Duration(milliseconds: 140),
                                child: _buildResetButton(dark),
                              ),
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
              progress: _headerProgress,
              title: _spanish ? 'Personalizar Inicio' : 'Customize Home',
              leading: _buildCompactBackButton(dark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool dark) {
    return Transform.translate(
      offset: Offset(0, -10 * _headerProgress),
      child: Opacity(
        opacity: 1 - _headerProgress,
        child: Row(
          children: [
            AppPressable(scale: 0.86, child: _buildBackButton(dark)),
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
                    _spanish ? 'Personalizar Inicio' : 'Customize Home',
                    style: TextStyle(
                      color: dark
                          ? const Color(0xFFF8FAFC)
                          : const Color(0xFF111827),
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
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

  Widget _buildExplanationCard(bool dark) {
    return _card(
      dark,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMiniHomeDemo(dark),
          const SizedBox(height: 18),
          Text(
            _spanish
                ? 'Elige qué información quieres ver en tu Inicio. Puedes mostrar u ocultar secciones según lo que sea más importante para ti.'
                : 'Choose what information appears on Home. Show or hide sections based on what matters most to you.',
            style: TextStyle(
              color: dark ? const Color(0xFFF1F5F9) : const Color(0xFF1F2937),
              fontSize: 15,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _spanish
                ? 'Esta opción solo modifica el contenido que aparece en Inicio. No cambia los colores ni el diseño general de la aplicación.'
                : 'This only changes the content shown on Home. It does not change the app colors or overall design.',
            style: TextStyle(
              color: dark ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniHomeDemo(bool dark) {
    Widget preview(List<double> blocks) {
      return Expanded(
        child: Container(
          height: 112,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF222833) : const Color(0xFFF7F8FB),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: dark ? const Color(0xFF303744) : const Color(0xFFE4E7ED),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 36,
                height: 5,
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: _primaryColor,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 9),
              for (int index = 0; index < blocks.length; index++) ...[
                Container(
                  height: blocks[index],
                  decoration: BoxDecoration(
                    color: index == 0
                        ? _primaryColor.withValues(alpha: dark ? 0.24 : 0.12)
                        : (dark
                              ? const Color(0xFF303744)
                              : const Color(0xFFE7EAF0)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                if (index < blocks.length - 1) const SizedBox(height: 6),
              ],
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        preview(const [18, 18, 18]),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Icon(Icons.arrow_forward_rounded, color: _primaryColor),
        ),
        preview(const [28]),
      ],
    );
  }

  Widget _buildOptions(bool dark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 9),
          child: Text(
            _spanish ? 'INFORMACIÓN ACADÉMICA' : 'ACADEMIC INFORMATION',
            style: TextStyle(
              color: dark ? const Color(0xFF9BA3B2) : const Color(0xFF6B7280),
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
            ),
          ),
        ),
        _card(
          dark,
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(
                    child: CircularProgressIndicator(color: _primaryColor),
                  ),
                )
              : Column(
                  children: [
                    _option(
                      dark: dark,
                      key: const Key('home-summary-switch'),
                      icon: Icons.grid_view_rounded,
                      title: _spanish
                          ? 'Resumen académico'
                          : 'Academic summary',
                      description: _spanish
                          ? 'Asignaturas, clases de hoy y próxima clase.'
                          : 'Subjects, today’s classes and next class.',
                      value: _preferences.summaryVisible,
                      onChanged: (value) =>
                          _save(_preferences.copyWith(summaryVisible: value)),
                    ),
                    _divider(dark),
                    _option(
                      dark: dark,
                      key: const Key('home-classes-switch'),
                      icon: Icons.today_outlined,
                      title: _spanish ? 'Clases de hoy' : 'Today’s classes',
                      description: _spanish
                          ? 'Detalle de tus bloques programados para hoy.'
                          : 'Details of your scheduled blocks for today.',
                      value: _preferences.todayClassesVisible,
                      onChanged: (value) => _save(
                        _preferences.copyWith(todayClassesVisible: value),
                      ),
                    ),
                    _divider(dark),
                    _option(
                      dark: dark,
                      key: const Key('home-subjects-switch'),
                      icon: Icons.menu_book_outlined,
                      title: _spanish ? 'Mis asignaturas' : 'My subjects',
                      description: _spanish
                          ? 'Lista breve de tus asignaturas registradas.'
                          : 'A short list of your registered subjects.',
                      value: _preferences.subjectsVisible,
                      onChanged: (value) =>
                          _save(_preferences.copyWith(subjectsVisible: value)),
                    ),
                    _divider(dark),
                    _option(
                      dark: dark,
                      key: const Key('home-next-task-switch'),
                      icon: Icons.assignment_outlined,
                      title: _spanish ? 'Próxima tarea' : 'Next task',
                      description: _spanish
                          ? 'Tu entrega pendiente más cercana.'
                          : 'Your nearest pending deadline.',
                      value: _preferences.nextTaskVisible,
                      onChanged: (value) =>
                          _save(_preferences.copyWith(nextTaskVisible: value)),
                    ),
                    _divider(dark),
                    _option(
                      dark: dark,
                      key: const Key('home-next-evaluation-switch'),
                      icon: Icons.school_outlined,
                      title: _spanish
                          ? 'Próxima evaluación'
                          : 'Next evaluation',
                      description: _spanish
                          ? 'La siguiente evaluación de tu calendario.'
                          : 'The next evaluation on your calendar.',
                      value: _preferences.nextEvaluationVisible,
                      onChanged: (value) => _save(
                        _preferences.copyWith(nextEvaluationVisible: value),
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 26),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 9),
          child: Text(
            _spanish ? 'ASISTENCIA INTELIGENTE' : 'SMART ASSISTANCE',
            style: TextStyle(
              color: dark ? const Color(0xFF9BA3B2) : const Color(0xFF6B7280),
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
            ),
          ),
        ),
        _card(
          dark,
          child: _option(
            dark: dark,
            key: const Key('home-smart-summary-switch'),
            icon: Icons.auto_awesome_outlined,
            title: _spanish ? 'Resumen inteligente' : 'Smart summary',
            description: _spanish
                ? 'Muestra una prioridad académica cuando sea relevante.'
                : 'Shows an academic priority when it is relevant.',
            value: _preferences.smartSummaryVisible,
            onChanged: (value) =>
                _save(_preferences.copyWith(smartSummaryVisible: value)),
          ),
        ),
      ],
    );
  }

  Widget _option({
    required bool dark,
    required Key key,
    required IconData icon,
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF2B3047) : const Color(0xFFEEF0FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: _primaryColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: dark
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF1F2937),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: dark
                        ? const Color(0xFF9BA3B2)
                        : const Color(0xFF6B7280),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Switch.adaptive(
            key: key,
            value: value,
            activeTrackColor: _primaryColor,
            activeThumbColor: Colors.white,
            onChanged: _saving ? null : onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildResetButton(bool dark) {
    return AppPressable(
      scale: 0.98,
      child: OutlinedButton.icon(
        key: const Key('reset-home'),
        onPressed: _loading || _saving ? null : _reset,
        icon: const Icon(Icons.restart_alt_rounded),
        label: Text(_spanish ? 'Restablecer Inicio' : 'Reset Home'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          foregroundColor: _primaryColor,
          side: BorderSide(
            color: dark ? const Color(0xFF42496D) : const Color(0xFFD7DAFF),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _card(
    bool dark, {
    required Widget child,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF191E27) : Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: dark ? const Color(0xFF2A303B) : const Color(0xFFE7EAF0),
        ),
        boxShadow: dark
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

  Widget _divider(bool dark) {
    return Divider(
      height: 1,
      indent: 78,
      color: dark ? const Color(0xFF2A303B) : const Color(0xFFE7EAF0),
    );
  }

  Widget _buildBackButton(bool dark) {
    return InkWell(
      onTap: _back,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF191E27) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: dark ? const Color(0xFF2A303B) : const Color(0xFFE2E6ED),
          ),
        ),
        child: Icon(
          Icons.chevron_left_rounded,
          color: dark ? const Color(0xFFE7EAF0) : const Color(0xFF374151),
        ),
      ),
    );
  }

  Widget _buildCompactBackButton(bool dark) {
    return AppPressable(
      scale: 0.86,
      child: GestureDetector(
        onTap: _back,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF222833) : const Color(0xFFF4F5F8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: dark ? const Color(0xFF303744) : const Color(0xFFE2E6ED),
            ),
          ),
          child: Icon(
            Icons.chevron_left_rounded,
            color: dark ? const Color(0xFFE7EAF0) : const Color(0xFF374151),
          ),
        ),
      ),
    );
  }
}
