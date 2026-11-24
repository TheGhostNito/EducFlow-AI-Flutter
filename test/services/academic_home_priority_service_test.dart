import 'package:eduflow_ai/models/evaluacion.dart';
import 'package:eduflow_ai/models/tarea.dart';
import 'package:eduflow_ai/services/academic_home_priority_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const AcademicHomePriorityService service = AcademicHomePriorityService();
  final DateTime now = DateTime(2026, 9, 7, 12);

  Tarea task(String id, int days, {EstadoTarea state = EstadoTarea.pendiente}) {
    return Tarea(
      id: id,
      titulo: 'Tarea $id',
      prioridad: PrioridadTarea.media,
      estado: state,
      fechaEntrega: DateTime(2026, 9, 7 + days),
      creadaEn: now,
      actualizadaEn: now,
    );
  }

  Evaluacion evaluation(String id, int days, {String? time}) {
    return Evaluacion(
      id: id,
      titulo: 'Evaluación $id',
      asignaturaId: 'subject',
      tipo: TipoEvaluacion.prueba,
      fecha: DateTime(2026, 9, 7 + days),
      hora: time,
      creadaEn: now,
      actualizadaEn: now,
    );
  }

  test('selecciona la tarea pendiente con fecha más cercana', () {
    final Tarea? selected = service.selectNextTask([
      task('lejana', 5),
      task('completada', 1, state: EstadoTarea.completada),
      task('cercana', 2),
    ], now: now);

    expect(selected?.id, 'cercana');
  });

  test('selecciona la evaluación futura más cercana y excluye pasadas', () {
    final Evaluacion? selected = service.selectNextEvaluation([
      evaluation('pasada', -1),
      evaluation('lejana', 7),
      evaluation('cercana', 2),
    ], now: now);

    expect(selected?.id, 'cercana');
  });

  test('excluye una evaluación de hoy cuya hora ya pasó', () {
    final Evaluacion? selected = service.selectNextEvaluation([
      evaluation('pasada-hoy', 0, time: '10:00'),
      evaluation('mañana', 1),
    ], now: now);

    expect(selected?.id, 'mañana');
  });

  test('elige una prioridad académica relevante', () {
    final AcademicInsight? insight = service.selectPriority(
      tasks: [task('tarea', 5)],
      evaluations: [evaluation('evaluacion', 4)],
      todayClassCount: 0,
      now: now,
    );

    expect(insight?.kind, AcademicInsightKind.upcomingEvaluation);
    expect(insight?.evaluation?.id, 'evaluacion');
    expect(insight?.secondaryTask?.id, 'tarea');
  });

  test('una tarea urgente gana frente a una evaluación menos próxima', () {
    final AcademicInsight? insight = service.selectPriority(
      tasks: [task('urgente', 0)],
      evaluations: [evaluation('posterior', 3)],
      todayClassCount: 5,
      now: now,
    );

    expect(insight?.kind, AcademicInsightKind.overdueOrTodayTask);
    expect(insight?.task?.id, 'urgente');
    expect(insight?.secondaryEvaluation?.id, 'posterior');
  });

  test('no repite una única tarea que ya informa su tarjeta normal', () {
    final AcademicInsight? insight = service.selectPriority(
      tasks: [task('única', 0)],
      evaluations: const [],
      todayClassCount: 0,
      now: now,
    );

    expect(insight, isNull);
  });

  test('muestra una única tarea urgente si su tarjeta normal está oculta', () {
    final AcademicInsight? insight = service.selectPriority(
      tasks: [task('única', 0)],
      evaluations: const [],
      todayClassCount: 0,
      now: now,
      nextTaskVisible: false,
    );

    expect(insight?.primary.task?.id, 'única');
    expect(insight?.secondary, isNull);
  });

  test('no repite una única evaluación si su tarjeta normal está visible', () {
    final AcademicInsight? insight = service.selectPriority(
      tasks: const [],
      evaluations: [evaluation('única', 1)],
      todayClassCount: 0,
      now: now,
    );

    expect(insight, isNull);
  });

  test('muestra una única evaluación si su tarjeta normal está oculta', () {
    final AcademicInsight? insight = service.selectPriority(
      tasks: const [],
      evaluations: [evaluation('única', 1)],
      todayClassCount: 0,
      now: now,
      nextEvaluationVisible: false,
    );

    expect(insight?.primary.evaluation?.id, 'única');
    expect(insight?.secondary, isNull);
  });

  test('combina una tarea urgente con una evaluación cercana', () {
    final AcademicInsight? insight = service.selectPriority(
      tasks: [task('hoy', 0)],
      evaluations: [evaluation('mañana', 1)],
      todayClassCount: 0,
      now: now,
    );

    expect(insight?.primary.task?.id, 'hoy');
    expect(insight?.secondary?.evaluation?.id, 'mañana');
  });
}
