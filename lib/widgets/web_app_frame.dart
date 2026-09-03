import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/platform/web_environment.dart';

/// Completa los insets web sin sumarlos a los que ya proporcione el motor.
/// El teclado sigue descontándose del padding inferior como en Flutter nativo.
MediaQueryData withWebSafeArea(MediaQueryData data, EdgeInsets safeArea) {
  final padding = EdgeInsets.fromLTRB(
    math.max(data.viewPadding.left, safeArea.left),
    math.max(data.viewPadding.top, safeArea.top),
    math.max(data.viewPadding.right, safeArea.right),
    math.max(data.viewPadding.bottom, safeArea.bottom),
  );
  return data.copyWith(
    viewPadding: padding,
    padding: EdgeInsets.fromLTRB(
      math.max(0, padding.left - data.viewInsets.left),
      math.max(0, padding.top - data.viewInsets.top),
      math.max(0, padding.right - data.viewInsets.right),
      math.max(0, padding.bottom - data.viewInsets.bottom),
    ),
  );
}

class WebAppFrame extends StatefulWidget {
  const WebAppFrame({super.key, required this.dark, required this.child});

  final bool dark;
  final Widget child;

  @override
  State<WebAppFrame> createState() => _WebAppFrameState();
}

class _WebAppFrameState extends State<WebAppFrame> with WidgetsBindingObserver {
  bool _metricsScheduled = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WidgetsBinding.instance.addObserver(this);
      syncWebTheme(widget.dark);
    }
  }

  @override
  void didUpdateWidget(WebAppFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (kIsWeb && oldWidget.dark != widget.dark) syncWebTheme(widget.dark);
  }

  @override
  void didChangeMetrics() {
    if (_metricsScheduled) return;
    _metricsScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _metricsScheduled = false;
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    if (kIsWeb) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return widget.child;
    return MediaQuery(
      data: withWebSafeArea(MediaQuery.of(context), readWebSafeArea()),
      child: widget.child,
    );
  }
}
