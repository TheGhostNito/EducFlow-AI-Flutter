import 'package:eduflow_ai/widgets/app_animated_visibility.dart';
import 'package:eduflow_ai/widgets/app_pressable.dart';
import 'package:eduflow_ai/widgets/app_reveal.dart';
import 'package:eduflow_ai/widgets/auth_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Widget child, {bool reducirMovimiento = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducirMovimiento),
      child: Scaffold(body: child),
    ),
  );

  testWidgets(
    'los avisos se recogen, conservan su texto y dejan de anunciarse',
    (tester) async {
      Widget mensaje(String text) => app(AuthStatusMessage(message: text));
      await tester.pumpWidget(mensaje('Revisa el correo'));
      final height = tester.getSize(find.byType(AppAnimatedVisibility)).height;
      await tester.pumpWidget(mensaje(''));
      await tester.pump(const Duration(milliseconds: 90));
      final halfway = tester.getSize(find.byType(AppAnimatedVisibility)).height;
      expect(halfway, greaterThan(0));
      expect(halfway, lessThan(height));
      expect(find.text('Revisa el correo'), findsOneWidget);
      expect(
        tester
            .widget<ExcludeSemantics>(
              find
                  .descendant(
                    of: find.byType(AppAnimatedVisibility),
                    matching: find.byType(ExcludeSemantics),
                  )
                  .first,
            )
            .excluding,
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(AppAnimatedVisibility)).height, 0);
      await tester.pumpWidget(mensaje('Intenta nuevamente'));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(AppAnimatedVisibility)).height,
        greaterThan(0),
      );
      expect(find.text('Intenta nuevamente'), findsOneWidget);
    },
  );

  testWidgets('la entrada recorre 12 píxeles aunque el contenido sea alto', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const AppReveal(child: SizedBox(width: 200, height: 600))),
    );
    final transform = tester.widget<Transform>(
      find
          .descendant(
            of: find.byType(AppReveal),
            matching: find.byType(Transform),
          )
          .first,
    );
    expect(transform.transform.storage[13], 12);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Transform>(
            find
                .descendant(
                  of: find.byType(AppReveal),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .transform
          .storage[13],
      0,
    );
  });

  testWidgets(
    'movimiento reducido muestra el contenido sin esperas ni escala',
    (tester) async {
      await tester.pumpWidget(
        app(
          const AppReveal(
            delay: Duration(seconds: 1),
            child: AppPressable(child: SizedBox(width: 200, height: 80)),
          ),
          reducirMovimiento: true,
        ),
      );
      expect(
        tester
            .widget<FadeTransition>(
              find
                  .descendant(
                    of: find.byType(AppReveal),
                    matching: find.byType(FadeTransition),
                  )
                  .first,
            )
            .opacity
            .value,
        1,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(AppPressable)),
      );
      await tester.pump();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
      await gesture.cancel();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('un desplazamiento cancela la pulsación y su vibración', (
    tester,
  ) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      app(const AppPressable(child: SizedBox(width: 200, height: 100))),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(AppPressable)),
    );
    await tester.pump();
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      lessThan(1),
    );
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    await gesture.up();
    expect(haptics, isEmpty);
    await tester.tap(find.byType(AppPressable));
    expect(haptics, hasLength(1));
    await tester.pumpAndSettle();
  });
}
