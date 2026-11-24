import 'dart:async';

import 'package:eduflow_ai/models/asignatura.dart';
import 'package:eduflow_ai/models/evaluacion.dart';
import 'package:eduflow_ai/models/nota.dart';
import 'package:eduflow_ai/models/tarea.dart';
import 'package:eduflow_ai/pages/calendar/calendar_page.dart';
import 'package:eduflow_ai/pages/evaluations/evaluations_page.dart';
import 'package:eduflow_ai/pages/tasks/tasks_page.dart';
import 'package:eduflow_ai/services/asignaturas_service.dart';
import 'package:eduflow_ai/services/evaluaciones_service.dart';
import 'package:eduflow_ai/services/notas_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime now = DateTime(2026, 9, 7);

  test('Tareas localiza por ID el elemento que debe abrir directamente', () {
    final List<Tarea> tasks = [
      Tarea(
        id: 'task-1',
        titulo: 'Primera',
        prioridad: PrioridadTarea.media,
        estado: EstadoTarea.pendiente,
        creadaEn: now,
        actualizadaEn: now,
      ),
      Tarea(
        id: 'task-2',
        titulo: 'Objetivo',
        prioridad: PrioridadTarea.alta,
        estado: EstadoTarea.pendiente,
        creadaEn: now,
        actualizadaEn: now,
      ),
    ];

    expect(findTaskForInitialDetail(tasks, 'task-2')?.titulo, 'Objetivo');
    expect(findTaskForInitialDetail(tasks, 'missing'), isNull);
  });

  test('Calendario localiza por ID la evaluación que debe enfocar', () {
    final List<Evaluacion> evaluations = [
      Evaluacion(
        id: 'evaluation-1',
        titulo: 'Unidad 1',
        asignaturaId: 'subject',
        tipo: TipoEvaluacion.prueba,
        fecha: now,
        creadaEn: now,
        actualizadaEn: now,
      ),
      Evaluacion(
        id: 'evaluation-2',
        titulo: 'Unidad 2',
        asignaturaId: 'subject',
        tipo: TipoEvaluacion.examen,
        fecha: now.add(const Duration(days: 1)),
        creadaEn: now,
        actualizadaEn: now,
      ),
    ];

    expect(
      findEvaluationForInitialDetail(evaluations, 'evaluation-2')?.titulo,
      'Unidad 2',
    );
    expect(findEvaluationForInitialDetail(evaluations, 'missing'), isNull);
    expect(
      findEvaluationForDetail(evaluations, 'evaluation-2')?.titulo,
      'Unidad 2',
    );
    expect(findEvaluationForDetail(evaluations, 'missing'), isNull);
  });

  test('Evaluaciones deriva el estado temporal sin persistirlo', () {
    Evaluacion evaluation(DateTime date) => Evaluacion(
      id: 'evaluation',
      titulo: 'Prueba',
      asignaturaId: 'subject',
      tipo: TipoEvaluacion.prueba,
      fecha: date,
      creadaEn: now,
      actualizadaEn: now,
    );

    expect(
      estadoTemporalEvaluacion(evaluation(DateTime(2026, 9, 6)), ahora: now),
      EstadoTemporalEvaluacion.anterior,
    );
    expect(
      estadoTemporalEvaluacion(evaluation(now), ahora: now),
      EstadoTemporalEvaluacion.hoy,
    );
    expect(
      estadoTemporalEvaluacion(evaluation(DateTime(2026, 9, 8)), ahora: now),
      EstadoTemporalEvaluacion.proxima,
    );
  });

  test('Tareas y evaluaciones se filtran por asignatura', () {
    final List<Tarea> tasks = [
      Tarea(
        id: 'task-a',
        titulo: 'Tarea A',
        asignaturaId: 'subject-a',
        prioridad: PrioridadTarea.media,
        estado: EstadoTarea.pendiente,
        creadaEn: now,
        actualizadaEn: now,
      ),
      Tarea(
        id: 'task-b',
        titulo: 'Tarea B',
        asignaturaId: 'subject-b',
        prioridad: PrioridadTarea.media,
        estado: EstadoTarea.pendiente,
        creadaEn: now,
        actualizadaEn: now,
      ),
    ];
    final List<Evaluacion> evaluations = [
      Evaluacion(
        id: 'evaluation-a',
        titulo: 'Evaluación A',
        asignaturaId: 'subject-a',
        tipo: TipoEvaluacion.prueba,
        fecha: now,
        creadaEn: now,
        actualizadaEn: now,
      ),
      Evaluacion(
        id: 'evaluation-b',
        titulo: 'Evaluación B',
        asignaturaId: 'subject-b',
        tipo: TipoEvaluacion.prueba,
        fecha: now,
        creadaEn: now,
        actualizadaEn: now,
      ),
    ];

    expect(filterTasksForSubject(tasks, 'subject-a').single.id, 'task-a');
    expect(
      filterEvaluationsForSubject(evaluations, 'subject-a').single.id,
      'evaluation-a',
    );
    expect(filterTasksForSubject(tasks, null), hasLength(2));
    expect(filterEvaluationsForSubject(evaluations, ''), hasLength(2));
  });

  testWidgets('Evaluaciones carga el listado y abre el detalle por ID', (
    tester,
  ) async {
    final DateTime today = DateTime.now();
    final Evaluacion evaluation = Evaluacion(
      id: 'evaluation-direct',
      titulo: 'Examen integrador',
      asignaturaId: 'subject',
      tipo: TipoEvaluacion.examen,
      fecha: today.add(const Duration(days: 2)),
      descripcion: 'Contenidos de todas las unidades.',
      ponderacion: 35,
      creadaEn: today,
      actualizadaEn: today,
    );
    final evaluationsService = EvaluacionesService(
      dataSource: _EvaluationsDataSource([evaluation]),
      uidProvider: () => 'user',
    );
    final subjectsService = AsignaturasService(
      dataSource: _SubjectsDataSource([
        const Asignatura(
          id: 'subject',
          nombre: 'Matemática',
          estado: EstadoAsignatura.enCurso,
          origen: OrigenAsignatura.manual,
        ),
      ]),
      uidProvider: () => 'user',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: EvaluationsPage(
          initialEvaluationId: evaluation.id,
          evaluacionesService: evaluationsService,
          asignaturasService: subjectsService,
          gradesLoader: () async => const DatosCalificacionesEvaluaciones(
            configuracion: ConfiguracionNotas.predeterminada,
            calificaciones: {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byKey(const ValueKey('evaluation-card-evaluation-direct')),
      findsOneWidget,
    );
    expect(find.text('Examen integrador'), findsWidgets);
    expect(find.text('Matemática'), findsWidgets);
    expect(find.text('Contenidos de todas las unidades.'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
  });

  testWidgets('Evaluaciones muestra una nota real y la retira al recargar', (
    tester,
  ) async {
    final DateTime yesterday = DateTime.now().subtract(const Duration(days: 1));
    final Evaluacion evaluation = Evaluacion(
      id: 'evaluation-graded',
      titulo: 'Prueba corregida',
      asignaturaId: 'subject',
      tipo: TipoEvaluacion.prueba,
      fecha: yesterday,
      creadaEn: yesterday,
      actualizadaEn: yesterday,
    );
    final dataSource = _EvaluationsDataSource([evaluation]);
    final gradeChanges = StreamController<void>.broadcast();
    final evaluationsService = EvaluacionesService(
      dataSource: dataSource,
      uidProvider: () => 'user',
    );
    final subjectsService = AsignaturasService(
      dataSource: _SubjectsDataSource([
        const Asignatura(
          id: 'subject',
          nombre: 'Matemática',
          estado: EstadoAsignatura.enCurso,
          origen: OrigenAsignatura.manual,
        ),
      ]),
      uidProvider: () => 'user',
    );
    DatosCalificacionesEvaluaciones grades =
        const DatosCalificacionesEvaluaciones(
          configuracion: ConfiguracionNotas(
            notaMinima: 1,
            notaMaxima: 7,
            notaAprobacion: 4,
            decimales: 1,
            politicaRedondeo: PoliticaRedondeoNotas.masCercano,
          ),
          calificaciones: {
            'evaluation-graded': CalificacionEvaluacion(
              evaluacionId: 'evaluation-graded',
              nota: 2.5,
            ),
          },
        );

    await tester.pumpWidget(
      MaterialApp(
        home: EvaluationsPage(
          evaluacionesService: evaluationsService,
          asignaturasService: subjectsService,
          gradesLoader: () async => grades,
          gradeChanges: () => gradeChanges.stream,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Anterior'), findsOneWidget);
    expect(find.text('Evaluada'), findsOneWidget);
    expect(find.text('Nota: 2,5'), findsOneWidget);
    expect(find.text('Aprobada'), findsNothing);
    final Text evaluatedLabel = tester.widget<Text>(find.text('Evaluada'));
    expect(evaluatedLabel.style?.color, const Color(0xFF059669));

    await tester.tap(
      find.byKey(const ValueKey('evaluation-card-evaluation-graded')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('evaluation-detail-graded')),
      findsOneWidget,
    );
    expect(find.text('2,5'), findsOneWidget);

    Navigator.of(tester.element(find.text('Prueba corregida').last)).pop();
    await tester.pumpAndSettle();
    grades = const DatosCalificacionesEvaluaciones(
      configuracion: ConfiguracionNotas.predeterminada,
      calificaciones: {},
    );
    gradeChanges.add(null);
    await tester.pumpAndSettle();

    expect(find.text('Anterior'), findsOneWidget);
    expect(find.text('Evaluada'), findsNothing);
    expect(find.text('Nota: 2,5'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await gradeChanges.close();
    await dataSource.dispose();
  });
}

class _EvaluationsDataSource implements EvaluacionesDataSource {
  _EvaluationsDataSource(this.items);

  final List<Evaluacion> items;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  Future<void> dispose() => _changes.close();

  @override
  Future<List<Evaluacion>> obtenerTodas(String uid) async => List.of(items);

  @override
  Future<Evaluacion?> obtenerPorId(String uid, String id) async {
    for (final Evaluacion item in items) {
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
  Stream<void> observarCambios(String uid) => _changes.stream;
}

class _SubjectsDataSource implements AsignaturasDataSource {
  _SubjectsDataSource(this.items);

  final List<Asignatura> items;

  @override
  Future<List<Asignatura>> obtenerTodas(String uid) async => List.of(items);

  @override
  Future<Asignatura?> obtenerPorId(String uid, String id) async {
    for (final Asignatura item in items) {
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
