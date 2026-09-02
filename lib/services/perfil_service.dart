import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/perfil_usuario.dart';

class PerfilService {
  PerfilService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  // =========================================================
  // CREAR PERFIL INICIAL
  // =========================================================

  Future<void> crearPerfilInicial({
    required String uid,
    required String nombre,
    required String correoPrincipal,
    required String idioma,
  }) async {
    final DocumentReference<Map<String, dynamic>> referencia = _firestore
        .collection('usuarios')
        .doc(uid);

    await referencia.set({
      'uid': uid,

      'nombre': nombre.trim(),

      'correoPrincipal': correoPrincipal.trim().toLowerCase(),

      'correoInstitucional': '',

      'nivelEducativo': '',

      'nombreEstablecimiento': '',

      'tipoEstablecimiento': '',

      'cursoActual': '',

      'carrera': '',

      'semestreActual': null,

      'anioIngreso': null,

      'sede': '',

      'jornada': '',

      'estadoAcademico': '',

      'idioma': idioma == 'en' ? 'en' : 'es',

      'perfilCompleto': false,

      'fechaCreacion': FieldValue.serverTimestamp(),

      'fechaActualizacion': FieldValue.serverTimestamp(),
    });
  }

  // =========================================================
  // OBTENER PERFIL
  // =========================================================

  Future<PerfilUsuario?> obtenerPerfil(String uid) async {
    final DocumentReference<Map<String, dynamic>> referencia = _firestore
        .collection('usuarios')
        .doc(uid);

    final DocumentSnapshot<Map<String, dynamic>> resultado = await referencia
        .get();

    if (!resultado.exists) {
      return null;
    }

    final Map<String, dynamic>? data = resultado.data();

    if (data == null) {
      return null;
    }

    return PerfilUsuario.fromMap(data, uidFallback: resultado.id);
  }

  // =========================================================
  // ACTUALIZAR PERFIL
  // =========================================================

  Future<void> actualizarPerfil(
    String uid,
    ActualizarPerfilUsuario datos,
  ) async {
    final DocumentReference<Map<String, dynamic>> referencia = _firestore
        .collection('usuarios')
        .doc(uid);

    final String nombre = datos.nombre.trim();

    final String correoInstitucional = datos.correoInstitucional
        .trim()
        .toLowerCase();

    final String nombreEstablecimiento = datos.nombreEstablecimiento.trim();

    final String tipoEstablecimiento = datos.tipoEstablecimiento.trim();

    final String cursoActual = datos.cursoActual.trim();

    final String carrera = datos.carrera.trim();

    final String sede = datos.sede.trim();

    final String jornada = datos.jornada.trim();

    final String estadoAcademico = datos.estadoAcademico.trim();

    final bool perfilCompleto = _comprobarPerfilCompleto(
      nombre: nombre,
      nivelEducativo: datos.nivelEducativo,
      nombreEstablecimiento: nombreEstablecimiento,
      cursoActual: cursoActual,
      carrera: carrera,
      semestreActual: datos.semestreActual,
      anioIngreso: datos.anioIngreso,
    );

    await referencia.update({
      'nombre': nombre,

      'correoInstitucional': correoInstitucional,

      'nivelEducativo': datos.nivelEducativo.valorFirestore,

      'nombreEstablecimiento': nombreEstablecimiento,

      'tipoEstablecimiento': tipoEstablecimiento,

      'cursoActual': cursoActual,

      'carrera': carrera,

      'semestreActual': datos.semestreActual,

      'anioIngreso': datos.anioIngreso,

      'sede': sede,

      'jornada': jornada,

      'estadoAcademico': estadoAcademico,

      'idioma': datos.idioma == 'en' ? 'en' : 'es',

      'perfilCompleto': perfilCompleto,

      'fechaActualizacion': FieldValue.serverTimestamp(),
    });
  }

  // =========================================================
  // COMPROBAR PERFIL COMPLETO
  // =========================================================

  bool _comprobarPerfilCompleto({
    required String nombre,
    required NivelEducativoPerfil nivelEducativo,
    required String nombreEstablecimiento,
    required String cursoActual,
    required String carrera,
    required int? semestreActual,
    required int? anioIngreso,
  }) {
    final bool datosBaseCompletos =
        nombre.trim().isNotEmpty &&
        nivelEducativo != NivelEducativoPerfil.vacio &&
        nombreEstablecimiento.trim().isNotEmpty &&
        anioIngreso != null &&
        anioIngreso > 0;

    if (!datosBaseCompletos) {
      return false;
    }

    if (nivelEducativo == NivelEducativoPerfil.basica ||
        nivelEducativo == NivelEducativoPerfil.media) {
      return cursoActual.trim().isNotEmpty;
    }

    if (nivelEducativo == NivelEducativoPerfil.superior ||
        nivelEducativo == NivelEducativoPerfil.tecnico) {
      return carrera.trim().isNotEmpty && semestreActual != null;
    }

    if (nivelEducativo == NivelEducativoPerfil.curso ||
        nivelEducativo == NivelEducativoPerfil.otro) {
      return cursoActual.trim().isNotEmpty;
    }

    return false;
  }
}
