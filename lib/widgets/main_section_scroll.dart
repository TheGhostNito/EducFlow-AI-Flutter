import 'package:flutter/widgets.dart';

/// Lleva una sección principal a su inicio sin alterar la ruta actual.
Future<void> scrollMainSectionToTop(
  BuildContext context,
  ScrollController controller,
) async {
  if (!controller.hasClients) return;

  final double top = controller.position.minScrollExtent;
  if (controller.offset <= top + 1) return;

  if (MediaQuery.disableAnimationsOf(context)) {
    controller.jumpTo(top);
    return;
  }

  await controller.animateTo(
    top,
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
  );
}
