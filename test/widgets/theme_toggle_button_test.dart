import 'package:eduflow_ai/services/theme_service.dart';
import 'package:eduflow_ai/widgets/theme_toggle_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/firebase_auth_test_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final host = FirebaseAuthTestHost();

  setUpAll(host.initialize);
  setUp(() {
    host.reset();
    ThemeService.instance.resetForSignedOutUser();
  });

  Widget harness() {
    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) => MaterialApp(
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: ThemeService.instance.themeMode,
        home: const Scaffold(body: ThemeToggleButton()),
      ),
    );
  }

  testWidgets('tema precargado y rebuild conservan el icono correcto', (
    tester,
  ) async {
    await ThemeService.instance.setDarkMode(true);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
    expect(find.byType(AnimatedRotation), findsNothing);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
  });

  testWidgets('doble toque rápido sólo cambia el tema una vez', (tester) async {
    await tester.pumpWidget(harness());
    await tester.tap(find.byType(InkWell));
    await tester.tap(find.byType(InkWell), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(ThemeService.instance.isDarkMode, isTrue);
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
  });
}
