import 'package:eduflow_ai/models/asignatura.dart';
import 'package:eduflow_ai/services/asignaturas_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = AsignaturasSqlCodec();

  group('AsignaturasSqlCodec', () {
    test('reconstruye una asignatura y normaliza horas SQL', () {
      final resultado = codec.reconstruir(
        asignaturas: [_filaAsignatura(id: 'mat', nombre: 'Matemática')],
        bloques: [
          {
            'asignatura_id': 'mat',
            'dia': 'lunes',
            'hora_inicio': '08:30:00',
            'hora_fin': '10:00:00.000000',
            'sala': 'A-1',
          },
        ],
        relaciones: const [],
      );

      expect(resultado, hasLength(1));
      expect(resultado.single.nombre, 'Matemática');
      expect(resultado.single.horario, hasLength(1));
      expect(resultado.single.horario.single.dia, DiaSemana.lunes);
      expect(resultado.single.horario.single.horaInicio, '08:30');
      expect(resultado.single.horario.single.horaFin, '10:00');
      expect(resultado.single.horario.single.sala, 'A-1');
    });

    test('reconstruye prerrequisitos y asignaturas siguientes', () {
      final resultado = codec
          .reconstruir(
            asignaturas: [
              _filaAsignatura(id: 'calculo-2', nombre: 'Cálculo II'),
            ],
            bloques: const [],
            relaciones: const [
              {
                'asignatura_id': 'calculo-2',
                'relacionada_id': 'calculo-1',
                'tipo': 'prerrequisito',
              },
              {
                'asignatura_id': 'calculo-2',
                'relacionada_id': 'calculo-3',
                'tipo': 'siguiente',
              },
            ],
          )
          .single;

      expect(resultado.prerrequisitosIds, ['calculo-1']);
      expect(resultado.asignaturasSiguientesIds, ['calculo-3']);
    });

    test('genera payloads snake_case para las tres tablas', () {
      const asignatura = Asignatura(
        id: 'fisica',
        nombre: ' Física ',
        estado: EstadoAsignatura.enCurso,
        origen: OrigenAsignatura.manual,
        correoProfesor: ' PROFE@EJEMPLO.CL ',
        horario: [
          BloqueHorario(
            dia: DiaSemana.martes,
            horaInicio: '09:00',
            horaFin: '10:30',
          ),
        ],
        prerrequisitosIds: ['mat'],
      );

      expect(
        codec.asignaturaPayload(asignatura),
        containsPair('nombre', 'Física'),
      );
      expect(
        codec.asignaturaPayload(asignatura),
        containsPair('correo_profesor', 'profe@ejemplo.cl'),
      );
      expect(codec.bloquesPayload(asignatura).single['hora_inicio'], '09:00');
      expect(
        codec.relacionesPayload(asignatura).single,
        containsPair('relacionada_id', 'mat'),
      );
    });
  });

  group('AsignaturasService', () {
    test('lee una asignatura por id', () async {
      final dataSource = _FakeAsignaturasDataSource()
        ..guardar('u1', _asignatura('a', 'Álgebra'));
      final service = _service(dataSource, 'u1');

      final resultado = await service.obtenerPorId('a');

      expect(resultado?.nombre, 'Álgebra');
      expect(dataSource.ultimoUid, 'u1');
    });

    test('lee varias asignaturas con orden alfabético normalizado', () async {
      final dataSource = _FakeAsignaturasDataSource()
        ..guardar('u1', _asignatura('z', 'Zoología'))
        ..guardar('u1', _asignatura('a', 'Álgebra'));
      final service = _service(dataSource, 'u1');

      final resultado = await service.obtenerTodas();

      expect(resultado.map((item) => item.id), ['a', 'z']);
    });

    test('crea mediante el datasource y aumenta versionDatos', () async {
      final dataSource = _FakeAsignaturasDataSource();
      final service = _service(dataSource, 'u1');

      await service.agregar(_asignatura('a', 'Álgebra'));

      expect((await dataSource.obtenerPorId('u1', 'a'))?.nombre, 'Álgebra');
      expect(dataSource.ultimaOperacion, 'crear');
      expect(service.versionDatos, 1);
    });

    test('actualiza mediante el datasource y aumenta versionDatos', () async {
      final dataSource = _FakeAsignaturasDataSource()
        ..guardar('u1', _asignatura('a', 'Álgebra'));
      final service = _service(dataSource, 'u1');

      await service.actualizar(_asignatura('a', 'Álgebra Lineal'));

      expect(
        (await dataSource.obtenerPorId('u1', 'a'))?.nombre,
        'Álgebra Lineal',
      );
      expect(dataSource.ultimaOperacion, 'actualizar');
      expect(service.versionDatos, 1);
    });

    test(
      'un error atómico no deja datos parciales ni aumenta la versión',
      () async {
        final dataSource = _FakeAsignaturasDataSource()..fallarGuardado = true;
        final service = _service(dataSource, 'u1');

        await expectLater(
          service.agregar(_asignatura('a', 'Álgebra')),
          throwsStateError,
        );

        expect(await dataSource.obtenerPorId('u1', 'a'), isNull);
        expect(service.versionDatos, 0);
      },
    );

    test('bloquea la eliminación cuando existen evaluaciones', () async {
      final dataSource = _FakeAsignaturasDataSource()
        ..guardar('u1', _asignatura('a', 'Álgebra'))
        ..asignaturasConEvaluaciones.add('u1/a');
      final service = _service(dataSource, 'u1');

      await expectLater(
        service.eliminar('a'),
        throwsA(isA<AsignaturaConEvaluacionesException>()),
      );

      expect(await dataSource.obtenerPorId('u1', 'a'), isNotNull);
      expect(service.versionDatos, 0);
    });

    test('elimina cuando no existen evaluaciones', () async {
      final dataSource = _FakeAsignaturasDataSource()
        ..guardar('u1', _asignatura('a', 'Álgebra'));
      final service = _service(dataSource, 'u1');

      await service.eliminar('a');

      expect(await dataSource.obtenerPorId('u1', 'a'), isNull);
      expect(service.versionDatos, 1);
    });

    test('aísla lecturas y escrituras por UID', () async {
      final dataSource = _FakeAsignaturasDataSource()
        ..guardar('u1', _asignatura('comun', 'Versión U1'))
        ..guardar('u2', _asignatura('comun', 'Versión U2'));

      final resultadoU1 = await _service(
        dataSource,
        'u1',
      ).obtenerPorId('comun');
      final resultadoU2 = await _service(
        dataSource,
        'u2',
      ).obtenerPorId('comun');

      expect(resultadoU1?.nombre, 'Versión U1');
      expect(resultadoU2?.nombre, 'Versión U2');
    });
  });
}

AsignaturasService _service(_FakeAsignaturasDataSource dataSource, String uid) {
  return AsignaturasService(dataSource: dataSource, uidProvider: () => uid);
}

Asignatura _asignatura(String id, String nombre) => Asignatura(
  id: id,
  nombre: nombre,
  estado: EstadoAsignatura.registrada,
  origen: OrigenAsignatura.manual,
);

Map<String, dynamic> _filaAsignatura({
  required String id,
  required String nombre,
}) => {'id': id, 'nombre': nombre, 'estado': 'registrada', 'origen': 'manual'};

class _FakeAsignaturasDataSource implements AsignaturasDataSource {
  final Map<String, Map<String, Asignatura>> _datos = {};
  final Set<String> asignaturasConEvaluaciones = {};
  bool fallarGuardado = false;
  String? ultimoUid;
  String? ultimaOperacion;

  void guardar(String uid, Asignatura asignatura) {
    _datos.putIfAbsent(uid, () => {})[asignatura.id] = asignatura;
  }

  @override
  Future<List<Asignatura>> obtenerTodas(String uid) async {
    ultimoUid = uid;
    return List.of(_datos[uid]?.values ?? const []);
  }

  @override
  Future<Asignatura?> obtenerPorId(String uid, String id) async {
    ultimoUid = uid;
    return _datos[uid]?[id];
  }

  @override
  Future<void> agregar(String uid, Asignatura asignatura) async {
    ultimoUid = uid;
    ultimaOperacion = 'crear';
    if (fallarGuardado) throw StateError('rollback simulado');
    guardar(uid, asignatura);
  }

  @override
  Future<void> actualizar(String uid, Asignatura asignatura) async {
    ultimoUid = uid;
    ultimaOperacion = 'actualizar';
    if (fallarGuardado) throw StateError('rollback simulado');
    guardar(uid, asignatura);
  }

  @override
  Future<void> eliminar(String uid, String id) async {
    ultimoUid = uid;
    if (asignaturasConEvaluaciones.contains('$uid/$id')) {
      throw const AsignaturaConEvaluacionesException();
    }
    _datos[uid]?.remove(id);
  }

  @override
  Stream<void> observarCambios(String uid) => const Stream.empty();
}
