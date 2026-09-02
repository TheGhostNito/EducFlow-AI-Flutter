import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter/services.dart';

import '../services/notification_badge_service.dart';

class MainBottomNav extends StatefulWidget {
  const MainBottomNav({
    super.key,
    required this.currentIndex,
    required this.onHome,
    required this.onSchedule,
    required this.onAi,
    required this.onCalendar,
    required this.onNotifications,
    this.showNotificationDot = false,
  });

  final int currentIndex;

  final VoidCallback onHome;
  final VoidCallback onSchedule;
  final VoidCallback onAi;
  final VoidCallback onCalendar;
  final VoidCallback onNotifications;

  // Se mantiene por compatibilidad con cualquier pantalla vieja
  // que todavía lo esté enviando manualmente.
  final bool showNotificationDot;

  @override
  State<MainBottomNav> createState() => _MainBottomNavState();
}

class _MainBottomNavState extends State<MainBottomNav> {
  final NotificationBadgeService _badgeService =
      NotificationBadgeService.instance;

  @override
  void initState() {
    super.initState();

    _badgeService.start();
    _badgeService.addListener(_actualizarBadge);
  }

  @override
  void dispose() {
    _badgeService.removeListener(_actualizarBadge);

    super.dispose();
  }

  void _actualizarBadge() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bool oscuro = Theme.of(context).brightness == Brightness.dark;

    final double screenWidth = MediaQuery.sizeOf(context).width;

    final double safeBottom = MediaQuery.paddingOf(context).bottom;

    final bool mobile = screenWidth <= 560;

    final double horizontalMargin = mobile ? 7 : 12;

    final double availableWidth = screenWidth - (horizontalMargin * 2);

    final double barWidth = math.min(430, availableWidth);

    final double barHeight = mobile ? 64 : 68;

    final double padding = mobile ? 6 : 7;

    final double bottom = math.max(16, safeBottom);

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: Center(
        child: Container(
          width: barWidth,
          height: barHeight,
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: oscuro ? const Color(0xFF191F29) : Colors.white,
            borderRadius: BorderRadius.circular(mobile ? 21 : 23),
            border: Border.all(
              color: oscuro ? const Color(0xFF2D3541) : const Color(0xFFE3E6ED),
            ),
            boxShadow: [
              BoxShadow(
                color: oscuro
                    ? const Color(0x4D000000)
                    : const Color(0x2110172A),
                blurRadius: 38,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: _NavigationButton(
                  icon: Ionicons.home,
                  active: widget.currentIndex == 0,
                  oscuro: oscuro,
                  mobile: mobile,
                  onTap: widget.onHome,
                ),
              ),

              const SizedBox(width: 4),

              Expanded(
                child: _NavigationButton(
                  icon: Ionicons.timeOutline,
                  active: widget.currentIndex == 1,
                  oscuro: oscuro,
                  mobile: mobile,
                  onTap: widget.onSchedule,
                ),
              ),

              const SizedBox(width: 4),

              Expanded(
                child: Center(
                  child: _AiNavigationButton(
                    oscuro: oscuro,
                    onTap: widget.onAi,
                  ),
                ),
              ),

              const SizedBox(width: 4),

              Expanded(
                child: _NavigationButton(
                  icon: Ionicons.calendarClearOutline,
                  active: widget.currentIndex == 3,
                  oscuro: oscuro,
                  mobile: mobile,
                  onTap: widget.onCalendar,
                ),
              ),

              const SizedBox(width: 4),

              Expanded(
                child: _NavigationButton(
                  icon: Ionicons.notificationsOutline,
                  active: widget.currentIndex == 4,
                  oscuro: oscuro,
                  mobile: mobile,
                  showNotificationDot: widget.showNotificationDot,
                  notificationCount: _badgeService.unreadCount,
                  onTap: widget.onNotifications,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================
// BOTÓN NORMAL
// ===========================================================

class _NavigationButton extends StatefulWidget {
  const _NavigationButton({
    required this.icon,
    required this.active,
    required this.oscuro,
    required this.mobile,
    required this.onTap,
    this.showNotificationDot = false,
    this.notificationCount = 0,
  });

  final IconData icon;
  final bool active;
  final bool oscuro;
  final bool mobile;
  final bool showNotificationDot;
  final int notificationCount;

  final VoidCallback onTap;

  @override
  State<_NavigationButton> createState() => _NavigationButtonState();
}

class _NavigationButtonState extends State<_NavigationButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 230),
    );

    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 0.84,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.84,
          end: 1.06,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 27,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.06,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 28,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  Future<void> _presionar() async {
    if (_controller.isAnimating) {
      return;
    }

    HapticFeedback.selectionClick();

    _controller.forward(from: 0);

    await Future<void>.delayed(const Duration(milliseconds: 85));

    if (!mounted) {
      return;
    }

    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final Color color = widget.active
        ? (widget.oscuro ? const Color(0xFFB8BBFF) : const Color(0xFF5B5FEF))
        : (widget.oscuro ? const Color(0xFF858E9D) : const Color(0xFFA1A7B3));

    final Color background = widget.active
        ? (widget.oscuro ? const Color(0xFF2B3047) : const Color(0xFFECEEFF))
        : Colors.transparent;

    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) {
        return Transform.scale(
          scale: _scale.value * (widget.active ? 1.05 : 1),
          child: child,
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _presionar,
          borderRadius: BorderRadius.circular(widget.mobile ? 14 : 16),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Container(
            height: widget.mobile ? 46 : 50,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(widget.mobile ? 14 : 16),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(widget.icon, color: color, size: widget.mobile ? 21 : 23),

                if (widget.notificationCount > 0)
                  Positioned(
                    top: widget.mobile ? 3 : 4,
                    right: widget.mobile ? 5 : 7,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 17,
                        minHeight: 17,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          width: 1.5,
                          color: widget.oscuro
                              ? const Color(0xFF191F29)
                              : Colors.white,
                        ),
                      ),
                      child: Text(
                        widget.notificationCount > 9
                            ? '9+'
                            : '${widget.notificationCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8.5,
                          height: 1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  )
                else if (widget.showNotificationDot)
                  Positioned(
                    top: widget.mobile ? 7 : 9,
                    right: widget.mobile ? 12 : 13,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                        border: Border.all(
                          width: 2,
                          color: widget.oscuro
                              ? const Color(0xFF191F29)
                              : Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================
// BOTÓN CENTRAL DE IA
// ===========================================================

class _AiNavigationButton extends StatefulWidget {
  const _AiNavigationButton({required this.oscuro, required this.onTap});

  final bool oscuro;

  final VoidCallback onTap;

  @override
  State<_AiNavigationButton> createState() => _AiNavigationButtonState();
}

class _AiNavigationButtonState extends State<_AiNavigationButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _scale;

  late final Animation<double> _translateY;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    _scale =
        TweenSequence<double>([
          TweenSequenceItem(
            tween: Tween<double>(begin: 1, end: 0.84),
            weight: 42,
          ),
          TweenSequenceItem(
            tween: Tween<double>(begin: 0.84, end: 1.11),
            weight: 30,
          ),
          TweenSequenceItem(
            tween: Tween<double>(begin: 1.11, end: 1),
            weight: 28,
          ),
        ]).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Cubic(0.22, 1, 0.36, 1),
          ),
        );

    _translateY =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween<double>(begin: 0, end: 1), weight: 42),
          TweenSequenceItem(
            tween: Tween<double>(begin: 1, end: -3),
            weight: 30,
          ),
          TweenSequenceItem(
            tween: Tween<double>(begin: -3, end: 0),
            weight: 28,
          ),
        ]).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Cubic(0.22, 1, 0.36, 1),
          ),
        );
  }

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  Future<void> _presionar() async {
    if (_controller.isAnimating) {
      return;
    }

    HapticFeedback.lightImpact();

    _controller.forward(from: 0);

    await Future<void>.delayed(const Duration(milliseconds: 180));

    if (!mounted) {
      return;
    }

    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _presionar,
      child: Transform.translate(
        offset: const Offset(0, -17),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _translateY.value),
              child: Transform.scale(scale: _scale.value, child: child),
            );
          },
          child: Container(
            width: 56,
            height: 56,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(19),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.oscuro
                    ? const [Color(0xFF777BFF), Color(0xFF7650DF)]
                    : const [Color(0xFF686CF7), Color(0xFF8357E9)],
              ),
              boxShadow: widget.oscuro
                  ? const []
                  : const [
                      BoxShadow(
                        color: Color(0x525B5FEF),
                        blurRadius: 23,
                        offset: Offset(0, 10),
                      ),
                    ],
            ),
            child: Stack(
              children: [
                Positioned(
                  top: -10,
                  left: -5,
                  child: Container(
                    width: 45,
                    height: 45,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0x3DFFFFFF), Color(0x00FFFFFF)],
                      ),
                    ),
                  ),
                ),
                const Center(
                  child: Icon(Ionicons.sparkles, color: Colors.white, size: 25),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
