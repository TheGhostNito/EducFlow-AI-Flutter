import 'package:eduflow_ai/models/asignatura.dart';
import 'package:eduflow_ai/models/periodo_academico.dart';
import 'package:eduflow_ai/models/sesion_clase.dart';
import 'package:eduflow_ai/services/ai_schedule_context_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const builder = AiScheduleContextBuilder();

  test('expone diez bloques y cuatro sesiones del horario importado', () {
    final subjects = [
      _subject('bpm', 'Business Process Management', 'BPM', const [
        BloqueHorario(
          dia: DiaSemana.lunes,
          horaInicio: '08:31',
          horaFin: '09:50',
          sala: 'A-101',
        ),
        BloqueHorario(
          dia: DiaSemana.miercoles,
          horaInicio: '10:01',
          horaFin: '11:20',
        ),
      ]),
      _subject('integracion', 'Integración de Plataformas', 'IPL', const [
        BloqueHorario(
          dia: DiaSemana.lunes,
          horaInicio: '10:01',
          horaFin: '11:20',
        ),
        BloqueHorario(
          dia: DiaSemana.jueves,
          horaInicio: '08:31',
          horaFin: '09:50',
        ),
      ]),
      _subject('ingles', 'Inglés Intermedio Alto', 'INI', const [
        BloqueHorario(
          dia: DiaSemana.lunes,
          horaInicio: '11:31',
          horaFin: '12:50',
        ),
        BloqueHorario(
          dia: DiaSemana.viernes,
          horaInicio: '08:31',
          horaFin: '09:50',
        ),
      ]),
      _subject('datos', 'Big Data', 'BIY', const [
        BloqueHorario(
          dia: DiaSemana.martes,
          horaInicio: '08:31',
          horaFin: '09:50',
        ),
        BloqueHorario(
          dia: DiaSemana.jueves,
          horaInicio: '10:01',
          horaFin: '11:20',
        ),
      ]),
      _subject('etica', 'Ética Profesional', 'ETI', const [
        BloqueHorario(
          dia: DiaSemana.martes,
          horaInicio: '11:31',
          horaFin: '12:50',
        ),
      ]),
      _subject('proyecto', 'Proyecto Integrado', 'PRY', const [
        BloqueHorario(
          dia: DiaSemana.viernes,
          horaInicio: '10:01',
          horaFin: '11:20',
        ),
      ]),
    ];
    final periods = [
      PeriodoAcademico(
        id: 'period-2026-2',
        anio: 2026,
        tipo: TipoPeriodoAcademico.semestre,
        numero: 2,
        nombre: 'Segundo semestre 2026',
        fechaInicio: DateTime(2026, 8, 1),
        fechaFin: DateTime(2026, 12, 20),
      ),
    ];
    final sessions = [
      _session('specific-1', 'bpm', DateTime(2026, 11, 23), '08:31', '09:50'),
      _session(
        'specific-2',
        'integracion',
        DateTime(2026, 11, 23),
        '10:01',
        '11:20',
      ),
      _session(
        'specific-3',
        'ingles',
        DateTime(2026, 11, 23),
        '11:31',
        '12:50',
      ),
      _session(
        'specific-4',
        'proyecto',
        DateTime(2026, 11, 27),
        '10:01',
        '11:20',
      ),
    ];

    final result = builder.build(
      subjects: subjects,
      periods: periods,
      sessions: sessions,
      now: DateTime(2026, 11, 23, 7),
    );

    expect(result['exito'], isTrue);
    expect(result['estado'], 'horario_disponible');
    expect(result['sinDatos'], isFalse);
    expect(result['cantidadBloquesSemanales'], 10);
    expect(result['cantidadSesionesConFecha'], 4);
    expect(
      result['clasesSemanales'],
      contains(containsPair('asignatura', 'Business Process Management')),
    );
    final weekly = result['clasesSemanales']! as List;
    final bpmMonday = weekly.cast<Map>().firstWhere(
      (item) =>
          item['sigla'] == 'BPM' &&
          item['dia'] == 'lunes' &&
          item['horaInicio'] == '08:31',
    );
    expect(bpmMonday['horaFin'], '09:50');
    expect(bpmMonday['periodo'], 'Segundo semestre 2026');
  });

  test('distingue ausencia real con una respuesta exitosa explícita', () {
    final result = builder.build(
      subjects: const [],
      periods: const [],
      sessions: const [],
      now: DateTime(2026, 11, 23),
    );

    expect(result['exito'], isTrue);
    expect(result['sinDatos'], isTrue);
    expect(result['estado'], 'sin_horario_registrado');
  });
}

Asignatura _subject(
  String id,
  String name,
  String code,
  List<BloqueHorario> schedule,
) => Asignatura(
  id: id,
  nombre: name,
  sigla: code,
  periodoAcademicoId: 'period-2026-2',
  horario: schedule,
  estado: EstadoAsignatura.enCurso,
  origen: OrigenAsignatura.horario,
);

SesionClase _session(
  String id,
  String subjectId,
  DateTime date,
  String start,
  String end,
) => SesionClase(
  id: id,
  asignaturaId: subjectId,
  periodoAcademicoId: 'period-2026-2',
  fecha: date,
  horaInicio: start,
  horaFin: end,
  origen: OrigenSesionClase.horario,
);
