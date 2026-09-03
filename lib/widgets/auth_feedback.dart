import 'package:flutter/material.dart';

import '../services/translation_service.dart';
import 'app_animated_visibility.dart';

Duration _transitionDuration(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 180);

class PasswordVisibilityButton extends StatelessWidget {
  const PasswordVisibilityButton({
    super.key,
    required this.visible,
    required this.onPressed,
  });

  final bool visible;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool oscuro = Theme.of(context).brightness == Brightness.dark;
    final bool espanol = TranslationService.instance.isSpanish;

    return IconButton(
      onPressed: onPressed,
      tooltip: visible
          ? (espanol ? 'Ocultar contraseña' : 'Hide password')
          : (espanol ? 'Mostrar contraseña' : 'Show password'),
      color: oscuro ? const Color(0xFFA9B1BF) : const Color(0xFF7B8492),
      icon: AnimatedSwitcher(
        duration: _transitionDuration(context),
        child: Icon(
          visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          key: ValueKey(visible),
        ),
      ),
    );
  }
}

/// Conserva el diseño de los avisos de Login y Registro.
class AuthStatusMessage extends StatefulWidget {
  const AuthStatusMessage({
    super.key,
    required this.message,
    this.success = false,
    this.padding = EdgeInsets.zero,
  });

  final String message;
  final bool success;
  final EdgeInsetsGeometry padding;

  @override
  State<AuthStatusMessage> createState() => _AuthStatusMessageState();
}

class _AuthStatusMessageState extends State<AuthStatusMessage> {
  late String _ultimoMensaje = widget.message;

  @override
  void didUpdateWidget(AuthStatusMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message.isNotEmpty) {
      _ultimoMensaje = widget.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool oscuro = Theme.of(context).brightness == Brightness.dark;
    final Color color = widget.success
        ? (oscuro ? const Color(0xFF6EE7B7) : const Color(0xFF047857))
        : (oscuro ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C));

    return AppAnimatedVisibility(
      visible: widget.message.isNotEmpty,
      child: Padding(
        padding: widget.padding,
        child: Semantics(
          liveRegion: true,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.success
                  ? (oscuro ? const Color(0xFF17362D) : const Color(0xFFECFDF5))
                  : (oscuro
                        ? const Color(0xFF321D22)
                        : const Color(0xFFFEF2F2)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.success
                    ? (oscuro
                          ? const Color(0xFF205D4B)
                          : const Color(0xFFA7F3D0))
                    : (oscuro
                          ? const Color(0xFF5F2B31)
                          : const Color(0xFFFECACA)),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  widget.success
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  color: color,
                  size: 19,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _ultimoMensaje,
                    style: TextStyle(color: color, fontSize: 13, height: 1.4),
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

class AuthButtonContent extends StatelessWidget {
  const AuthButtonContent({
    super.key,
    required this.loading,
    required this.label,
    required this.loadingLabel,
    this.compact = false,
  });

  final bool loading;
  final String label;
  final String loadingLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color? color = DefaultTextStyle.of(context).style.color;
    return Semantics(
      liveRegion: true,
      label: loading ? loadingLabel : label,
      excludeSemantics: true,
      child: AnimatedSwitcher(
        duration: _transitionDuration(context),
        child: Row(
          key: ValueKey(loading),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading) ...[
              SizedBox.square(
                dimension: compact ? 17 : 19,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: color,
                ),
              ),
              const SizedBox(width: 9),
            ],
            Flexible(
              child: Text(
                loading ? loadingLabel : label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: compact ? null : 16,
                  fontWeight: compact ? FontWeight.w600 : FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
