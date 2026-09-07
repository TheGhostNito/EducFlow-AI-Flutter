import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../pages/ai/ai_chat_page.dart';
import '../../pages/calendar/calendar_page.dart';
import '../../pages/dashboard/dashboard_page.dart';
import '../../pages/notifications/notifications_page.dart';
import '../../pages/schedule/schedule_page.dart';
import '../../services/notification_service.dart';

enum SeccionPrincipal { inicio, horario, ia, calendario, notificaciones }

typedef MainSectionBuilder = Widget Function(
  BuildContext context,
  SeccionPrincipal section,
  String? notificationPayload,
);

/// Las secciones comparten una ruta. Solo los detalles y formularios se apilan
/// con Navigator, por lo que Atrás no recorre las pestañas visitadas.
class MainNavigation extends StatefulWidget {
  const MainNavigation({
    super.key,
    this.sectionBuilder,
    @visibleForTesting this.isWebOverride,
  });

  final MainSectionBuilder? sectionBuilder;
  final bool? isWebOverride;

  static void goTo(BuildContext context, SeccionPrincipal section) {
    final state = context.findAncestorStateOfType<_MainNavigationState>();
    assert(
      state != null,
      'Las secciones deben abrirse dentro de MainNavigation.',
    );
    state?._select(section);
  }

  static void openEvaluation(BuildContext context, String evaluationId) {
    final state = context.findAncestorStateOfType<_MainNavigationState>();
    assert(
      state != null,
      'El Calendario debe abrirse dentro de MainNavigation.',
    );
    state?._select(
      SeccionPrincipal.calendario,
      payload: 'evaluation:${evaluationId.trim()}',
    );
  }

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  final NotificationService _notifications = NotificationService.instance;
  SeccionPrincipal _section = SeccionPrincipal.inicio;
  String? _payload;
  int _notificationVersion = 0;
  bool _notificationScheduled = false;

  @override
  void initState() {
    super.initState();
    // Este contenedor solo se monta con una sesión autenticada. El listener
    // permanece activo al cambiar de sección, también después del Login.
    _notifications.notificationPayload.addListener(_onNotification);
    _onNotification();
  }

  @override
  void dispose() {
    _notifications.notificationPayload.removeListener(_onNotification);
    super.dispose();
  }

  void _onNotification() {
    if (_notificationScheduled ||
        _notifications.notificationPayload.value == null) {
      return;
    }
    _notificationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notificationScheduled = false;
      final payload = _notifications.notificationPayload.value?.trim() ?? '';
      if (payload.isEmpty) return;
      _notifications.consumirPayload(payload);
      if (payload.startsWith('academic|')) {
        _select(SeccionPrincipal.notificaciones, payload: payload);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _select(SeccionPrincipal section, {String? payload}) {
    if (_section == section && payload == null) return;
    setState(() {
      _section = section;
      _payload = payload;
      if (payload != null) _notificationVersion++;
    });
  }

  Widget _buildSection(
    BuildContext context,
    SeccionPrincipal section,
    String? payload,
  ) {
    return switch (section) {
      SeccionPrincipal.inicio => const DashboardPage(),
      SeccionPrincipal.horario => const SchedulePage(),
      SeccionPrincipal.ia => const AiChatPage(),
      SeccionPrincipal.calendario => CalendarPage(
        initialEvaluationId: payload?.startsWith('evaluation:') == true
            ? payload!.substring('evaluation:'.length)
            : null,
      ),
      SeccionPrincipal.notificaciones => NotificationsPage(
        initialPayload: payload,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final bool isWeb = widget.isWebOverride ?? kIsWeb;
    return PopScope<Object?>(
      // En web, la entrada técnica que usa el motor para recibir popstate no
      // debe convertirse en una salida/reentrada a la misma PWA desde Inicio.
      // En Android, Inicio continúa delegando Atrás al sistema.
      canPop: _section == SeccionPrincipal.inicio && !isWeb,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _section != SeccionPrincipal.inicio) {
          _select(SeccionPrincipal.inicio);
        }
      },
      child: KeyedSubtree(
        key: ValueKey((_section, _notificationVersion)),
        child: (widget.sectionBuilder ?? _buildSection)(
          context,
          _section,
          _payload,
        ),
      ),
    );
  }
}
