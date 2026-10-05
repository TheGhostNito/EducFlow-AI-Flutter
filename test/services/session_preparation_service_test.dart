import 'dart:async';

import 'package:eduflow_ai/core/auth/session_controller.dart';
import 'package:eduflow_ai/models/perfil_usuario.dart';
import 'package:eduflow_ai/services/session_preparation_service.dart';
import 'package:eduflow_ai/services/user_preferences_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const identity = SessionUserIdentity(
    uid: 'uid-a',
    email: 'a@example.com',
    displayName: 'A',
  );
  const profile = PerfilUsuario(
    uid: 'uid-a',
    nombre: 'A',
    correoPrincipal: 'a@example.com',
    correoInstitucional: '',
    nivelEducativo: NivelEducativoPerfil.vacio,
    nombreEstablecimiento: '',
    tipoEstablecimiento: '',
    cursoActual: '',
    carrera: '',
    semestreActual: null,
    anioIngreso: null,
    sede: '',
    jornada: '',
    estadoAcademico: '',
    idioma: 'es',
    perfilCompleto: false,
  );

  SessionPreparationService service({
    Future<void> Function()? role,
    Future<PerfilUsuario> Function()? ensureProfile,
    Future<void> Function()? root,
    Future<UserPreferences> Function()? load,
    void Function(UserPreferences)? apply,
  }) {
    return SessionPreparationService(
      ensureRole: (_, _) => role?.call() ?? Future<void>.value(),
      ensureProfile: (_, _, _) =>
          ensureProfile?.call() ?? Future.value(profile),
      ensureCompatibilityRoot: (_, _, _, _) =>
          root?.call() ?? Future<void>.value(),
      loadPreferences: (_) =>
          load?.call() ?? Future.value(UserPreferences.defaults),
      applyPreferences: apply ?? (_) {},
    );
  }

  test('un fallo de rol detiene perfil, raíz y preferencias', () async {
    var profiles = 0;
    var roots = 0;
    var loads = 0;
    final subject = service(
      role: () async => throw StateError('claim ausente'),
      ensureProfile: () async {
        profiles++;
        return profile;
      },
      root: () async => roots++,
      load: () async {
        loads++;
        return UserPreferences.defaults;
      },
    );

    await expectLater(
      subject.prepare(identity, null, () => true),
      throwsStateError,
    );
    expect((profiles, roots, loads), (0, 0, 0));
  });

  test('el orden exige rol antes de cualquier acceso de perfil', () async {
    final events = <String>[];
    final subject = service(
      role: () async {
        events.add('token-renovado-y-claim-confirmado');
      },
      ensureProfile: () async {
        events.add('supabase-perfil');
        return profile;
      },
      root: () async => events.add('firestore-root'),
      load: () async {
        events.add('preferencias-leidas');
        return UserPreferences.defaults;
      },
      apply: (_) => events.add('preferencias-aplicadas'),
    );

    await subject.prepare(identity, null, () => true);
    expect(events, [
      'token-renovado-y-claim-confirmado',
      'supabase-perfil',
      'firestore-root',
      'preferencias-leidas',
      'preferencias-aplicadas',
    ]);
  });

  test('invalidación durante lectura no aplica efectos globales', () async {
    final pending = Completer<UserPreferences>();
    var valid = true;
    var applied = false;
    final subject = service(
      load: () => pending.future,
      apply: (_) => applied = true,
    );

    final preparation = subject.prepare(identity, null, () => valid);
    await Future<void>.delayed(Duration.zero);
    valid = false;
    pending.complete(UserPreferences.defaults.copyWith(theme: 'dark'));

    await expectLater(
      preparation,
      throwsA(isA<SessionPreparationInvalidated>()),
    );
    expect(applied, isFalse);
  });

  test(
    'fallos de perfil y Firestore se propagan como error controlado',
    () async {
      await expectLater(
        service(ensureProfile: () async => throw StateError('perfil'))
            .prepare(identity, null, () => true),
        throwsStateError,
      );
      await expectLater(
        service(root: () async => throw StateError('firestore'))
            .prepare(identity, null, () => true),
        throwsStateError,
      );
    },
  );

  test(
    'A lento no puede reemplazar preferencias ya aplicadas para B',
    () async {
      SessionUserIdentity? current = identity;
      final auth = StreamController<SessionUserIdentity?>();
      final slowA = Completer<UserPreferences>();
      UserPreferences? applied;
      final subject = service(
        load: () {
          if (current?.uid == 'uid-a') return slowA.future;
          return Future.value(
            UserPreferences.defaults.copyWith(
              theme: 'dark',
              language: 'en',
              timeFormat: '12h',
            ),
          );
        },
        apply: (preferences) => applied = preferences,
      );
      final controller = SessionController(
        currentUserProvider: () => current,
        authChanges: auth.stream,
        sessionPreparation: subject.prepare,
        signOutAction: () async {},
      );

      await Future<void>.delayed(Duration.zero);
      current = const SessionUserIdentity(
        uid: 'uid-b',
        email: 'b@example.com',
        displayName: 'B',
      );
      auth.add(current);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(
        (applied?.theme, applied?.language, applied?.timeFormat),
        ('dark', 'en', '12h'),
      );

      slowA.complete(
        UserPreferences.defaults.copyWith(
          theme: 'light',
          language: 'es',
          timeFormat: '24h',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        (applied?.theme, applied?.language, applied?.timeFormat),
        ('dark', 'en', '12h'),
      );

      controller.dispose();
      await auth.close();
    },
  );
}
