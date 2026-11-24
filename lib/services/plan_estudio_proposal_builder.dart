import '../models/asignatura.dart';
import '../models/plan_estudio.dart';

class PlanEstudioProposalBuilder {
  const PlanEstudioProposalBuilder();

  PlanEstudioPropuesto build({
    required Map<String, Object?> arguments,
    required List<Asignatura> asignaturas,
    required String conversationId,
    required DateTime now,
    PlanEstudioPropuesto? current,
  }) {
    final asignatura = _resolveSubject(arguments, asignaturas);
    final title = _requiredText(arguments['titulo'], 'titulo', max: 120);
    final objective = _requiredText(
      arguments['objetivo'],
      'objetivo',
      max: 500,
    );
    final rawSessions = arguments['sesiones'];
    if (rawSessions is! List ||
        rawSessions.isEmpty ||
        rawSessions.length > 20) {
      throw const FormatException(
        'El plan debe contener entre 1 y 20 sesiones.',
      );
    }

    final planId = current != null && current.asignaturaId == asignatura.id
        ? current.id
        : 'plan_${_stableHash('$conversationId|${asignatura.id}|${now.microsecondsSinceEpoch}')}';
    final today = DateTime(now.year, now.month, now.day);
    final sessions = <SesionPlanEstudio>[];

    for (var index = 0; index < rawSessions.length; index++) {
      final raw = rawSessions[index];
      if (raw is! Map) {
        throw const FormatException('Una sesión del plan no es válida.');
      }
      final item = Map<String, Object?>.from(raw);
      final date = _parseDate(item['fecha']);
      if (date.isBefore(today)) {
        throw const FormatException(
          'El plan contiene una sesión anterior a la fecha actual.',
        );
      }
      final startTime = _parseTime(item['horaInicio']);
      final duration = _parseDuration(item['duracionMinutos']);
      final sessionTitle = _requiredText(
        item['titulo'],
        'titulo de sesión',
        max: 100,
      );
      final activity = _requiredText(
        item['actividad'],
        'actividad de sesión',
        max: 600,
      );
      final sessionKey =
          '${fechaPlanEstudioSql(date)}|$startTime|$sessionTitle|$index';
      sessions.add(
        SesionPlanEstudio(
          id: 'sesion_${_stableHash('$planId|$sessionKey')}',
          titulo: sessionTitle,
          actividad: activity,
          fecha: date,
          horaInicio: startTime,
          duracionMinutos: duration,
        ),
      );
    }

    sessions.sort((a, b) => a.inicio.compareTo(b.inicio));
    for (var index = 1; index < sessions.length; index++) {
      if (sessions[index].inicio.isBefore(sessions[index - 1].fin)) {
        throw const FormatException(
          'El plan contiene sesiones que se superponen.',
        );
      }
    }

    return PlanEstudioPropuesto(
      id: planId,
      titulo: title,
      objetivo: objective,
      asignaturaId: asignatura.id,
      asignaturaNombre: asignatura.nombre,
      evaluacionId: _optionalText(arguments['evaluacionId'], max: 120),
      sesiones: List.unmodifiable(sessions),
      revision: (current?.revision ?? 0) + 1,
    );
  }

  Asignatura _resolveSubject(
    Map<String, Object?> arguments,
    List<Asignatura> subjects,
  ) {
    final requestedId = _optionalText(arguments['asignaturaId'], max: 200);
    final requestedName = _normalize(
      _optionalText(arguments['asignatura'], max: 200) ?? '',
    );

    final matches = subjects.where((subject) {
      if (requestedId != null && subject.id == requestedId) return true;
      if (requestedName.isEmpty) return false;
      return _normalize(subject.nombre) == requestedName ||
          _normalize(subject.sigla ?? '') == requestedName;
    }).toList();
    if (matches.length != 1) {
      throw const FormatException(
        'La asignatura no pudo identificarse de manera inequívoca.',
      );
    }
    return matches.single;
  }

  DateTime _parseDate(Object? value) {
    final text = value?.toString().trim() ?? '';
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
    if (match == null) {
      throw const FormatException('La fecha de una sesión no es válida.');
    }
    final date = DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
    if (fechaPlanEstudioSql(date) != text) {
      throw const FormatException('La fecha de una sesión no es válida.');
    }
    return date;
  }

  String _parseTime(Object? value) {
    final text = value?.toString().trim() ?? '';
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(text);
    if (match == null ||
        int.parse(match.group(1)!) > 23 ||
        int.parse(match.group(2)!) > 59) {
      throw const FormatException('La hora de una sesión no es válida.');
    }
    return text;
  }

  int _parseDuration(Object? value) {
    final duration = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    if (duration == null || duration < 15 || duration > 240) {
      throw const FormatException(
        'La duración debe estar entre 15 y 240 minutos.',
      );
    }
    return duration;
  }

  String _requiredText(Object? value, String field, {required int max}) {
    final text = _optionalText(value, max: max);
    if (text == null) throw FormatException('Falta $field en el plan.');
    return text;
  }

  String? _optionalText(Object? value, {required int max}) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return text.length <= max ? text : text.substring(0, max).trimRight();
  }

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9áéíóúüñ]+'), ' ').trim();

  String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
