import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import '../../services/academic_notification_scheduler.dart';
import '../../services/time_format_service.dart';
import '../../services/translation_service.dart';
import '../../services/user_preferences_service.dart';
import '../../widgets/app_pressable.dart';
import '../../widgets/app_scroll_header.dart';
import '../../widgets/app_status_snackbar.dart';

class NotificationPreferencesPage extends StatefulWidget {
  const NotificationPreferencesPage({super.key});

  @override
  State<NotificationPreferencesPage> createState() =>
      _NotificationPreferencesPageState();
}

class _NotificationPreferencesPageState
    extends State<NotificationPreferencesPage> {
  static const Color _primaryColor = Color(0xFF5B5FEF);

  final UserPreferencesService _preferencesService =
      UserPreferencesService.instance;
  final AcademicNotificationScheduler _scheduler =
      AcademicNotificationScheduler.instance;
  final TranslationService _translationService = TranslationService.instance;
  final TimeFormatService _timeFormatService = TimeFormatService.instance;
  final ScrollController _scrollController = ScrollController();

  NotificationPreferences _preferences = NotificationPreferences.defaults;

  bool _loading = true;

  Future<void> _saveQueue = Future<void>.value();
  int _saveVersion = 0;

  double _headerProgress = 0;

  bool get _spanish => _translationService.isSpanish;

  @override
  void initState() {
    super.initState();
    _translationService.addListener(_refreshView);
    _timeFormatService.addListener(_refreshView);
    _scrollController.addListener(_listenScroll);
    _load();
  }

  @override
  void dispose() {
    _translationService.removeListener(_refreshView);
    _timeFormatService.removeListener(_refreshView);
    _scrollController.removeListener(_listenScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _refreshView() {
    if (mounted) setState(() {});
  }

  void _listenScroll() {
    if (!_scrollController.hasClients) return;

    final double offset = _scrollController.offset;
    const double start = 45;
    const double end = 145;

    final double progress = ((offset - start) / (end - start)).clamp(0.0, 1.0);

    if ((progress - _headerProgress).abs() < 0.01) return;

    setState(() {
      _headerProgress = progress;
    });
  }

  Future<void> _load() async {
    try {
      final UserPreferences preferences = await _preferencesService
          .getCurrentPreferences(forceRefresh: true);

      if (!mounted) return;

      setState(() {
        _preferences = preferences.notifications;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _save(NotificationPreferences next) async {
    final NotificationPreferences previous = _preferences;
    final int version = ++_saveVersion;

    // Actualización optimista: el control cambia al instante y
    // los demás no se deshabilitan mientras Firestore responde.
    setState(() {
      _preferences = next;
    });

    final Future<void> operation = _saveQueue.then((_) async {
      try {
        await _preferencesService.setNotificationPreferences(next);
        await _scheduler.syncNow();
      } catch (_) {
        if (!mounted) {
          return;
        }

        if (version == _saveVersion) {
          setState(() {
            _preferences = previous;
          });

          showAppStatusSnackBar(
            context,
            message: _spanish
                ? 'No pudimos guardar las preferencias.'
                : 'We could not save your preferences.',
            type: AppStatusType.error,
          );
        }
      }
    });

    _saveQueue = operation;
    await operation;
  }

  void _back() {
    HapticFeedback.selectionClick();
    Navigator.of(context).maybePop();
  }

  Future<void> _pickTaskTime() async {
    final String? value = await _pickTime(_preferences.taskReminderTime);
    if (value == null) return;

    await _save(_preferences.copyWith(taskReminderTime: value));
  }

  Future<void> _pickEvaluationTime() async {
    final String? value = await _pickTime(_preferences.evaluationReminderTime);
    if (value == null) return;

    await _save(_preferences.copyWith(evaluationReminderTime: value));
  }

  Future<String?> _pickTime(String current) async {
    HapticFeedback.selectionClick();

    final List<String> parts = current.split(':');
    final int hour = int.tryParse(parts.first) ?? 18;
    final int minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    final TimeOfDay? selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
    );

    if (selected == null) return null;

    return '${selected.hour.toString().padLeft(2, '0')}:'
        '${selected.minute.toString().padLeft(2, '0')}';
  }

  String _displayTime(String value) {
    return _timeFormatService.formatStoredTime(context, value);
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
              child: ListView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(10, 24, 10, 60),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: _buildHeader(dark),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: _loading
                          ? const SizedBox(
                              height: 320,
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: _primaryColor,
                                  strokeWidth: 3,
                                ),
                              ),
                            )
                          : _buildContent(dark),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AppScrollHeader(
              progress: _headerProgress,
              title: _spanish ? 'Preferencias' : 'Preferences',
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
          crossAxisAlignment: CrossAxisAlignment.start,
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
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _spanish
                        ? 'Preferencias de notificaciones'
                        : 'Notification preferences',
                    style: TextStyle(
                      color: dark
                          ? const Color(0xFFF8FAFC)
                          : const Color(0xFF111827),
                      fontSize: 30,
                      height: 1.08,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _spanish
                        ? 'Elige qué recordatorios académicos quieres recibir y cuándo.'
                        : 'Choose which academic reminders you want to receive and when.',
                    style: TextStyle(
                      color: dark
                          ? const Color(0xFF9BA3B2)
                          : const Color(0xFF6B7280),
                      fontSize: 14,
                      height: 1.4,
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

  Widget _buildContent(bool dark) {
    return Column(
      children: [
        _card(
          dark: dark,
          child: _settingRow(
            dark: dark,
            icon: Ionicons.notificationsOutline,
            iconColor: _primaryColor,
            iconBackground: dark
                ? const Color(0xFF292936)
                : const Color(0xFFEEF0FF),
            title: _spanish
                ? 'Notificaciones académicas'
                : 'Academic notifications',
            description: _spanish
                ? 'Activa o pausa todos los recordatorios de EduFlow.'
                : 'Enable or pause all EduFlow reminders.',
            trailing: Switch.adaptive(
              value: _preferences.enabled,
              activeTrackColor: _primaryColor,
              activeThumbColor: Colors.white,
              onChanged: (value) {
                HapticFeedback.selectionClick();
                _save(_preferences.copyWith(enabled: value));
              },
            ),
          ),
        ),
        const SizedBox(height: 22),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: _preferences.enabled ? 1 : 0.45,
          child: IgnorePointer(
            ignoring: !_preferences.enabled,
            child: Column(
              children: [
                _buildClassCard(dark),
                const SizedBox(height: 14),
                _buildTaskCard(dark),
                const SizedBox(height: 14),
                _buildEvaluationCard(dark),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildClassCard(bool dark) {
    return _card(
      dark: dark,
      child: Column(
        children: [
          _settingRow(
            dark: dark,
            icon: Icons.schedule_rounded,
            iconColor: const Color(0xFF3B82F6),
            iconBackground: dark
                ? const Color(0xFF1E3150)
                : const Color(0xFFEAF2FF),
            title: _spanish ? 'Clases' : 'Classes',
            description: _spanish
                ? 'Recibe un aviso antes de que comience cada clase.'
                : 'Get a reminder before each class starts.',
            trailing: Switch.adaptive(
              value: _preferences.classesEnabled,
              activeTrackColor: _primaryColor,
              activeThumbColor: Colors.white,
              onChanged: (value) {
                HapticFeedback.selectionClick();
                _save(_preferences.copyWith(classesEnabled: value));
              },
            ),
          ),
          _divider(dark),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 17),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _spanish ? 'Avisar antes' : 'Remind me before',
                    style: TextStyle(
                      color: dark
                          ? const Color(0xFFE7EAF0)
                          : const Color(0xFF374151),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  children: [15, 30, 60].map((minutes) {
                    final bool selected =
                        _preferences.classLeadMinutes == minutes;

                    return ChoiceChip(
                      label: Text(minutes == 60 ? '1 h' : '$minutes min'),
                      selected: selected,
                      onSelected: !_preferences.classesEnabled
                          ? null
                          : (value) {
                              if (!value) return;
                              HapticFeedback.selectionClick();
                              _save(
                                _preferences.copyWith(
                                  classLeadMinutes: minutes,
                                ),
                              );
                            },
                      selectedColor: _primaryColor.withValues(
                        alpha: dark ? 0.28 : 0.15,
                      ),
                      backgroundColor: dark
                          ? const Color(0xFF222229)
                          : const Color(0xFFFAFBFC),
                      side: BorderSide(
                        color: selected
                            ? _primaryColor
                            : (dark
                                  ? const Color(0xFF34343C)
                                  : const Color(0xFFE7EAF0)),
                      ),
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        color: selected
                            ? (dark ? const Color(0xFFDADBFF) : _primaryColor)
                            : (dark
                                  ? const Color(0xFFB8BEC9)
                                  : const Color(0xFF6B7280)),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(bool dark) {
    return _card(
      dark: dark,
      child: Column(
        children: [
          _settingRow(
            dark: dark,
            icon: Icons.description_outlined,
            iconColor: const Color(0xFFF59E0B),
            iconBackground: dark
                ? const Color(0xFF35291D)
                : const Color(0xFFFFF7E8),
            title: _spanish ? 'Tareas' : 'Tasks',
            description: _spanish
                ? 'Recibe un recordatorio el día anterior a la entrega.'
                : 'Get a reminder the day before a task is due.',
            trailing: Switch.adaptive(
              value: _preferences.tasksEnabled,
              activeTrackColor: _primaryColor,
              activeThumbColor: Colors.white,
              onChanged: (value) {
                HapticFeedback.selectionClick();
                _save(_preferences.copyWith(tasksEnabled: value));
              },
            ),
          ),
          _divider(dark),
          _timeRow(
            dark: dark,
            title: _spanish ? 'Hora del recordatorio' : 'Reminder time',
            time: _preferences.taskReminderTime,
            enabled: _preferences.tasksEnabled,
            onTap: _pickTaskTime,
          ),
        ],
      ),
    );
  }

  Widget _buildEvaluationCard(bool dark) {
    return _card(
      dark: dark,
      child: Column(
        children: [
          _settingRow(
            dark: dark,
            icon: Icons.school_outlined,
            iconColor: const Color(0xFF8B5CF6),
            iconBackground: dark
                ? const Color(0xFF302446)
                : const Color(0xFFF1EBFF),
            title: _spanish ? 'Evaluaciones' : 'Evaluations',
            description: _spanish
                ? 'Recibe un recordatorio el día anterior a cada evaluación.'
                : 'Get a reminder the day before each evaluation.',
            trailing: Switch.adaptive(
              value: _preferences.evaluationsEnabled,
              activeTrackColor: _primaryColor,
              activeThumbColor: Colors.white,
              onChanged: (value) {
                HapticFeedback.selectionClick();
                _save(_preferences.copyWith(evaluationsEnabled: value));
              },
            ),
          ),
          _divider(dark),
          _timeRow(
            dark: dark,
            title: _spanish ? 'Hora del recordatorio' : 'Reminder time',
            time: _preferences.evaluationReminderTime,
            enabled: _preferences.evaluationsEnabled,
            onTap: _pickEvaluationTime,
          ),
        ],
      ),
    );
  }

  Widget _timeRow({
    required bool dark,
    required String title,
    required String time,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return AppPressable(
      scale: enabled ? 0.99 : 1,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: dark
                        ? const Color(0xFFE7EAF0)
                        : const Color(0xFF374151),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xFF222229)
                      : const Color(0xFFFAFBFC),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: dark
                        ? const Color(0xFF34343C)
                        : const Color(0xFFE7EAF0),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _displayTime(time),
                      style: TextStyle(
                        color: enabled
                            ? _primaryColor
                            : (dark
                                  ? const Color(0xFF666A74)
                                  : const Color(0xFFAEB3BD)),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: enabled
                          ? _primaryColor
                          : (dark
                                ? const Color(0xFF666A74)
                                : const Color(0xFFAEB3BD)),
                      size: 18,
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

  Widget _card({required bool dark, required Widget child}) {
    return Container(
      width: double.infinity,
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

  Widget _settingRow({
    required bool dark,
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
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: iconColor, size: 23),
          ),
          const SizedBox(width: 15),
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
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: TextStyle(
                    color: dark
                        ? const Color(0xFF9BA3B2)
                        : const Color(0xFF6B7280),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }

  Widget _divider(bool dark) {
    return Divider(
      height: 1,
      color: dark ? const Color(0xFF2A303B) : const Color(0xFFE7EAF0),
    );
  }

  Widget _buildBackButton(bool dark) {
    return GestureDetector(
      onTap: _back,
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF191E27) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: dark ? const Color(0xFF2A303B) : const Color(0xFFE2E6ED),
          ),
        ),
        child: Icon(
          Ionicons.chevronBackOutline,
          color: dark ? const Color(0xFFE7EAF0) : const Color(0xFF374151),
          size: 22,
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
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF222833) : const Color(0xFFF4F5F8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: dark ? const Color(0xFF303744) : const Color(0xFFE2E6ED),
            ),
          ),
          child: Icon(
            Ionicons.chevronBackOutline,
            color: dark ? const Color(0xFFE7EAF0) : const Color(0xFF374151),
            size: 19,
          ),
        ),
      ),
    );
  }
}
