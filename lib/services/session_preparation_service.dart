import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../core/auth/session_controller.dart';
import '../models/perfil_usuario.dart';
import 'perfil_service.dart';
import 'theme_service.dart';
import 'time_format_service.dart';
import 'translation_service.dart';
import 'user_preferences_service.dart';

typedef EnsureSessionRole = Future<void> Function(
  SessionUserIdentity identity,
  SessionValidityGuard isValid,
);
typedef EnsureSessionProfile = Future<PerfilUsuario> Function(
  SessionUserIdentity identity,
  RegistrationSessionData? registration,
  SessionValidityGuard isValid,
);
typedef EnsureSessionCompatibilityRoot = Future<void> Function(
  SessionUserIdentity identity,
  RegistrationSessionData? registration,
  PerfilUsuario profile,
  SessionValidityGuard isValid,
);
typedef LoadSessionPreferences = Future<UserPreferences> Function(String uid);
typedef ApplySessionPreferences = void Function(UserPreferences preferences);

class SessionPreparationService {
  SessionPreparationService({
    required this.ensureRole,
    required this.ensureProfile,
    required this.ensureCompatibilityRoot,
    required this.loadPreferences,
    required this.applyPreferences,
  });

  factory SessionPreparationService.production() {
    return SessionPreparationService(
      ensureRole: _ensureSupabaseRole,
      ensureProfile: _ensureProductionProfile,
      ensureCompatibilityRoot: _ensureProductionCompatibilityRoot,
      loadPreferences: (uid) => UserPreferencesService.instance
          .getPreferencesForUser(uid, forceRefresh: true),
      applyPreferences: _applyProductionPreferences,
    );
  }

  static final SessionPreparationService instance =
      SessionPreparationService.production();

  final EnsureSessionRole ensureRole;
  final EnsureSessionProfile ensureProfile;
  final EnsureSessionCompatibilityRoot ensureCompatibilityRoot;
  final LoadSessionPreferences loadPreferences;
  final ApplySessionPreferences applyPreferences;

  Future<void> prepare(
    SessionUserIdentity identity,
    RegistrationSessionData? registration,
    SessionValidityGuard isValid,
  ) async {
    _checkValid(isValid);
    await ensureRole(identity, isValid);
    _checkValid(isValid);

    final profile = await ensureProfile(identity, registration, isValid);
    _checkValid(isValid);

    await ensureCompatibilityRoot(identity, registration, profile, isValid);
    _checkValid(isValid);

    // La lectura no cambia el estado visual global. Las tres preferencias se
    // aplican juntas únicamente después de validar de nuevo UID y generación.
    final preferences = await loadPreferences(identity.uid);
    _checkValid(isValid);
    applyPreferences(preferences);
    _checkValid(isValid);
  }

  static Future<void> _ensureSupabaseRole(
    SessionUserIdentity identity,
    SessionValidityGuard isValid,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != identity.uid) {
      throw const SessionPreparationInvalidated();
    }

    var token = await user.getIdToken();
    _checkValid(isValid);
    if (token == null || token.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-id-token',
        message: 'No fue posible obtener la credencial del usuario.',
      );
    }

    final response = await Supabase.instance.client.functions.invoke(
      'firebase-role',
      headers: {'Authorization': 'Bearer $token'},
      body: const <String, dynamic>{},
    );
    _checkValid(isValid);

    final data = response.data;
    if (data is! Map || data['success'] != true) {
      throw FirebaseAuthException(
        code: 'role-assignment-failed',
        message: 'No fue posible preparar la cuenta para acceder a los datos.',
      );
    }

    if (data['refreshToken'] == true) {
      token = await user.getIdToken(true);
      _checkValid(isValid);
      if (token == null || token.isEmpty) {
        throw FirebaseAuthException(
          code: 'missing-refreshed-id-token',
          message: 'No fue posible renovar la credencial del usuario.',
        );
      }
    }

    var result = await user.getIdTokenResult();
    _checkValid(isValid);
    if (result.claims?['role'] != 'authenticated') {
      result = await user.getIdTokenResult(true);
      _checkValid(isValid);
    }

    if (result.claims?['role'] != 'authenticated') {
      throw FirebaseAuthException(
        code: 'role-not-available',
        message:
            'La cuenta todavía no está preparada para acceder a los datos.',
      );
    }
  }

  static Future<PerfilUsuario> _ensureProductionProfile(
    SessionUserIdentity identity,
    RegistrationSessionData? registration,
    SessionValidityGuard isValid,
  ) {
    return PerfilService(isSessionCurrent: isValid).asegurarPerfilInicial(
      uid: identity.uid,
      nombre: registration?.name ?? identity.displayName ?? '',
      correoPrincipal: registration?.email ?? identity.email ?? '',
      idioma: registration?.language ?? 'es',
    );
  }

  static Future<void> _ensureProductionCompatibilityRoot(
    SessionUserIdentity identity,
    RegistrationSessionData? registration,
    PerfilUsuario profile,
    SessionValidityGuard isValid,
  ) async {
    _checkValid(isValid);
    final initialPreferences = UserPreferences.defaults.copyWith(
      language: registration?.language ?? profile.idioma,
      theme: registration?.theme,
    );
    await UserPreferencesService.instance.ensureCompatibilityRoot(
      uid: identity.uid,
      email: registration?.email ?? identity.email ?? '',
      initialPreferences: initialPreferences,
    );
  }

  static void _applyProductionPreferences(UserPreferences preferences) {
    ThemeService.instance.applyUserPreference(preferences.theme);
    TranslationService.instance.applyUserPreference(preferences.language);
    TimeFormatService.instance.applyUserPreference(preferences.timeFormat);
  }

  static void _checkValid(SessionValidityGuard isValid) {
    if (!isValid()) {
      throw const SessionPreparationInvalidated();
    }
  }
}

class SessionPreparationInvalidated implements Exception {
  const SessionPreparationInvalidated();
}
