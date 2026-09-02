import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/tarea.dart';

class TareasService {
  TareasService._();

  static final TareasService instance = TareasService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  int _versionDatos = 0;

  int get versionDatos => _versionDatos;

  // =========================================================
  // USUARIO
  // =========================================================

  String _uidActual() {
    final User? usuario = _auth.currentUser;

    if (usuario == null) {
      throw StateError('No existe un usuario autenticado.');
    }

    return usuario.uid;
  }

  // =========================================================
  // COLECCIÓN DEL USUARIO
  // =========================================================

  CollectionReference<Map<String, dynamic>> _coleccion() {
    final String uid = _uidActual();

    return _firestore.collection('usuarios').doc(uid).collection('tareas');
  }

  // =========================================================
  // OBTENER TODAS
  // =========================================================

  Future<List<Tarea>> obtenerTodas() async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _coleccion()
        .get();

    final List<Tarea> tareas = snapshot.docs
        .map(
          (documento) =>
              Tarea.fromMap(id: documento.id, data: documento.data()),
        )
        .toList();

    tareas.sort(_compararTareas);

    return tareas;
  }

  // =========================================================
  // OBTENER POR ID
  // =========================================================

  Future<Tarea?> obtenerPorId(String id) async {
    final String cleanId = id.trim();

    if (cleanId.isEmpty) {
      return null;
    }

    final DocumentSnapshot<Map<String, dynamic>> snapshot = await _coleccion()
        .doc(cleanId)
        .get();

    final Map<String, dynamic>? data = snapshot.data();

    if (!snapshot.exists || data == null) {
      return null;
    }

    return Tarea.fromMap(id: snapshot.id, data: data);
  }

  // =========================================================
  // CREAR
  // =========================================================

  Future<Tarea> crear({
    required String titulo,
    String? descripcion,
    String? asignaturaId,
    PrioridadTarea prioridad = PrioridadTarea.media,
    DateTime? fechaEntrega,
    String? horaEntrega,
  }) async {
    final String tituloLimpio = titulo.trim();

    if (tituloLimpio.isEmpty) {
      throw ArgumentError('El título de la tarea es obligatorio.');
    }

    final DocumentReference<Map<String, dynamic>> documento = _coleccion()
        .doc();

    final DateTime ahora = DateTime.now();

    final Tarea tarea = Tarea(
      id: documento.id,
      titulo: tituloLimpio,
      descripcion: _limpiarNullable(descripcion),
      asignaturaId: _limpiarNullable(asignaturaId),
      prioridad: prioridad,
      estado: EstadoTarea.pendiente,
      fechaEntrega: fechaEntrega,
      horaEntrega: _normalizarHoraNullable(horaEntrega),
      creadaEn: ahora,
      actualizadaEn: ahora,
    );

    await documento.set(tarea.toMap());

    _versionDatos++;

    return tarea;
  }

  // =========================================================
  // ACTUALIZAR
  // =========================================================

  Future<Tarea> actualizar(Tarea tarea) async {
    final String tituloLimpio = tarea.titulo.trim();

    if (tituloLimpio.isEmpty) {
      throw ArgumentError('El título de la tarea es obligatorio.');
    }

    final Tarea actualizada = tarea.copyWith(
      titulo: tituloLimpio,
      descripcion: _limpiarNullable(tarea.descripcion),
      asignaturaId: _limpiarNullable(tarea.asignaturaId),
      horaEntrega: _normalizarHoraNullable(tarea.horaEntrega),
      actualizadaEn: DateTime.now(),
    );

    await _coleccion()
        .doc(actualizada.id)
        .set(actualizada.toMap(), SetOptions(merge: true));

    _versionDatos++;

    return actualizada;
  }

  // =========================================================
  // COMPLETAR / REABRIR
  // =========================================================

  Future<Tarea> cambiarEstado({
    required Tarea tarea,
    required bool completada,
  }) async {
    final DateTime ahora = DateTime.now();

    final Tarea actualizada = tarea.copyWith(
      estado: completada ? EstadoTarea.completada : EstadoTarea.pendiente,
      completadaEn: completada ? ahora : null,
      limpiarCompletadaEn: !completada,
      actualizadaEn: ahora,
    );

    await _coleccion()
        .doc(actualizada.id)
        .set(actualizada.toMap(), SetOptions(merge: true));

    _versionDatos++;

    return actualizada;
  }

  // =========================================================
  // ELIMINAR
  // =========================================================

  Future<void> eliminar(String id) async {
    final String cleanId = id.trim();

    if (cleanId.isEmpty) {
      return;
    }

    await _coleccion().doc(cleanId).delete();

    _versionDatos++;
  }

  // =========================================================
  // ORDEN
  // =========================================================

  int _compararTareas(Tarea a, Tarea b) {
    // Pendientes primero.
    if (a.estado != b.estado) {
      return a.pendiente ? -1 : 1;
    }

    // Las tareas con fecha aparecen antes
    // que las que no tienen fecha.
    if (a.fechaEntrega == null && b.fechaEntrega != null) {
      return 1;
    }

    if (a.fechaEntrega != null && b.fechaEntrega == null) {
      return -1;
    }

    if (a.fechaEntrega != null && b.fechaEntrega != null) {
      final int fecha = a.fechaEntrega!.compareTo(b.fechaEntrega!);

      if (fecha != 0) {
        return fecha;
      }

      final int hora = _minutosHora(a.horaEntrega)
          .compareTo(_minutosHora(b.horaEntrega));

      if (hora != 0) {
        return hora;
      }
    }

    // Finalmente, las más recientes primero.
    return b.creadaEn.compareTo(a.creadaEn);
  }

  int _minutosHora(String? value) {
    final String hora = value?.trim() ?? '';

    if (hora.isEmpty) {
      // Una tarea con fecha pero sin hora
      // queda después de las que sí tienen
      // una hora concreta ese mismo día.
      return 24 * 60;
    }

    final List<String> partes = hora.split(':');

    if (partes.length != 2) {
      return 24 * 60;
    }

    final int? horas = int.tryParse(partes[0]);

    final int? minutos = int.tryParse(partes[1]);

    if (horas == null ||
        minutos == null ||
        horas < 0 ||
        horas > 23 ||
        minutos < 0 ||
        minutos > 59) {
      return 24 * 60;
    }

    return (horas * 60) + minutos;
  }

  // =========================================================
  // HELPERS
  // =========================================================

  String? _limpiarNullable(String? value) {
    final String clean = value?.trim() ?? '';

    return clean.isEmpty ? null : clean;
  }

  String? _normalizarHoraNullable(String? value) {
    final String clean = value?.trim() ?? '';

    if (clean.isEmpty) {
      return null;
    }

    final List<String> partes = clean.split(':');

    if (partes.length != 2) {
      throw ArgumentError('La hora debe utilizar el formato HH:mm.');
    }

    final int? horas = int.tryParse(partes[0]);

    final int? minutos = int.tryParse(partes[1]);

    if (horas == null ||
        minutos == null ||
        horas < 0 ||
        horas > 23 ||
        minutos < 0 ||
        minutos > 59) {
      throw ArgumentError('La hora indicada no es válida.');
    }

    return '${horas.toString().padLeft(2, '0')}:'
        '${minutos.toString().padLeft(2, '0')}';
  }
}
