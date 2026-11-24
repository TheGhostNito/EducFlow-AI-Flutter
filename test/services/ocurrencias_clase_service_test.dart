import 'package:eduflow_ai/models/asignatura.dart';
import 'package:eduflow_ai/models/periodo_academico.dart';
import 'package:eduflow_ai/models/sesion_clase.dart';
import 'package:eduflow_ai/services/ocurrencias_clase_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = OcurrenciasClaseService();

  final periodo2024 = PeriodoAcademico(
    id: 'duoc-2024-1',
    anio: 2024,
    tipo: TipoPeriodoAcademico.semestre,
    numero: 1,
    nombre: 'Primer semestre 2024',
    fechaInicio: DateTime(2024, 3, 1),
    fechaFin: DateTime(2024, 7, 31),
    institucion: 'DUOC UC',
    estado: EstadoPeriodoAcademico.historico,
  );
  final periodo2025 = PeriodoAcademico(
    id: 'duoc-2025-1',
    anio: 2025,
    tipo: TipoPeriodoAcademico.semestre,
    numero: 1,
    nombre: 'Primer semestre 2025',
    fechaInicio: DateTime(2025, 3, 1),
    fechaFin: DateTime(2025, 7, 31),
    institucion: 'DUOC UC',
  );

  final asignaturas2024 = _asignaturasSemanales(
    periodoId: periodo2024.id,
    sufijo: '2024',
  );
  final asignaturas2025 = _asignaturasSemanales(
    periodoId: periodo2025.id,
    sufijo: '2025',
  );
  final portafolio3 = _portafolio(
    id: 'portafolio-3',
    nombre: 'Proceso de Portafolio 3',
    periodoId: periodo2024.id,
  );
  final portafolio5 = _portafolio(
    id: 'portafolio-5',
    nombre: 'Proceso de Portafolio 5',
    periodoId: periodo2025.id,
  );
  final fechasPortafolio3 = <DateTime>[
    DateTime(2024, 3, 15),
    DateTime(2024, 4, 19),
    DateTime(2024, 5, 17),
    DateTime(2024, 6, 14),
  ];
  final fechasPortafolio5 = <DateTime>[
    DateTime(2025, 3, 14),
    DateTime(2025, 4, 18),
    DateTime(2025, 5, 16),
    DateTime(2025, 6, 13),
  ];
  final sesiones = <SesionClase>[
    ..._sesionesPortafolio(
      asignaturaId: portafolio3.id,
      periodoId: periodo2024.id,
      fechas: fechasPortafolio3,
    ),
    ..._sesionesPortafolio(
      asignaturaId: portafolio5.id,
      periodoId: periodo2025.id,
      fechas: fechasPortafolio5,
    ),
  ];
  final asignaturas = <Asignatura>[
    ...asignaturas2024,
    portafolio3,
    ...asignaturas2025,
    portafolio5,
  ];
  final periodos = [periodo2024, periodo2025];

  test('cada semana contiene solo las seis asignaturas de su período', () {
    final semana2024 = _ocurrenciasSemana(
      service,
      lunes: DateTime(2024, 3, 4),
      asignaturas: asignaturas,
      periodos: periodos,
      sesiones: sesiones,
    );
    final semana2025 = _ocurrenciasSemana(
      service,
      lunes: DateTime(2025, 3, 3),
      asignaturas: asignaturas,
      periodos: periodos,
      sesiones: sesiones,
    );

    expect(semana2024, hasLength(6));
    expect(
      semana2024.map((item) => item.asignatura.id),
      everyElement(endsWith('-2024')),
    );
    expect(semana2025, hasLength(6));
    expect(
      semana2025.map((item) => item.asignatura.id),
      everyElement(endsWith('-2025')),
    );
  });

  test('las clases históricas no aparecen en una fecha del período actual', () {
    final ocurrencias = service.obtenerParaFecha(
      fecha: DateTime(2025, 3, 3),
      asignaturas: asignaturas,
      periodos: periodos,
      sesiones: sesiones,
    );

    expect(
      ocurrencias.map((item) => item.asignatura.id),
      isNot(contains('asignatura-1-2024')),
    );
    expect(
      ocurrencias.map((item) => item.asignatura.id),
      contains('asignatura-1-2025'),
    );
  });

  test('Portafolio 3 aparece exclusivamente en sus cuatro fechas', () {
    for (final fecha in fechasPortafolio3) {
      final ocurrencias = service.obtenerParaFecha(
        fecha: fecha,
        asignaturas: asignaturas,
        periodos: periodos,
        sesiones: sesiones,
      );
      expect(
        ocurrencias.where((item) => item.asignatura.id == portafolio3.id),
        hasLength(1),
      );
    }

    final fueraDeFechas = service.obtenerParaFecha(
      fecha: DateTime(2024, 3, 22),
      asignaturas: asignaturas,
      periodos: periodos,
      sesiones: sesiones,
    );
    expect(
      fueraDeFechas.where((item) => item.asignatura.id == portafolio3.id),
      isEmpty,
    );
  });

  test('Portafolio 5 aparece exclusivamente en sus cuatro fechas', () {
    for (final fecha in fechasPortafolio5) {
      final ocurrencias = service.obtenerParaFecha(
        fecha: fecha,
        asignaturas: asignaturas,
        periodos: periodos,
        sesiones: sesiones,
      );
      expect(
        ocurrencias.where((item) => item.asignatura.id == portafolio5.id),
        hasLength(1),
      );
    }

    final fueraDeFechas = service.obtenerParaFecha(
      fecha: DateTime(2025, 3, 21),
      asignaturas: asignaturas,
      periodos: periodos,
      sesiones: sesiones,
    );
    expect(
      fueraDeFechas.where((item) => item.asignatura.id == portafolio5.id),
      isEmpty,
    );
  });

  test('detecta conflicto entre bloque semanal y sesión del mismo período', () {
    final semanal = Asignatura(
      id: 'semanal',
      nombre: 'Clase semanal',
      periodoAcademicoId: periodo2025.id,
      estado: EstadoAsignatura.enCurso,
      origen: OrigenAsignatura.horario,
      horario: const [
        BloqueHorario(
          dia: DiaSemana.viernes,
          horaInicio: '10:00',
          horaFin: '11:30',
        ),
      ],
    );
    final fechada = _portafolio(
      id: 'fechada',
      nombre: 'Sesión fechada',
      periodoId: periodo2025.id,
    );
    final sesion = SesionClase(
      id: 'sesion-conflicto',
      asignaturaId: fechada.id,
      periodoAcademicoId: periodo2025.id,
      fecha: DateTime(2025, 4, 18),
      horaInicio: '11:00',
      horaFin: '12:00',
    );

    final conflictos = service.buscarConflictosParaFecha(
      fecha: sesion.fecha,
      asignaturas: [semanal, fechada],
      periodos: periodos,
      sesiones: [sesion],
    );

    expect(conflictos, hasLength(1));
    expect(
      {conflictos.single.primera.tipo, conflictos.single.segunda.tipo},
      {TipoOcurrenciaClase.semanal, TipoOcurrenciaClase.fechaEspecifica},
    );
  });

  test('bloques equivalentes de períodos distintos no generan conflicto', () {
    final conflictos = service.buscarConflictosParaFecha(
      fecha: DateTime(2025, 3, 3),
      asignaturas: [asignaturas2024.first, asignaturas2025.first],
      periodos: periodos,
      sesiones: const [],
    );

    expect(conflictos, isEmpty);
  });

  test('una asignatura heredada conserva su recurrencia semanal', () {
    const heredada = Asignatura(
      id: 'heredada',
      nombre: 'Asignatura heredada',
      estado: EstadoAsignatura.registrada,
      origen: OrigenAsignatura.manual,
      horario: [
        BloqueHorario(
          dia: DiaSemana.lunes,
          horaInicio: '08:00',
          horaFin: '09:00',
        ),
      ],
    );

    final ocurrencias = service.obtenerParaFecha(
      fecha: DateTime(2030, 1, 7),
      asignaturas: const [heredada],
      periodos: const [],
      sesiones: const [],
    );

    expect(ocurrencias, hasLength(1));
    expect(ocurrencias.single.tipo, TipoOcurrenciaClase.semanal);
  });

  test('un período sin fechas limita el patrón semanal a su año', () {
    final periodo = PeriodoAcademico(
      id: 'periodo-incompleto-2025',
      anio: 2025,
      tipo: TipoPeriodoAcademico.semestre,
      numero: 1,
      nombre: 'Primer semestre 2025',
    );
    final asignatura = _semanalIncompleta(periodo.id);

    final dentro = service.obtenerParaFecha(
      fecha: DateTime(2025, 3, 3),
      asignaturas: [asignatura],
      periodos: [periodo],
      sesiones: const [],
    );
    final fuera = service.obtenerParaFecha(
      fecha: DateTime(2026, 3, 2),
      asignaturas: [asignatura],
      periodos: [periodo],
      sesiones: const [],
    );

    expect(dentro, hasLength(1));
    expect(dentro.single.esProvisional, isTrue);
    expect(fuera, isEmpty);
  });

  test('un período histórico incompleto no reaparece como actual', () {
    final historico = PeriodoAcademico(
      id: 'historico-incompleto-2024',
      anio: 2024,
      tipo: TipoPeriodoAcademico.semestre,
      numero: 1,
      nombre: 'Primer semestre 2024',
      estado: EstadoPeriodoAcademico.historico,
    );

    final ocurrencias = service.obtenerParaFecha(
      fecha: DateTime(2025, 3, 3),
      asignaturas: [_semanalIncompleta(historico.id)],
      periodos: [historico],
      sesiones: const [],
    );

    expect(ocurrencias, isEmpty);
  });

  test('cada límite conocido restringe las clases semanales por separado', () {
    final startOnly = PeriodoAcademico(
      id: 'inicio-2025',
      anio: 2025,
      tipo: TipoPeriodoAcademico.semestre,
      numero: 1,
      nombre: 'Inicio conocido',
      fechaInicio: DateTime(2025, 3, 1),
    );
    final endOnly = PeriodoAcademico(
      id: 'fin-2025',
      anio: 2025,
      tipo: TipoPeriodoAcademico.semestre,
      numero: 1,
      nombre: 'Fin conocido',
      fechaFin: DateTime(2025, 7, 31),
    );

    expect(
      service.obtenerParaFecha(
        fecha: DateTime(2025, 2, 24),
        asignaturas: [_semanalIncompleta(startOnly.id)],
        periodos: [startOnly],
        sesiones: const [],
      ),
      isEmpty,
    );
    expect(
      service
          .obtenerParaFecha(
            fecha: DateTime(2025, 3, 3),
            asignaturas: [_semanalIncompleta(startOnly.id)],
            periodos: [startOnly],
            sesiones: const [],
          )
          .single
          .esProvisional,
      isTrue,
    );
    expect(
      service.obtenerParaFecha(
        fecha: DateTime(2025, 8, 4),
        asignaturas: [_semanalIncompleta(endOnly.id)],
        periodos: [endOnly],
        sesiones: const [],
      ),
      isEmpty,
    );
  });

  test('las sesiones exactas sobreviven sin fechas oficiales del período', () {
    final periodo = PeriodoAcademico(
      id: 'portafolio-incompleto',
      anio: 2025,
      tipo: TipoPeriodoAcademico.semestre,
      numero: 1,
      nombre: 'Primer semestre 2025',
    );
    final asignatura = _portafolio(
      id: 'portafolio-incompleto',
      nombre: 'Proceso de Portafolio 5',
      periodoId: periodo.id,
    );
    final sesion = SesionClase(
      id: 'sesion-exacta',
      asignaturaId: asignatura.id,
      periodoAcademicoId: periodo.id,
      fecha: DateTime(2025, 4, 18),
      horaInicio: '18:30',
      horaFin: '20:00',
    );

    final ocurrencias = service.obtenerParaFecha(
      fecha: sesion.fecha,
      asignaturas: [asignatura],
      periodos: [periodo],
      sesiones: [sesion],
    );

    expect(ocurrencias, hasLength(1));
    expect(ocurrencias.single.tipo, TipoOcurrenciaClase.fechaEspecifica);
    expect(ocurrencias.single.esProvisional, isFalse);
  });
}

Asignatura _semanalIncompleta(String periodoId) {
  return Asignatura(
    id: 'semanal-$periodoId',
    nombre: 'Clase semanal incompleta',
    periodoAcademicoId: periodoId,
    estado: EstadoAsignatura.enCurso,
    origen: OrigenAsignatura.horario,
    horario: const [
      BloqueHorario(
        dia: DiaSemana.lunes,
        horaInicio: '08:00',
        horaFin: '09:30',
      ),
    ],
  );
}

List<Asignatura> _asignaturasSemanales({
  required String periodoId,
  required String sufijo,
}) {
  const dias = [
    DiaSemana.lunes,
    DiaSemana.martes,
    DiaSemana.miercoles,
    DiaSemana.jueves,
    DiaSemana.viernes,
    DiaSemana.sabado,
  ];
  return [
    for (var index = 0; index < 6; index++)
      Asignatura(
        id: 'asignatura-${index + 1}-$sufijo',
        nombre: 'Asignatura ${index + 1} $sufijo',
        periodoAcademicoId: periodoId,
        estado: EstadoAsignatura.enCurso,
        origen: OrigenAsignatura.horario,
        horario: [
          BloqueHorario(
            dia: dias[index],
            horaInicio: '08:00',
            horaFin: '09:30',
            sala: 'Sala ${index + 1}',
          ),
        ],
      ),
  ];
}

Asignatura _portafolio({
  required String id,
  required String nombre,
  required String periodoId,
}) {
  return Asignatura(
    id: id,
    nombre: nombre,
    periodoAcademicoId: periodoId,
    estado: EstadoAsignatura.enCurso,
    origen: OrigenAsignatura.horario,
  );
}

List<SesionClase> _sesionesPortafolio({
  required String asignaturaId,
  required String periodoId,
  required List<DateTime> fechas,
}) {
  return [
    for (var index = 0; index < fechas.length; index++)
      SesionClase(
        id: '$asignaturaId-sesion-${index + 1}',
        asignaturaId: asignaturaId,
        periodoAcademicoId: periodoId,
        fecha: fechas[index],
        horaInicio: '18:30',
        horaFin: '20:00',
        sala: 'Sala Portafolio',
        origen: OrigenSesionClase.horario,
      ),
  ];
}

List<OcurrenciaClase> _ocurrenciasSemana(
  OcurrenciasClaseService service, {
  required DateTime lunes,
  required List<Asignatura> asignaturas,
  required List<PeriodoAcademico> periodos,
  required List<SesionClase> sesiones,
}) {
  return [
    for (var offset = 0; offset < 7; offset++)
      ...service.obtenerParaFecha(
        fecha: lunes.add(Duration(days: offset)),
        asignaturas: asignaturas,
        periodos: periodos,
        sesiones: sesiones,
      ),
  ];
}
