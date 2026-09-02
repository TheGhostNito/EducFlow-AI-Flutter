import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSwipeDelete extends StatefulWidget {
  const AppSwipeDelete({
    super.key,
    required this.child,
    required this.deleteLabel,
    required this.onConfirmDelete,
    required this.onDelete,
    this.tutorialKey,
    this.borderRadius = 19,
    this.deleteThreshold = 0.52,
    this.deleteColor = const Color(0xFFB42318),
    this.tutorialTitle,
    this.tutorialMessage,
    this.tutorialButtonLabel,
  });

  /// Tarjeta o contenido que se podrá deslizar.
  final Widget child;

  /// Texto mostrado detrás de la tarjeta.
  final String deleteLabel;

  /// Debe devolver true si el usuario confirma la eliminación.
  final Future<bool> Function() onConfirmDelete;

  /// Acción que elimina realmente el elemento.
  final Future<void> Function() onDelete;

  /// Si se proporciona, muestra una demostración del gesto
  /// una sola vez en este dispositivo.
  ///
  /// Ejemplo:
  /// educflow-swipe-delete-tasks
  final String? tutorialKey;
  final String? tutorialTitle;
  final String? tutorialMessage;
  final String? tutorialButtonLabel;

  final double borderRadius;

  /// Porcentaje del ancho que debe deslizarse para solicitar
  /// la eliminación.
  final double deleteThreshold;

  final Color deleteColor;

  @override
  State<AppSwipeDelete> createState() => _AppSwipeDeleteState();
}

class _AppSwipeDeleteState extends State<AppSwipeDelete>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;

  double _offset = 0;
  double _animationFrom = 0;
  double _animationTo = 0;

  bool _busy = false;
  bool _tutorialScheduled = false;
  bool _userInteracted = false;
  bool _thresholdHapticTriggered = false;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );

    _animationController.addListener(_handleAnimation);
  }

  @override
  void dispose() {
    _animationController
      ..removeListener(_handleAnimation)
      ..dispose();

    super.dispose();
  }

  // =========================================================
  // ANIMACIÓN
  // =========================================================

  void _handleAnimation() {
    if (!mounted) {
      return;
    }

    final double curved = Curves.easeOutCubic.transform(
      _animationController.value,
    );

    setState(() {
      _offset = _animationFrom + ((_animationTo - _animationFrom) * curved);
    });
  }

  Future<void> _animateTo(
    double target, {
    Duration duration = const Duration(milliseconds: 240),
  }) async {
    if (!mounted) {
      return;
    }

    _animationController.stop();

    _animationFrom = _offset;
    _animationTo = target;

    _animationController.duration = duration;

    await _animationController.forward(from: 0);

    if (!mounted) {
      return;
    }

    setState(() {
      _offset = target;
    });
  }

  // =========================================================
  // TUTORIAL
  // =========================================================

  void _scheduleTutorial(double width) {
    if (_tutorialScheduled || widget.tutorialKey == null || width <= 0) {
      return;
    }

    _tutorialScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runTutorial(width);
    });
  }

  Future<void> _runTutorial(double width) async {
    final String? tutorialKey = widget.tutorialKey;

    if (tutorialKey == null) {
      return;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final bool alreadySeen = prefs.getBool(tutorialKey) ?? false;

    if (alreadySeen || !mounted || _userInteracted) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 550));

    if (!mounted || _userInteracted) {
      return;
    }

    final String? title = widget.tutorialTitle;

    final String? message = widget.tutorialMessage;

    final String? buttonLabel = widget.tutorialButtonLabel;

    if (title != null && message != null && buttonLabel != null) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.78),
        builder: (dialogContext) {
          final bool dark =
              Theme.of(dialogContext).brightness == Brightness.dark;

          return AlertDialog(
            backgroundColor: dark ? const Color(0xFF18181D) : Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            icon: Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFB42318)
                    .withValues(alpha: dark ? 0.18 : 0.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.swipe_left_rounded,
                color: Color(0xFFEF4444),
                size: 30,
              ),
            ),
            title: Text(title, textAlign: TextAlign.center),
            content: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: dark ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
                height: 1.45,
              ),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              FilledButton(
                onPressed: () {
                  HapticFeedback.selectionClick();

                  Navigator.of(dialogContext).pop();
                },
                child: Text(buttonLabel),
              ),
            ],
          );
        },
      );
    }

    if (!mounted) {
      return;
    }

    await prefs.setBool(tutorialKey, true);

    // Después de cerrar el aviso,
    // mostramos físicamente cómo se hace.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    if (!mounted || _userInteracted) {
      return;
    }

    final double revealDistance = width < 300 ? width * 0.23 : 78;

    HapticFeedback.selectionClick();

    await _animateTo(
      -revealDistance,
      duration: const Duration(milliseconds: 360),
    );

    if (!mounted || _userInteracted) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 650));

    if (!mounted || _userInteracted) {
      return;
    }

    await _animateTo(0, duration: const Duration(milliseconds: 420));
  }

  // =========================================================
  // GESTO
  // =========================================================

  void _onHorizontalDragStart(DragStartDetails details) {
    if (_busy) {
      return;
    }

    _userInteracted = true;
    _animationController.stop();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details, double width) {
    if (_busy) {
      return;
    }

    final double next = (_offset + details.delta.dx).clamp(-width, 0.0);

    final double threshold = width * widget.deleteThreshold;

    final bool crossedThreshold = -next >= threshold;

    if (crossedThreshold && !_thresholdHapticTriggered) {
      _thresholdHapticTriggered = true;

      HapticFeedback.mediumImpact();
    } else if (!crossedThreshold) {
      _thresholdHapticTriggered = false;
    }

    setState(() {
      _offset = next;
    });
  }

  Future<void> _onHorizontalDragEnd(
    DragEndDetails details,
    double width,
  ) async {
    if (_busy) {
      return;
    }

    final double threshold = width * widget.deleteThreshold;

    final bool shouldDelete = -_offset >= threshold;

    _thresholdHapticTriggered = false;

    if (!shouldDelete) {
      await _animateTo(0);
      return;
    }

    await _requestDelete(width);
  }

  Future<void> _requestDelete(double width) async {
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
    });

    final bool confirmed = await widget.onConfirmDelete();

    if (!mounted) {
      return;
    }

    if (!confirmed) {
      setState(() {
        _busy = false;
      });

      await _animateTo(0);
      return;
    }

    HapticFeedback.mediumImpact();

    // Termina de sacar la tarjeta de la pantalla.
    await _animateTo(-width, duration: const Duration(milliseconds: 220));

    if (!mounted) {
      return;
    }

    await widget.onDelete();

    // Si la eliminación falló, el elemento seguirá montado.
    // En ese caso restauramos su posición.
    if (!mounted) {
      return;
    }

    setState(() {
      _busy = false;
    });

    await _animateTo(0);
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;

        _scheduleTutorial(width);

        final double revealProgress = (-_offset / 95).clamp(0.0, 1.0);

        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: Stack(
            children: [
              // Fondo de eliminación.
              //
              // Solo ocupa la parte que realmente ha quedado
              // descubierta al deslizar la tarjeta.
              // Así el rojo no queda detrás de toda la tarjeta.
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: (-_offset).clamp(0.0, width),
                child: Container(
                  color: widget.deleteColor,
                  padding: const EdgeInsets.only(right: 22),
                  alignment: Alignment.centerRight,
                  child: Opacity(
                    opacity: revealProgress,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.white,
                          size: 25,
                        ),

                        const SizedBox(height: 4),

                        Text(
                          widget.deleteLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Tarjeta.
              Transform.translate(
                offset: Offset(_offset, 0),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: _onHorizontalDragStart,
                  onHorizontalDragUpdate: (details) {
                    _onHorizontalDragUpdate(details, width);
                  },
                  onHorizontalDragEnd: (details) {
                    _onHorizontalDragEnd(details, width);
                  },
                  child: widget.child,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
