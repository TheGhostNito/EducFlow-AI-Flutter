import 'package:flutter/material.dart';

import '../services/theme_service.dart';

class ThemeToggleButton extends StatefulWidget {
  const ThemeToggleButton({super.key, this.disabled = false});

  final bool disabled;

  @override
  State<ThemeToggleButton> createState() => _ThemeToggleButtonState();
}

class _ThemeToggleButtonState extends State<ThemeToggleButton> {
  final ThemeService _themeService = ThemeService.instance;

  double _turns = 0;

  Future<void> _cambiarTema() async {
    if (widget.disabled) {
      return;
    }

    setState(() {
      _turns += 0.5;
    });

    await _themeService.toggleTheme();
  }

  @override
  Widget build(BuildContext context) {
    final bool oscuro = Theme.of(context).brightness == Brightness.dark;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: widget.disabled ? 0.55 : 1,
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
            onTap: widget.disabled ? null : _cambiarTema,
            child: Center(
              child: AnimatedRotation(
                turns: _turns,
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutBack,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: animation, child: child),
                    );
                  },
                  child: Icon(
                    oscuro
                        ? Icons.dark_mode_outlined
                        : Icons.light_mode_outlined,
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
      ),
    );
  }
}
