import 'package:eduflow_ai/models/asignatura.dart';
import 'package:eduflow_ai/models/evaluacion.dart';
import 'package:eduflow_ai/models/nota.dart';
import 'package:eduflow_ai/models/perfil_usuario.dart';
import 'package:eduflow_ai/pages/grades/subject_grades_page.dart';
import 'package:eduflow_ai/pages/grades/grades_page.dart';
import 'package:eduflow_ai/pages/grades/widgets/grade_input_dialogs.dart';
import 'package:eduflow_ai/services/notas_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const configuration = ConfiguracionNotas.predeterminada;

  testWidgets('cancelar objetivo enfocado diez veces no deja excepciones', (
    tester,
  ) async {
    await tester.pumpWidget(
      _dialogHost(
        onPressed: (context) => showTargetGradeDialog(
          context: context,
          initialValue: 4,
          configuration: configuration,
          spanish: true,
          onSave: (_) async {},
        ),
      ),
    );

    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.tap(find.byKey(const ValueKey('open-dialog')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('grade-goal-input')));
      await tester.enterText(
        find.byKey(const ValueKey('grade-goal-input')),
        '5,5',
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('cancelar editor enfocado diez veces no deja excepciones', (
    tester,
  ) async {
    await tester.pumpWidget(
      _dialogHost(
        onPressed: (context) => showEvaluationGradeDialog(
          context: context,
          title: 'Unidad 2',
          initialGrade: null,
          initialWeight: 40,
          otherWeight: 60,
          configuration: configuration,
          spanish: true,
          onSave: (_) async {},
        ),
      ),
    );

    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.tap(find.byKey(const ValueKey('open-dialog')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('grade-earned-input')));
      await tester.enterText(
        find.byKey(const ValueKey('grade-earned-input')),
        '5,5',
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('guarda un nuevo objetivo decimal antes de cerrar', (
    tester,
  ) async {
    double? saved;
    await tester.pumpWidget(
      _dialogHost(
        onPressed: (context) => showTargetGradeDialog(
          context: context,
          initialValue: 4,
          configuration: configuration,
          spanish: true,
          onSave: (value) async => saved = value,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-dialog')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('grade-goal-input')),
      '5,8',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(saved, 5.8);
    expect(find.byKey(const ValueKey('grade-goal-input')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('registra, edita y quita una nota real usando coma decimal', (
    tester,
  ) async {
    final rows = <String, double>{};
    double? initialGrade;

    Future<void> openDialog(BuildContext context) async {
      await showEvaluationGradeDialog(
        context: context,
        title: 'Unidad 2',
        initialGrade: initialGrade,
        initialWeight: 40,
        otherWeight: 60,
        configuration: configuration,
        spanish: true,
        onSave: (value) async {
          initialGrade = value.nota;
          if (value.nota == null) {
            rows.remove('evaluacion-1');
          } else {
            rows['evaluacion-1'] = value.nota!;
          }
        },
      );
    }

    await tester.pumpWidget(_dialogHost(onPressed: openDialog));

    await tester.tap(find.byKey(const ValueKey('open-dialog')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('grade-earned-input')),
      '5,5',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(rows['evaluacion-1'], 5.5);

    await tester.tap(find.byKey(const ValueKey('open-dialog')));
    await tester.pumpAndSettle();
    final reopened = tester.widget<TextField>(
      find.byKey(const ValueKey('grade-earned-input')),
    );
    expect(reopened.controller?.text, '5,5');
    await tester.enterText(
      find.byKey(const ValueKey('grade-earned-input')),
      '6,1',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(rows['evaluacion-1'], 6.1);

    await tester.tap(find.byKey(const ValueKey('open-dialog')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('grade-earned-input')),
      '',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(rows, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ponderación valida rango y suma antes de guardar', (
    tester,
  ) async {
    GradeEvaluationEdit? saved;
    await tester.pumpWidget(
      _dialogHost(
        onPressed: (context) => showEvaluationGradeDialog(
          context: context,
          title: 'Unidad 2',
          initialGrade: null,
          initialWeight: null,
          otherWeight: 80,
          configuration: configuration,
          spanish: true,
          onSave: (value) async => saved = value,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-dialog')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('grade-weight-input')),
      '25',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    expect(saved, isNull);
    expect(find.textContaining('no puede superar 100'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('grade-weight-input')),
      '20',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(saved?.ponderacion, 20);
  });

  testWidgets('tocar fuera de Hipótesis elimina el foco', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final date = DateTime(2026, 10, 4);
    final evaluation = Evaluacion(
      id: 'evaluacion-1',
      titulo: 'Unidad 2',
      asignaturaId: 'asignatura-1',
      tipo: TipoEvaluacion.prueba,
      fecha: date,
      ponderacion: 100,
      creadaEn: date,
      actualizadaEn: date,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SubjectGradesPage(
          asignatura: const Asignatura(
            id: 'asignatura-1',
            nombre: 'Matemática',
            estado: EstadoAsignatura.enCurso,
            origen: OrigenAsignatura.manual,
          ),
          evaluaciones: [evaluation],
          datosNotas: const DatosNotasUsuario(
            asignaturas: [],
            evaluaciones: [],
            configuracion: configuration,
            calificaciones: {},
            objetivos: {},
          ),
          notasService: NotasService(
            dataSource: _NoopNotasDataSource(),
            uidProvider: () => 'usuario-test',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = find
        .byKey(const ValueKey('grade-scenario-input-evaluacion-1'))
        .first;
    await tester.tap(field);
    await tester.enterText(field, '5,5');
    var editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);

    final panel = tester.getRect(
      find.byKey(const ValueKey('grades-scenario-panel')),
    );
    await tester.tapAt(panel.topLeft + const Offset(24, 24));
    await tester.pump();

    editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isFalse);
  });

  testWidgets('configuración libera foco y persiste antes de cerrar', (
    tester,
  ) async {
    ConfiguracionNotas? saved;
    await tester.pumpWidget(
      _dialogHost(
        onPressed: (context) => showGradeSettingsDialog(
          context: context,
          initial: configuration,
          spanish: true,
          onSave: (value) async => saved = value,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-dialog')));
    await tester.pumpAndSettle();
    final minField = find.byKey(const ValueKey('grade-settings-min-input'));
    await tester.tap(minField);
    var input = tester.widget<TextField>(minField);
    expect(input.focusNode?.hasFocus, isTrue);
    await tester.tap(find.text('Configurar escala'));
    await tester.pump();
    input = tester.widget<TextField>(minField);
    expect(input.focusNode?.hasFocus, isFalse);

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(saved?.notaMinima, configuration.notaMinima);
    expect(saved?.notaMaxima, configuration.notaMaxima);
    expect(saved?.notaAprobacion, configuration.notaAprobacion);
    expect(saved?.decimales, configuration.decimales);
    expect(saved?.politicaRedondeo, configuration.politicaRedondeo);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tarjeta abre detalle y Editar abre el formulario', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final date = DateTime(2026, 10, 5);
    final evaluation = Evaluacion(
      id: 'evaluacion-detalle',
      titulo: 'Unidad 2',
      asignaturaId: 'asignatura-1',
      tipo: TipoEvaluacion.prueba,
      fecha: date,
      ponderacion: 100,
      creadaEn: date,
      actualizadaEn: date,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SubjectGradesPage(
          asignatura: const Asignatura(
            id: 'asignatura-1',
            nombre: 'Matemática',
            estado: EstadoAsignatura.enCurso,
            origen: OrigenAsignatura.manual,
          ),
          evaluaciones: [evaluation],
          datosNotas: const DatosNotasUsuario(
            asignaturas: [],
            evaluaciones: [],
            configuracion: configuration,
            calificaciones: {
              'evaluacion-detalle': CalificacionEvaluacion(
                evaluacionId: 'evaluacion-detalle',
                nota: 5.5,
              ),
            },
            objetivos: {},
          ),
          notasService: NotasService(
            dataSource: _NoopNotasDataSource(),
            uidProvider: () => 'usuario-test',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('subject-final-grade-summary')),
      findsOneWidget,
    );
    expect(find.text('EVALUADO · APROBADO'), findsOneWidget);
    expect(
      find.text('Nota final 5,5. Objetivo personal alcanzado.'),
      findsOneWidget,
    );

    final card = find.byKey(
      const ValueKey('evaluation-grade-card-evaluacion-detalle'),
    );
    await tester.ensureVisible(card);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('evaluation-grade-detail-title')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('evaluation-grade-detail-grade')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('edit-evaluation-grade')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('grade-earned-input')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tarjeta finalizada prioriza nota final sobre objetivo personal',
    (tester) async {
      final source = _NoopNotasDataSource(
        assignments: const [
          {
            'id': 'big-data',
            'nombre': 'Big Data',
            'estado': 'en_curso',
            'origen': 'manual',
          },
        ],
        evaluations: const [
          {
            'id': 'final-big-data',
            'titulo': 'Evaluación final',
            'asignatura_id': 'big-data',
            'tipo': 'examen',
            'fecha': '2026-10-05',
            'ponderacion': 100,
            'creada_en': '2026-10-05T12:00:00Z',
            'actualizada_en': '2026-10-05T12:00:00Z',
          },
        ],
        grades: const [
          {'evaluacion_id': 'final-big-data', 'nota': 5.8},
        ],
        goals: const [
          {'asignatura_id': 'big-data', 'nota_objetivo': 6.0},
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GradesPage(
            notasService: NotasService(
              dataSource: source,
              uidProvider: () => 'usuario-test',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('grades-final-state-big-data')),
        findsOneWidget,
      );
      expect(find.text('Evaluado'), findsOneWidget);
      expect(find.text('NOTA FINAL'), findsOneWidget);
      expect(find.text('APROBADO'), findsOneWidget);
      expect(find.text('Objetivo personal no alcanzado.'), findsOneWidget);
      expect(find.text('PENDIENTE'), findsNothing);
      expect(find.textContaining('Necesitas'), findsNothing);
    },
  );

  testWidgets(
    'presentación y examen completos muestran nota final definitiva',
    (tester) async {
      final date = DateTime(2026, 10, 5);
      final coursework = Evaluacion(
        id: 'coursework',
        titulo: 'Presentación',
        asignaturaId: 'big-data',
        tipo: TipoEvaluacion.presentacion,
        fecha: date,
        ponderacion: 100,
        creadaEn: date,
        actualizadaEn: date,
      );
      final exam = Evaluacion(
        id: 'exam',
        titulo: 'Examen',
        asignaturaId: 'big-data',
        tipo: TipoEvaluacion.examen,
        fecha: date,
        ponderacion: 0,
        creadaEn: date,
        actualizadaEn: date,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SubjectGradesPage(
            asignatura: const Asignatura(
              id: 'big-data',
              nombre: 'Big Data',
              estado: EstadoAsignatura.enCurso,
              origen: OrigenAsignatura.manual,
            ),
            evaluaciones: [coursework, exam],
            datosNotas: const DatosNotasUsuario(
              asignaturas: [],
              evaluaciones: [],
              configuracion: configuration,
              calificaciones: {
                'coursework': CalificacionEvaluacion(
                  evaluacionId: 'coursework',
                  nota: 5.8,
                ),
                'exam': CalificacionEvaluacion(evaluacionId: 'exam', nota: 4.5),
              },
              objetivos: {
                'big-data': ObjetivoNotaAsignatura(
                  asignaturaId: 'big-data',
                  notaObjetivo: 6,
                ),
              },
              configuracionesCalculo: {
                'big-data': ConfiguracionCalculoAsignatura(
                  asignaturaId: 'big-data',
                  esquema: EsquemaCalculoNotas.presentacionExamen,
                  pesoPresentacion: 60,
                  pesoExamen: 40,
                  evaluacionExamenId: 'exam',
                ),
              },
              nivelEducativo: NivelEducativoPerfil.superior,
            ),
            notasService: NotasService(
              dataSource: _NoopNotasDataSource(),
              uidProvider: () => 'usuario-test',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('subject-final-grade-summary')),
        findsOneWidget,
      );
      expect(find.text('EVALUADO · APROBADO'), findsOneWidget);
      expect(find.text('5,3'), findsWidgets);
      expect(find.textContaining('Necesitas promediar'), findsNothing);
    },
  );

  testWidgets('volver del detalle conserva intencionalmente el scroll', (
    tester,
  ) async {
    final assignments = List.generate(
      12,
      (index) => <String, dynamic>{
        'id': 'asignatura-$index',
        'nombre': 'Asignatura $index',
        'estado': 'en_curso',
        'origen': 'manual',
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GradesPage(
          notasService: NotasService(
            dataSource: _NoopNotasDataSource(assignments: assignments),
            uidProvider: () => 'usuario-test',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final target = find.byKey(
      const ValueKey('grades-subject-card-asignatura-3'),
    );
    await tester.drag(
      find.byKey(const ValueKey('grades-subject-list')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    final listScrollable = find
        .descendant(
          of: find.byKey(const ValueKey('grades-subject-list')),
          matching: find.byType(Scrollable),
        )
        .first;
    final before = tester
        .state<ScrollableState>(listScrollable)
        .position
        .pixels;
    expect(before, greaterThan(0));

    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(find.byType(SubjectGradesPage), findsOneWidget);
    Navigator.of(tester.element(find.byType(SubjectGradesPage))).pop();
    await tester.pumpAndSettle();

    final after = tester.state<ScrollableState>(listScrollable).position.pixels;
    expect(after, closeTo(before, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('solo perfil superior ofrece el esquema avanzado', (
    tester,
  ) async {
    final date = DateTime(2026, 10, 5);
    final evaluation = Evaluacion(
      id: 'final',
      titulo: 'Examen',
      asignaturaId: 'asignatura-1',
      tipo: TipoEvaluacion.examen,
      fecha: date,
      ponderacion: 100,
      creadaEn: date,
      actualizadaEn: date,
    );

    Widget page(NivelEducativoPerfil level) {
      return MaterialApp(
        home: SubjectGradesPage(
          asignatura: const Asignatura(
            id: 'asignatura-1',
            nombre: 'Matemática',
            estado: EstadoAsignatura.enCurso,
            origen: OrigenAsignatura.manual,
          ),
          evaluaciones: [evaluation],
          datosNotas: DatosNotasUsuario(
            asignaturas: const [],
            evaluaciones: const [],
            configuracion: configuration,
            calificaciones: const {},
            objetivos: const {},
            nivelEducativo: level,
          ),
          notasService: NotasService(
            dataSource: _NoopNotasDataSource(),
            uidProvider: () => 'usuario-test',
          ),
        ),
      );
    }

    await tester.pumpWidget(page(NivelEducativoPerfil.media));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('configure-grade-scheme')), findsNothing);

    await tester.pumpWidget(page(NivelEducativoPerfil.superior));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('configure-grade-scheme')),
      findsOneWidget,
    );
  });
}

class _NoopNotasDataSource implements NotasDataSource {
  _NoopNotasDataSource({
    this.assignments = const [],
    this.evaluations = const [],
    this.grades = const [],
    this.goals = const [],
  });

  final List<Map<String, dynamic>> assignments;
  final List<Map<String, dynamic>> evaluations;
  final List<Map<String, dynamic>> grades;
  final List<Map<String, dynamic>> goals;
  @override
  Future<List<Map<String, dynamic>>> obtenerConfiguracionesCalculo(
    String uid,
  ) async => const [];

  @override
  Future<Map<String, dynamic>?> obtenerNivelEducativo(String uid) async => null;

  @override
  Future<void> guardarConfiguracionCalculo(Map<String, dynamic> values) async {}

  @override
  Future<void> eliminarCalificacion(String uid, String evaluacionId) async {}

  @override
  Future<void> guardarCalificacion(Map<String, dynamic> values) async {}

  @override
  Future<void> guardarConfiguracion(Map<String, dynamic> values) async {}

  @override
  Future<void> guardarObjetivo(Map<String, dynamic> values) async {}

  @override
  Future<void> guardarPonderacion(
    String uid,
    String evaluacionId,
    double? ponderacion,
  ) async {}

  @override
  Future<List<Map<String, dynamic>>> obtenerAsignaturas(String uid) async =>
      assignments;

  @override
  Future<List<Map<String, dynamic>>> obtenerCalificaciones(String uid) async =>
      grades;

  @override
  Future<Map<String, dynamic>?> obtenerConfiguracion(String uid) async => null;

  @override
  Future<List<Map<String, dynamic>>> obtenerEvaluaciones(String uid) async =>
      evaluations;

  @override
  Future<List<Map<String, dynamic>>> obtenerObjetivos(String uid) async =>
      goals;
}

Widget _dialogHost({
  required Future<Object?> Function(BuildContext context) onPressed,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: FilledButton(
            key: const ValueKey('open-dialog'),
            onPressed: () => onPressed(context),
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
}
