import 'package:eduflow_ai/widgets/web_app_frame.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'propaga notch e indicador inferior sin duplicar el padding del motor',
    () {
      const safe = EdgeInsets.fromLTRB(0, 59, 0, 34);
      final data = withWebSafeArea(
        const MediaQueryData(viewPadding: safe),
        safe,
      );
      expect(data.padding, safe);
      expect(data.viewPadding, safe);
      expect(withWebSafeArea(data, safe).padding, safe);
    },
  );

  test('el teclado conserva su inset y consume el padding inferior', () {
    const keyboard = EdgeInsets.only(bottom: 300);
    final data = withWebSafeArea(
      const MediaQueryData(viewInsets: keyboard),
      const EdgeInsets.only(top: 59, bottom: 34),
    );
    expect(data.padding, const EdgeInsets.only(top: 59));
    expect(data.viewPadding.bottom, 34);
    expect(data.viewInsets, keyboard);
  });

  test('la orientación horizontal protege ambos bordes', () {
    final data = withWebSafeArea(
      const MediaQueryData(),
      const EdgeInsets.fromLTRB(59, 0, 59, 21),
    );
    expect(data.padding, const EdgeInsets.fromLTRB(59, 0, 59, 21));
  });

  test('sin áreas inseguras mantiene las dimensiones de escritorio', () {
    const original = MediaQueryData(size: Size(1280, 720), devicePixelRatio: 2);
    expect(withWebSafeArea(original, EdgeInsets.zero), original);
  });
}
