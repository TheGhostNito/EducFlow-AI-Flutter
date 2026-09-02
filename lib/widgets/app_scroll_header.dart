import 'dart:ui';

import 'package:flutter/material.dart';

class AppScrollHeader extends StatelessWidget {
  const AppScrollHeader({
    super.key,
    required this.progress,
    required this.title,
    this.leading,
    this.trailing,
  });

  final double progress;
  final String title;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final bool oscuro = Theme.of(context).brightness == Brightness.dark;

    final double safeTop = MediaQuery.paddingOf(context).top;

    // Algunas pantallas pequeñas no alcanzan suficiente scroll
    // para que el progreso calculado por la página llegue a 1.
    // Remapeamos el progreso para que el header compacto pueda
    // completar la animación igualmente.
    final double rawProgress = progress.clamp(0.0, 1.0);

    final double normalizedProgress = ((rawProgress - 0.04) / 0.50).clamp(
      0.0,
      1.0,
    );

    final double visualProgress = Curves.easeOutCubic.transform(
      normalizedProgress,
    );

    return IgnorePointer(
      // Antes se esperaba hasta 0.85. Eso hacía que la flecha
      // pudiera verse pero todavía no responder al toque.
      ignoring: visualProgress < 0.12,
      child: Opacity(
        opacity: visualProgress,
        child: Transform.translate(
          offset: Offset(0, -18 * (1 - visualProgress)),
          child: ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: EdgeInsets.fromLTRB(12, safeTop + 7, 12, 9),
                decoration: BoxDecoration(
                  color: oscuro
                      ? const Color(0xEB18181C)
                      : const Color(0xE8FFFFFF),
                  border: Border(
                    bottom: BorderSide(
                      color: oscuro
                          ? const Color(0xAA303036)
                          : const Color(0xAAE3E6ED),
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: oscuro
                          ? const Color(0x26000000)
                          : const Color(0x120F172A),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: SizedBox(
                  height: 46,
                  child: Row(
                    children: [
                      if (leading != null) ...[
                        leading!,
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: oscuro
                                ? const Color(0xFFF8FAFC)
                                : const Color(0xFF111827),
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: 10),
                        trailing!,
                      ],
                    ],
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
