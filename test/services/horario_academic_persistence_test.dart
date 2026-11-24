import 'package:eduflow_ai/models/periodo_academico.dart';
import 'package:eduflow_ai/models/sesion_clase.dart';
import 'package:eduflow_ai/services/periodos_academicos_service.dart';
import 'package:eduflow_ai/services/sesiones_clase_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const periodosCodec = PeriodosAcademicosSqlCodec();
  const sesionesCodec = SesionesClaseSqlCodec();

  test('PeriodoAcademico conserva el contrato SQL al serializar', () {
    final periodo = PeriodoAcademico(
      id: 'duoc-2025-1',
      anio: 2025,
      tipo: TipoPeriodoAcademico.semestre,
      numero: 1,
      nombre: 'Primer semestre 2025',
      fechaInicio: DateTime(2025, 3, 3, 18, 30),
      fechaFin: DateTime(2025, 7, 18, 23, 59),
      institucion: ' DUOC UC ',
    );

    final payload = periodosCodec.payload(periodo);
    final recovered = periodosCodec.desdeFila(payload);

    expect(payload['fecha_inicio'], '2025-03-03');
    expect(payload['fecha_fin'], '2025-07-18');
    expect(payload['institucion'], 'DUOC UC');
    expect(recovered.id, periodo.id);
    expect(recovered.fechaInicio, DateTime(2025, 3, 3));
    expect(recovered.fechaFin, DateTime(2025, 7, 18));
    expect(recovered.estado, EstadoPeriodoAcademico.activo);
  });

  test('PeriodoAcademico serializa límites opcionales e independientes', () {
    final withoutDates = PeriodoAcademico(
      id: 'duoc-2025-sin-fechas',
      anio: 2025,
      tipo: TipoPeriodoAcademico.semestre,
      numero: 1,
      nombre: 'Primer semestre 2025',
    );
    final startOnly = PeriodoAcademico(
      id: 'duoc-2025-inicio',
      anio: 2025,
      tipo: TipoPeriodoAcademico.semestre,
      numero: 1,
      nombre: 'Primer semestre 2025',
      fechaInicio: DateTime(2025, 3, 3),
    );
    final endOnly = PeriodoAcademico(
      id: 'duoc-2025-fin',
      anio: 2025,
      tipo: TipoPeriodoAcademico.semestre,
      numero: 1,
      nombre: 'Primer semestre 2025',
      fechaFin: DateTime(2025, 7, 18),
    );

    expect(periodosCodec.payload(withoutDates)['fecha_inicio'], isNull);
    expect(periodosCodec.payload(withoutDates)['fecha_fin'], isNull);
    expect(periodosCodec.payload(startOnly)['fecha_inicio'], '2025-03-03');
    expect(periodosCodec.payload(startOnly)['fecha_fin'], isNull);
    expect(periodosCodec.payload(endOnly)['fecha_inicio'], isNull);
    expect(periodosCodec.payload(endOnly)['fecha_fin'], '2025-07-18');

    final recovered = periodosCodec.desdeFila({
      ...periodosCodec.payload(withoutDates),
      'estado': 'activo',
    });
    expect(recovered.fechaInicio, isNull);
    expect(recovered.fechaFin, isNull);
  });

  test('SesionClase normaliza horas SQL y conserva período y origen', () {
    final session = sesionesCodec.desdeFila({
      'id': 'portafolio-5-1',
      'asignatura_id': 'portafolio-5',
      'periodo_academico_id': 'duoc-2025-1',
      'fecha': '2025-04-18',
      'hora_inicio': '18:30:00',
      'hora_fin': '20:00:00.000000',
      'sala': 'A-101',
      'origen': 'horario',
    });

    expect(session.horaInicio, '18:30');
    expect(session.horaFin, '20:00');
    expect(session.periodoAcademicoId, 'duoc-2025-1');
    expect(session.origen, OrigenSesionClase.horario);
    expect(sesionesCodec.payload(session)['fecha'], '2025-04-18');
  });

  test('los codecs rechazan estados y contratos remotos desconocidos', () {
    expect(
      () => periodosCodec.desdeFila({
        'id': 'p1',
        'anio': 2025,
        'tipo': 'semestre',
        'numero': 1,
        'nombre': 'Semestre',
        'fecha_inicio': '2025-03-01',
        'fecha_fin': '2025-07-31',
        'estado': 'cerrado',
      }),
      throwsFormatException,
    );
    expect(
      () => sesionesCodec.desdeFila({
        'id': 's1',
        'asignatura_id': 'a1',
        'periodo_academico_id': 'p1',
        'fecha': '2025-04-01',
        'hora_inicio': '18:30',
        'hora_fin': '20:00',
        'origen': 'desconocido',
      }),
      throwsFormatException,
    );
  });

  test('PeriodosAcademicosService aísla operaciones por UID', () async {
    final dataSource = _FakePeriodosDataSource();
    final service = PeriodosAcademicosService(
      dataSource: dataSource,
      uidProvider: () => 'usuario-1',
    );
    final periodo = _periodo();

    await service.agregar(periodo);
    await service.asociarAsignatura(
      asignaturaId: 'asignatura-1',
      periodoAcademicoId: periodo.id,
    );
    await service.asociarAsignatura(
      asignaturaId: 'asignatura-heredada',
      periodoAcademicoId: null,
    );

    expect(dataSource.ultimoUid, 'usuario-1');
    expect(dataSource.periodos, [periodo]);
    expect(dataSource.asociaciones['asignatura-1'], periodo.id);
    expect(dataSource.asociaciones.containsKey('asignatura-heredada'), isTrue);
    expect(dataSource.asociaciones['asignatura-heredada'], isNull);
  });

  test('SesionesClaseService aísla CRUD por UID', () async {
    final dataSource = _FakeSesionesDataSource();
    final service = SesionesClaseService(
      dataSource: dataSource,
      uidProvider: () => 'usuario-2',
    );
    final sesion = SesionClase(
      id: 'sesion-1',
      asignaturaId: 'portafolio-5',
      periodoAcademicoId: 'duoc-2025-1',
      fecha: DateTime(2025, 4, 18),
      horaInicio: '18:30',
      horaFin: '20:00',
      origen: OrigenSesionClase.horario,
    );

    await service.agregar(sesion);
    expect(await service.obtenerTodas(), [sesion]);
    await service.eliminar(sesion.id);

    expect(dataSource.ultimoUid, 'usuario-2');
    expect(await service.obtenerTodas(), isEmpty);
  });
}

PeriodoAcademico _periodo() {
  return PeriodoAcademico(
    id: 'duoc-2025-1',
    anio: 2025,
    tipo: TipoPeriodoAcademico.semestre,
    numero: 1,
    nombre: 'Primer semestre 2025',
    fechaInicio: DateTime(2025, 3, 1),
    fechaFin: DateTime(2025, 7, 31),
  );
}

class _FakePeriodosDataSource implements PeriodosAcademicosDataSource {
  final List<PeriodoAcademico> periodos = [];
  final Map<String, String?> asociaciones = {};
  String? ultimoUid;

  @override
  Future<PeriodoAcademico> agregar(String uid, PeriodoAcademico periodo) async {
    ultimoUid = uid;
    periodos.add(periodo);
    return periodo;
  }

  @override
  Future<void> asociarAsignatura(
    String uid, {
    required String asignaturaId,
    required String? periodoAcademicoId,
  }) async {
    ultimoUid = uid;
    asociaciones[asignaturaId] = periodoAcademicoId;
  }

  @override
  Future<PeriodoAcademico> actualizar(
    String uid,
    PeriodoAcademico periodo,
  ) async {
    ultimoUid = uid;
    periodos
      ..removeWhere((item) => item.id == periodo.id)
      ..add(periodo);
    return periodo;
  }

  @override
  Future<void> eliminar(String uid, String id) async {
    ultimoUid = uid;
    periodos.removeWhere((item) => item.id == id);
  }

  @override
  Future<List<PeriodoAcademico>> obtenerTodos(String uid) async {
    ultimoUid = uid;
    return List.of(periodos);
  }
}

class _FakeSesionesDataSource implements SesionesClaseDataSource {
  final List<SesionClase> sesiones = [];
  String? ultimoUid;

  @override
  Future<SesionClase> agregar(String uid, SesionClase sesion) async {
    ultimoUid = uid;
    sesiones.add(sesion);
    return sesion;
  }

  @override
  Future<SesionClase> actualizar(String uid, SesionClase sesion) async {
    ultimoUid = uid;
    sesiones
      ..removeWhere((item) => item.id == sesion.id)
      ..add(sesion);
    return sesion;
  }

  @override
  Future<void> eliminar(String uid, String id) async {
    ultimoUid = uid;
    sesiones.removeWhere((item) => item.id == id);
  }

  @override
  Future<List<SesionClase>> obtenerTodas(String uid) async {
    ultimoUid = uid;
    return List.of(sesiones);
  }
}
