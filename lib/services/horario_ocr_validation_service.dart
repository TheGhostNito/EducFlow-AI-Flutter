import '../models/horario_ocr_result.dart';

class HorarioOcrValidationService {
  const HorarioOcrValidationService();

  HorarioOcrResult validate(
    Map<String, dynamic> raw, {
    required String documentHash,
    required int pageCount,
  }) {
    final issues = <HorarioOcrIssue>[];
    final period = _period(raw['period'], issues);
    final subjects = <HorarioOcrSubject>[];
    final byIdentity = <String, int>{};
    final rawSubjects = raw['subjects'];
    if (rawSubjects is! List) {
      throw const FormatException(
        'Gemini no devolvió la lista de asignaturas del horario.',
      );
    }

    for (final value in rawSubjects.take(100)) {
      if (value is! Map) {
        issues.add(
          const HorarioOcrIssue(
            code: 'invalid_subject',
            message: 'Se descartó una asignatura con estructura inválida.',
            severity: HorarioOcrIssueSeverity.error,
          ),
        );
        continue;
      }
      final parsed = _subject(Map<String, dynamic>.from(value), issues);
      if (parsed == null) continue;
      final identity = _identity(parsed);
      final existingIndex = identity == null ? null : byIdentity[identity];
      if (existingIndex == null) {
        if (identity != null) byIdentity[identity] = subjects.length;
        subjects.add(parsed);
      } else {
        subjects[existingIndex] = _merge(subjects[existingIndex], parsed);
        issues.add(
          HorarioOcrIssue(
            code: 'continued_subject_merged',
            message: 'Se unieron filas de la misma asignatura continuadas entre páginas.',
            severity: HorarioOcrIssueSeverity.warning,
            subjectKey: subjects[existingIndex].key,
          ),
        );
      }
    }

    _markAmbiguousNameDuplicates(subjects, issues);
    _validateSessionPeriods(subjects, period, issues);
    final pendingReview = _strings(raw['pendingReview'], maxItems: 100);
    if (subjects.isEmpty) {
      issues.add(
        const HorarioOcrIssue(
          code: 'no_subjects',
          message: 'No se detectaron asignaturas revisables.',
          severity: HorarioOcrIssueSeverity.error,
        ),
      );
    }
    return HorarioOcrResult(
      documentHash: documentHash,
      pageCount: pageCount,
      period: period,
      subjects: List.unmodifiable(subjects),
      issues: List.unmodifiable(issues),
      pendingReview: List.unmodifiable(pendingReview),
    );
  }

  HorarioOcrPeriod _period(Object? value, List<HorarioOcrIssue> issues) {
    final map = _map(value);
    final year = _integer(map['year']);
    final semester = _integer(map['semester']);
    final start = _date(map['startDate']);
    final end = _date(map['endDate']);
    final evidence = _strings(map['evidence']);
    final pending = _strings(map['pendingReasons']).toSet();
    if (year == null || year < 2000 || year > 2100) {
      pending.add('academic_year_requires_review');
      issues.add(
        const HorarioOcrIssue(
          code: 'invalid_academic_year',
          message: 'El año académico falta o no es válido.',
          severity: HorarioOcrIssueSeverity.error,
          field: 'period.year',
        ),
      );
    }
    if (semester == null || semester < 1 || semester > 3) {
      pending.add('academic_period_requires_review');
      issues.add(
        const HorarioOcrIssue(
          code: 'invalid_semester',
          message: 'El semestre académico falta o no es válido.',
          severity: HorarioOcrIssueSeverity.error,
          field: 'period.semester',
        ),
      );
    }
    if (start != null && end != null && end.isBefore(start)) {
      pending.add('period_dates_require_review');
      issues.add(
        const HorarioOcrIssue(
          code: 'invalid_period_range',
          message: 'Las fechas propuestas para el período están invertidas.',
          severity: HorarioOcrIssueSeverity.error,
          field: 'period',
        ),
      );
    }
    if (evidence.isEmpty) pending.add('period_without_evidence');
    return HorarioOcrPeriod(
      year: year != null && year >= 2000 && year <= 2100 ? year : null,
      semester: semester != null && semester >= 1 && semester <= 3
          ? semester
          : null,
      startDate: start,
      endDate: end,
      evidence: evidence,
      pendingReasons: pending.toList(),
    );
  }

  HorarioOcrSubject? _subject(
    Map<String, dynamic> map,
    List<HorarioOcrIssue> issues,
  ) {
    final key = _bounded(map['subjectKey'], 80);
    if (key == null || !RegExp(r'^subject_[A-Za-z0-9_-]+$').hasMatch(key)) {
      issues.add(
        const HorarioOcrIssue(
          code: 'invalid_subject_key',
          message: 'Se descartó una asignatura sin identificador seguro.',
          severity: HorarioOcrIssueSeverity.error,
          field: 'subjectKey',
        ),
      );
      return null;
    }
    final name = _bounded(map['name'], 240);
    final code = _bounded(map['code'], 40)?.toUpperCase().replaceAll(' ', '');
    final section = _bounded(map['section'], 40)?.toUpperCase();
    final professor = _bounded(map['professor'], 160);
    final professorEmail = _bounded(map['professorEmail'], 254)?.toLowerCase();
    final evidence = _strings(map['evidence']);
    final pending = _strings(map['pendingReasons']).toSet();
    final pages = _integers(map['sourcePages'], min: 1, max: 100);

    if (name == null) pending.add('subject_name_requires_review');
    if (code != null &&
        !RegExp(r'^[A-Z]{2,8}[0-9]{2,8}[A-Z0-9]*$').hasMatch(code)) {
      pending.add('subject_code_requires_review');
      issues.add(
        HorarioOcrIssue(
          code: 'invalid_subject_code',
          message: 'El código de la asignatura requiere revisión.',
          severity: HorarioOcrIssueSeverity.warning,
          subjectKey: key,
          field: 'code',
        ),
      );
    }
    if (section != null &&
        !RegExp(r'^[A-Z0-9][A-Z0-9._-]{0,39}$').hasMatch(section)) {
      pending.add('section_requires_review');
    }
    if (professorEmail != null &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(professorEmail)) {
      pending.add('professor_email_requires_review');
    }
    if (evidence.isEmpty) pending.add('subject_without_evidence');

    final blocks = <HorarioOcrWeeklyBlock>[];
    for (final value in _list(map['weeklyBlocks']).take(100)) {
      final block = _weeklyBlock(value, key, issues);
      if (block != null && !_containsBlock(blocks, block)) blocks.add(block);
    }
    final sessions = <HorarioOcrDatedSession>[];
    for (final value in _list(map['datedSessions']).take(100)) {
      final session = _datedSession(value, key, issues);
      if (session != null && !_containsSession(sessions, session)) {
        sessions.add(session);
      }
    }
    if (blocks.isEmpty && sessions.isEmpty) {
      pending.add('subject_without_classes');
      issues.add(
        HorarioOcrIssue(
          code: 'subject_without_classes',
          message: 'La asignatura no contiene clases reconocibles.',
          severity: HorarioOcrIssueSeverity.error,
          subjectKey: key,
        ),
      );
    }
    return HorarioOcrSubject(
      key: key,
      name: name,
      code: code,
      section: section,
      professor: professor,
      professorEmail: professorEmail,
      weeklyBlocks: List.unmodifiable(blocks),
      datedSessions: List.unmodifiable(sessions),
      sourcePages: List.unmodifiable(pages),
      evidence: List.unmodifiable(evidence),
      pendingReasons: List.unmodifiable(pending),
    );
  }

  HorarioOcrWeeklyBlock? _weeklyBlock(
    Object? value,
    String ownerKey,
    List<HorarioOcrIssue> issues,
  ) {
    final map = _map(value);
    final subjectKey = _bounded(map['subjectKey'], 80);
    if (subjectKey != ownerKey) {
      issues.add(
        HorarioOcrIssue(
          code: 'cross_subject_block_rejected',
          message: 'Se rechazó un bloque asociado a otra asignatura.',
          severity: HorarioOcrIssueSeverity.error,
          subjectKey: ownerKey,
          field: 'weeklyBlocks.subjectKey',
          page: _integer(map['page']),
        ),
      );
      return null;
    }
    final pending = _strings(map['pendingReasons']).toSet();
    final day = _day(map['day']);
    final start = _time(map['startTime']);
    final end = _time(map['endTime']);
    final evidence = _strings(map['evidence']);
    if (day == null) pending.add('day_requires_review');
    _validateTimeRange(start, end, pending);
    if (evidence.isEmpty) pending.add('block_without_evidence');
    return HorarioOcrWeeklyBlock(
      subjectKey: ownerKey,
      day: day,
      startTime: start,
      endTime: end,
      room: _bounded(map['room'], 100),
      page: _positiveInteger(map['page']),
      evidence: List.unmodifiable(evidence),
      pendingReasons: List.unmodifiable(pending),
    );
  }

  HorarioOcrDatedSession? _datedSession(
    Object? value,
    String ownerKey,
    List<HorarioOcrIssue> issues,
  ) {
    final map = _map(value);
    final subjectKey = _bounded(map['subjectKey'], 80);
    if (subjectKey != ownerKey) {
      issues.add(
        HorarioOcrIssue(
          code: 'cross_subject_session_rejected',
          message: 'Se rechazó una sesión asociada a otra asignatura.',
          severity: HorarioOcrIssueSeverity.error,
          subjectKey: ownerKey,
          field: 'datedSessions.subjectKey',
          page: _integer(map['page']),
        ),
      );
      return null;
    }
    final pending = _strings(map['pendingReasons']).toSet();
    final date = _date(map['date']);
    final start = _time(map['startTime']);
    final end = _time(map['endTime']);
    final evidence = _strings(map['evidence']);
    if (date == null) pending.add('date_requires_review');
    _validateTimeRange(start, end, pending);
    if (evidence.isEmpty) pending.add('session_without_evidence');
    return HorarioOcrDatedSession(
      subjectKey: ownerKey,
      date: date,
      startTime: start,
      endTime: end,
      room: _bounded(map['room'], 100),
      page: _positiveInteger(map['page']),
      evidence: List.unmodifiable(evidence),
      pendingReasons: List.unmodifiable(pending),
    );
  }

  void _validateTimeRange(String? start, String? end, Set<String> pending) {
    final startMinutes = _minutes(start);
    final endMinutes = _minutes(end);
    if (startMinutes == null ||
        endMinutes == null ||
        endMinutes <= startMinutes) {
      pending.add('time_range_requires_review');
    }
  }

  HorarioOcrSubject _merge(HorarioOcrSubject first, HorarioOcrSubject second) {
    final blocks = [...first.weeklyBlocks];
    for (final block in second.weeklyBlocks) {
      if (!_containsBlock(blocks, block)) blocks.add(block);
    }
    final sessions = [...first.datedSessions];
    for (final session in second.datedSessions) {
      if (!_containsSession(sessions, session)) sessions.add(session);
    }
    return HorarioOcrSubject(
      key: first.key,
      name: first.name ?? second.name,
      code: first.code ?? second.code,
      section: first.section ?? second.section,
      professor: first.professor ?? second.professor,
      professorEmail: first.professorEmail ?? second.professorEmail,
      weeklyBlocks: List.unmodifiable(blocks),
      datedSessions: List.unmodifiable(sessions),
      sourcePages: List.unmodifiable(
        {...first.sourcePages, ...second.sourcePages}.toList()..sort(),
      ),
      evidence: List.unmodifiable(
        {...first.evidence, ...second.evidence}.toList(),
      ),
      pendingReasons: List.unmodifiable(
        {...first.pendingReasons, ...second.pendingReasons}.toList(),
      ),
    );
  }

  void _markAmbiguousNameDuplicates(
    List<HorarioOcrSubject> subjects,
    List<HorarioOcrIssue> issues,
  ) {
    final names = <String, List<HorarioOcrSubject>>{};
    for (final subject in subjects) {
      final name = _normalized(subject.name);
      if (name == null) continue;
      names.putIfAbsent(name, () => []).add(subject);
    }
    for (final group in names.values.where((items) => items.length > 1)) {
      for (final subject in group) {
        issues.add(
          HorarioOcrIssue(
            code: 'ambiguous_duplicate_subject',
            message: 'Hay asignaturas con el mismo nombre pero identidad académica distinta.',
            severity: HorarioOcrIssueSeverity.warning,
            subjectKey: subject.key,
          ),
        );
      }
    }
  }

  void _validateSessionPeriods(
    List<HorarioOcrSubject> subjects,
    HorarioOcrPeriod period,
    List<HorarioOcrIssue> issues,
  ) {
    for (final subject in subjects) {
      for (final session in subject.datedSessions) {
        final date = session.date;
        if (date == null) continue;
        final wrongYear = period.year != null && date.year != period.year;
        final beforeStart =
            period.startDate != null && date.isBefore(period.startDate!);
        final afterEnd =
            period.endDate != null && date.isAfter(period.endDate!);
        if (wrongYear || beforeStart || afterEnd) {
          issues.add(
            HorarioOcrIssue(
              code: 'session_outside_period',
              message: 'La fecha de una sesión no coincide con el período detectado.',
              severity: HorarioOcrIssueSeverity.error,
              subjectKey: subject.key,
              field: 'datedSessions.date',
              page: session.page,
            ),
          );
        }
      }
    }
  }

  String? _identity(HorarioOcrSubject subject) {
    final code = _normalized(subject.code);
    final section = _normalized(subject.section);
    if (code == null || section == null) return null;
    return '$code|$section';
  }

  bool _containsBlock(
    List<HorarioOcrWeeklyBlock> values,
    HorarioOcrWeeklyBlock candidate,
  ) => values.any(
    (value) =>
        value.day == candidate.day &&
        value.startTime == candidate.startTime &&
        value.endTime == candidate.endTime &&
        _normalized(value.room) == _normalized(candidate.room),
  );

  bool _containsSession(
    List<HorarioOcrDatedSession> values,
    HorarioOcrDatedSession candidate,
  ) => values.any(
    (value) =>
        value.date == candidate.date &&
        value.startTime == candidate.startTime &&
        value.endTime == candidate.endTime &&
        _normalized(value.room) == _normalized(candidate.room),
  );

  HorarioOcrDay? _day(Object? value) =>
      switch (_normalized(value?.toString())) {
        'lunes' => HorarioOcrDay.lunes,
        'martes' => HorarioOcrDay.martes,
        'miercoles' => HorarioOcrDay.miercoles,
        'jueves' => HorarioOcrDay.jueves,
        'viernes' => HorarioOcrDay.viernes,
        'sabado' => HorarioOcrDay.sabado,
        'domingo' => HorarioOcrDay.domingo,
        _ => null,
      };

  String? _time(Object? value) {
    final text = _bounded(value, 8);
    if (text == null) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(text);
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  int? _minutes(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  DateTime? _date(Object? value) {
    final text = _bounded(value, 10);
    if (text == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
      return null;
    }
    final parsed = DateTime.tryParse(text);
    if (parsed == null || _dateText(parsed) != text) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  String _dateText(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> _map(Object? value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};
  List<Object?> _list(Object? value) => value is List ? value : const [];

  String? _bounded(Object? value, int maxLength) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text.length > maxLength ? null : text;
  }

  String? _normalized(String? value) {
    final text = value
        ?.toLowerCase()
        .replaceAll(RegExp(r'[áàä]'), 'a')
        .replaceAll(RegExp(r'[éèë]'), 'e')
        .replaceAll(RegExp(r'[íìï]'), 'i')
        .replaceAll(RegExp(r'[óòö]'), 'o')
        .replaceAll(RegExp(r'[úùü]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    return text == null || text.isEmpty ? null : text;
  }

  int? _integer(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  int? _positiveInteger(Object? value) {
    final result = _integer(value);
    return result != null && result > 0 ? result : null;
  }

  List<int> _integers(Object? value, {required int min, required int max}) =>
      _list(value)
          .map(_integer)
          .whereType<int>()
          .where((item) => item >= min && item <= max)
          .toSet()
          .toList()
        ..sort();

  List<String> _strings(Object? value, {int maxItems = 12}) =>
      _list(value)
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty && item.length <= 300)
          .take(maxItems)
          .toSet()
          .toList();
}
