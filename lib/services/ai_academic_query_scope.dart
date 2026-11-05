enum AiDateScopeKind {
  none,
  upcoming,
  today,
  tomorrow,
  thisWeek,
  nextWeek,
  exactDate,
  weekday,
  unsupported,
}

/// Interpreta fechas de calendario en la zona local del dispositivo.
/// Las fechas académicas de Supabase son fechas civiles, sin zona horaria.
class AiDateScope {
  const AiDateScope._(this.kind, this.now, {this.date, this.weekday});

  final AiDateScopeKind kind;
  final DateTime now;
  final DateTime? date;
  final int? weekday;

  static AiDateScope parse(String query, DateTime now) {
    final text = normalizeAcademicQuery(query);
    final raw = _foldAccents(query.toLowerCase());
    final dates = <DateTime>[];
    var invalidDate = false;

    void addDate(int year, int month, int day) {
      final candidate = DateTime(year, month, day);
      if (candidate.year != year ||
          candidate.month != month ||
          candidate.day != day) {
        invalidDate = true;
      } else {
        dates.add(candidate);
      }
    }

    for (final match in RegExp(
      r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b',
    ).allMatches(raw)) {
      addDate(int.parse(match[1]!), int.parse(match[2]!), int.parse(match[3]!));
    }
    for (final match in RegExp(
      r'\b(\d{1,2})/(\d{1,2})/(\d{4})\b',
    ).allMatches(raw)) {
      addDate(int.parse(match[3]!), int.parse(match[2]!), int.parse(match[1]!));
    }
    for (final match in RegExp(
      r'\b(\d{1,2})-(\d{1,2})-(\d{4})\b',
    ).allMatches(raw)) {
      addDate(int.parse(match[3]!), int.parse(match[2]!), int.parse(match[1]!));
    }
    const months = <String, int>{
      'enero': 1,
      'febrero': 2,
      'marzo': 3,
      'abril': 4,
      'mayo': 5,
      'junio': 6,
      'julio': 7,
      'agosto': 8,
      'septiembre': 9,
      'octubre': 10,
      'noviembre': 11,
      'diciembre': 12,
    };
    for (final match in RegExp(
      r'\b(\d{1,2})\s+de\s+(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre)\s+(?:de\s+)?(\d{4})\b',
    ).allMatches(raw)) {
      addDate(int.parse(match[3]!), months[match[2]!]!, int.parse(match[1]!));
    }

    final relative = <AiDateScopeKind>[
      if (containsAcademicPhrase(text, 'hoy') ||
          containsAcademicPhrase(text, 'today'))
        AiDateScopeKind.today,
      if (containsAcademicPhrase(text, 'manana') ||
          containsAcademicPhrase(text, 'tomorrow'))
        AiDateScopeKind.tomorrow,
      if (containsAcademicPhrase(text, 'esta semana') ||
          containsAcademicPhrase(text, 'this week'))
        AiDateScopeKind.thisWeek,
      if (containsAcademicPhrase(text, 'proxima semana') ||
          containsAcademicPhrase(text, 'la semana que viene') ||
          containsAcademicPhrase(text, 'next week'))
        AiDateScopeKind.nextWeek,
    ];
    final hasUnsupportedTime =
        RegExp(
          r'\b(ayer|pasado|pasada|mes|entre|desde|hasta|antes|despues|around|after|before)\b',
        ).hasMatch(text) ||
        RegExp(r'\b(?:a las|at)\s+\d{1,2}(?::\d{2})?\b').hasMatch(raw);
    final incompleteDate =
        RegExp(r'\b\d{1,2}/\d{1,2}\b(?!/\d{4})').hasMatch(raw) ||
        RegExp(
          r'\b\d{1,2}\s+de\s+(?:enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre)\b(?!\s+(?:de\s+)?\d{4})',
        ).hasMatch(raw);
    if (invalidDate ||
        incompleteDate ||
        hasUnsupportedTime ||
        dates.length > 1 ||
        relative.length > 1 ||
        (dates.isNotEmpty && relative.isNotEmpty)) {
      return AiDateScope._(AiDateScopeKind.unsupported, now);
    }
    if (dates.isNotEmpty) {
      return AiDateScope._(AiDateScopeKind.exactDate, now, date: dates.single);
    }
    if (relative.isNotEmpty) return AiDateScope._(relative.single, now);

    const weekdays = <String, int>{
      'lunes': DateTime.monday,
      'martes': DateTime.tuesday,
      'miercoles': DateTime.wednesday,
      'jueves': DateTime.thursday,
      'viernes': DateTime.friday,
      'sabado': DateTime.saturday,
      'domingo': DateTime.sunday,
      'monday': DateTime.monday,
      'tuesday': DateTime.tuesday,
      'wednesday': DateTime.wednesday,
      'thursday': DateTime.thursday,
      'friday': DateTime.friday,
      'saturday': DateTime.saturday,
      'sunday': DateTime.sunday,
    };
    final mentioned = weekdays.entries
        .where((entry) => containsAcademicPhrase(text, entry.key))
        .map((entry) => entry.value)
        .toSet();
    if (mentioned.length > 1) {
      return AiDateScope._(AiDateScopeKind.unsupported, now);
    }
    if (mentioned.isNotEmpty) {
      return AiDateScope._(
        AiDateScopeKind.weekday,
        now,
        weekday: mentioned.single,
      );
    }
    if (containsAcademicPhrase(text, 'proxima') ||
        containsAcademicPhrase(text, 'proximas') ||
        containsAcademicPhrase(text, 'proximo') ||
        containsAcademicPhrase(text, 'proximos') ||
        containsAcademicPhrase(text, 'upcoming') ||
        containsAcademicPhrase(text, 'next')) {
      return AiDateScope._(AiDateScopeKind.upcoming, now);
    }
    return AiDateScope._(AiDateScopeKind.none, now);
  }

  bool matches(DateTime value, String? time, {bool defaultUpcoming = false}) {
    final day = DateTime(value.year, value.month, value.day);
    final today = DateTime(now.year, now.month, now.day);
    final effective = kind == AiDateScopeKind.none && defaultUpcoming
        ? AiDateScopeKind.upcoming
        : kind;
    switch (effective) {
      case AiDateScopeKind.none:
        return true;
      case AiDateScopeKind.upcoming:
        if (day.isBefore(today)) return false;
        if (day.isAfter(today)) return true;
        final minutes = _timeMinutes(time);
        return minutes == null || minutes >= now.hour * 60 + now.minute;
      case AiDateScopeKind.today:
        return day == today;
      case AiDateScopeKind.tomorrow:
        return day == DateTime(now.year, now.month, now.day + 1);
      case AiDateScopeKind.thisWeek:
      case AiDateScopeKind.nextWeek:
        final monday = DateTime(now.year, now.month, now.day - now.weekday + 1);
        final start = effective == AiDateScopeKind.nextWeek
            ? DateTime(monday.year, monday.month, monday.day + 7)
            : monday;
        final end = DateTime(start.year, start.month, start.day + 7);
        return !day.isBefore(start) && day.isBefore(end);
      case AiDateScopeKind.exactDate:
        return day == date;
      case AiDateScopeKind.weekday:
        return day.weekday == weekday;
      case AiDateScopeKind.unsupported:
        return false;
    }
  }

  int? get targetWeekday => switch (kind) {
    AiDateScopeKind.today => now.weekday,
    AiDateScopeKind.tomorrow => DateTime(
      now.year,
      now.month,
      now.day + 1,
    ).weekday,
    AiDateScopeKind.exactDate => date?.weekday,
    AiDateScopeKind.weekday => weekday,
    _ => null,
  };

  static int? _timeMinutes(String? value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value?.trim() ?? '');
    if (match == null) return null;
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    if (hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }
}

String normalizeAcademicQuery(String value) =>
    _foldAccents(value.toLowerCase())
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

bool containsAcademicPhrase(String text, String phrase) =>
    RegExp('(?:^| )${RegExp.escape(phrase)}(?: |\u0024)').hasMatch(text);

String _foldAccents(String value) => value
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ü', 'u')
    .replaceAll('ñ', 'n');
