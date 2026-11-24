import 'package:eduflow_ai/widgets/app_full_screen_loading.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('usa una carga discreta sin estilo de depuración', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppFullScreenLoading(
          title: 'Cargando tu horario',
          description: 'Recuperando el documento original.',
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('Cargando tu horario'));
    final progress = tester.widget<SizedBox>(
      find.ancestor(
        of: find.byType(CircularProgressIndicator),
        matching: find.byType(SizedBox),
      ),
    );

    expect(title.style?.fontSize, 17);
    expect(title.style?.decoration, TextDecoration.none);
    expect(progress.width, 30);
    expect(progress.height, 30);
    expect(tester.takeException(), isNull);
  });
}
