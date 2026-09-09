import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../services/perfil_service.dart';
import '../../services/theme_service.dart';
import '../../services/translation_service.dart';
import '../../services/time_format_service.dart';

class AuthService {
  AuthService({
    FirebaseAuth? firebaseAuth,
    PerfilService? perfilService,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _perfilService = perfilService ?? PerfilService();

  final FirebaseAuth _firebaseAuth;
  final PerfilService _perfilService;

  User? get usuarioActual => _firebaseAuth.currentUser;

  bool get estaAutenticado => usuarioActual != null;

  Stream<User?> get usuarioStream => _firebaseAuth.authStateChanges();

  // =========================================================
  // ASEGURAR ROLE DE SUPABASE
  // =========================================================

  Future<void> _asegurarRoleSupabase(User usuario) async {
    final token = await usuario.getIdToken();

    if (token == null || token.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-id-token',
        message: 'No fue posible obtener la credencial del usuario.',
      );
    }

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'firebase-role',
        headers: {
          'Authorization': 'Bearer $token',
        },
        body: const <String, dynamic>{},
      );

      final data = response.data;

      if (data is! Map || data['success'] != true) {
        throw FirebaseAuthException(
          code: 'role-assignment-failed',
          message:
              'No fue posible preparar la cuenta para acceder a los datos.',
        );
      }

      final bool necesitaRenovarToken = data['refreshToken'] == true;

      if (necesitaRenovarToken) {
        await usuario.getIdToken(true);
      }

      final tokenResult = await usuario.getIdTokenResult();

      if (tokenResult.claims?['role'] != 'authenticated') {
        // Una última renovación por seguridad ante caché local.
        final refreshedResult = await usuario.getIdTokenResult(true);

        if (refreshedResult.claims?['role'] != 'authenticated') {
          throw FirebaseAuthException(
            code: 'role-not-available',
            message:
                'La cuenta todavía no está preparada para acceder a los datos.',
          );
        }
      }
    } on FirebaseAuthException {
      rethrow;
    } catch (_) {
      throw FirebaseAuthException(
        code: 'role-assignment-failed',
        message: 'No fue posible preparar la cuenta para acceder a los datos.',
      );
    }
  }

  // =========================================================
  // REGISTRO
  // =========================================================

  Future<UserCredential> registrar({
    required String nombre,
    required String correo,
    required String contrasena,
    required String idioma,
  }) async {
    final nombreNormalizado = nombre.trim();
    final correoNormalizado = correo.trim().toLowerCase();

    final credencial = await _firebaseAuth.createUserWithEmailAndPassword(
      email: correoNormalizado,
      password: contrasena,
    );

    final usuario = credencial.user;

    if (usuario == null) {
      throw FirebaseAuthException(
        code: 'user-not-created',
        message: 'No fue posible obtener el usuario creado.',
      );
    }

    if (nombreNormalizado.isNotEmpty) {
      await usuario.updateDisplayName(nombreNormalizado);

      await usuario.reload();
    }

    // Antes de acceder a PostgreSQL/Supabase,
    // aseguramos role=authenticated.
    await _asegurarRoleSupabase(usuario);

    await _perfilService.crearPerfilInicial(
      uid: usuario.uid,
      nombre: nombreNormalizado,
      correoPrincipal: correoNormalizado,
      idioma: idioma,
    );

    await ThemeService.instance.loadCurrentUserPreferences(
      forceRefresh: true,
    );

    await TranslationService.instance.loadCurrentUserPreferences(
      forceRefresh: false,
    );

    await TimeFormatService.instance.loadCurrentUserPreferences(
      forceRefresh: false,
    );

    return credencial;
  }

  // =========================================================
  // INICIAR SESIÓN
  // =========================================================

  Future<UserCredential> iniciarSesion({
    required String correo,
    required String contrasena,
  }) async {
    final correoNormalizado = correo.trim().toLowerCase();

    final UserCredential credencial = await _firebaseAuth
        .signInWithEmailAndPassword(
          email: correoNormalizado,
          password: contrasena,
        );

    final usuario = credencial.user;

    if (usuario == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No fue posible obtener el usuario autenticado.',
      );
    }

    // También lo comprobamos al iniciar sesión.
    // Esto recupera automáticamente cuentas antiguas
    // o registros interrumpidos.
    await _asegurarRoleSupabase(usuario);

    await ThemeService.instance.loadCurrentUserPreferences(
      forceRefresh: true,
    );

    await TranslationService.instance.loadCurrentUserPreferences(
      forceRefresh: false,
    );

    await TimeFormatService.instance.loadCurrentUserPreferences(
      forceRefresh: false,
    );

    return credencial;
  }

  // =========================================================
  // CERRAR SESIÓN
  // =========================================================

  Future<void> cerrarSesion() async {
    await _firebaseAuth.signOut();

    ThemeService.instance.resetForSignedOutUser();

    TranslationService.instance.resetForSignedOutUser();

    await TimeFormatService.instance.resetForSignedOutUser();
  }

  // =========================================================
  // RECUPERAR CONTRASEÑA
  // =========================================================

  Future<void> recuperarContrasena({
    required String correo,
  }) async {
    final correoNormalizado = correo.trim().toLowerCase();

    if (correoNormalizado.isEmpty) {
      throw ArgumentError(
        'Debe ingresar un correo electrónico.',
      );
    }

    await _firebaseAuth.sendPasswordResetEmail(
      email: correoNormalizado,
    );
  }
}