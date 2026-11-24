import 'package:eduflow_ai/models/evaluacion.dart';
import 'package:eduflow_ai/models/nota.dart';
import 'package:eduflow_ai/pages/grades/widgets/grade_scheme_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('configura presentación y examen con el selector propio', (
    tester,
  ) async {
    ConfiguracionCalculoAsignatura? saved;
    final DateTime now = DateTime(2026, 10, 8);
    final Evaluacion exam = Evaluacion(
      id: 'exam',
      titulo: 'Examen final',
      asignaturaId: 'subject',
      tipo: TipoEvaluacion.examen,
      fecha: now,
      creadaEn: now,
      actualizadaEn: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showGradeSchemeDialog(
                context: context,
                initial: ConfiguracionCalculoAsignatura.directa('subject'),
                evaluaciones: [exam],
                spanish: true,
                onSave: (value) async => saved = value,
              ),
              child: const Text('Configurar'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Configurar'));
    await tester.pumpAndSettle();
    expect(find.text('Esquema de cálculo'), findsOneWidget);
    expect(find.text('Cálculo directo'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('grade-scheme-presentacionExamen')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('grade-scheme-exam')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('grade-scheme-exam-exam')));
    await tester.pumpAndSettle();
    final Finder saveButton = find.byKey(const ValueKey('save-grade-scheme'));
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(saved?.esquema, EsquemaCalculoNotas.presentacionExamen);
    expect(saved?.evaluacionExamenId, 'exam');
    expect(saved?.pesoPresentacion, 60);
    expect(saved?.pesoExamen, 40);
  });
}
