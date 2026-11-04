import 'package:eduflow_ai/services/notification_state_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? uid = 'user-a';
  late _FakeNotificationStateDataSource dataSource;
  late NotificationStateService service;

  setUp(() {
    uid = 'user-a';
    dataSource = _FakeNotificationStateDataSource();
    service = NotificationStateService(
      dataSource: dataSource,
      uidProvider: () => uid,
    );
  });

  test('leer, ocultar y marcar leída conserva los otros campos', () async {
    await service.ocultar('tarea-1');
    await service.marcarLeida(notificationId: 'tarea-1', leida: true);
    final states = await service.obtenerEstados();
    expect(states['tarea-1']?.ocultada, isTrue);
    expect(states['tarea-1']?.leida, isTrue);

    await service.restaurar('tarea-1');
    expect((await service.obtenerEstados())['tarea-1']?.leida, isTrue);
    expect((await service.obtenerEstados())['tarea-1']?.ocultada, isFalse);
  });

  test('marca un lote sin duplicados y mantiene aislamiento por UID', () async {
    await service.marcarTodasComoLeidas(['tarea-1', 'tarea-2', 'tarea-1']);
    expect((await service.obtenerEstados()).length, 2);
    uid = 'user-b';
    expect(await service.obtenerEstados(), isEmpty);
    await service.marcarLeida(notificationId: 'tarea-1', leida: false);
    expect((await service.obtenerEstados())['tarea-1']?.leida, isFalse);
    uid = 'user-a';
    expect((await service.obtenerEstados())['tarea-1']?.leida, isTrue);
  });

  test('elimina solo el estado del UID actual', () async {
    await service.ocultar('tarea-1');
    uid = 'user-b';
    await service.ocultar('tarea-1');
    await service.eliminarEstado('tarea-1');
    expect(await service.obtenerEstados(), isEmpty);
    uid = 'user-a';
    expect((await service.obtenerEstados())['tarea-1']?.ocultada, isTrue);
  });
}

class _FakeNotificationStateDataSource implements NotificationStateDataSource {
  final rows = <String, Map<String, dynamic>>{};
  String key(String uid, String id) => '$uid/$id';

  @override
  Future<List<Map<String, dynamic>>> getAll(String uid) async => rows.entries
      .where((entry) => entry.key.startsWith('$uid/'))
      .map((entry) => Map<String, dynamic>.from(entry.value))
      .toList();

  @override
  Future<void> insertIfMissing(String uid, Iterable<String> ids) async {
    for (final id in ids) {
      rows.putIfAbsent(
        key(uid, id),
        () => {
          'usuario_uid': uid,
          'notificacion_id': id,
          'leida': false,
          'ocultada': false,
        },
      );
    }
  }

  @override
  Future<void> update(
    String uid,
    Iterable<String> ids,
    Map<String, dynamic> fields,
  ) async {
    for (final id in ids) {
      rows[key(uid, id)]?.addAll(fields);
    }
  }

  @override
  Future<void> delete(String uid, String id) async {
    rows.remove(key(uid, id));
  }
}
