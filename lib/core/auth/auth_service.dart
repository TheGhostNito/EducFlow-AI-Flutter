import 'package:firebase_auth/firebase_auth.dart';

import '../../services/perfil_service.dart';

import '../../services/theme_service.dart';
import '../../services/translation_service.dart';
import '../../services/time_format_service.dart';

class AuthService {
  AuthService({FirebaseAuth? firebaseAuth, PerfilService? perfilService})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
      _perfilService = perfilService ?? PerfilService();

  final FirebaseAuth _firebaseAuth;
  final PerfilService _perfilService;

  User? get usuarioActual => _firebaseAuth.currentUser;

  bool get estaAutenticado => usuarioActual != null;

  Stream<User?> get usuarioStream => _firebaseAuth.authStateChanges();

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

    await _perfilService.crearPerfilInicial(
      uid: usuario.uid,
      nombre: nombreNormalizado,
      correoPrincipal: correoNormalizado,
      idioma: idioma,
    );

    await ThemeService.instance.loadCurrentUserPreferences(forceRefresh: true);

    await TranslationService.instance.loadCurrentUserPreferences(
      forceRefresh: false,
    );

    await TimeFormatService.instance.loadCurrentUserPreferences(
      forceRefresh: false,
    );

    return credencial;
  }

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

    await ThemeService.instance.loadCurrentUserPreferences(forceRefresh: true);

    await TranslationService.instance.loadCurrentUserPreferences(
      forceRefresh: false,
    );

    await TimeFormatService.instance.loadCurrentUserPreferences(
      forceRefresh: false,
    );

    return credencial;
  }

  Future<void> cerrarSesion() async {
    await _firebaseAuth.signOut();

    ThemeService.instance.resetForSignedOutUser();

    TranslationService.instance.resetForSignedOutUser();

    await TimeFormatService.instance.resetForSignedOutUser();
  }

  Future<void> recuperarContrasena({required String correo}) async {
    final correoNormalizado = correo.trim().toLowerCase();

    if (correoNormalizado.isEmpty) {
      throw ArgumentError('Debe ingresar un correo electrónico.');
    }

    await _firebaseAuth.sendPasswordResetEmail(email: correoNormalizado);
  }
}
