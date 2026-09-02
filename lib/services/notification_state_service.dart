import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/notificacion_app.dart';

class EstadoNotificacionApp {
  const EstadoNotificacionApp({
    required this.id,
    required this.leida,
    required this.ocultada,
    this.actualizadaEn,
  });

  final String id;
  final bool leida;
  final bool ocultada;
  final DateTime? actualizadaEn;

  factory EstadoNotificacionApp.fromMap(String id, Map<String, dynamic> data) {
    return EstadoNotificacionApp(
      id: id,
      leida: data['leida'] as bool? ?? false,
      ocultada: data['ocultada'] as bool? ?? false,
      actualizadaEn: (data['actualizadaEn'] as Timestamp?)?.toDate(),
    );
  }
}

class NotificationStateService {
  NotificationStateService._();

  static final NotificationStateService instance = NotificationStateService._();

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
        .collection('estadoNotificaciones');
  }

  Future<Map<String, EstadoNotificacionApp>> obtenerEstados() async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _collection
        .get();

    return {
      for (final doc in snapshot.docs)
        doc.id: EstadoNotificacionApp.fromMap(doc.id, doc.data()),
    };
  }

  List<NotificacionApp> aplicarEstados({
    required List<NotificacionApp> notificaciones,
    required Map<String, EstadoNotificacionApp> estados,
    bool incluirOcultadas = false,
  }) {
    final List<NotificacionApp> resultado = [];

    for (final NotificacionApp notificacion in notificaciones) {
      final EstadoNotificacionApp? estado = estados[notificacion.id];

      final NotificacionApp actualizada = notificacion.copyWith(
        leida: estado?.leida ?? false,
        ocultada: estado?.ocultada ?? false,
      );

      if (!incluirOcultadas && actualizada.ocultada) {
        continue;
      }

      resultado.add(actualizada);
    }

    return resultado;
  }

  Future<void> marcarLeida({
    required String notificationId,
    required bool leida,
  }) async {
    await _collection.doc(notificationId).set({
      'leida': leida,
      'actualizadaEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> alternarLeida(NotificacionApp notificacion) async {
    await marcarLeida(
      notificationId: notificacion.id,
      leida: !notificacion.leida,
    );
  }

  Future<void> marcarTodasComoLeidas(Iterable<String> notificationIds) async {
    final List<String> ids = notificationIds
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList();

    if (ids.isEmpty) {
      return;
    }

    // Firestore permite hasta 500 operaciones por batch.
    // Dejamos margen por seguridad.
    const int tamanoLote = 450;

    for (int inicio = 0; inicio < ids.length; inicio += tamanoLote) {
      final int fin = (inicio + tamanoLote < ids.length)
          ? inicio + tamanoLote
          : ids.length;

      final WriteBatch batch = _firestore.batch();

      for (final String id in ids.sublist(inicio, fin)) {
        batch.set(_collection.doc(id), {
          'leida': true,
          'actualizadaEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await batch.commit();
    }
  }

  Future<void> ocultar(String notificationId) async {
    await _collection.doc(notificationId).set({
      'ocultada': true,
      'actualizadaEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> restaurar(String notificationId) async {
    await _collection.doc(notificationId).set({
      'ocultada': false,
      'actualizadaEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> eliminarEstado(String notificationId) async {
    await _collection.doc(notificationId).delete();
  }
}
