import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppPressable extends StatefulWidget {
  const AppPressable({
    super.key,
    required this.child,
    this.scale = 0.94,
    this.haptic = true,
  });

  final Widget child;
  final double scale;
  final bool haptic;

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  bool _pressed = false;

  void _down(PointerDownEvent event) {
    if (widget.haptic) {
      HapticFeedback.selectionClick();
    }

    setState(() {
      _pressed = true;
    });
  }

  void _up(PointerEvent event) {
    if (!_pressed) {
      return;
    }

    setState(() {
      _pressed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: const Duration(milliseconds: 140),
        curve: const Cubic(0.22, 1, 0.36, 1),
        child: widget.child,
      ),
    );
  }
}
