import 'dart:async';

import 'package:eduflow_ai/models/tarea.dart';
import 'package:eduflow_ai/services/tareas_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = TareasSqlCodec();

  group('TareasSqlCodec', () {
    test('convierte una fila SQL pendiente y normaliza fecha y hora', () {
      final tarea = codec.desdeFila(
        _filaSql(hora: '08:30:00.000000'),
      );

      expect(tarea.id, 'tarea-1');
      expect(tarea.asignaturaId, 'asig-1');
      expect(tarea.fechaEntrega, DateTime(2026, 10, 15));
      expect(tarea.horaEntrega, '08:30');
      expect(tarea.prioridad, PrioridadTarea.alta);
      expect(tarea.estado, EstadoTarea.pendiente);
      expect(tarea.completadaEn, isNull);
      expect(tarea.creadaEn.isUtc, isFalse);
      expect(tarea.actualizadaEn.isUtc, isFalse);
    });

    test('convierte una tarea completada con timestamp local', () {
      final tarea = codec.desdeFila(
        _filaSql(
          estado: 'completada',
          completadaEn: '2026-10-16T14:30:00Z',
        ),
      );

      expect(tarea.estado, EstadoTarea.completada);
      expect(tarea.completada, isTrue);
      expect(tarea.completadaEn, isNotNull);
      expect(tarea.completadaEn!.isUtc, isFalse);
    });

    test('admite campos opcionales nulos', () {
      final tarea = codec.desdeFila(
        _filaSql(
          asignaturaId: null,
          descripcion: null,
          fecha: null,
          hora: null,
        ),
      );

      expect(tarea.asignaturaId, isNull);
      expect(tarea.descripcion, isNull);
      expect(tarea.fechaEntrega, isNull);
      expect(tarea.horaEntrega, isNull);
    });

    test('rechaza incoherencia estado pendiente y completada_en', () {
      expect(
        () => codec.desdeFila(
          _filaSql(completadaEn: '2026-10-16T14:30:00Z'),
        ),
        throwsFormatException,
      );
    });

    test('rechaza incoherencia estado completada sin completada_en', () {
      expect(
        () => codec.desdeFila(_filaSql(estado: 'completada')),
        throwsFormatException,
      );
    });

    test('genera payload snake_case sin UID ni timestamps administrados', () {
      final payload = codec.payload(
        _tarea(
          id: ' tarea-1 ',
          titulo: ' Informe ',
          estado: EstadoTarea.completada,
          completadaEn: DateTime.utc(2026, 10, 16, 14, 30),
        ),
      );

      expect(payload['id'], 'tarea-1');
      expect(payload['titulo'], 'Informe');
      expect(payload['asignatura_id'], 'asig-1');
      expect(payload['fecha_entrega'], '2026-10-15');
      expect(payload['hora_entrega'], '08:30');
      expect(payload['prioridad'], 'alta');
      expect(payload['estado'], 'completada');
      expect(payload['completada_en'], '2026-10-16T14:30:00.000Z');
      expect(payload, isNot(contains('usuario_uid')));
      expect(payload, isNot(contains('creada_en')));
      expect(payload, isNot(contains('actualizada_en')));
    });
  });

  group('TareasService', () {
    test('lee una tarea por ID usando el UID actual', () async {
      final dataSource = _FakeTareasDataSource()
        ..guardar('u1', _tarea(id: 't1', titulo: 'Informe'));
      addTearDown(dataSource.dispose);
      final service = _service(dataSource, 'u1');

      final resultado = await service.obtenerPorId('t1');

      expect(resultado?.titulo, 'Informe');
      expect(dataSource.ultimoUid, 'u1');
    });

    test('lee varias y conserva el orden funcional existente', () async {
      final dataSource = _FakeTareasDataSource()
        ..guardar(
          'u1',
          _tarea(
            id: 'completada',
            estado: EstadoTarea.completada,
            completadaEn: DateTime(2026, 10, 14),
          ),
        )
        ..guardar(
          'u1',
          _tarea(id: 'sin-hora', horaEntrega: null),
        )
        ..guardar(
          'u1',
          _tarea(id: 'temprano', horaEntrega: '07:30'),
        )
        ..guardar(
          'u1',
          _tarea(
            id: 'anterior',
            fechaEntrega: DateTime(2026, 10, 14),
          ),
        );
      addTearDown(dataSource.dispose);

      final resultado = await _service(dataSource, 'u1').obtenerTodas();

      expect(resultado.map((item) => item.id), [
        'anterior',
        'temprano',
        'sin-hora',
        'completada',
      ]);
    });

    test('crea pendiente y utiliza el ID generado por PostgreSQL', () async {
      final dataSource = _FakeTareasDataSource();
      addTearDown(dataSource.dispose);
      final service = _service(dataSource, 'u1');

      final creada = await service.crear(
        titulo: ' Informe ',
        asignaturaId: ' asig-1 ',
        prioridad: PrioridadTarea.alta,
        fechaEntrega: DateTime(2026, 10, 15, 22),
        horaEntrega: '08:30',
      );

      expect(creada.id, 'sql-1');
      expect(creada.titulo, 'Informe');
      expect(creada.asignaturaId, 'asig-1');
      expect(creada.fechaEntrega, DateTime(2026, 10, 15));
      expect(creada.estado, EstadoTarea.pendiente);
      expect(creada.completadaEn, isNull);
      expect(dataSource.ultimaOperacion, 'crear');
      expect(service.versionDatos, 1);
    });

    test('actualiza conservando ID y creadaEn', () async {
      final original = _tarea(id: 't1', titulo: 'Informe');
      final dataSource = _FakeTareasDataSource()..guardar('u1', original);
      addTearDown(dataSource.dispose);
      final service = _service(dataSource, 'u1');

      final actualizada = await service.actualizar(
        original.copyWith(titulo: 'Informe final'),
      );

      expect(actualizada.id, 't1');
      expect(actualizada.titulo, 'Informe final');
      expect(actualizada.creadaEn, original.creadaEn);
      expect(dataSource.ultimaOperacion, 'actualizar');
      expect(service.versionDatos, 1);
    });

    test('completa y reabre manteniendo la coherencia de estado', () async {
      final dataSource = _FakeTareasDataSource();
      addTearDown(dataSource.dispose);
      final service = _service(dataSource, 'u1');
      final pendiente = _tarea(id: 't1');
      dataSource.guardar('u1', pendiente);

      final completada = await service.cambiarEstado(
        tarea: pendiente,
        completada: true,
      );
      final reabierta = await service.cambiarEstado(
        tarea: completada,
        completada: false,
      );

      expect(completada.estado, EstadoTarea.completada);
      expect(completada.completadaEn, isNotNull);
      expect(reabierta.estado, EstadoTarea.pendiente);
      expect(reabierta.completadaEn, isNull);
      expect(service.versionDatos, 2);
    });

    test('elimina y limpia el estado de notificación centralmente', () async {
      final dataSource = _FakeTareasDataSource()
        ..guardar('u1', _tarea(id: 't1'));
      addTearDown(dataSource.dispose);
      final limpiadas = <String>[];
      final service = _service(
        dataSource,
        'u1',
        limpiar: (id) async => limpiadas.add(id),
      );

      await service.eliminar('t1');

      expect(await service.obtenerPorId('t1'), isNull);
      expect(limpiadas, ['tarea-t1']);
      expect(service.versionDatos, 1);
    });

    test('un fallo de limpieza Firestore no revierte la eliminación SQL', () async {
      final dataSource = _FakeTareasDataSource()
        ..guardar('u1', _tarea(id: 't1'));
      addTearDown(dataSource.dispose);
      final service = _service(
        dataSource,
        'u1',
        limpiar: (_) async => throw StateError('Firestore no disponible'),
      );

      await service.eliminar('t1');

      expect(await service.obtenerPorId('t1'), isNull);
      expect(service.versionDatos, 1);
    });

    test('propaga Realtime del usuario y actualiza versionDatos', () async {
      final dataSource = _FakeTareasDataSource();
      addTearDown(dataSource.dispose);
      final service = _service(dataSource, 'u1');
      final evento = service.observarCambios().first;

      dataSource.emitirCambio('u1');

      await evento;
      expect(service.versionDatos, 1);
    });

    test('aísla lecturas, escrituras y Realtime por UID', () async {
      final dataSource = _FakeTareasDataSource()
        ..guardar('u1', _tarea(id: 'comun', titulo: 'Versión U1'))
        ..guardar('u2', _tarea(id: 'comun', titulo: 'Versión U2'));
      addTearDown(dataSource.dispose);
      final serviceU1 = _service(dataSource, 'u1');
      final serviceU2 = _service(dataSource, 'u2');
      var eventosU1 = 0;
      final subscription = serviceU1.observarCambios().listen(
        (_) => eventosU1++,
      );
      addTearDown(subscription.cancel);

      expect((await serviceU1.obtenerPorId('comun'))?.titulo, 'Versión U1');
      expect((await serviceU2.obtenerPorId('comun'))?.titulo, 'Versión U2');

      dataSource.emitirCambio('u2');
      await Future<void>.delayed(Duration.zero);
      expect(eventosU1, 0);
    });
  });
}

TareasService _service(
  _FakeTareasDataSource dataSource,
  String uid, {
  Future<void> Function(String)? limpiar,
}) {
  return TareasService(
    dataSource: dataSource,
    uidProvider: () => uid,
    limpiarEstadoNotificacion: limpiar ?? (_) async {},
  );
}

Tarea _tarea({
  String id = 'tarea-1',
  String titulo = 'Informe',
  String? descripcion = 'Descripción',
  String? asignaturaId = 'asig-1',
  PrioridadTarea prioridad = PrioridadTarea.alta,
  EstadoTarea estado = EstadoTarea.pendiente,
  DateTime? fechaEntrega,
  String? horaEntrega = '08:30',
  DateTime? completadaEn,
}) {
  return Tarea(
    id: id,
    titulo: titulo,
    descripcion: descripcion,
    asignaturaId: asignaturaId,
    prioridad: prioridad,
    estado: estado,
    fechaEntrega: fechaEntrega ?? DateTime(2026, 10, 15),
    horaEntrega: horaEntrega,
    creadaEn: DateTime.utc(2026, 10, 1, 12),
    actualizadaEn: DateTime.utc(2026, 10, 2, 12),
    completadaEn: completadaEn,
  );
}

Map<String, dynamic> _filaSql({
  Object? descripcion = 'Descripción',
  Object? asignaturaId = 'asig-1',
  Object? fecha = '2026-10-15',
  Object? hora = '08:30:00',
  String estado = 'pendiente',
  Object? completadaEn,
}) => {
  'id': 'tarea-1',
  'titulo': 'Informe',
  'descripcion': descripcion,
  'asignatura_id': asignaturaId,
  'prioridad': 'alta',
  'estado': estado,
  'fecha_entrega': fecha,
  'hora_entrega': hora,
  'creada_en': '2026-10-01T12:00:00Z',
  'actualizada_en': '2026-10-02T12:00:00Z',
  'completada_en': completadaEn,
};

class _FakeTareasDataSource implements TareasDataSource {
  final Map<String, Map<String, Tarea>> _datos = {};
  final Map<String, StreamController<void>> _cambios = {};
  int _secuencia = 0;
  String? ultimoUid;
  String? ultimaOperacion;

  void guardar(String uid, Tarea tarea) {
    _datos.putIfAbsent(uid, () => {})[tarea.id] = tarea;
  }

  void emitirCambio(String uid) {
    _controlador(uid).add(null);
  }

  @override
  Future<List<Tarea>> obtenerTodas(String uid) async {
    ultimoUid = uid;
    return List.of(_datos[uid]?.values ?? const []);
  }

  @override
  Future<Tarea?> obtenerPorId(String uid, String id) async {
    ultimoUid = uid;
    return _datos[uid]?[id];
  }

  @override
  Future<Tarea> crear(String uid, Tarea tarea) async {
    ultimoUid = uid;
    ultimaOperacion = 'crear';
    final creada = tarea.copyWith(id: 'sql-${++_secuencia}');
    guardar(uid, creada);
    return creada;
  }

  @override
  Future<Tarea> actualizar(String uid, Tarea tarea) async {
    ultimoUid = uid;
    ultimaOperacion = 'actualizar';
    final creadaEn = _datos[uid]?[tarea.id]?.creadaEn ?? tarea.creadaEn;
    final guardada = tarea.copyWith(creadaEn: creadaEn);
    guardar(uid, guardada);
    return guardada;
  }

  @override
  Future<void> eliminar(String uid, String id) async {
    ultimoUid = uid;
    ultimaOperacion = 'eliminar';
    _datos[uid]?.remove(id);
  }

  @override
  Stream<void> observarCambios(String uid) => _controlador(uid).stream;

  StreamController<void> _controlador(String uid) {
    return _cambios.putIfAbsent(uid, StreamController<void>.broadcast);
  }

  Future<void> dispose() async {
    for (final controller in _cambios.values) {
      await controller.close();
    }
  }
}
