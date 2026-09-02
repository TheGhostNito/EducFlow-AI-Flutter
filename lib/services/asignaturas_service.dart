import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/asignatura.dart';

class AsignaturasService {
  AsignaturasService._()
    : _firestore = FirebaseFirestore.instance,
      _auth = FirebaseAuth.instance;

  static final AsignaturasService instance = AsignaturasService._();

  final FirebaseFirestore _firestore;

  final FirebaseAuth _auth;

  int _versionInterna = 0;

  int get versionDatos => _versionInterna;

  // =========================================================
  // OBTENER TODAS
  // =========================================================

  Future<List<Asignatura>> obtenerTodas() async {
    final String uid = _obtenerUidUsuario();

    final QuerySnapshot<Map<String, dynamic>> resultado = await _firestore
        .collection('usuarios')
        .doc(uid)
        .collection('asignaturas')
        .get();

    final List<Asignatura> asignaturas = resultado.docs.map((documento) {
      return Asignatura.fromMap(id: documento.id, data: documento.data());
    }).toList();

    asignaturas.sort((a, b) {
      final String nombreA = _normalizarParaOrden(a.nombre);

      final String nombreB = _normalizarParaOrden(b.nombre);

      return nombreA.compareTo(nombreB);
    });

    return asignaturas;
  }

  // =========================================================
  // OBTENER POR ID
  // =========================================================

  Future<Asignatura?> obtenerPorId(String id) async {
    final String uid = _obtenerUidUsuario();

    final DocumentSnapshot<Map<String, dynamic>> resultado = await _firestore
        .collection('usuarios')
        .doc(uid)
        .collection('asignaturas')
        .doc(id)
        .get();

    if (!resultado.exists) {
      return null;
    }

    final Map<String, dynamic>? data = resultado.data();

    if (data == null) {
      return null;
    }

    return Asignatura.fromMap(id: resultado.id, data: data);
  }

  // =========================================================
  // AGREGAR
  // =========================================================

  Future<void> agregar(Asignatura asignatura) async {
    final String uid = _obtenerUidUsuario();

    final DocumentReference<Map<String, dynamic>> referencia = _firestore
        .collection('usuarios')
        .doc(uid)
        .collection('asignaturas')
        .doc(asignatura.id);

    await referencia.set({
      ...asignatura.toMap(),

      'fechaCreacion': FieldValue.serverTimestamp(),

      'fechaActualizacion': FieldValue.serverTimestamp(),
    });

    _marcarComoActualizado();
  }

  // =========================================================
  // ACTUALIZAR
  // =========================================================

  Future<void> actualizar(Asignatura asignatura) async {
    final String uid = _obtenerUidUsuario();

    final DocumentReference<Map<String, dynamic>> referencia = _firestore
        .collection('usuarios')
        .doc(uid)
        .collection('asignaturas')
        .doc(asignatura.id);

    final Map<String, dynamic> datos = asignatura.toMap();

    // Igual que en Ionic, durante una
    // actualización no modificamos
    // fechaCreacion.
    datos.remove('id');

    await referencia.update({
      ...datos,

      'fechaActualizacion': FieldValue.serverTimestamp(),
    });

    _marcarComoActualizado();
  }

  // =========================================================
  // ELIMINAR
  // =========================================================

  Future<void> eliminar(String id) async {
    final String uid = _obtenerUidUsuario();

    await _firestore
        .collection('usuarios')
        .doc(uid)
        .collection('asignaturas')
        .doc(id)
        .delete();

    _marcarComoActualizado();
  }

  // =========================================================
  // VERSIONADO
  // =========================================================

  void _marcarComoActualizado() {
    _versionInterna++;
  }

  // =========================================================
  // USUARIO ACTUAL
  // =========================================================

  String _obtenerUidUsuario() {
    final User? usuario = _auth.currentUser;

    if (usuario == null) {
      throw StateError('No existe un usuario autenticado.');
    }

    return usuario.uid;
  }

  // =========================================================
  // ORDEN ALFABÉTICO
  // =========================================================

  String _normalizarParaOrden(String texto) {
    return texto
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u');
  }
}
