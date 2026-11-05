enum CalendarViewMode { semana, mes }

class CalendarNavigationResult {
  const CalendarNavigationResult({
    required this.selectedDate,
    required this.visibleMonth,
  });

  final DateTime selectedDate;
  final DateTime visibleMonth;
}

CalendarNavigationResult navigateCalendar({
  required CalendarViewMode mode,
  required DateTime selectedDate,
  required DateTime visibleMonth,
  required int direction,
}) {
  assert(direction == -1 || direction == 1);
  final DateTime selected = DateTime(
    selectedDate.year,
    selectedDate.month,
    selectedDate.day,
  );

  if (mode == CalendarViewMode.semana) {
    final DateTime next = selected.add(Duration(days: 7 * direction));
    return CalendarNavigationResult(
      selectedDate: next,
      visibleMonth: DateTime(next.year, next.month, 1),
    );
  }

  final DateTime month = DateTime(
    visibleMonth.year,
    visibleMonth.month + direction,
    1,
  );
  final int lastDay = DateTime(month.year, month.month + 1, 0).day;
  final int day = selected.day > lastDay ? lastDay : selected.day;
  return CalendarNavigationResult(
    selectedDate: DateTime(month.year, month.month, day),
    visibleMonth: month,
  );
}
