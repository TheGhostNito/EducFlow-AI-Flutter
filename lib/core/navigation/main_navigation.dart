import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../../pages/ai/ai_chat_page.dart';
import '../../pages/calendar/calendar_page.dart';
import '../../pages/dashboard/dashboard_page.dart';
import '../../pages/evaluations/evaluations_page.dart';
import '../../pages/notifications/notifications_page.dart';
import '../../pages/schedule/schedule_page.dart';
import '../../services/notification_service.dart';
import '../../widgets/main_bottom_nav.dart';

enum SeccionPrincipal {
  inicio,
  horario,
  ia,
  calendario,
  notificaciones,
  evaluaciones,
}

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
  static _MainNavigationState? _activeState;

  static void goTo(BuildContext context, SeccionPrincipal section) {
    final state =
        context.findAncestorStateOfType<_MainNavigationState>() ?? _activeState;
    assert(
      state != null,
      'Las secciones deben abrirse dentro de MainNavigation.',
    );
    state?._select(section);
  }

  static void openEvaluation(BuildContext context, String evaluationId) {
    final state =
        context.findAncestorStateOfType<_MainNavigationState>() ?? _activeState;
    assert(
      state != null,
      'Evaluaciones debe abrirse dentro de MainNavigation.',
    );
    state?._select(
      SeccionPrincipal.evaluaciones,
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
  bool _bottomNavVisible = true;
  final GlobalKey _sectionContentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    MainNavigation._activeState = this;
    // Este contenedor solo se monta con una sesión autenticada. El listener
    // permanece activo al cambiar de sección, también después del Login.
    _notifications.notificationPayload.addListener(_onNotification);
    _onNotification();
  }

  @override
  void dispose() {
    if (identical(MainNavigation._activeState, this)) {
      MainNavigation._activeState = null;
    }
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
      _bottomNavVisible = true;
      _payload = payload;
      if (payload != null) _notificationVersion++;
    });
  }

  void _activate(SeccionPrincipal section) {
    if (_section != section) {
      _select(section);
      return;
    }
    if (!_bottomNavVisible) setState(() => _bottomNavVisible = true);
    _scrollActiveSectionToTop();
  }

  Future<void> _scrollActiveSectionToTop() async {
    final root = _sectionContentKey.currentContext;
    if (root == null) return;
    final positions = <ScrollPosition>[];
    void collect(Element element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final position = (element.state as ScrollableState).position;
        if (position.axis == Axis.vertical && position.hasPixels) {
          positions.add(position);
        }
      }
      element.visitChildElements(collect);
    }

    root.visitChildElements(collect);
    if (positions.isEmpty) return;
    positions.sort((a, b) => b.maxScrollExtent.compareTo(a.maxScrollExtent));
    final position = positions.first;
    if (position.pixels <= position.minScrollExtent + 1) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      position.jumpTo(position.minScrollExtent);
      return;
    }
    await position.animateTo(
      position.minScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  bool _handleScroll(UserScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification.metrics.maxScrollExtent <= 0) {
      if (!_bottomNavVisible) setState(() => _bottomNavVisible = true);
      return false;
    }
    final visible = switch (notification.direction) {
      ScrollDirection.reverse => false,
      ScrollDirection.forward => true,
      ScrollDirection.idle => _bottomNavVisible,
    };
    if (visible != _bottomNavVisible) {
      setState(() => _bottomNavVisible = visible);
    }
    return false;
  }

  int get _navigationIndex => switch (_section) {
    SeccionPrincipal.inicio => 0,
    SeccionPrincipal.horario => 1,
    SeccionPrincipal.ia => 2,
    SeccionPrincipal.calendario => 3,
    SeccionPrincipal.notificaciones => 4,
    SeccionPrincipal.evaluaciones => 0,
  };

  Widget _buildSection(
    BuildContext context,
    SeccionPrincipal section,
    String? payload,
  ) {
    return switch (section) {
      SeccionPrincipal.inicio => const DashboardPage(),
      SeccionPrincipal.horario => const SchedulePage(),
      SeccionPrincipal.ia => const AiChatPage(),
      SeccionPrincipal.calendario => const CalendarPage(),
      SeccionPrincipal.notificaciones => NotificationsPage(
        initialPayload: payload,
      ),
      SeccionPrincipal.evaluaciones => EvaluationsPage(
        initialEvaluationId: payload?.startsWith('evaluation:') == true
            ? payload!.substring('evaluation:'.length)
            : null,
        onBack: () => _select(SeccionPrincipal.inicio),
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
      child: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<UserScrollNotification>(
              onNotification: _handleScroll,
              child: KeyedSubtree(
                key: _sectionContentKey,
                child: KeyedSubtree(
                  key: ValueKey((_section, _notificationVersion)),
                  child: (widget.sectionBuilder ?? _buildSection)(
                    context,
                    _section,
                    _payload,
                  ),
                ),
              ),
            ),
          ),
          if (_section != SeccionPrincipal.ia &&
              _section != SeccionPrincipal.evaluaciones)
            MainBottomNav(
              currentIndex: _navigationIndex,
              visible: _bottomNavVisible,
              onHome: () => _activate(SeccionPrincipal.inicio),
              onSchedule: () => _activate(SeccionPrincipal.horario),
              onAi: () => _select(SeccionPrincipal.ia),
              onCalendar: () => _activate(SeccionPrincipal.calendario),
              onNotifications: () => _activate(SeccionPrincipal.notificaciones),
            ),
        ],
      ),
    );
  }
}
