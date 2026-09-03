import 'package:flutter/material.dart';

/// Expande o recoge un mensaje sin dejar espacio ni elementos interactivos
/// cuando está oculto. Las animaciones se pueden invertir durante la escritura.
class AppAnimatedVisibility extends StatelessWidget {
  const AppAnimatedVisibility({
    super.key,
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: visible ? 1 : 0, end: visible ? 1 : 0),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      child: IgnorePointer(
        ignoring: !visible,
        child: ExcludeSemantics(excluding: !visible, child: child),
      ),
      builder: (context, value, child) {
        return ClipRect(
          child: Align(
            alignment: Alignment.topLeft,
            heightFactor: value,
            child: Opacity(opacity: value, child: child),
          ),
        );
      },
    );
  }
}
