import 'package:flutter/material.dart';

import '../services/translation_service.dart';

class LanguageSelector extends StatefulWidget {
  const LanguageSelector({
    super.key,
    this.disabled = false,
    this.onLanguageChanged,
  });

  final bool disabled;
  final VoidCallback? onLanguageChanged;

  @override
  State<LanguageSelector> createState() => _LanguageSelectorState();
}

class _LanguageSelectorState extends State<LanguageSelector>
    with SingleTickerProviderStateMixin {
  final TranslationService _translationService = TranslationService.instance;

  final LayerLink _layerLink = LayerLink();

  OverlayEntry? _overlayEntry;

  late final AnimationController _animationController;
  late final Animation<double> _animation;

  bool _menuAbierto = false;

  static const Color _primaryColor = Color(0xFF5B5FEF);

  // =========================================================
  // CICLO DE VIDA
  // =========================================================

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );

    _animation = CurvedAnimation(
      parent: _animationController,
      curve: const Cubic(0.22, 1, 0.36, 1),
    );

    _translationService.addListener(_actualizarIdioma);
  }

  void _actualizarIdioma() {
    if (mounted) {
      setState(() {});
    }

    _overlayEntry?.markNeedsBuild();
  }

  @override
  void didUpdateWidget(LanguageSelector oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.disabled && !oldWidget.disabled && _menuAbierto) {
      _cerrarMenu();
    }
  }

  @override
  void dispose() {
    _overlayEntry?.remove();

    _translationService.removeListener(_actualizarIdioma);

    _animationController.dispose();

    super.dispose();
  }

  // =========================================================
  // MENÚ
  // =========================================================

  Future<void> _alternarMenu() async {
    if (widget.disabled) {
      return;
    }

    if (_menuAbierto) {
      await _cerrarMenu();
    } else {
      _abrirMenu();
    }
  }

  void _abrirMenu() {
    if (_menuAbierto) {
      return;
    }

    setState(() {
      _menuAbierto = true;
    });

    _overlayEntry = _crearOverlay();

    Overlay.of(context).insert(_overlayEntry!);

    _animationController.forward(from: 0);
  }

  Future<void> _cerrarMenu() async {
    if (!_menuAbierto) {
      return;
    }

    await _animationController.reverse();

    _overlayEntry?.remove();
    _overlayEntry = null;

    if (mounted) {
      setState(() {
        _menuAbierto = false;
      });
    }
  }

  Future<void> _cambiarIdioma() async {
    await _translationService.toggleLanguage();

    widget.onLanguageChanged?.call();

    await _cerrarMenu();
  }

  // =========================================================
  // OVERLAY
  // =========================================================

  OverlayEntry _crearOverlay() {
    return OverlayEntry(
      builder: (overlayContext) {
        final bool oscuro =
            Theme.of(overlayContext).brightness == Brightness.dark;

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _cerrarMenu,
                child: const SizedBox.expand(),
              ),
            ),

            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              offset: const Offset(0, 7),
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  final double value = _animation.value;

                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, -6 * (1 - value)),
                      child: Transform.scale(
                        alignment: Alignment.topCenter,
                        scaleX: 1,
                        scaleY: 0.94 + (0.06 * value),
                        child: child,
                      ),
                    ),
                  );
                },
                child: _buildDropdown(oscuro),
              ),
            ),
          ],
        );
      },
    );
  }

  // =========================================================
  // DROPDOWN
  // =========================================================

  Widget _buildDropdown(bool oscuro) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 132,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: oscuro ? const Color(0xFF191F29) : Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: oscuro ? const Color(0xFF2B323E) : const Color(0xFFE1E5EC),
          ),
          boxShadow: oscuro
              ? const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ]
              : const [
                  BoxShadow(
                    color: Color(0x240F172A),
                    blurRadius: 30,
                    offset: Offset(0, 13),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: _cambiarIdioma,
            child: SizedBox(
              height: 42,
              child: Row(
                children: [
                  const SizedBox(width: 10),

                  const Icon(Icons.language, size: 17, color: _primaryColor),

                  const SizedBox(width: 9),

                  Text(
                    _translationService.isSpanish ? 'English' : 'Español',
                    style: TextStyle(
                      color: oscuro
                          ? const Color(0xFFDCE1E9)
                          : const Color(0xFF374151),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final bool oscuro = Theme.of(context).brightness == Brightness.dark;

    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        width: 132,
        height: 44,
        child: OutlinedButton(
          onPressed: widget.disabled ? null : _alternarMenu,
          style: OutlinedButton.styleFrom(
            backgroundColor: oscuro ? const Color(0xFF191F29) : Colors.white,
            foregroundColor: oscuro
                ? const Color(0xFFEDF1F7)
                : const Color(0xFF374151),
            disabledBackgroundColor: oscuro
                ? const Color(0xFF191F29)
                : Colors.white,
            disabledForegroundColor: oscuro
                ? const Color(0xFF727B88)
                : const Color(0xFFA0A7B2),
            side: BorderSide(
              color: oscuro ? const Color(0xFF2B323E) : const Color(0xFFE1E5EC),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
          ),
          child: Row(
            children: [
              const Icon(Icons.language, size: 18, color: _primaryColor),

              const SizedBox(width: 9),

              Expanded(
                child: Text(
                  _translationService.isSpanish ? 'Español' : 'English',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              Icon(
                _menuAbierto
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 18,
                color: oscuro
                    ? const Color(0xFF8C96A5)
                    : const Color(0xFF9CA3AF),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
