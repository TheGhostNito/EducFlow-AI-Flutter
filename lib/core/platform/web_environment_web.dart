import 'dart:js_interop';

import 'package:flutter/widgets.dart';

@JS('educflowPwa.setTheme')
external void _setTheme(JSBoolean dark);

@JS('educflowPwa.getSafeArea')
external JSArray<JSNumber> _getSafeArea();

void syncWebTheme(bool dark) => _setTheme(dark.toJS);

EdgeInsets readWebSafeArea() {
  final values = _getSafeArea().toDart;
  return EdgeInsets.fromLTRB(
    values[0].toDartDouble,
    values[1].toDartDouble,
    values[2].toDartDouble,
    values[3].toDartDouble,
  );
}
