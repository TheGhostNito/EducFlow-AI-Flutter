import 'package:eduflow_ai/models/tarea.dart';
import 'package:eduflow_ai/services/study_plan_task_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const marker = '[EDUFLOW_PLAN_ESTUDIO:plan-1:session-1]';

  test('oculta el marcador y lo conserva al editar la descripción', () {
    const original = 'Actividad visible\n$marker';

    expect(
      StudyPlanTaskMetadata.visibleDescription(original),
      'Actividad visible',
    );
    expect(
      StudyPlanTaskMetadata.preserveMarkers(
        originalDescription: original,
        editedVisibleDescription: 'Actividad corregida',
      ),
      'Actividad corregida\n$marker',
    );
  });

  test('reconoce sesiones antiguas sin depender del título', () {
    final task = Tarea(
      id: 'task-1',
      titulo: 'Título editado por el estudiante',
      descripcion: marker,
      prioridad: PrioridadTarea.media,
      estado: EstadoTarea.pendiente,
      creadaEn: DateTime(2026, 11, 23),
      actualizadaEn: DateTime(2026, 11, 23),
    );

    expect(StudyPlanTaskMetadata.isStudySession(task), isTrue);
  });
}
