import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/evaluacion.dart';

class EvaluacionesService {
  EvaluacionesService._();

  static final EvaluacionesService instance = EvaluacionesService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid {
    final User? user = _auth.currentUser;

    if (user == null) {
      throw StateError('No hay un usuario autenticado.');
    }

    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _collection {
    return _firestore
        .collection('usuarios')
        .doc(_uid)
        .collection('evaluaciones');
  }

  Future<List<Evaluacion>> obtenerTodas() async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _collection
        .get();

    final List<Evaluacion> evaluaciones = snapshot.docs
        .map((doc) => Evaluacion.fromMap(doc.id, doc.data()))
        .toList();

    evaluaciones.sort((a, b) {
      final int fecha = a.fecha.compareTo(b.fecha);

      if (fecha != 0) {
        return fecha;
      }

      final String horaA = a.hora?.trim().isNotEmpty == true
          ? a.hora!
          : '99:99';

      final String horaB = b.hora?.trim().isNotEmpty == true
          ? b.hora!
          : '99:99';

      return horaA.compareTo(horaB);
    });

    return evaluaciones;
  }

  Future<Evaluacion?> obtenerPorId(String id) async {
    final DocumentSnapshot<Map<String, dynamic>> doc = await _collection
        .doc(id)
        .get();

    if (!doc.exists || doc.data() == null) {
      return null;
    }

    return Evaluacion.fromMap(doc.id, doc.data()!);
  }

  Future<Evaluacion> crear({
    required String titulo,
    required String asignaturaId,
    required DateTime fecha,
    TipoEvaluacion tipo = TipoEvaluacion.prueba,
    String? descripcion,
    String? hora,
    double? ponderacion,
  }) async {
    final String tituloLimpio = titulo.trim();

    final String asignaturaLimpia = asignaturaId.trim();

    if (tituloLimpio.isEmpty) {
      throw ArgumentError('El título es obligatorio.');
    }

    if (asignaturaLimpia.isEmpty) {
      throw ArgumentError('La asignatura es obligatoria.');
    }

    _validarHora(hora);
    _validarPonderacion(ponderacion);

    final DateTime ahora = DateTime.now();

    final DocumentReference<Map<String, dynamic>> ref = _collection.doc();

    final Evaluacion evaluacion = Evaluacion(
      id: ref.id,
      titulo: tituloLimpio,
      asignaturaId: asignaturaLimpia,
      tipo: tipo,
      fecha: DateTime(fecha.year, fecha.month, fecha.day),
      hora: _limpiarOpcional(hora),
      descripcion: _limpiarOpcional(descripcion),
      ponderacion: ponderacion,
      creadaEn: ahora,
      actualizadaEn: ahora,
    );

    await ref.set(evaluacion.toMap());

    return evaluacion;
  }

  Future<void> actualizar(Evaluacion evaluacion) async {
    final String titulo = evaluacion.titulo.trim();

    final String asignatura = evaluacion.asignaturaId.trim();

    if (titulo.isEmpty || asignatura.isEmpty) {
      throw ArgumentError('Título y asignatura son obligatorios.');
    }

    _validarHora(evaluacion.hora);

    _validarPonderacion(evaluacion.ponderacion);

    final Evaluacion actualizada = evaluacion.copyWith(
      titulo: titulo,
      asignaturaId: asignatura,
      actualizadaEn: DateTime.now(),
    );

    await _collection
        .doc(evaluacion.id)
        .set(actualizada.toMap(), SetOptions(merge: true));
  }

  Future<void> eliminar(String id) async {
    await _collection.doc(id).delete();
  }

  String? _limpiarOpcional(String? value) {
    final String limpio = value?.trim() ?? '';

    return limpio.isEmpty ? null : limpio;
  }

  void _validarHora(String? value) {
    final String hora = value?.trim() ?? '';

    if (hora.isEmpty) {
      return;
    }

    final RegExp pattern = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$');

    if (!pattern.hasMatch(hora)) {
      throw ArgumentError('La hora debe estar en formato HH:mm.');
    }
  }

  void _validarPonderacion(double? value) {
    if (value == null) {
      return;
    }

    if (value < 0 || value > 100) {
      throw ArgumentError('La ponderación debe estar entre 0 y 100.');
    }
  }
}
