import 'package:eduflow_ai/widgets/app_scroll_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('el encabezado opaco omite el desenfoque del contenido', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Stack(
          children: [
            ColoredBox(color: Colors.green),
            AppScrollHeader(
              progress: 1,
              title: 'Inicio',
              opaqueBackground: true,
            ),
          ],
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    final Container decorated = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(AppScrollHeader),
            matching: find.byType(Container),
          )
          .first,
    );
    final BoxDecoration decoration = decorated.decoration! as BoxDecoration;
    expect(decoration.color, Colors.white);
  });

  testWidgets('el encabezado estándar evita desenfoque nativo', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppScrollHeader(progress: 1, title: 'Asignaturas'),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
  });
}
