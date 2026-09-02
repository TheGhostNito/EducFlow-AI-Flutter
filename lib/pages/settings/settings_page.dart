import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import '../../services/notification_service.dart';
import '../../services/theme_service.dart';
import '../../services/translation_service.dart';
import '../../widgets/app_pressable.dart';
import '../../widgets/app_reveal.dart';
import '../../widgets/app_scroll_header.dart';
import '../../services/time_format_service.dart';
import 'notification_preferences_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  final ThemeService _themeService = ThemeService.instance;

  final TranslationService _translationService = TranslationService.instance;

  final NotificationService _notificationService = NotificationService.instance;

  final ScrollController _scrollController = ScrollController();

  final TimeFormatService _timeFormatService = TimeFormatService.instance;

  static const Color _primaryColor = Color(0xFF5B5FEF);

  double _progresoHeader = 0;

  EstadoNotificaciones _estadoNotificaciones =
      EstadoNotificaciones.noSolicitadas;

  bool _cargandoNotificaciones = true;
  bool _procesandoNotificaciones = false;

  bool get _espanol => _translationService.isSpanish;

  // =========================================================
  // CICLO DE VIDA
  // =========================================================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _translationService.addListener(_actualizarPantalla);

    _themeService.addListener(_actualizarPantalla);

    _timeFormatService.addListener(_actualizarPantalla);

    _scrollController.addListener(_escucharScroll);

    _actualizarEstadoNotificaciones();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _translationService.removeListener(_actualizarPantalla);

    _timeFormatService.removeListener(_actualizarPantalla);

    _themeService.removeListener(_actualizarPantalla);

    _scrollController.removeListener(_escucharScroll);

    _scrollController.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _actualizarEstadoNotificaciones(silencioso: true);
    }
  }

  void _actualizarPantalla() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  // =========================================================
  // SCROLL / HEADER
  // =========================================================

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
  // NAVEGACIÓN
  // =========================================================

  void _volver() {
    HapticFeedback.selectionClick();

    Navigator.of(context).maybePop();
  }

  Future<void> _abrirPreferenciasNotificaciones() async {
    HapticFeedback.selectionClick();

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationPreferencesPage()),
    );
  }

  // =========================================================
  // TEMA
  // =========================================================

  Future<void> _cambiarTema(bool enabled) async {
    HapticFeedback.selectionClick();

    await _themeService.setDarkMode(enabled);
  }

  // =========================================================
  // IDIOMA
  // =========================================================

  Future<void> _cambiarIdioma(AppLanguage language) async {
    HapticFeedback.selectionClick();

    await _translationService.changeLanguage(language);
  }

  String _nombreIdioma(AppLanguage language) {
    switch (language) {
      case AppLanguage.es:
        return _espanol ? 'Español' : 'Spanish';

      case AppLanguage.en:
        return _espanol ? 'Inglés' : 'English';
    }
  }

  // =========================================================
  // FORMATO DE HORA
  // =========================================================

  Future<void> _cambiarFormatoHora(TimeFormatPreference preference) async {
    HapticFeedback.selectionClick();

    await _timeFormatService.setPreference(preference);
  }

  String _nombreFormatoHora(TimeFormatPreference preference) {
    switch (preference) {
      case TimeFormatPreference.system:
        return _espanol ? 'Según el dispositivo' : 'Device setting';

      case TimeFormatPreference.h24:
        return _espanol ? '24 horas' : '24-hour';

      case TimeFormatPreference.h12:
        return _espanol ? '12 horas (AM/PM)' : '12-hour (AM/PM)';
    }
  }

  String _etiquetaCortaFormatoHora(TimeFormatPreference preference) {
    switch (preference) {
      case TimeFormatPreference.system:
        return _espanol ? 'Dispositivo' : 'Device';

      case TimeFormatPreference.h24:
        return '24 h';

      case TimeFormatPreference.h12:
        return '12 h';
    }
  }

  String _ejemploFormatoHora(TimeFormatPreference preference) {
    switch (preference) {
      case TimeFormatPreference.system:
        return _timeFormatService.formatStoredTime(context, '14:30');

      case TimeFormatPreference.h24:
        return '14:30';

      case TimeFormatPreference.h12:
        return '2:30 PM';
    }
  }

  Future<void> _abrirSelectorFormatoHora() async {
    HapticFeedback.selectionClick();

    final TimeFormatPreference? seleccion =
        await showModalBottomSheet<TimeFormatPreference>(
          context: context,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black.withValues(alpha: 0.78),
          builder: (sheetContext) {
            final bool oscuro =
                Theme.of(sheetContext).brightness == Brightness.dark;

            final TimeFormatPreference actual = _timeFormatService.preference;

            return Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 22),
              decoration: BoxDecoration(
                color: oscuro ? const Color(0xFF18181D) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                border: Border(
                  top: BorderSide(
                    color: oscuro
                        ? const Color(0xFF303038)
                        : const Color(0xFFE7EAF0),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: oscuro
                            ? const Color(0xFF4B4B53)
                            : const Color(0xFFD5D9E0),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _espanol ? 'FORMATO DE HORA' : 'TIME FORMAT',
                                style: const TextStyle(
                                  color: _primaryColor,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                ),
                              ),

                              const SizedBox(height: 5),

                              Text(
                                _espanol
                                    ? 'Cómo mostrar la hora'
                                    : 'How time is displayed',
                                style: TextStyle(
                                  color: oscuro
                                      ? const Color(0xFFF8FAFC)
                                      : const Color(0xFF111827),
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),

                              const SizedBox(height: 5),

                              Text(
                                _espanol
                                    ? 'Esto solo cambia cómo ves las horas. Tus datos se guardan de la misma forma.'
                                    : 'This only changes how times are displayed. Your data is stored the same way.',
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

                        IconButton(
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                          },
                          style: IconButton.styleFrom(
                            backgroundColor: oscuro
                                ? const Color(0xFF24242A)
                                : const Color(0xFFF3F4F7),
                          ),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  for (final TimeFormatPreference preference
                      in TimeFormatPreference.values) ...[
                    _buildTimeFormatOption(
                      context: sheetContext,
                      oscuro: oscuro,
                      preference: preference,
                      selected: preference == actual,
                    ),

                    if (preference != TimeFormatPreference.values.last)
                      const SizedBox(height: 9),
                  ],
                ],
              ),
            );
          },
        );

    if (seleccion == null) {
      return;
    }

    await _cambiarFormatoHora(seleccion);
  }

  Widget _buildTimeFormatOption({
    required BuildContext context,
    required bool oscuro,
    required TimeFormatPreference preference,
    required bool selected,
  }) {
    return AppPressable(
      scale: 0.985,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();

          Navigator.of(context).pop(preference);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? (oscuro ? const Color(0xFF292936) : const Color(0xFFEEF0FF))
                : (oscuro ? const Color(0xFF222229) : const Color(0xFFFAFBFC)),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected
                  ? _primaryColor
                  : (oscuro
                        ? const Color(0xFF34343C)
                        : const Color(0xFFE7EAF0)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: oscuro
                      ? const Color(0xFF292936)
                      : const Color(0xFFEEF0FF),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  preference == TimeFormatPreference.system
                      ? Icons.phone_android_rounded
                      : Icons.schedule_rounded,
                  color: _primaryColor,
                  size: 20,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _nombreFormatoHora(preference),
                            style: TextStyle(
                              color: oscuro
                                  ? const Color(0xFFF8FAFC)
                                  : const Color(0xFF1F2937),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),

                        if (preference == TimeFormatPreference.system) ...[
                          const SizedBox(width: 7),

                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _primaryColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _espanol ? 'Recomendado' : 'Recommended',
                              style: const TextStyle(
                                color: _primaryColor,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 4),

                    Text(
                      preference == TimeFormatPreference.system
                          ? (_espanol
                                ? 'Usa la configuración actual de tu dispositivo.'
                                : 'Uses your device\'s current setting.')
                          : (_espanol
                                ? 'Ejemplo: ${_ejemploFormatoHora(preference)}'
                                : 'Example: ${_ejemploFormatoHora(preference)}'),
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFA9B1BF)
                            : const Color(0xFF6B7280),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: _primaryColor,
                  size: 22,
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: oscuro
                      ? const Color(0xFF7F899A)
                      : const Color(0xFF9CA3AF),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeFormatSection(bool oscuro) {
    return _buildSection(
      oscuro: oscuro,
      label: _espanol ? 'FORMATO DE HORA' : 'TIME FORMAT',
      child: _buildSettingsCard(
        oscuro: oscuro,
        child: AppPressable(
          scale: 0.99,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _abrirSelectorFormatoHora,
            child: _buildSettingRow(
              oscuro: oscuro,
              icon: Ionicons.timeOutline,
              iconColor: const Color(0xFF5B5FEF),
              iconBackground: oscuro
                  ? const Color(0xFF292936)
                  : const Color(0xFFEEF0FF),
              title: _espanol ? 'Formato de hora' : 'Time format',
              description: _espanol
                  ? 'Elige cómo se muestran las horas en toda la aplicación.'
                  : 'Choose how time is displayed throughout the application.',
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: oscuro
                      ? const Color(0xFF222833)
                      : const Color(0xFFFAFBFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: oscuro
                        ? const Color(0xFF303744)
                        : const Color(0xFFDFE3EA),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _etiquetaCortaFormatoHora(_timeFormatService.preference),
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFE7EAF0)
                            : const Color(0xFF374151),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(width: 5),

                    const Icon(
                      Icons.chevron_right_rounded,
                      color: _primaryColor,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================
  // NOTIFICACIONES
  // =========================================================

  Future<void> _actualizarEstadoNotificaciones({
    bool silencioso = false,
  }) async {
    if (!silencioso && mounted) {
      setState(() {
        _cargandoNotificaciones = true;
      });
    }

    final EstadoNotificaciones estado = await _notificationService
        .obtenerEstado();

    if (!mounted) {
      return;
    }

    setState(() {
      _estadoNotificaciones = estado;
      _cargandoNotificaciones = false;
    });
  }

  Future<void> _accionNotificaciones() async {
    if (_procesandoNotificaciones || _cargandoNotificaciones) {
      return;
    }

    HapticFeedback.selectionClick();

    switch (_estadoNotificaciones) {
      case EstadoNotificaciones.activadas:
        return;

      case EstadoNotificaciones.bloqueadas:
        await _notificationService.abrirAjustesDelSistema();

        return;

      case EstadoNotificaciones.noCompatibles:
        return;

      case EstadoNotificaciones.noSolicitadas:
        break;
    }

    setState(() {
      _procesandoNotificaciones = true;
    });

    try {
      final EstadoNotificaciones estado = await _notificationService
          .solicitarPermiso();

      if (!mounted) {
        return;
      }

      setState(() {
        _estadoNotificaciones = estado;
      });

      if (estado == EstadoNotificaciones.activadas) {
        await Future<void>.delayed(const Duration(milliseconds: 350));

        await _notificationService.mostrarNotificacionPrueba(espanol: _espanol);
      }
    } finally {
      if (mounted) {
        setState(() {
          _procesandoNotificaciones = false;
        });
      }
    }
  }

  String get _textoEstadoNotificaciones {
    if (_cargandoNotificaciones || _procesandoNotificaciones) {
      return _espanol ? 'Comprobando...' : 'Checking...';
    }

    switch (_estadoNotificaciones) {
      case EstadoNotificaciones.activadas:
        return _espanol ? 'Activadas' : 'Enabled';

      case EstadoNotificaciones.bloqueadas:
        return _espanol ? 'Bloqueadas' : 'Blocked';

      case EstadoNotificaciones.noSolicitadas:
        return _espanol ? 'Activar' : 'Enable';

      case EstadoNotificaciones.noCompatibles:
        return _espanol ? 'No disponible' : 'Unavailable';
    }
  }

  String get _descripcionNotificaciones {
    if (_estadoNotificaciones == EstadoNotificaciones.bloqueadas) {
      return _espanol
          ? 'Las notificaciones están bloqueadas. Toca el botón para abrir los ajustes del dispositivo.'
          : 'Notifications are blocked. Tap the button to open your device settings.';
    }

    if (_estadoNotificaciones == EstadoNotificaciones.noCompatibles) {
      return _espanol
          ? 'Las notificaciones no están disponibles en este dispositivo.'
          : 'Notifications are not available on this device.';
    }

    return _espanol
        ? 'Recibe avisos sobre clases, tareas y recordatorios importantes.'
        : 'Receive alerts about classes, tasks and important reminders.';
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double ancho = constraints.maxWidth;

                  final double horizontal = ancho <= 560
                      ? 10
                      : ancho <= 800
                      ? 24
                      : 40;

                  return ListView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      ancho <= 560 ? 24 : 32,
                      horizontal,
                      60,
                    ),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 800),
                          child: _buildHeader(oscuro),
                        ),
                      ),

                      const SizedBox(height: 30),

                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 800),
                          child: Column(
                            children: [
                              AppReveal(child: _buildAppearanceSection(oscuro)),

                              const SizedBox(height: 26),

                              AppReveal(
                                delay: const Duration(milliseconds: 70),
                                child: _buildLanguageSection(oscuro, ancho),
                              ),

                              const SizedBox(height: 26),

                              AppReveal(
                                delay: const Duration(milliseconds: 140),
                                child: _buildTimeFormatSection(oscuro),
                              ),

                              const SizedBox(height: 26),

                              AppReveal(
                                delay: const Duration(milliseconds: 210),
                                child: _buildNotificationsSection(oscuro),
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
              progress: _progresoHeader,
              title: _espanol ? 'Ajustes' : 'Settings',
              leading: _buildCompactBackButton(oscuro),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // HEADER GRANDE
  // =========================================================

  Widget _buildHeader(bool oscuro) {
    return Transform.translate(
      offset: Offset(0, -10 * _progresoHeader),
      child: Transform.scale(
        alignment: Alignment.topLeft,
        scale: 1 - (0.015 * _progresoHeader),
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
                      _espanol ? 'Ajustes' : 'Settings',
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF111827),
                        fontSize: 34,
                        height: 1.08,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      _espanol
                          ? 'Personaliza la apariencia y las preferencias de EducFlow AI.'
                          : 'Customize the appearance and preferences of EducFlow AI.',
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFF9BA3B2)
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
      ),
    );
  }

  Widget _buildBackButton(bool oscuro) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _volver,
        borderRadius: BorderRadius.circular(15),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: oscuro ? const Color(0xFF191E27) : Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: oscuro ? const Color(0xFF2A303B) : const Color(0xFFE2E6ED),
            ),
            boxShadow: oscuro
                ? const []
                : const [
                    BoxShadow(
                      color: Color(0x0E0F172A),
                      blurRadius: 17,
                      offset: Offset(0, 6),
                    ),
                  ],
          ),
          child: Icon(
            Ionicons.chevronBackOutline,
            color: oscuro ? const Color(0xFFE7EAF0) : const Color(0xFF374151),
            size: 22,
          ),
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
            color: oscuro ? const Color(0xFF222833) : const Color(0xFFF4F5F8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: oscuro ? const Color(0xFF303744) : const Color(0xFFE2E6ED),
            ),
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

  // =========================================================
  // APARIENCIA
  // =========================================================

  Widget _buildAppearanceSection(bool oscuro) {
    return _buildSection(
      oscuro: oscuro,
      label: _espanol ? 'APARIENCIA' : 'APPEARANCE',
      child: _buildSettingsCard(
        oscuro: oscuro,
        child: _buildSettingRow(
          oscuro: oscuro,
          icon: Ionicons.moonOutline,
          iconColor: const Color(0xFF7C3AED),
          iconBackground: oscuro
              ? const Color(0xFF302446)
              : const Color(0xFFF1EBFF),
          title: _espanol ? 'Modo oscuro' : 'Dark mode',
          description: _espanol
              ? 'Utiliza colores oscuros en toda la aplicación.'
              : 'Use darker colors throughout the application.',
          trailing: Switch.adaptive(
            value: _themeService.isDarkMode,
            activeTrackColor: _primaryColor,
            activeThumbColor: Colors.white,
            onChanged: _cambiarTema,
          ),
        ),
      ),
    );
  }

  // =========================================================
  // IDIOMA
  // =========================================================

  Widget _buildLanguageSection(bool oscuro, double ancho) {
    final bool movil = ancho <= 560;

    final Widget selector = _buildLanguageSelector(oscuro, expand: movil);

    return _buildSection(
      oscuro: oscuro,
      label: _espanol ? 'IDIOMA' : 'LANGUAGE',
      child: _buildSettingsCard(
        oscuro: oscuro,
        child: movil
            ? Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildSettingIcon(
                          icon: Ionicons.languageOutline,
                          color: const Color(0xFF2563EB),
                          background: oscuro
                              ? const Color(0xFF1E3150)
                              : const Color(0xFFEAF2FF),
                          size: 45,
                        ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: _buildSettingInformation(
                            oscuro: oscuro,
                            title: _espanol
                                ? 'Idioma de la aplicación'
                                : 'Application language',
                            description: _espanol
                                ? 'Selecciona el idioma utilizado por la interfaz.'
                                : 'Choose the language used by the interface.',
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    Padding(
                      padding: const EdgeInsets.only(left: 57),
                      child: selector,
                    ),
                  ],
                ),
              )
            : _buildSettingRow(
                oscuro: oscuro,
                icon: Ionicons.languageOutline,
                iconColor: const Color(0xFF2563EB),
                iconBackground: oscuro
                    ? const Color(0xFF1E3150)
                    : const Color(0xFFEAF2FF),
                title: _espanol
                    ? 'Idioma de la aplicación'
                    : 'Application language',
                description: _espanol
                    ? 'Selecciona el idioma utilizado por la interfaz.'
                    : 'Choose the language used by the interface.',
                trailing: selector,
              ),
      ),
    );
  }

  Widget _buildLanguageSelector(bool oscuro, {required bool expand}) {
    final AppLanguage actual = _translationService.currentLanguage;

    final AppLanguage alternativa = actual == AppLanguage.es
        ? AppLanguage.en
        : AppLanguage.es;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double anchoSelector = expand ? constraints.maxWidth : 150;

        return SizedBox(
          width: anchoSelector,
          child: MenuAnchor(
            crossAxisUnconstrained: false,
            alignmentOffset: const Offset(0, 7),
            style: MenuStyle(
              backgroundColor: WidgetStatePropertyAll(
                oscuro ? const Color(0xFF191E27) : Colors.white,
              ),
              surfaceTintColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
              elevation: const WidgetStatePropertyAll(12),
              padding: const WidgetStatePropertyAll(EdgeInsets.all(5)),
              minimumSize: WidgetStatePropertyAll(Size(anchoSelector, 0)),
              maximumSize: WidgetStatePropertyAll(
                Size(anchoSelector, double.infinity),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                  side: BorderSide(
                    color: oscuro
                        ? const Color(0xFF303744)
                        : const Color(0xFFE1E5EC),
                  ),
                ),
              ),
            ),
            menuChildren: [
              MenuItemButton(
                onPressed: () {
                  _cambiarIdioma(alternativa);
                },
                style: ButtonStyle(
                  minimumSize: const WidgetStatePropertyAll(Size(0, 42)),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 11),
                  ),
                  backgroundColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  foregroundColor: WidgetStatePropertyAll(
                    oscuro ? const Color(0xFFE7EAF0) : const Color(0xFF374151),
                  ),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
                trailingIcon: const Icon(
                  Ionicons.languageOutline,
                  color: _primaryColor,
                  size: 17,
                ),
                child: Text(
                  _nombreIdioma(alternativa),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            builder: (context, controller, child) {
              return AppPressable(
                scale: 0.96,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (controller.isOpen) {
                      controller.close();
                    } else {
                      controller.open();
                    }
                  },
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    decoration: BoxDecoration(
                      color: oscuro
                          ? const Color(0xFF222833)
                          : const Color(0xFFFAFBFC),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: oscuro
                            ? const Color(0xFF303744)
                            : const Color(0xFFDFE3EA),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _nombreIdioma(actual),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: oscuro
                                  ? const Color(0xFFE7EAF0)
                                  : const Color(0xFF374151),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        AnimatedRotation(
                          turns: controller.isOpen ? 0.5 : 0,
                          duration: const Duration(milliseconds: 180),
                          curve: const Cubic(0.22, 1, 0.36, 1),
                          child: Icon(
                            Ionicons.chevronDownOutline,
                            color: oscuro
                                ? const Color(0xFF9BA3B2)
                                : const Color(0xFF8B91A0),
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // =========================================================
  // NOTIFICACIONES
  // =========================================================

  Widget _buildNotificationsSection(bool oscuro) {
    final bool activadas =
        _estadoNotificaciones == EstadoNotificaciones.activadas;

    final bool bloqueadas =
        _estadoNotificaciones == EstadoNotificaciones.bloqueadas;

    return _buildSection(
      oscuro: oscuro,
      label: _espanol ? 'NOTIFICACIONES' : 'NOTIFICATIONS',
      child: _buildSettingsCard(
        oscuro: oscuro,
        child: Column(
          children: [
            _buildSettingRow(
              oscuro: oscuro,
              icon: activadas
                  ? Ionicons.notifications
                  : Ionicons.notificationsOutline,
              iconColor: activadas
                  ? const Color(0xFF059669)
                  : bloqueadas
                  ? const Color(0xFFDC2626)
                  : _primaryColor,
              iconBackground: activadas
                  ? (oscuro ? const Color(0xFF183A34) : const Color(0xFFE8F8F2))
                  : bloqueadas
                  ? (oscuro ? const Color(0xFF3A2328) : const Color(0xFFFEECEC))
                  : (oscuro
                        ? const Color(0xFF2B3047)
                        : const Color(0xFFEEF0FF)),
              title: _espanol ? 'Notificaciones' : 'Notifications',
              description: _descripcionNotificaciones,
              trailing: _buildNotificationButton(oscuro),
            ),
            Divider(
              height: 1,
              color: oscuro ? const Color(0xFF2A303B) : const Color(0xFFE7EAF0),
            ),
            AppPressable(
              scale: 0.99,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _abrirPreferenciasNotificaciones,
                child: _buildSettingRow(
                  oscuro: oscuro,
                  icon: Icons.tune_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  iconBackground: oscuro
                      ? const Color(0xFF302446)
                      : const Color(0xFFF1EBFF),
                  title: _espanol
                      ? 'Preferencias de notificaciones'
                      : 'Notification preferences',
                  description: _espanol
                      ? 'Elige qué avisos recibir y con cuánta anticipación.'
                      : 'Choose which alerts to receive and when.',
                  trailing: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: oscuro
                          ? const Color(0xFF222833)
                          : const Color(0xFFFAFBFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: oscuro
                            ? const Color(0xFF303744)
                            : const Color(0xFFDFE3EA),
                      ),
                    ),
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      color: _primaryColor,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationButton(bool oscuro) {
    final bool activadas =
        _estadoNotificaciones == EstadoNotificaciones.activadas;

    final bool bloqueadas =
        _estadoNotificaciones == EstadoNotificaciones.bloqueadas;

    final bool disponible =
        _estadoNotificaciones != EstadoNotificaciones.noCompatibles;

    Color foreground;
    Color background;
    Color border;

    if (activadas) {
      foreground = const Color(0xFF059669);

      background = oscuro ? const Color(0xFF183A34) : const Color(0xFFE8F8F2);

      border = oscuro ? const Color(0xFF26584E) : const Color(0xFFBEE9DA);
    } else if (bloqueadas) {
      foreground = const Color(0xFFDC2626);

      background = oscuro ? const Color(0xFF3A2328) : const Color(0xFFFEECEC);

      border = oscuro ? const Color(0xFF5C343C) : const Color(0xFFF5C8C8);
    } else {
      foreground = _primaryColor;

      background = oscuro ? const Color(0xFF2B3047) : const Color(0xFFEEF0FF);

      border = oscuro ? const Color(0xFF42496D) : const Color(0xFFD7DAFF);
    }

    return AppPressable(
      scale: 0.94,
      child: TextButton(
        onPressed: disponible && !activadas && !_procesandoNotificaciones
            ? _accionNotificaciones
            : null,
        style: TextButton.styleFrom(
          minimumSize: const Size(84, 42),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          backgroundColor: background,
          foregroundColor: foreground,
          disabledForegroundColor: foreground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: border),
          ),
        ),
        child: Text(
          _textoEstadoNotificaciones,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  // =========================================================
  // COMPONENTES BASE
  // =========================================================

  Widget _buildSection({
    required bool oscuro,
    required String label,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 9),
          child: Text(
            label,
            style: TextStyle(
              color: oscuro ? const Color(0xFF9BA3B2) : const Color(0xFF6B7280),
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
            ),
          ),
        ),

        child,
      ],
    );
  }

  Widget _buildSettingsCard({required bool oscuro, required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: oscuro ? const Color(0xFF191E27) : Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: oscuro ? const Color(0xFF2A303B) : const Color(0xFFE7EAF0),
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

  Widget _buildSettingRow({
    required bool oscuro,
    required IconData icon,
    required Color iconColor,
    required Color iconBackground,
    required String title,
    required String description,
    required Widget trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Row(
        children: [
          _buildSettingIcon(
            icon: icon,
            color: iconColor,
            background: iconBackground,
          ),

          const SizedBox(width: 15),

          Expanded(
            child: _buildSettingInformation(
              oscuro: oscuro,
              title: title,
              description: description,
            ),
          ),

          const SizedBox(width: 12),

          trailing,
        ],
      ),
    );
  }

  Widget _buildSettingIcon({
    required IconData icon,
    required Color color,
    required Color background,
    double size = 48,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Icon(icon, color: color, size: 23),
    );
  }

  Widget _buildSettingInformation({
    required bool oscuro,
    required String title,
    required String description,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: oscuro ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),

        const SizedBox(height: 5),

        Text(
          description,
          style: TextStyle(
            color: oscuro ? const Color(0xFF9BA3B2) : const Color(0xFF6B7280),
            fontSize: 13.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
