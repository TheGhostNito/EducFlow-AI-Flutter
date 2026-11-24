// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:eduflow_ai/main.dart';

import 'support/firebase_auth_test_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FirebaseAuthTestHost().initialize();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'https://ubjmdfwkjgblnjgmufpc.supabase.co',
      publishableKey: 'sb_publishable_DmUj02VfZSkZOzoR11oq5A_TumX6rfA',
    );
  });

  testWidgets('EducFlow AI muestra el inicio de sesión sin usuario', (
    tester,
  ) async {
    await tester.pumpWidget(const EducFlowApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('EducFlow AI'), findsOneWidget);
    expect(find.text('Inicia sesión'), findsOneWidget);
    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
