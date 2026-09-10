import 'dart:async';

import 'package:eduflow_ai/core/auth/auth_gate.dart';
import 'package:eduflow_ai/core/auth/session_controller.dart';
import 'package:eduflow_ai/pages/login/login_page.dart';
import 'package:eduflow_ai/pages/register/register_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<bool> autofillFinishes;

  setUp(() {
    autofillFinishes = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.textInput, (call) async {
          if (call.method == 'TextInput.finishAutofillContext') {
            autofillFinishes.add(call.arguments as bool);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.textInput, null);
  });

  SessionUserIdentity identity(String uid) => SessionUserIdentity(
    uid: uid,
    email: '$uid@example.com',
    displayName: uid,
  );

  Widget app(Widget home) {
    return MaterialApp(
      builder: (context, child) => AutofillGroup(
        onDisposeAction: AutofillContextAction.cancel,
        child: child!,
      ),
      home: home,
    );
  }

  testWidgets('Login no confirma en preparing y confirma una vez en ready', (
    tester,
  ) async {
    SessionUserIdentity? current;
    final auth = StreamController<SessionUserIdentity?>();
    final pending = Completer<void>();
    final positiveStatuses = <SessionStatus>[];
    final controller = SessionController(
      currentUserProvider: () => current,
      authChanges: auth.stream,
      sessionPreparation: (_, _, _) => pending.future,
      signOutAction: () async {},
    );
    addTearDown(() async {
      controller.dispose();
      await auth.close();
    });

    await tester.pumpWidget(
      app(
        AuthGate(
          sessionController: controller,
          loginBuilder: (_) => LoginPage(
            sessionController: controller,
            autofillFinisher: (shouldSave) {
              autofillFinishes.add(shouldSave);
              if (shouldSave) {
                positiveStatuses.add(controller.status);
              }
            },
            loginAction: (_, _) async {
              current = identity('a');
              auth.add(current);
            },
          ),
          readyBuilder: (_) => const Scaffold(body: Text('MAIN-TEST')),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).at(0), 'a@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'clave');
    await tester.ensureVisible(find.byType(ElevatedButton));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(find.text('Preparando tu espacio…'), findsOneWidget);
    expect(autofillFinishes, isEmpty);

    pending.complete();
    await tester.pumpAndSettle();
    await tester.pump();
    expect(find.text('MAIN-TEST'), findsOneWidget);
    expect(autofillFinishes, [true]);
    expect(positiveStatuses, [SessionStatus.ready]);
  });

  testWidgets('error de preparación cancela Autofill sin guardar', (
    tester,
  ) async {
    SessionUserIdentity? current;
    final auth = StreamController<SessionUserIdentity?>();
    final controller = SessionController(
      currentUserProvider: () => current,
      authChanges: auth.stream,
      sessionPreparation: (_, _, _) async => throw StateError('perfil'),
      signOutAction: () async {},
    );
    addTearDown(() async {
      controller.dispose();
      await auth.close();
    });

    await tester.pumpWidget(
      app(
        AuthGate(
          sessionController: controller,
          loginBuilder: (_) => LoginPage(
            sessionController: controller,
            autofillFinisher: autofillFinishes.add,
            loginAction: (_, _) async {
              current = identity('a');
              auth.add(current);
            },
          ),
          readyBuilder: (_) => const Text('MAIN-TEST'),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).at(0), 'a@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'clave');
    await tester.ensureVisible(find.byType(ElevatedButton));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await tester.pump();

    expect(find.text('No pudimos preparar tu sesión'), findsOneWidget);
    expect(autofillFinishes, [false]);
  });

  testWidgets('Registro solo desaparece al llegar a ready y confirma una vez', (
    tester,
  ) async {
    SessionUserIdentity? current;
    final auth = StreamController<SessionUserIdentity?>();
    final pending = Completer<void>();
    final positiveStatuses = <SessionStatus>[];
    final controller = SessionController(
      currentUserProvider: () => current,
      authChanges: auth.stream,
      sessionPreparation: (_, _, _) => pending.future,
      signOutAction: () async {},
    );
    addTearDown(() async {
      controller.dispose();
      await auth.close();
    });

    await tester.pumpWidget(
      app(
        AuthGate(
          sessionController: controller,
          loginBuilder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RegisterPage(
                    sessionController: controller,
                    autofillFinisher: (shouldSave) {
                      autofillFinishes.add(shouldSave);
                      if (shouldSave) {
                        positiveStatuses.add(controller.status);
                      }
                    },
                    registerAction: (_, _, _, _) async {
                      current = identity('nuevo');
                      auth.add(current);
                    },
                  ),
                ),
              ),
              child: const Text('ABRIR-REGISTRO'),
            ),
          ),
          readyBuilder: (_) => const Scaffold(body: Text('MAIN-TEST')),
        ),
      ),
    );
    await tester.tap(find.text('ABRIR-REGISTRO'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Estudiante');
    await tester.enterText(fields.at(1), 'nuevo@example.com');
    await tester.enterText(fields.at(2), 'abcdef1!');
    await tester.enterText(fields.at(3), 'abcdef1!');
    await tester.ensureVisible(find.byType(ElevatedButton));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(find.byType(RegisterPage), findsOneWidget);
    expect(autofillFinishes, isEmpty);

    pending.complete();
    await tester.pumpAndSettle();
    await tester.pump();
    expect(find.byType(RegisterPage), findsNothing);
    expect(find.text('MAIN-TEST'), findsOneWidget);
    expect(autofillFinishes, [true]);
    expect(positiveStatuses, [SessionStatus.ready]);
  });

  testWidgets('cancelar Registro finaliza Autofill sin guardar', (
    tester,
  ) async {
    final auth = StreamController<SessionUserIdentity?>();
    final controller = SessionController(
      currentUserProvider: () => null,
      authChanges: auth.stream,
      sessionPreparation: (_, _, _) async {},
      signOutAction: () async {},
    );
    addTearDown(() async {
      controller.dispose();
      await auth.close();
    });
    await tester.pumpWidget(
      app(
        Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RegisterPage(
                      sessionController: controller,
                      autofillFinisher: autofillFinishes.add,
                    ),
                  ),
                ),
                child: const Text('ABRIR-REGISTRO'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ABRIR-REGISTRO'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Iniciar sesión'));
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterPage), findsNothing);
    expect(autofillFinishes, [false]);
  });
}
