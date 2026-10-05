import 'dart:async';

import 'package:eduflow_ai/core/auth/auth_gate.dart';
import 'package:eduflow_ai/core/auth/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AuthGate hace imposible saltarse preparación y error', (
    tester,
  ) async {
    SessionUserIdentity? current;
    final auth = StreamController<SessionUserIdentity?>();
    final firstPreparation = Completer<void>();
    var attempts = 0;
    final controller = SessionController(
      currentUserProvider: () => current,
      authChanges: auth.stream,
      sessionPreparation: (_, _, _) {
        attempts++;
        if (attempts == 1) return firstPreparation.future;
        return Future<void>.value();
      },
      signOutAction: () async {},
    );
    addTearDown(() async {
      controller.dispose();
      await auth.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          sessionController: controller,
          loginBuilder: (_) => const Text('LOGIN-TEST'),
          readyBuilder: (_) => const Text('MAIN-TEST'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('LOGIN-TEST'), findsOneWidget);
    expect(find.text('MAIN-TEST'), findsNothing);

    current = const SessionUserIdentity(
      uid: 'a',
      email: 'a@example.com',
      displayName: 'A',
    );
    auth.add(current);
    await tester.pump();
    await tester.pump();
    expect(find.text('Preparando tu espacio…'), findsOneWidget);
    expect(find.text('MAIN-TEST'), findsNothing);

    firstPreparation.completeError(StateError('perfil'));
    await tester.pump();
    await tester.pump();
    expect(find.text('No pudimos preparar tu sesión'), findsOneWidget);
    expect(find.text('MAIN-TEST'), findsNothing);

    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pump();
    expect(find.text('MAIN-TEST'), findsOneWidget);
    expect(find.text('LOGIN-TEST'), findsNothing);
  });
}
