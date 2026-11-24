import 'package:eduflow_ai/pages/calendar/calendar_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('navegación semanal', () {
    test('avanza exactamente siete días y cruza de mes', () {
      final result = navigateCalendar(
        mode: CalendarViewMode.semana,
        selectedDate: DateTime(2026, 10, 30),
        visibleMonth: DateTime(2026, 10),
        direction: 1,
      );

      expect(result.selectedDate, DateTime(2026, 11, 6));
      expect(result.visibleMonth, DateTime(2026, 11));
    });

    test('retrocede exactamente siete días y cruza de año', () {
      final result = navigateCalendar(
        mode: CalendarViewMode.semana,
        selectedDate: DateTime(2027, 1, 3),
        visibleMonth: DateTime(2027, 1),
        direction: -1,
      );

      expect(result.selectedDate, DateTime(2026, 12, 27));
      expect(result.visibleMonth, DateTime(2026, 12));
    });
  });

  group('navegación mensual', () {
    test('avanza un mes y conserva el día seleccionado', () {
      final result = navigateCalendar(
        mode: CalendarViewMode.mes,
        selectedDate: DateTime(2026, 10, 14),
        visibleMonth: DateTime(2026, 10),
        direction: 1,
      );

      expect(result.selectedDate, DateTime(2026, 11, 14));
      expect(result.visibleMonth, DateTime(2026, 11));
    });

    test('ajusta el día al último disponible del nuevo mes', () {
      final result = navigateCalendar(
        mode: CalendarViewMode.mes,
        selectedDate: DateTime(2027, 1, 31),
        visibleMonth: DateTime(2027, 1),
        direction: 1,
      );

      expect(result.selectedDate, DateTime(2027, 2, 28));
      expect(result.visibleMonth, DateTime(2027, 2));
    });

    test('cruza de diciembre a enero', () {
      final result = navigateCalendar(
        mode: CalendarViewMode.mes,
        selectedDate: DateTime(2026, 12, 15),
        visibleMonth: DateTime(2026, 12),
        direction: 1,
      );

      expect(result.selectedDate, DateTime(2027, 1, 15));
      expect(result.visibleMonth, DateTime(2027, 1));
    });
  });
}
