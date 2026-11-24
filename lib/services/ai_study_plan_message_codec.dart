import 'dart:convert';

import '../models/plan_estudio.dart';

enum AiStudyPlanEventState { saved, cancelled }

class AiStudyPlanEvent {
  const AiStudyPlanEvent({
    required this.messageId,
    required this.planId,
    required this.state,
  });

  final String messageId;
  final String planId;
  final AiStudyPlanEventState state;
}

class DecodedAiStudyPlanMessage {
  const DecodedAiStudyPlanMessage({
    required this.visibleText,
    this.proposal,
    this.event,
  });

  final String visibleText;
  final PlanEstudioPropuesto? proposal;
  final AiStudyPlanEvent? event;
}

/// Serializa metadatos estructurados dentro del texto que el repositorio de
/// chat cifra de extremo a extremo. El sobre nunca se muestra ni se envía a
/// la IA como parte del contexto conversacional.
abstract final class AiStudyPlanMessageCodec {
  static const _prefix = '[[EDUFLOW_STUDY_PLAN_V1:';
  static const _suffix = ']]';

  static String encodeProposal(
    String visibleText,
    PlanEstudioPropuesto proposal,
  ) => _encode(visibleText, {'kind': 'proposal', 'plan': proposal.toJson()});

  static String encodeEvent({
    required String messageId,
    required String planId,
    required AiStudyPlanEventState state,
  }) => _encode('', {
    'kind': 'event',
    'messageId': messageId,
    'planId': planId,
    'state': state.name,
  });

  static DecodedAiStudyPlanMessage decode(String storedText) {
    final markerStart = storedText.lastIndexOf('\n\n$_prefix');
    final startsWithMarker = storedText.startsWith(_prefix);
    final start = markerStart >= 0
        ? markerStart + 2
        : (startsWithMarker ? 0 : -1);
    if (start < 0 || !storedText.endsWith(_suffix)) {
      return DecodedAiStudyPlanMessage(visibleText: storedText);
    }

    final encodedStart = start + _prefix.length;
    final encodedEnd = storedText.length - _suffix.length;
    try {
      final payload = jsonDecode(
        utf8.decode(
          base64Url.decode(storedText.substring(encodedStart, encodedEnd)),
        ),
      );
      if (payload is! Map) {
        return DecodedAiStudyPlanMessage(visibleText: storedText);
      }
      final data = Map<String, Object?>.from(payload);
      final visible = start == 0 ? '' : storedText.substring(0, start - 2);
      if (data['kind'] == 'proposal') {
        return DecodedAiStudyPlanMessage(
          visibleText: visible,
          proposal: _planFromJson(data['plan']),
        );
      }
      if (data['kind'] == 'event') {
        final messageId = _text(data['messageId']);
        final planId = _text(data['planId']);
        final state = AiStudyPlanEventState.values.where(
          (value) => value.name == data['state'],
        );
        if (messageId == null || planId == null || state.length != 1) {
          throw const FormatException('Evento de plan inválido.');
        }
        return DecodedAiStudyPlanMessage(
          visibleText: visible,
          event: AiStudyPlanEvent(
            messageId: messageId,
            planId: planId,
            state: state.single,
          ),
        );
      }
    } catch (_) {
      // Los mensajes históricos y sobres dañados siguen siendo legibles.
    }
    return DecodedAiStudyPlanMessage(visibleText: storedText);
  }

  static String _encode(String visibleText, Map<String, Object?> payload) {
    final marker =
        '$_prefix${base64Url.encode(utf8.encode(jsonEncode(payload)))}$_suffix';
    return visibleText.trim().isEmpty
        ? marker
        : '${visibleText.trim()}\n\n$marker';
  }

  static PlanEstudioPropuesto _planFromJson(Object? value) {
    if (value is! Map) throw const FormatException('Plan inválido.');
    final data = Map<String, Object?>.from(value);
    final rawSessions = data['sesiones'];
    if (rawSessions is! List ||
        rawSessions.isEmpty ||
        rawSessions.length > 20) {
      throw const FormatException('Sesiones inválidas.');
    }
    final sessions = rawSessions
        .map((raw) {
          if (raw is! Map) throw const FormatException('Sesión inválida.');
          final item = Map<String, Object?>.from(raw);
          final date = DateTime.tryParse(_text(item['fecha']) ?? '');
          final duration = item['duracionMinutos'] is num
              ? (item['duracionMinutos'] as num).toInt()
              : int.tryParse(item['duracionMinutos']?.toString() ?? '');
          final id = _text(item['id']);
          final title = _text(item['titulo']);
          final activity = _text(item['actividad']);
          final start = _text(item['horaInicio']);
          if (id == null ||
              title == null ||
              activity == null ||
              date == null ||
              start == null ||
              !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(start) ||
              duration == null ||
              duration < 15 ||
              duration > 240) {
            throw const FormatException('Sesión inválida.');
          }
          return SesionPlanEstudio(
            id: id,
            titulo: title,
            actividad: activity,
            fecha: DateTime(date.year, date.month, date.day),
            horaInicio: start,
            duracionMinutos: duration,
          );
        })
        .toList(growable: false);
    final id = _text(data['id']);
    final title = _text(data['titulo']);
    final objective = _text(data['objetivo']);
    final subjectId = _text(data['asignaturaId']);
    final subjectName = _text(data['asignaturaNombre']);
    final revision = data['revision'] is num
        ? (data['revision'] as num).toInt()
        : int.tryParse(data['revision']?.toString() ?? '');
    if (id == null ||
        title == null ||
        objective == null ||
        subjectId == null ||
        subjectName == null ||
        revision == null ||
        revision < 1) {
      throw const FormatException('Plan inválido.');
    }
    return PlanEstudioPropuesto(
      id: id,
      titulo: title,
      objetivo: objective,
      asignaturaId: subjectId,
      asignaturaNombre: subjectName,
      evaluacionId: _text(data['evaluacionId']),
      sesiones: List.unmodifiable(sessions),
      revision: revision,
    );
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text.length > 1000 ? null : text;
  }
}
