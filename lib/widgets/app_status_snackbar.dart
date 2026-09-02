import 'package:flutter/material.dart';

enum AppStatusType { success, error, warning, info }

void showAppStatusSnackBar(
  BuildContext context, {
  required String message,
  AppStatusType type = AppStatusType.success,
  Duration duration = const Duration(seconds: 3),
  double bottomMargin = 16,
}) {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        padding: EdgeInsets.zero,
        margin: EdgeInsets.fromLTRB(12, 0, 12, bottomMargin),
        content: _AppStatusSnackBar(
          message: message,
          type: type,
          duration: duration,
        ),
      ),
    );
}

class _AppStatusSnackBar extends StatefulWidget {
  const _AppStatusSnackBar({
    required this.message,
    required this.type,
    required this.duration,
  });

  final String message;
  final AppStatusType type;
  final Duration duration;

  @override
  State<_AppStatusSnackBar> createState() => _AppStatusSnackBarState();
}

class _AppStatusSnackBarState extends State<_AppStatusSnackBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: 1,
    );

    _controller.reverse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _accent {
    switch (widget.type) {
      case AppStatusType.success:
        return const Color(0xFF22C55E);

      case AppStatusType.error:
        return const Color(0xFFEF4444);

      case AppStatusType.warning:
        return const Color(0xFFF59E0B);

      case AppStatusType.info:
        return const Color(0xFF5B5FEF);
    }
  }

  IconData get _icon {
    switch (widget.type) {
      case AppStatusType.success:
        return Icons.check_circle_outline_rounded;

      case AppStatusType.error:
        return Icons.error_outline_rounded;

      case AppStatusType.warning:
        return Icons.warning_amber_rounded;

      case AppStatusType.info:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF18181D) : Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: dark ? const Color(0xFF303038) : const Color(0xFFE3E6ED),
        ),
        boxShadow: dark
            ? const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ]
            : const [
                BoxShadow(
                  color: Color(0x2110172A),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 37,
                  height: 37,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: dark ? 0.16 : 0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(_icon, color: _accent, size: 20),
                ),

                const SizedBox(width: 11),

                Expanded(
                  child: Text(
                    widget.message,
                    style: TextStyle(
                      color: dark
                          ? const Color(0xFFF8FAFC)
                          : const Color(0xFF1F2937),
                      fontSize: 13,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: _controller.value,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
