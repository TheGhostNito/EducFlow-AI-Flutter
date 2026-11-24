import 'package:eduflow_ai/pages/settings/settings_page.dart';
import 'package:eduflow_ai/services/translation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ionicons/ionicons.dart';

void main() {
  setUp(() => TranslationService.instance.applyUserPreference('es'));

  testWidgets('Ajustes conserva navegación sin laboratorio OCR', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              ),
              child: const Text('Abrir ajustes'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir ajustes'));
    await tester.pumpAndSettle();

    expect(find.text('APARIENCIA'), findsOneWidget);
    expect(find.text('INICIO'), findsOneWidget);
    expect(find.text('Prueba OCR Storage'), findsNothing);
    expect(find.text('OCR'), findsNothing);
    await tester.tap(
      find.ancestor(
        of: find.byIcon(Ionicons.chevronBackOutline).first,
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Abrir ajustes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
