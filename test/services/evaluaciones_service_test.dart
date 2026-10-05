import 'dart:async';

import 'package:eduflow_ai/models/evaluacion.dart';
import 'package:eduflow_ai/services/evaluaciones_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = EvaluacionesSqlCodec();

  group('EvaluacionesSqlCodec', () {
    test('convierte una fila SQL y normaliza fecha, hora y numeric', () {
      final evaluacion = codec.desdeFila(
        _filaSql(hora: '08:30:00.000000', ponderacion: '25.50'),
      );

      expect(evaluacion.id, 'eval-1');
      expect(evaluacion.asignaturaId, 'asig-1');
      expect(evaluacion.fecha, DateTime(2026, 10, 15));
      expect(evaluacion.hora, '08:30');
      expect(evaluacion.ponderacion, 25.5);
      expect(evaluacion.tipo, TipoEvaluacion.examen);
      expect(evaluacion.creadaEn.isUtc, isFalse);
      expect(evaluacion.actualizadaEn.isUtc, isFalse);
    });

    test('admite hora y ponderación nulas', () {
      final evaluacion = codec.desdeFila(
        _filaSql(hora: null, ponderacion: null),
      );

      expect(evaluacion.hora, isNull);
      expect(evaluacion.ponderacion, isNull);
    });

    test('genera payload snake_case sin timestamps administrados por SQL', () {
      final payload = codec.payload(
        _evaluacion(
          id: ' eval-1 ',
          titulo: ' Examen final ',
          hora: '09:45',
          ponderacion: 40,
        ),
      );

      expect(payload['id'], 'eval-1');
      expect(payload['titulo'], 'Examen final');
      expect(payload['asignatura_id'], 'asig-1');
      expect(payload['fecha'], '2026-10-15');
      expect(payload['hora'], '09:45');
      expect(payload['ponderacion'], 40);
      expect(payload, isNot(contains('usuario_uid')));
      expect(payload, isNot(contains('creada_en')));
      expect(payload, isNot(contains('actualizada_en')));
    });
  });

  group('EvaluacionesService', () {
    test('lee una evaluación por id', () async {
      final dataSource = _FakeEvaluacionesDataSource()
        ..guardar('u1', _evaluacion(id: 'e1', titulo: 'Control'));
      addTearDown(dataSource.dispose);
      final service = _service(dataSource, 'u1');

      final resultado = await service.obtenerPorId('e1');

      expect(resultado?.titulo, 'Control');
      expect(dataSource.ultimoUid, 'u1');
    });

    test('lee varias y las ordena por fecha y hora', () async {
      final dataSource = _FakeEvaluacionesDataSource()
        ..guardar(
          'u1',
          _evaluacion(id: 'sin-hora', titulo: 'Sin hora', hora: null),
        )
        ..guardar(
          'u1',
          _evaluacion(id: 'temprano', titulo: 'Temprano', hora: '08:00'),
        )
        ..guardar(
          'u1',
          _evaluacion(
            id: 'anterior',
            titulo: 'Anterior',
            fecha: DateTime(2026, 10, 14),
          ),
        );
      addTearDown(dataSource.dispose);

      final resultado = await _service(dataSource, 'u1').obtenerTodas();

      expect(resultado.map((item) => item.id), [
        'anterior',
        'temprano',
        'sin-hora',
      ]);
    });

    test('crea y usa el ID generado por PostgreSQL', () async {
      final dataSource = _FakeEvaluacionesDataSource();
      addTearDown(dataSource.dispose);
      final service = _service(dataSource, 'u1');

      final creada = await service.crear(
        titulo: ' Examen ',
        asignaturaId: ' asig-1 ',
        fecha: DateTime(2026, 10, 15, 22, 10),
        hora: '10:30',
        ponderacion: 35,
      );

      expect(creada.id, 'sql-1');
      expect(creada.titulo, 'Examen');
      expect(creada.asignaturaId, 'asig-1');
      expect(creada.fecha, DateTime(2026, 10, 15));
      expect(creada.ponderacion, 35);
      expect(dataSource.ultimaOperacion, 'crear');
      expect(service.versionDatos, 1);
    });

    test('crea con ponderación nula y acepta ponderación válida', () async {
      final dataSource = _FakeEvaluacionesDataSource();
      addTearDown(dataSource.dispose);
      final service = _service(dataSource, 'u1');

      final sinPonderacion = await service.crear(
        titulo: 'Control',
        asignaturaId: 'asig-1',
        fecha: DateTime(2026, 10, 15),
      );
      final conPonderacion = await service.crear(
        titulo: 'Examen',
        asignaturaId: 'asig-1',
        fecha: DateTime(2026, 10, 16),
        ponderacion: 100,
      );

      expect(sinPonderacion.ponderacion, isNull);
      expect(conPonderacion.ponderacion, 100);
    });

    test('actualiza conservando el ID existente', () async {
      final dataSource = _FakeEvaluacionesDataSource()
        ..guardar('u1', _evaluacion(id: 'e1', titulo: 'Control'));
      addTearDown(dataSource.dispose);
      final service = _service(dataSource, 'u1');

      await service.actualizar(
        _evaluacion(id: 'e1', titulo: 'Control corregido'),
      );

      final actualizada = await service.obtenerPorId('e1');
      expect(actualizada?.id, 'e1');
      expect(actualizada?.titulo, 'Control corregido');
      expect(dataSource.ultimaOperacion, 'actualizar');
      expect(service.versionDatos, 1);
    });

    test('elimina una evaluación sin nota', () async {
      final dataSource = _FakeEvaluacionesDataSource()
        ..guardar('u1', _evaluacion(id: 'e1'));
      addTearDown(dataSource.dispose);
      final service = _service(dataSource, 'u1');

      await service.eliminar('e1');

      expect(await service.obtenerPorId('e1'), isNull);
      expect(service.versionDatos, 1);
    });

    test('protege una evaluación con nota simulada', () async {
      final dataSource = _FakeEvaluacionesDataSource()
        ..guardar('u1', _evaluacion(id: 'e1'))
        ..evaluacionesConNota.add('u1/e1');
      addTearDown(dataSource.dispose);
      final service = _service(dataSource, 'u1');

      await expectLater(
        service.eliminar('e1'),
        throwsA(isA<EvaluacionConNotaException>()),
      );

      expect(await service.obtenerPorId('e1'), isNotNull);
      expect(service.versionDatos, 0);
    });

    test('propaga eventos Realtime del usuario y actualiza la versión', () async {
      final dataSource = _FakeEvaluacionesDataSource();
      addTearDown(dataSource.dispose);
      final service = _service(dataSource, 'u1');
      final evento = service.observarCambios().first;

      dataSource.emitirCambio('u1');

      await evento;
      expect(service.versionDatos, 1);
    });

    test('aísla lecturas, escrituras y Realtime por UID', () async {
      final dataSource = _FakeEvaluacionesDataSource()
        ..guardar('u1', _evaluacion(id: 'comun', titulo: 'Versión U1'))
        ..guardar('u2', _evaluacion(id: 'comun', titulo: 'Versión U2'));
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

EvaluacionesService _service(
  _FakeEvaluacionesDataSource dataSource,
  String uid,
) => EvaluacionesService(dataSource: dataSource, uidProvider: () => uid);

Evaluacion _evaluacion({
  String id = 'eval-1',
  String titulo = 'Examen final',
  DateTime? fecha,
  String? hora = '08:30',
  double? ponderacion = 25,
}) => Evaluacion(
  id: id,
  titulo: titulo,
  asignaturaId: 'asig-1',
  tipo: TipoEvaluacion.examen,
  fecha: fecha ?? DateTime(2026, 10, 15),
  hora: hora,
  descripcion: 'Descripción',
  ponderacion: ponderacion,
  creadaEn: DateTime.utc(2026, 10, 1, 12),
  actualizadaEn: DateTime.utc(2026, 10, 2, 12),
);

Map<String, dynamic> _filaSql({Object? hora, Object? ponderacion}) => {
  'id': 'eval-1',
  'asignatura_id': 'asig-1',
  'titulo': 'Examen final',
  'tipo': 'examen',
  'fecha': '2026-10-15',
  'hora': hora,
  'descripcion': 'Descripción',
  'ponderacion': ponderacion,
  'creada_en': '2026-10-01T12:00:00Z',
  'actualizada_en': '2026-10-02T12:00:00Z',
};

class _FakeEvaluacionesDataSource implements EvaluacionesDataSource {
  final Map<String, Map<String, Evaluacion>> _datos = {};
  final Map<String, StreamController<void>> _cambios = {};
  final Set<String> evaluacionesConNota = {};
  int _secuencia = 0;
  String? ultimoUid;
  String? ultimaOperacion;

  void guardar(String uid, Evaluacion evaluacion) {
    _datos.putIfAbsent(uid, () => {})[evaluacion.id] = evaluacion;
  }

  void emitirCambio(String uid) {
    _controlador(uid).add(null);
  }

  @override
  Future<List<Evaluacion>> obtenerTodas(String uid) async {
    ultimoUid = uid;
    return List.of(_datos[uid]?.values ?? const []);
  }

  @override
  Future<Evaluacion?> obtenerPorId(String uid, String id) async {
    ultimoUid = uid;
    return _datos[uid]?[id];
  }

  @override
  Future<Evaluacion> crear(String uid, Evaluacion evaluacion) async {
    ultimoUid = uid;
    ultimaOperacion = 'crear';
    final creada = Evaluacion(
      id: 'sql-${++_secuencia}',
      titulo: evaluacion.titulo,
      asignaturaId: evaluacion.asignaturaId,
      tipo: evaluacion.tipo,
      fecha: evaluacion.fecha,
      hora: evaluacion.hora,
      descripcion: evaluacion.descripcion,
      ponderacion: evaluacion.ponderacion,
      creadaEn: evaluacion.creadaEn,
      actualizadaEn: evaluacion.actualizadaEn,
    );
    guardar(uid, creada);
    return creada;
  }

  @override
  Future<void> actualizar(String uid, Evaluacion evaluacion) async {
    ultimoUid = uid;
    ultimaOperacion = 'actualizar';
    guardar(uid, evaluacion);
  }

  @override
  Future<void> eliminar(String uid, String id) async {
    ultimoUid = uid;
    if (evaluacionesConNota.contains('$uid/$id')) {
      throw const EvaluacionConNotaException();
    }
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
