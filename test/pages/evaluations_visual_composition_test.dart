import 'package:eduflow_ai/models/asignatura.dart';
import 'package:eduflow_ai/models/evaluacion.dart';
import 'package:eduflow_ai/models/nota.dart';
import 'package:eduflow_ai/pages/evaluations/evaluations_page.dart';
import 'package:eduflow_ai/services/asignaturas_service.dart';
import 'package:eduflow_ai/services/evaluaciones_service.dart';
import 'package:eduflow_ai/services/notas_service.dart';
import 'package:eduflow_ai/widgets/app_scroll_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Evaluaciones evita desenfocar tarjetas evaluadas bajo la cabecera',
    (tester) async {
      final now = DateTime.now();
      final evaluations = List.generate(
        8,
        (index) => Evaluacion(
          id: index == 0 ? 'evaluation-graded' : 'evaluation-$index',
          titulo: index == 0 ? 'Prueba corregida' : 'Evaluación $index',
          asignaturaId: 'subject',
          tipo: TipoEvaluacion.prueba,
          fecha: now.subtract(Duration(days: index + 1)),
          creadaEn: now,
          actualizadaEn: now,
        ),
      );
      final evaluationsService = EvaluacionesService(
        dataSource: _EvaluationsDataSource(evaluations),
        uidProvider: () => 'user',
      );
      final subjectsService = AsignaturasService(
        dataSource: const _SubjectsDataSource([
          Asignatura(
            id: 'subject',
            nombre: 'Matemática',
            estado: EstadoAsignatura.enCurso,
            origen: OrigenAsignatura.manual,
          ),
        ]),
        uidProvider: () => 'user',
      );

      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: EvaluationsPage(
              evaluacionesService: evaluationsService,
              asignaturasService: subjectsService,
              gradesLoader: () async => const DatosCalificacionesEvaluaciones(
                configuracion: ConfiguracionNotas.predeterminada,
                calificaciones: {
                  'evaluation-graded': CalificacionEvaluacion(
                    evaluacionId: 'evaluation-graded',
                    nota: 5.5,
                  ),
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Evaluada'), findsOneWidget);
        final evaluatedLabel = tester.widget<Text>(find.text('Evaluada'));
        expect(evaluatedLabel.style?.color, const Color(0xFF059669));
        expect(find.byType(BackdropFilter), findsNothing);

        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pumpAndSettle();

        final headerOpacity = tester.widget<Opacity>(
          find
              .descendant(
                of: find.byType(AppScrollHeader),
                matching: find.byType(Opacity),
              )
              .first,
        );
        expect(headerOpacity.opacity, greaterThan(0));
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.text('Evaluada'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );
}

class _EvaluationsDataSource implements EvaluacionesDataSource {
  const _EvaluationsDataSource(this.items);

  final List<Evaluacion> items;

  @override
  Future<List<Evaluacion>> obtenerTodas(String uid) async => List.of(items);

  @override
  Future<Evaluacion?> obtenerPorId(String uid, String id) async {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Future<Evaluacion> crear(String uid, Evaluacion evaluacion) async =>
      evaluacion;

  @override
  Future<void> actualizar(String uid, Evaluacion evaluacion) async {}

  @override
  Future<void> eliminar(String uid, String id) async {}

  @override
  Stream<void> observarCambios(String uid) => const Stream<void>.empty();
}

class _SubjectsDataSource implements AsignaturasDataSource {
  const _SubjectsDataSource(this.items);

  final List<Asignatura> items;

  @override
  Future<List<Asignatura>> obtenerTodas(String uid) async => List.of(items);

  @override
  Future<Asignatura?> obtenerPorId(String uid, String id) async {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Future<void> agregar(String uid, Asignatura asignatura) async {}

  @override
  Future<void> actualizar(String uid, Asignatura asignatura) async {}

  @override
  Future<void> eliminar(String uid, String id) async {}

  @override
  Stream<void> observarCambios(String uid) => const Stream<void>.empty();
}
