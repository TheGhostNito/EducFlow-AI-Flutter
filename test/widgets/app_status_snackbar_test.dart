import 'package:eduflow_ai/widgets/app_status_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el progreso usa la duración restante y queda limitado entre 0 y 1', () {
    final DateTime start = DateTime(2026, 9, 9, 12);
    const Duration duration = Duration(seconds: 3);
    final DateTime expiresAt = start.add(duration);

    expect(
      appStatusProgressFraction(
        duration: duration,
        expiresAt: expiresAt,
        now: start,
      ),
      1,
    );
    expect(
      appStatusProgressFraction(
        duration: duration,
        expiresAt: expiresAt,
        now: start.add(const Duration(milliseconds: 1500)),
      ),
      closeTo(0.5, 0.001),
    );
    expect(
      appStatusProgressFraction(
        duration: duration,
        expiresAt: expiresAt,
        now: expiresAt.add(const Duration(milliseconds: 1)),
      ),
      0,
    );
    expect(
      appStatusProgressFraction(
        duration: duration,
        expiresAt: expiresAt,
        now: start.subtract(const Duration(seconds: 1)),
      ),
      1,
    );
  });

  test('reconstrucciones posteriores nunca aumentan el progreso', () {
    final DateTime start = DateTime(2026, 9, 9, 12);
    const Duration duration = Duration(seconds: 3);
    final DateTime expiresAt = start.add(duration);
    final double firstMount = appStatusProgressFraction(
      duration: duration,
      expiresAt: expiresAt,
      now: start.add(const Duration(milliseconds: 800)),
    );
    final double secondMount = appStatusProgressFraction(
      duration: duration,
      expiresAt: expiresAt,
      now: start.add(const Duration(milliseconds: 1800)),
    );

    expect(secondMount, lessThan(firstMount));
  });

  testWidgets(
    'al remontarse el contenido comienza desde la fracción realmente restante',
    (tester) async {
      const Duration duration = Duration(milliseconds: 400);
      await tester.pumpWidget(
        const _StatusHost(type: AppStatusType.info, duration: duration),
      );
      await tester.tap(find.text('Mostrar'));
      await tester.pump();
      final Widget content = tester
          .widget<SnackBar>(find.byType(SnackBar))
          .content;

      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: content)),
        ),
      );
      await tester.pump();

      final FractionallySizedBox progress = tester.widget(
        find.byKey(const Key('app-status-progress')),
      );
      expect(progress.widthFactor, greaterThan(0));
      expect(progress.widthFactor, lessThan(0.7));

      await tester.pump(const Duration(milliseconds: 250));
      final FractionallySizedBox expiredProgress = tester.widget(
        find.byKey(const Key('app-status-progress')),
      );
      expect(expiredProgress.widthFactor, 0);
    },
  );

  for (final MapEntry<AppStatusType, IconData> entry in {
    AppStatusType.success: Icons.check_circle_outline_rounded,
    AppStatusType.error: Icons.error_outline_rounded,
    AppStatusType.warning: Icons.warning_amber_rounded,
    AppStatusType.info: Icons.info_outline_rounded,
  }.entries) {
    testWidgets('${entry.key.name} mantiene su icono y muestra el progreso', (
      tester,
    ) async {
      await tester.pumpWidget(_StatusHost(type: entry.key));
      await tester.tap(find.text('Mostrar'));
      await tester.pump();

      expect(find.byIcon(entry.value), findsOneWidget);
      final FractionallySizedBox progress = tester.widget(
        find.byKey(const Key('app-status-progress')),
      );
      expect(progress.widthFactor, closeTo(1, 0.02));

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Mensaje'), findsNothing);
    });
  }
}

class _StatusHost extends StatelessWidget {
  const _StatusHost({
    required this.type,
    this.duration = const Duration(seconds: 3),
  });

  final AppStatusType type;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () => showAppStatusSnackBar(
                context,
                message: 'Mensaje',
                type: type,
                duration: duration,
              ),
              child: const Text('Mostrar'),
            );
          },
        ),
      ),
    );
  }
}
