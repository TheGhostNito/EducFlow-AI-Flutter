import 'dart:async';

import 'package:flutter/material.dart';

class AppReveal extends StatefulWidget {
  const AppReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 300),
    this.offsetY = 12,
  });

  final Widget child;

  final Duration delay;

  final Duration duration;

  final double offsetY;

  @override
  State<AppReveal> createState() => _AppRevealState();
}

class _AppRevealState extends State<AppReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _opacity;

  late final Animation<double> _position;
  late final CurvedAnimation _curve;
  Timer? _delayTimer;
  bool _started = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: widget.duration);

    _curve = CurvedAnimation(
      parent: _controller,
      curve: const Cubic(0.22, 1, 0.36, 1),
    );

    _opacity = _curve;

    // Distancia fija: una tarjeta alta no debe recorrer el 12% de su altura.
    _position = Tween<double>(begin: widget.offsetY, end: 0).animate(_curve);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _delayTimer?.cancel();
      _controller.value = 1;
      _started = true;
    } else if (!_started) {
      _started = true;
      if (widget.delay == Duration.zero) {
        _controller.forward();
      } else {
        _delayTimer = Timer(widget.delay, () => _controller.forward());
      }
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _curve.dispose();
    _controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: AnimatedBuilder(
        animation: _position,
        child: widget.child,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, _position.value),
          child: child,
        ),
      ),
    );
  }
}
