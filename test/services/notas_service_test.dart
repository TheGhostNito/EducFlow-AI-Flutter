import 'package:eduflow_ai/models/nota.dart';
import 'package:eduflow_ai/services/notas_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const configuration = ConfiguracionNotas.predeterminada;

  test('crea, actualiza y elimina la nota real de una evaluación', () async {
    final dataSource = _FakeNotasDataSource();
    final service = NotasService(
      dataSource: dataSource,
      uidProvider: () => 'usuario-1',
    );

    await service.guardarCalificacion(
      const CalificacionEvaluacion(evaluacionId: 'evaluacion-1', nota: 5.5),
      configuration,
    );

    expect(dataSource.calificaciones['usuario-1/evaluacion-1'], 5.5);
    expect(dataSource.ultimoPayloadCalificacion, {
      'usuario_uid': 'usuario-1',
      'evaluacion_id': 'evaluacion-1',
      'nota': 5.5,
    });

    await service.guardarCalificacion(
      const CalificacionEvaluacion(evaluacionId: 'evaluacion-1', nota: 6.1),
      configuration,
    );
    expect(dataSource.calificaciones['usuario-1/evaluacion-1'], 6.1);

    await service.eliminarCalificacion('evaluacion-1');
    expect(dataSource.calificaciones, isEmpty);
  });

  test('ponderación se guarda únicamente mediante evaluaciones', () async {
    final dataSource = _FakeNotasDataSource();
    final service = NotasService(
      dataSource: dataSource,
      uidProvider: () => 'usuario-1',
    );

    await service.guardarPonderacion('evaluacion-1', 35.5);

    expect(dataSource.ponderaciones['usuario-1/evaluacion-1'], 35.5);
    expect(dataSource.ultimoPayloadCalificacion, isNull);
  });

  test(
    'rechaza nota y ponderación fuera de rango antes de persistir',
    () async {
      final dataSource = _FakeNotasDataSource();
      final service = NotasService(
        dataSource: dataSource,
        uidProvider: () => 'usuario-1',
      );

      await expectLater(
        service.guardarCalificacion(
          const CalificacionEvaluacion(evaluacionId: 'evaluacion-1', nota: 7.1),
          configuration,
        ),
        throwsArgumentError,
      );
      await expectLater(
        service.guardarPonderacion('evaluacion-1', 100.1),
        throwsArgumentError,
      );

      expect(dataSource.calificaciones, isEmpty);
      expect(dataSource.ponderaciones, isEmpty);
    },
  );

  test('guarda configuración presentación/examen por asignatura', () async {
    final dataSource = _FakeNotasDataSource();
    final service = NotasService(
      dataSource: dataSource,
      uidProvider: () => 'usuario-1',
    );
    const scheme = ConfiguracionCalculoAsignatura(
      asignaturaId: 'asignatura-1',
      esquema: EsquemaCalculoNotas.presentacionExamen,
      pesoPresentacion: 70,
      pesoExamen: 30,
      evaluacionExamenId: 'evaluacion-final',
    );

    await service.guardarConfiguracionCalculo(scheme);

    expect(dataSource.ultimoPayloadConfiguracionCalculo, {
      'usuario_uid': 'usuario-1',
      'asignatura_id': 'asignatura-1',
      'esquema': 'presentacion_examen',
      'peso_presentacion': 70.0,
      'peso_examen': 30.0,
      'evaluacion_examen_id': 'evaluacion-final',
    });
  });
}

class _FakeNotasDataSource implements NotasDataSource {
  final Map<String, double> calificaciones = {};
  final Map<String, double?> ponderaciones = {};
  Map<String, dynamic>? ultimoPayloadCalificacion;
  Map<String, dynamic>? ultimoPayloadConfiguracionCalculo;

  @override
  Future<List<Map<String, dynamic>>> obtenerConfiguracionesCalculo(
    String uid,
  ) async => [];

  @override
  Future<Map<String, dynamic>?> obtenerNivelEducativo(String uid) async => null;

  @override
  Future<void> guardarConfiguracionCalculo(Map<String, dynamic> values) async {
    ultimoPayloadConfiguracionCalculo = Map.of(values);
  }

  @override
  Future<void> guardarCalificacion(Map<String, dynamic> values) async {
    ultimoPayloadCalificacion = Map.of(values);
    calificaciones['${values['usuario_uid']}/${values['evaluacion_id']}'] =
        (values['nota'] as num).toDouble();
  }

  @override
  Future<void> eliminarCalificacion(String uid, String evaluacionId) async {
    calificaciones.remove('$uid/$evaluacionId');
  }

  @override
  Future<void> guardarPonderacion(
    String uid,
    String evaluacionId,
    double? ponderacion,
  ) async {
    ponderaciones['$uid/$evaluacionId'] = ponderacion;
  }

  @override
  Future<void> guardarConfiguracion(Map<String, dynamic> values) async {}

  @override
  Future<void> guardarObjetivo(Map<String, dynamic> values) async {}

  @override
  Future<List<Map<String, dynamic>>> obtenerAsignaturas(String uid) async => [];

  @override
  Future<List<Map<String, dynamic>>> obtenerCalificaciones(String uid) async =>
      [];

  @override
  Future<Map<String, dynamic>?> obtenerConfiguracion(String uid) async => null;

  @override
  Future<List<Map<String, dynamic>>> obtenerEvaluaciones(String uid) async =>
      [];

  @override
  Future<List<Map<String, dynamic>>> obtenerObjetivos(String uid) async => [];
}
