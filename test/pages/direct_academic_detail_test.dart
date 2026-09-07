import 'package:eduflow_ai/models/evaluacion.dart';
import 'package:eduflow_ai/models/tarea.dart';
import 'package:eduflow_ai/pages/calendar/calendar_page.dart';
import 'package:eduflow_ai/pages/tasks/tasks_page.dart';
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
  });
}
