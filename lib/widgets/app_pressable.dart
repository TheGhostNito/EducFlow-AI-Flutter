import 'package:flutter/gestures.dart';
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
  int? _pointer;
  Offset? _origin;

  void _down(PointerDownEvent event) {
    if (_pointer != null || event.buttons != kPrimaryButton) {
      return;
    }
    _pointer = event.pointer;
    _origin = event.position;
    setState(() {
      _pressed = true;
    });
  }

  void _move(PointerMoveEvent event) {
    if (_pointer == event.pointer &&
        _pressed &&
        (event.position - _origin!).distance > kTouchSlop) {
      setState(() {
        _pressed = false;
      });
    }
  }

  void _up(PointerEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    _origin = null;
    if (!_pressed) {
      return;
    }
    // Desplazar una lista o cancelar el gesto no debe provocar una vibración.
    if (event is PointerUpEvent && widget.haptic) {
      HapticFeedback.selectionClick();
    }
    setState(() {
      _pressed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool reducirMovimiento = MediaQuery.disableAnimationsOf(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: AnimatedScale(
        scale: _pressed && !reducirMovimiento ? widget.scale : 1,
        duration: reducirMovimiento
            ? Duration.zero
            : const Duration(milliseconds: 140),
        curve: const Cubic(0.22, 1, 0.36, 1),
        child: widget.child,
      ),
    );
  }
}
