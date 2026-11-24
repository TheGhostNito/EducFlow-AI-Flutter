import 'package:eduflow_ai/models/horario_ocr_result.dart';

class HorarioOcrReferenceComparison {
  const HorarioOcrReferenceComparison({required this.issueCodes});

  final List<String> issueCodes;

  bool get matches => issueCodes.isEmpty;
}

class HorarioOcrReferenceComparator {
  const HorarioOcrReferenceComparator();

  HorarioOcrReferenceComparison compare({
    required HorarioOcrResult actual,
    required Map<String, dynamic> expected,
  }) {
    final issues = <String>[];
    final expectedYear = _integer(expected['anio']);
    final expectedSemester = _integer(expected['numero']);
    if (actual.period.year != expectedYear) issues.add('period_year_mismatch');
    if (actual.period.semester != expectedSemester) {
      issues.add('period_semester_mismatch');
    }
    if (expected['fecha_inicio_periodo'] == null &&
        actual.period.startDate != null) {
      issues.add('invented_period_start');
    }
    if (expected['fecha_fin_periodo'] == null &&
        actual.period.endDate != null) {
      issues.add('invented_period_end');
    }
    final expectedSubjects = _list(expected['asignaturas']);
    if (actual.subjects.length != expectedSubjects.length) {
      issues.add('subject_count_mismatch');
    }
    final matchedKeys = <String>{};
    for (final rawExpected in expectedSubjects) {
      final subjectExpected = _map(rawExpected);
      final code = _normalized(subjectExpected['sigla']);
      final section = _normalized(subjectExpected['seccion']);
      final matches = actual.subjects
          .where(
            (subject) =>
                _normalized(subject.code) == code &&
                _normalized(subject.section) == section,
          )
          .toList();
      if (matches.length != 1) {
        issues.add('subject_identity_mismatch');
        continue;
      }
      final subject = matches.single;
      matchedKeys.add(subject.key);
      if (_normalized(subject.name) !=
          _normalized(subjectExpected['nombre_documento'])) {
        issues.add('subject_name_mismatch:${subject.key}');
      }
      final expectedProfessor = _normalized(subjectExpected['profesor']);
      if (_normalized(subject.professor) != expectedProfessor) {
        issues.add('professor_mismatch:${subject.key}');
      }
      final expectedEmail = _normalized(subjectExpected['correo_profesor']);
      if (_normalized(subject.professorEmail) != expectedEmail) {
        issues.add('professor_email_mismatch:${subject.key}');
      }
      final interpretation = subjectExpected['interpretacion']?.toString();
      if (interpretation == 'sesiones_fechadas_no_semanal') {
        if (subject.weeklyBlocks.isNotEmpty) {
          issues.add('dated_subject_has_weekly_blocks:${subject.key}');
        }
        _compareSessions(subject, subjectExpected, issues);
      } else {
        if (subject.datedSessions.isNotEmpty) {
          issues.add('weekly_subject_has_dated_sessions:${subject.key}');
        }
        _compareModules(subject, subjectExpected, issues);
      }
    }
    if (actual.subjects.any((subject) => !matchedKeys.contains(subject.key))) {
      issues.add('unexpected_subject');
    }
    return HorarioOcrReferenceComparison(issueCodes: List.unmodifiable(issues));
  }

  void _compareSessions(
    HorarioOcrSubject actual,
    Map<String, dynamic> expected,
    List<String> issues,
  ) {
    final sessions = _list(expected['sesiones_fechadas']);
    if (actual.datedSessions.length != sessions.length) {
      issues.add('session_count_mismatch:${actual.key}');
    }
    for (final value in sessions) {
      final expectedSession = _map(value);
      final found = actual.datedSessions.any(
        (session) =>
            _date(session.date) == expectedSession['fecha']?.toString() &&
            session.startTime == expectedSession['inicio']?.toString() &&
            session.endTime == expectedSession['fin']?.toString() &&
            _normalized(session.room) == _normalized(expectedSession['sala']),
      );
      if (!found) issues.add('session_mismatch:${actual.key}');
    }
  }

  void _compareModules(
    HorarioOcrSubject actual,
    Map<String, dynamic> expected,
    List<String> issues,
  ) {
    final modules = _list(expected['modulos_semanales_visibles'])
        .map(_map)
        .toList();
    for (final module in modules) {
      final moduleStart = _minutes(module['inicio']?.toString());
      final moduleEnd = _minutes(module['fin']?.toString());
      final covered = actual.weeklyBlocks.any((block) {
        final start = _minutes(block.startTime);
        final end = _minutes(block.endTime);
        return _day(block.day) == _normalized(module['dia']) &&
            _normalized(block.room) == _normalized(module['sala']) &&
            start != null &&
            end != null &&
            moduleStart != null &&
            moduleEnd != null &&
            start <= moduleStart &&
            end >= moduleEnd;
      });
      if (!covered) issues.add('weekly_module_missing:${actual.key}');
    }
    for (final block in actual.weeklyBlocks) {
      final start = _minutes(block.startTime);
      final end = _minutes(block.endTime);
      final covered =
          modules.where((module) {
            final moduleStart = _minutes(module['inicio']?.toString());
            final moduleEnd = _minutes(module['fin']?.toString());
            return _day(block.day) == _normalized(module['dia']) &&
                _normalized(block.room) == _normalized(module['sala']) &&
                start != null &&
                end != null &&
                moduleStart != null &&
                moduleEnd != null &&
                moduleStart >= start &&
                moduleEnd <= end;
          }).toList()..sort(
            (left, right) =>
                left['inicio'].toString().compareTo(right['inicio'].toString()),
          );
      final exactBounds =
          covered.isNotEmpty &&
          covered.first['inicio']?.toString() == block.startTime &&
          covered.last['fin']?.toString() == block.endTime;
      var contiguous = true;
      for (var index = 1; index < covered.length; index++) {
        final previousEnd = _minutes(covered[index - 1]['fin']?.toString());
        final nextStart = _minutes(covered[index]['inicio']?.toString());
        if (previousEnd == null || nextStart != previousEnd + 1) {
          contiguous = false;
          break;
        }
      }
      if (!exactBounds || !contiguous) {
        issues.add('weekly_block_not_exact_module_coverage:${actual.key}');
      }
    }
  }

  String? _day(HorarioOcrDay? day) => switch (day) {
    HorarioOcrDay.lunes => 'lunes',
    HorarioOcrDay.martes => 'martes',
    HorarioOcrDay.miercoles => 'miercoles',
    HorarioOcrDay.jueves => 'jueves',
    HorarioOcrDay.viernes => 'viernes',
    HorarioOcrDay.sabado => 'sabado',
    HorarioOcrDay.domingo => 'domingo',
    null => null,
  };

  String? _date(DateTime? value) => value == null
      ? null
      : '${value.year.toString().padLeft(4, '0')}-'
            '${value.month.toString().padLeft(2, '0')}-'
            '${value.day.toString().padLeft(2, '0')}';

  int? _minutes(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    return hour == null || minute == null ? null : hour * 60 + minute;
  }

  String? _normalized(Object? value) {
    final text = value
        ?.toString()
        .toLowerCase()
        .replaceAll(RegExp(r'[áàä]'), 'a')
        .replaceAll(RegExp(r'[éèë]'), 'e')
        .replaceAll(RegExp(r'[íìï]'), 'i')
        .replaceAll(RegExp(r'[óòö]'), 'o')
        .replaceAll(RegExp(r'[úùü]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    return text == null || text.isEmpty ? null : text;
  }

  int? _integer(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');
  Map<String, dynamic> _map(Object? value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};
  List<Object?> _list(Object? value) => value is List ? value : const [];
}
