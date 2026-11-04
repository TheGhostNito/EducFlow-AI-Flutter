import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

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
      actualizadaEn: DateTime.tryParse(
        data['actualizada_en']?.toString() ?? '',
      ),
    );
  }
}

abstract interface class NotificationStateDataSource {
  Future<List<Map<String, dynamic>>> getAll(String uid);
  Future<void> insertIfMissing(String uid, Iterable<String> ids);
  Future<void> update(
    String uid,
    Iterable<String> ids,
    Map<String, dynamic> fields,
  );
  Future<void> delete(String uid, String id);
}

class SupabaseNotificationStateDataSource
    implements NotificationStateDataSource {
  SupabaseNotificationStateDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> getAll(String uid) async {
    final rows = await _client
        .from('estado_notificaciones')
        .select('notificacion_id,leida,ocultada,actualizada_en')
        .eq('usuario_uid', uid);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  @override
  Future<void> insertIfMissing(String uid, Iterable<String> ids) async {
    await _client
        .from('estado_notificaciones')
        .upsert(
          [
            for (final id in ids) {'usuario_uid': uid, 'notificacion_id': id},
          ],
          onConflict: 'usuario_uid,notificacion_id',
          ignoreDuplicates: true,
        );
  }

  @override
  Future<void> update(
    String uid,
    Iterable<String> ids,
    Map<String, dynamic> fields,
  ) async {
    await _client
        .from('estado_notificaciones')
        .update(fields)
        .eq('usuario_uid', uid)
        .inFilter('notificacion_id', ids.toList());
  }

  @override
  Future<void> delete(String uid, String id) async {
    await _client
        .from('estado_notificaciones')
        .delete()
        .eq('usuario_uid', uid)
        .eq('notificacion_id', id);
  }
}

class NotificationStateService extends ChangeNotifier {
  NotificationStateService({
    NotificationStateDataSource? dataSource,
    this._uidProvider,
  }) : _dataSourceOverride = dataSource,
       super();

  static final NotificationStateService instance = NotificationStateService();

  final NotificationStateDataSource? _dataSourceOverride;
  final String? Function()? _uidProvider;
  NotificationStateDataSource get _dataSource =>
      _dataSourceOverride ??
      SupabaseNotificationStateDataSource(Supabase.instance.client);

  String get _uid {
    final uid = _uidProvider?.call() ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('No hay un usuario autenticado.');
    return uid;
  }

  Future<Map<String, EstadoNotificacionApp>> obtenerEstados() async {
    final uid = _uid;
    final rows = await _dataSource.getAll(uid);
    if (_uid != uid) throw StateError('La sesión cambió.');
    return {
      for (final row in rows)
        row['notificacion_id'] as String: EstadoNotificacionApp.fromMap(
          row['notificacion_id'] as String,
          row,
        ),
    };
  }

  List<NotificacionApp> aplicarEstados({
    required List<NotificacionApp> notificaciones,
    required Map<String, EstadoNotificacionApp> estados,
    bool incluirOcultadas = false,
  }) {
    final resultado = <NotificacionApp>[];
    for (final notificacion in notificaciones) {
      final estado = estados[notificacion.id];
      final actualizada = notificacion.copyWith(
        leida: estado?.leida ?? false,
        ocultada: estado?.ocultada ?? false,
      );
      if (!incluirOcultadas && actualizada.ocultada) continue;
      resultado.add(actualizada);
    }
    return resultado;
  }

  Future<void> marcarLeida({
    required String notificationId,
    required bool leida,
  }) => _update([notificationId], {'leida': leida});

  Future<void> alternarLeida(NotificacionApp notificacion) =>
      marcarLeida(notificationId: notificacion.id, leida: !notificacion.leida);

  Future<void> marcarTodasComoLeidas(Iterable<String> notificationIds) async {
    final ids = notificationIds
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList();
    final uid = _uid;
    for (var start = 0; start < ids.length; start += 450) {
      if (_uid != uid) throw StateError('La sesión cambió.');
      final end = start + 450 < ids.length ? start + 450 : ids.length;
      await _update(ids.sublist(start, end), {'leida': true}, expectedUid: uid);
    }
  }

  Future<void> ocultar(String notificationId) =>
      _update([notificationId], {'ocultada': true});

  Future<void> restaurar(String notificationId) =>
      _update([notificationId], {'ocultada': false});

  Future<void> eliminarEstado(String notificationId) async {
    final uid = _uid;
    await _dataSource.delete(uid, notificationId);
    if (_uid == uid) notifyListeners();
  }

  Future<void> _update(
    List<String> ids,
    Map<String, dynamic> fields, {
    String? expectedUid,
  }) async {
    if (ids.isEmpty || ids.any((id) => id.trim().isEmpty)) return;
    final uid = _uid;
    if (expectedUid != null && uid != expectedUid) {
      throw StateError('La sesión cambió.');
    }
    await _dataSource.insertIfMissing(uid, ids);
    if (_uid != uid) throw StateError('La sesión cambió.');
    await _dataSource.update(uid, ids, {
      ...fields,
      'actualizada_en': DateTime.now().toUtc().toIso8601String(),
    });
    if (_uid == uid) notifyListeners();
  }
}
