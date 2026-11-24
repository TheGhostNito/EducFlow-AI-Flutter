import 'package:eduflow_ai/models/asignatura.dart';
import 'package:eduflow_ai/services/plan_estudio_proposal_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const builder = PlanEstudioProposalBuilder();
  final subjects = [
    const Asignatura(
      id: 'bpm-1',
      nombre: 'Business Process Management',
      sigla: 'BPM',
      estado: EstadoAsignatura.enCurso,
      origen: OrigenAsignatura.manual,
    ),
  ];

  test('construye una propuesta para una asignatura real y fecha futura', () {
    final plan = builder.build(
      arguments: _arguments(),
      asignaturas: subjects,
      conversationId: 'chat-1',
      now: DateTime(2026, 11, 23, 10),
    );

    expect(plan.asignaturaId, 'bpm-1');
    expect(plan.evaluacionId, 'evaluation-1');
    expect(plan.sesiones, hasLength(2));
    expect(plan.sesiones.first.fecha, DateTime(2026, 11, 24));
    expect(plan.duracionTotalMinutos, 90);
    expect(plan.revision, 1);
  });

  test('una modificación reemplaza el plan y conserva su identidad', () {
    final original = builder.build(
      arguments: _arguments(),
      asignaturas: subjects,
      conversationId: 'chat-1',
      now: DateTime(2026, 11, 23, 10),
    );
    final shorter = builder.build(
      arguments: _arguments(duration: 30),
      asignaturas: subjects,
      conversationId: 'chat-1',
      now: DateTime(2026, 11, 23, 10, 5),
      current: original,
    );

    expect(shorter.id, original.id);
    expect(shorter.revision, 2);
    expect(
      shorter.sesiones.every((item) => item.duracionMinutos == 30),
      isTrue,
    );
  });

  test('pregunta nuevamente si la asignatura no se puede resolver', () {
    final arguments = _arguments()
      ..['asignaturaId'] = 'inexistente'
      ..['asignatura'] = 'Asignatura inexistente';

    expect(
      () => builder.build(
        arguments: arguments,
        asignaturas: subjects,
        conversationId: 'chat-1',
        now: DateTime(2026, 11, 23),
      ),
      throwsFormatException,
    );
  });

  test('rechaza sesiones superpuestas antes de mostrarlas', () {
    final arguments = _arguments();
    arguments['sesiones'] = [
      _session('2026-11-24', '16:00', 60, 'Teoría'),
      _session('2026-11-24', '16:30', 45, 'Ejercicios'),
    ];

    expect(
      () => builder.build(
        arguments: arguments,
        asignaturas: subjects,
        conversationId: 'chat-1',
        now: DateTime(2026, 11, 23),
      ),
      throwsFormatException,
    );
  });
}

Map<String, Object?> _arguments({int duration = 45}) => {
  'titulo': 'Preparación evaluación BPM',
  'objetivo': 'Repasar modelamiento y practicar ejercicios.',
  'asignaturaId': 'bpm-1',
  'asignatura': 'BPM',
  'evaluacionId': 'evaluation-1',
  'sesiones': [
    _session('2026-11-24', '16:00', duration, 'Conceptos clave'),
    _session('2026-11-25', '17:00', duration, 'Práctica BPMN'),
  ],
};

Map<String, Object?> _session(
  String date,
  String time,
  int duration,
  String title,
) => {
  'titulo': title,
  'actividad': 'Estudiar $title con apuntes y ejercicios.',
  'fecha': date,
  'horaInicio': time,
  'duracionMinutos': duration,
};
