import 'package:eduflow_ai/models/plan_estudio.dart';
import 'package:eduflow_ai/services/ai_study_plan_message_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recupera propuesta estructurada sin exponer el sobre cifrable', () {
    final stored = AiStudyPlanMessageCodec.encodeProposal(
      'Preparé una propuesta breve.',
      _plan(),
    );

    final decoded = AiStudyPlanMessageCodec.decode(stored);

    expect(decoded.visibleText, 'Preparé una propuesta breve.');
    expect(decoded.proposal?.id, 'plan-1');
    expect(decoded.proposal?.sesiones.single.actividad, 'Resolver ejercicios');
    expect(decoded.visibleText, isNot(contains('EDUFLOW_STUDY_PLAN_V1')));
  });

  test('recupera eventos invisibles y conserva mensajes históricos', () {
    final event = AiStudyPlanMessageCodec.decode(
      AiStudyPlanMessageCodec.encodeEvent(
        messageId: 'message-1',
        planId: 'plan-1',
        state: AiStudyPlanEventState.cancelled,
      ),
    );

    expect(event.visibleText, isEmpty);
    expect(event.event?.messageId, 'message-1');
    expect(event.event?.state, AiStudyPlanEventState.cancelled);
    expect(
      AiStudyPlanMessageCodec.decode('Respuesta histórica').visibleText,
      'Respuesta histórica',
    );
  });

  test('un sobre inválido permanece legible y no crea una tarjeta', () {
    const stored = 'Respuesta\n\n[[EDUFLOW_STUDY_PLAN_V1:no-es-base64]]';

    final decoded = AiStudyPlanMessageCodec.decode(stored);

    expect(decoded.visibleText, stored);
    expect(decoded.proposal, isNull);
    expect(decoded.event, isNull);
  });
}

PlanEstudioPropuesto _plan() => PlanEstudioPropuesto(
  id: 'plan-1',
  titulo: 'Plan BPM',
  objetivo: 'Preparar evaluación',
  asignaturaId: 'bpm-1',
  asignaturaNombre: 'BPM',
  revision: 2,
  sesiones: [
    SesionPlanEstudio(
      id: 'session-1',
      titulo: 'Práctica',
      actividad: 'Resolver ejercicios',
      fecha: DateTime(2026, 11, 24),
      horaInicio: '16:00',
      duracionMinutos: 45,
    ),
  ],
);
