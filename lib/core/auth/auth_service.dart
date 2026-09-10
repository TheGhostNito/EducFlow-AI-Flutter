import 'package:firebase_auth/firebase_auth.dart';

import 'session_controller.dart';

class AuthService {
  AuthService({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  User? get usuarioActual => _firebaseAuth.currentUser;

  bool get estaAutenticado => usuarioActual != null;

  Stream<User?> get usuarioStream => _firebaseAuth.authStateChanges();

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

    if (credencial.user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No fue posible obtener el usuario autenticado.',
      );
    }

    return credencial;
  }

  // =========================================================
  // CERRAR SESIÓN
  // =========================================================

  Future<void> cerrarSesion() async {
    await SessionController.instance.signOut();
  }

  // =========================================================
  // RECUPERAR CONTRASEÑA
  // =========================================================

  Future<void> recuperarContrasena({required String correo}) async {
    final correoNormalizado = correo.trim().toLowerCase();

    if (correoNormalizado.isEmpty) {
      throw ArgumentError('Debe ingresar un correo electrónico.');
    }

    await _firebaseAuth.sendPasswordResetEmail(email: correoNormalizado);
  }
}
