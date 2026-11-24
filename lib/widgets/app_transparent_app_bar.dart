import 'package:flutter/material.dart';

/// Cabecera compacta para rutas sin encabezado grande desplazable.
/// Comparte la apariencia del encabezado desplazable sin desenfoque nativo.
class AppTransparentAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const AppTransparentAppBar({super.key, required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: dark ? const Color(0xEB18181C) : const Color(0xE8FFFFFF),
      leadingWidth: 58,
      leading: Navigator.canPop(context)
          ? Center(
              child: IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.maybePop(context),
                style: IconButton.styleFrom(
                  fixedSize: const Size(38, 38),
                  backgroundColor: dark
                      ? const Color(0xFF222833)
                      : const Color(0xFFF4F5F8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: dark
                          ? const Color(0xFF303744)
                          : const Color(0xFFE2E6ED),
                    ),
                  ),
                ),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
            )
          : null,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w800,
          letterSpacing: -.4,
        ),
      ),
      actions: actions,
      shape: Border(
        bottom: BorderSide(
          color: dark ? const Color(0xAA303036) : const Color(0xAAE3E6ED),
        ),
      ),
    );
  }
}
