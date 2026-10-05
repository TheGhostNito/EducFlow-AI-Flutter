import 'package:flutter/material.dart';

import '../services/theme_service.dart';
import '../services/translation_service.dart';
import 'app_status_snackbar.dart';

class ThemeToggleButton extends StatefulWidget {
  const ThemeToggleButton({super.key, this.disabled = false});

  final bool disabled;

  @override
  State<ThemeToggleButton> createState() => _ThemeToggleButtonState();
}

class _ThemeToggleButtonState extends State<ThemeToggleButton> {
  final ThemeService _themeService = ThemeService.instance;

  bool _changing = false;
  DateTime? _lastToggle;

  Future<void> _cambiarTema() async {
    final now = DateTime.now();
    if (widget.disabled ||
        _changing ||
        (_lastToggle != null &&
            now.difference(_lastToggle!) < const Duration(milliseconds: 350))) {
      return;
    }

    _lastToggle = now;
    setState(() => _changing = true);
    try {
      await _themeService.toggleTheme();
    } catch (_) {
      if (mounted) {
        showAppStatusSnackBar(
          context,
          message: TranslationService.instance.isSpanish
              ? 'No pudimos guardar el tema. Se restauró la opción anterior.'
              : 'We could not save the theme. The previous option was restored.',
          type: AppStatusType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool oscuro = Theme.of(context).brightness == Brightness.dark;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: widget.disabled || _changing ? 0.55 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: oscuro ? const Color(0xFF191F29) : Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: oscuro ? const Color(0xFF2B323E) : const Color(0xFFE1E5EC),
          ),
          boxShadow: oscuro
              ? const []
              : const [
                  BoxShadow(
                    color: Color(0x120F172A),
                    blurRadius: 20,
                    offset: Offset(0, 7),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: widget.disabled || _changing ? null : _cambiarTema,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  );
                },
                child: Icon(
                  oscuro ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                  key: ValueKey(oscuro),
                  size: 22,
                  color: oscuro
                      ? const Color(0xFFF6C453)
                      : const Color(0xFF5B5FEF),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
