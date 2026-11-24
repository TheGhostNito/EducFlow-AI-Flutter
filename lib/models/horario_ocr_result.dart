enum HorarioOcrIssueSeverity { warning, error }

enum HorarioOcrDay {
  lunes,
  martes,
  miercoles,
  jueves,
  viernes,
  sabado,
  domingo,
}

class HorarioOcrIssue {
  const HorarioOcrIssue({
    required this.code,
    required this.message,
    required this.severity,
    this.subjectKey,
    this.field,
    this.page,
  });

  final String code;
  final String message;
  final HorarioOcrIssueSeverity severity;
  final String? subjectKey;
  final String? field;
  final int? page;
}

class HorarioOcrPeriod {
  const HorarioOcrPeriod({
    required this.year,
    required this.semester,
    required this.evidence,
    required this.pendingReasons,
    this.startDate,
    this.endDate,
  });

  final int? year;
  final int? semester;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<String> evidence;
  final List<String> pendingReasons;

  bool get needsReview =>
      year == null ||
      semester == null ||
      pendingReasons.isNotEmpty ||
      evidence.isEmpty;
}

class HorarioOcrWeeklyBlock {
  const HorarioOcrWeeklyBlock({
    required this.subjectKey,
    required this.day,
    required this.startTime,
    required this.endTime,
    required this.page,
    required this.evidence,
    required this.pendingReasons,
    this.room,
  });

  final String subjectKey;
  final HorarioOcrDay? day;
  final String? startTime;
  final String? endTime;
  final String? room;
  final int? page;
  final List<String> evidence;
  final List<String> pendingReasons;

  bool get needsReview =>
      day == null ||
      startTime == null ||
      endTime == null ||
      evidence.isEmpty ||
      pendingReasons.isNotEmpty;
}

class HorarioOcrDatedSession {
  const HorarioOcrDatedSession({
    required this.subjectKey,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.page,
    required this.evidence,
    required this.pendingReasons,
    this.room,
  });

  final String subjectKey;
  final DateTime? date;
  final String? startTime;
  final String? endTime;
  final String? room;
  final int? page;
  final List<String> evidence;
  final List<String> pendingReasons;

  bool get needsReview =>
      date == null ||
      startTime == null ||
      endTime == null ||
      evidence.isEmpty ||
      pendingReasons.isNotEmpty;
}

class HorarioOcrSubject {
  const HorarioOcrSubject({
    required this.key,
    required this.name,
    required this.code,
    required this.section,
    required this.professor,
    required this.professorEmail,
    required this.weeklyBlocks,
    required this.datedSessions,
    required this.sourcePages,
    required this.evidence,
    required this.pendingReasons,
  });

  final String key;
  final String? name;
  final String? code;
  final String? section;
  final String? professor;
  final String? professorEmail;
  final List<HorarioOcrWeeklyBlock> weeklyBlocks;
  final List<HorarioOcrDatedSession> datedSessions;
  final List<int> sourcePages;
  final List<String> evidence;
  final List<String> pendingReasons;

  bool get needsReview =>
      name == null ||
      evidence.isEmpty ||
      pendingReasons.isNotEmpty ||
      weeklyBlocks.any((block) => block.needsReview) ||
      datedSessions.any((session) => session.needsReview);
}

class HorarioOcrResult {
  const HorarioOcrResult({
    required this.documentHash,
    required this.pageCount,
    required this.period,
    required this.subjects,
    required this.issues,
    required this.pendingReview,
    this.processorVersion = 'horario-ocr-v1',
  });

  final String documentHash;
  final int pageCount;
  final HorarioOcrPeriod period;
  final List<HorarioOcrSubject> subjects;
  final List<HorarioOcrIssue> issues;
  final List<String> pendingReview;
  final String processorVersion;

  /// La Fase 2A produce una propuesta, nunca datos autorizados para guardar.
  bool get requiresHumanReview => true;

  bool get hasBlockingIssues =>
      subjects.isEmpty ||
      issues.any((issue) => issue.severity == HorarioOcrIssueSeverity.error);
}
