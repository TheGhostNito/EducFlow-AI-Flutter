import 'dart:async';

import 'package:eduflow_ai/core/auth/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SessionUserIdentity user(String uid) => SessionUserIdentity(
    uid: uid,
    email: '$uid@example.com',
    displayName: 'Estudiante',
  );

  test('sin usuario queda unauthenticated', () async {
    SessionUserIdentity? current;
    final auth = StreamController<SessionUserIdentity?>();
    final controller = SessionController(
      currentUserProvider: () => current,
      authChanges: auth.stream,
      sessionPreparation: (_, _, _) async {},
      signOutAction: () async {},
    );

    await Future<void>.delayed(Duration.zero);
    expect(controller.status, SessionStatus.unauthenticated);

    controller.dispose();
    await auth.close();
  });

  test('usuario pasa por preparing y llega a ready', () async {
    SessionUserIdentity? current;
    final auth = StreamController<SessionUserIdentity?>();
    final preparation = Completer<void>();
    final controller = SessionController(
      currentUserProvider: () => current,
      authChanges: auth.stream,
      sessionPreparation: (_, _, _) => preparation.future,
      signOutAction: () async {},
    );

    current = user('uno');
    auth.add(current);
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, SessionStatus.preparing);

    preparation.complete();
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, SessionStatus.ready);

    controller.dispose();
    await auth.close();
  });

  test('error controlado y retry ejecuta una nueva preparación', () async {
    SessionUserIdentity? current = user('uno');
    final auth = StreamController<SessionUserIdentity?>();
    var attempts = 0;
    final controller = SessionController(
      currentUserProvider: () => current,
      authChanges: auth.stream,
      sessionPreparation: (_, _, _) async {
        attempts += 1;
        if (attempts == 1) throw Exception('fallo de perfil');
      },
      signOutAction: () async {},
    );

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, SessionStatus.error);

    await controller.retry();
    expect(attempts, 2);
    expect(controller.status, SessionStatus.ready);

    controller.dispose();
    await auth.close();
    current = null;
  });

  test(
    'retry de registro no vuelve a ejecutar la operación Firebase',
    () async {
      SessionUserIdentity? current;
      final auth = StreamController<SessionUserIdentity?>();
      var firebaseRegistrations = 0;
      var preparations = 0;
      RegistrationSessionData? receivedRegistration;
      final controller = SessionController(
        currentUserProvider: () => current,
        authChanges: auth.stream,
        sessionPreparation: (_, registration, _) async {
          preparations += 1;
          receivedRegistration = registration;
          if (preparations == 1) throw Exception('perfil ausente');
        },
        signOutAction: () async {},
      );

      await controller.authenticate(
        registration: const RegistrationSessionData(
          name: 'Martín',
          email: 'martin@example.com',
          language: 'es',
          theme: 'dark',
        ),
        operation: () async {
          firebaseRegistrations += 1;
          current = user('nuevo');
          auth.add(current);
        },
      );

      expect(controller.status, SessionStatus.error);
      await controller.retry();

      expect(firebaseRegistrations, 1);
      expect(preparations, 2);
      expect(receivedRegistration?.name, 'Martín');
      expect(receivedRegistration?.theme, 'dark');
      expect(controller.status, SessionStatus.ready);

      controller.dispose();
      await auth.close();
    },
  );

  test('dos solicitudes del mismo UID comparten una preparación', () async {
    final current = user('uno');
    final auth = StreamController<SessionUserIdentity?>();
    final preparation = Completer<void>();
    var calls = 0;
    final controller = SessionController(
      currentUserProvider: () => current,
      authChanges: auth.stream,
      sessionPreparation: (_, _, _) {
        calls += 1;
        return preparation.future;
      },
      signOutAction: () async {},
    );

    await Future<void>.delayed(Duration.zero);
    final first = controller.requestPreparation();
    final second = controller.requestPreparation();
    expect(calls, 1);

    preparation.complete();
    await Future.wait([first, second]);
    expect(controller.status, SessionStatus.ready);

    controller.dispose();
    await auth.close();
  });

  test('logout durante await ignora el resultado anterior', () async {
    SessionUserIdentity? current = user('uno');
    final auth = StreamController<SessionUserIdentity?>();
    final preparation = Completer<void>();
    final controller = SessionController(
      currentUserProvider: () => current,
      authChanges: auth.stream,
      sessionPreparation: (_, _, _) => preparation.future,
      signOutAction: () async {
        current = null;
        auth.add(null);
      },
    );

    await Future<void>.delayed(Duration.zero);
    await controller.signOut();
    preparation.complete();
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, SessionStatus.unauthenticated);
    expect(controller.activeUid, isNull);

    controller.dispose();
    await auth.close();
  });

  test('cambio de UID invalida la preparación anterior', () async {
    SessionUserIdentity? current = user('uno');
    final auth = StreamController<SessionUserIdentity?>();
    final first = Completer<void>();
    final second = Completer<void>();
    final controller = SessionController(
      currentUserProvider: () => current,
      authChanges: auth.stream,
      sessionPreparation: (identity, _, _) {
        return identity.uid == 'uno' ? first.future : second.future;
      },
      signOutAction: () async {},
    );

    await Future<void>.delayed(Duration.zero);
    current = user('dos');
    auth.add(current);
    await Future<void>.delayed(Duration.zero);
    first.complete();
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, SessionStatus.preparing);
    expect(controller.activeUid, 'dos');

    second.complete();
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, SessionStatus.ready);

    controller.dispose();
    await auth.close();
  });

  test('datos de registro de A nunca se entregan al UID B', () async {
    SessionUserIdentity? current;
    final auth = StreamController<SessionUserIdentity?>();
    final registrations = <String, RegistrationSessionData?>{};
    final controller = SessionController(
      currentUserProvider: () => current,
      authChanges: auth.stream,
      sessionPreparation: (identity, registration, _) async {
        registrations[identity.uid] = registration;
        if (identity.uid == 'a') {
          throw StateError('fallo preparando A');
        }
      },
      signOutAction: () async {},
    );

    await controller.authenticate(
      registration: const RegistrationSessionData(
        name: 'Cuenta A',
        email: 'a@example.com',
        language: 'es',
        theme: 'dark',
      ),
      operation: () async {
        current = user('a');
        auth.add(current);
      },
    );
    expect(controller.status, SessionStatus.error);

    current = user('b');
    auth.add(current);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(registrations['a']?.name, 'Cuenta A');
    expect(registrations['b'], isNull);
    expect(controller.status, SessionStatus.ready);

    controller.dispose();
    await auth.close();
  });

  test('rechaza dos operaciones de autenticación simultáneas', () async {
    SessionUserIdentity? current;
    final auth = StreamController<SessionUserIdentity?>();
    final pending = Completer<void>();
    final controller = SessionController(
      currentUserProvider: () => current,
      authChanges: auth.stream,
      sessionPreparation: (_, _, _) async {},
      signOutAction: () async {},
    );

    final first = controller.authenticate(operation: () => pending.future);
    await expectLater(
      controller.authenticate(operation: () async {}),
      throwsStateError,
    );
    current = user('a');
    auth.add(current);
    pending.complete();
    await first;

    controller.dispose();
    await auth.close();
  });

  test('publica ready antes de notificar el resultado positivo', () async {
    SessionUserIdentity? current;
    final auth = StreamController<SessionUserIdentity?>();
    final events = <String>[];
    final callbackStatuses = <SessionStatus>[];
    final controller = SessionController(
      currentUserProvider: () => current,
      authChanges: auth.stream,
      sessionPreparation: (_, _, _) async {},
      signOutAction: () async {},
    );
    controller.addListener(() => events.add(controller.status.name));

    await controller.authenticate(
      onPreparationResult: (ready) {
        callbackStatuses.add(controller.status);
        events.add('autofill:$ready');
      },
      operation: () async {
        current = user('a');
        auth.add(current);
      },
    );

    expect(events.indexOf('autofill:true'), isNonNegative);
    expect(callbackStatuses, [SessionStatus.ready]);
    expect(
      events.lastIndexOf(SessionStatus.ready.name),
      lessThan(events.indexOf('autofill:true')),
    );
    controller.dispose();
    await auth.close();
  });

  test(
    'un intento fallido no confirma y el retry confirma una vez en ready',
    () async {
      SessionUserIdentity? current;
      final auth = StreamController<SessionUserIdentity?>();
      final callbackStatuses = <SessionStatus>[];
      final controller = SessionController(
        currentUserProvider: () => current,
        authChanges: auth.stream,
        sessionPreparation: (_, _, _) async {},
        signOutAction: () async {},
      );

      await expectLater(
        controller.authenticate<void>(
          onPreparationResult: (_) {
            callbackStatuses.add(controller.status);
          },
          operation: () async => throw StateError('autenticación fallida'),
        ),
        throwsStateError,
      );
      expect(callbackStatuses, isEmpty);

      await controller.authenticate<void>(
        onPreparationResult: (ready) {
          if (ready) {
            callbackStatuses.add(controller.status);
          }
        },
        operation: () async {
          current = user('a');
          auth.add(current);
        },
      );

      expect(callbackStatuses, [SessionStatus.ready]);
      expect(controller.status, SessionStatus.ready);
      controller.dispose();
      await auth.close();
    },
  );

  test('ticket impide mutaciones tardías de badge y scheduler', () async {
    SessionUserIdentity? current = user('a');
    final auth = StreamController<SessionUserIdentity?>();
    final controller = SessionController(
      currentUserProvider: () => current,
      authChanges: auth.stream,
      sessionPreparation: (_, _, _) async {},
      signOutAction: () async {},
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final ticket = controller.captureTicket()!;
    final load = Completer<void>();
    var badgeMutations = 0;
    var notificationMutations = 0;
    final staleWork = () async {
      await load.future;
      if (!controller.isCurrentTicket(ticket)) return;
      badgeMutations++;
      if (!controller.isCurrentTicket(ticket)) return;
      notificationMutations++;
    }();

    current = user('b');
    auth.add(current);
    await Future<void>.delayed(Duration.zero);
    load.complete();
    await staleWork;

    expect(badgeMutations, 0);
    expect(notificationMutations, 0);
    controller.dispose();
    await auth.close();
  });
}
