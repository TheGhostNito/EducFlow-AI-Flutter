import 'package:eduflow_ai/services/ai_academic_query_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 14, 8, 30);

  test('respeta límites civiles de esta semana y próxima semana', () {
    final thisWeek = AiDateScope.parse('esta semana', now);
    final nextWeek = AiDateScope.parse('próxima semana', now);
    expect(thisWeek.matches(DateTime(2026, 10, 12), null), isTrue);
    expect(thisWeek.matches(DateTime(2026, 10, 18), null), isTrue);
    expect(thisWeek.matches(DateTime(2026, 10, 19), null), isFalse);
    expect(nextWeek.matches(DateTime(2026, 10, 18), null), isFalse);
    expect(nextWeek.matches(DateTime(2026, 10, 19), null), isTrue);
    expect(nextWeek.matches(DateTime(2026, 10, 25), null), isTrue);
    expect(nextWeek.matches(DateTime(2026, 10, 26), null), isFalse);
  });

  test('acepta fechas completas y rechaza fechas inválidas o incompletas', () {
    for (final query in [
      '14/10/2026',
      '14-10-2026',
      '2026-10-14',
      '14 de octubre de 2026',
    ]) {
      final scope = AiDateScope.parse(query, now);
      expect(scope.kind, AiDateScopeKind.exactDate, reason: query);
      expect(scope.matches(DateTime(2026, 10, 14), null), isTrue);
      expect(scope.matches(DateTime(2026, 10, 15), null), isFalse);
    }
    expect(
      AiDateScope.parse('31/02/2026', now).kind,
      AiDateScopeKind.unsupported,
    );
    expect(
      AiDateScope.parse('14 de octubre', now).kind,
      AiDateScopeKind.unsupported,
    );
  });

  test('próximas compara horas de hoy en zona local del dispositivo', () {
    final scope = AiDateScope.parse('próximas', now);
    expect(scope.matches(DateTime(2026, 10, 13), '23:59'), isFalse);
    expect(scope.matches(DateTime(2026, 10, 14), '08:29'), isFalse);
    expect(scope.matches(DateTime(2026, 10, 14), '08:30'), isTrue);
    expect(scope.matches(DateTime(2026, 10, 14), null), isTrue);
    expect(scope.matches(DateTime(2026, 10, 15), '00:00'), isTrue);
  });
}
