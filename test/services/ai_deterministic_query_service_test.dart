import 'dart:async';

import 'package:eduflow_ai/models/asignatura.dart';
import 'package:eduflow_ai/models/evaluacion.dart';
import 'package:eduflow_ai/models/tarea.dart';
import 'package:eduflow_ai/services/ai_deterministic_query_service.dart';
import 'package:eduflow_ai/services/ai_function_calling_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final subject = Asignatura(
    id: 'matematicas',
    nombre: 'Matemáticas',
    profesor: 'Ana Pérez',
    sala: 'B-12',
    estado: EstadoAsignatura.enCurso,
    origen: OrigenAsignatura.manual,
    horario: const [
      BloqueHorario(
        dia: DiaSemana.miercoles,
        horaInicio: '09:00',
        horaFin: '10:30',
      ),
    ],
  );
  final now = DateTime(2026, 10, 14, 8);

  AiDeterministicQueryService createService({
    List<Asignatura>? subjects,
    List<Evaluacion>? evaluations,
    List<Tarea>? tasks,
  }) {
    return AiDeterministicQueryService(
      loadSubjects: () async => subjects ?? [subject],
      loadEvaluations: () async => evaluations ?? const [],
      loadTasks: () async => tasks ?? const [],
      now: () => now,
    );
  }

  test('resuelve saludos localmente y deja preguntas complejas a Gemini', () {
    final service = createService();

    expect(
      service.classify('Hola, buenas tardes'),
      AiDeterministicQueryKind.greeting,
    );
    expect(
      service.classify('Planifica cómo estudiar para mis próximas pruebas'),
      AiDeterministicQueryKind.gemini,
    );
    expect(
      service.classify('Explícame qué es Big Data'),
      AiDeterministicQueryKind.gemini,
    );
  });

  test('una solicitud explícita de plan tiene prioridad sobre horario', () {
    final service = createService();

    expect(
      service.classify(
        'Hazme un plan de estudio para BPM durante esta semana, '
        'considerando mis horarios de clases. Quiero sesiones de repaso '
        'y ejercicios prácticos',
      ),
      AiDeterministicQueryKind.gemini,
    );
    expect(
      service.classify(
        'Modifica mi plan de estudio y cambia la sesión del miércoles',
      ),
      AiDeterministicQueryKind.gemini,
    );
  });

  test('enruta profesor y sala por sus formulaciones naturales', () async {
    final dataScience = Asignatura(
      id: 'ciencia-datos',
      nombre: 'Ciencia de Datos',
      profesor: 'María Soto',
      correoProfesor: 'maria.soto@duoc.cl',
      sala: 'C-204',
      estado: EstadoAsignatura.enCurso,
      origen: OrigenAsignatura.manual,
    );
    final service = createService(subjects: [subject, dataScience]);

    expect(
      service.classify('¿Qué profesor me hace Ciencia de Datos?'),
      AiDeterministicQueryKind.teachers,
    );
    expect(
      service.classify('¿En qué sala tengo Ciencia de Datos?'),
      AiDeterministicQueryKind.rooms,
    );

    final teacher = await service.tryResolve(
      '¿Qué profesor me hace Ciencia de Datos?',
    );
    final room = await service.tryResolve(
      '¿En qué sala tengo Ciencia de Datos?',
    );

    expect(teacher, contains('Ciencia de Datos: María Soto'));
    expect(teacher, contains('Correo: maria.soto@duoc.cl'));
    expect(teacher, isNot(contains('Matemáticas')));
    expect(room, contains('Ciencia de Datos: C-204'));
    expect(room, isNot(contains('Matemáticas')));
  });

  test(
    'profesor sin correo y asignatura sin profesor no inventan datos',
    () async {
      final withoutEmail = Asignatura(
        id: 'bpm',
        nombre: 'BPM',
        profesor: 'Ana Pérez',
        estado: EstadoAsignatura.enCurso,
        origen: OrigenAsignatura.manual,
      );
      final withoutTeacher = Asignatura(
        id: 'fisica',
        nombre: 'Física',
        estado: EstadoAsignatura.enCurso,
        origen: OrigenAsignatura.manual,
      );

      final bpm = await createService(subjects: [withoutEmail])
          .tryResolve('¿Qué profesor tengo en BPM?');
      final physics = await createService(subjects: [withoutTeacher])
          .tryResolve('¿Qué profesor tengo en Física?');

      expect(bpm, contains('BPM: Ana Pérez'));
      expect(bpm, contains('No hay correo registrado para este profesor'));
      expect(physics, contains('Física: No hay profesor registrado'));
      expect(physics, isNot(contains('@')));
    },
  );

  test('clasifica una consulta natural de próximas evaluaciones', () {
    final service = createService();

    expect(
      service.classify('¿Cuáles son mis próximas evaluaciones?'),
      AiDeterministicQueryKind.upcomingEvaluations,
    );
  });

  test(
    'consulta de tareas exacta y variante de la captura usan ruta local',
    () async {
      final service = createService(
        tasks: [
          _task('tarea', 'Informe de laboratorio', DateTime(2026, 10, 16)),
        ],
      );
      for (final prompt in [
        '¿Qué tareas tengo pendientes?',
        'que tares tengo pendientes?',
      ]) {
        expect(service.classify(prompt), AiDeterministicQueryKind.pendingTasks);
        expect(
          await service.tryResolve(prompt),
          contains('Informe de laboratorio'),
        );
      }
    },
  );

  test('lista solo evaluaciones de hoy o futuras sin invocar Gemini', () async {
    final service = createService(
      evaluations: [
        _evaluation('anterior', 'Control anterior', DateTime(2026, 10, 13)),
        _evaluation('hoy', 'Prueba 1', DateTime(2026, 10, 14), hora: '11:30'),
        _evaluation('futura', 'Examen final', DateTime(2026, 11, 2)),
      ],
    );

    final response = await service.tryResolve(
      '¿Cuáles son mis próximas evaluaciones?',
    );

    expect(response, contains('Prueba 1'));
    expect(response, contains('14 de octubre de 2026'));
    expect(response, contains('Matemáticas'));
    expect(response, contains('Examen final'));
    expect(response, isNot(contains('Control anterior')));
  });

  test(
    'diferencia entre ausencia total y ausencia de próximos datos',
    () async {
      final empty = createService();
      final onlyPast = createService(
        evaluations: [
          _evaluation('anterior', 'Control anterior', DateTime(2026, 10, 13)),
        ],
      );

      expect(
        await empty.tryResolve('mis próximas evaluaciones'),
        'Todavía no tienes evaluaciones registradas.',
      );
      expect(
        await onlyPast.tryResolve('mis próximas evaluaciones'),
        'No tienes próximas evaluaciones registradas.',
      );
    },
  );

  test('consulta horarios recurrentes del día solicitado', () async {
    final service = createService();

    final response = await service.tryResolve('¿Qué clases tengo hoy?');

    expect(response, contains('Matemáticas'));
    expect(response, contains('09:00–10:30'));
    expect(response, contains('sala B-12'));
  });

  test(
    'la IA no presenta bloques con período sin resolver su vigencia',
    () async {
      final historica = Asignatura(
        id: 'hist-2024',
        nombre: 'Clase histórica 2024',
        periodoAcademicoId: '2024-1',
        estado: EstadoAsignatura.enCurso,
        origen: OrigenAsignatura.horario,
        horario: const [
          BloqueHorario(
            dia: DiaSemana.miercoles,
            horaInicio: '09:00',
            horaFin: '10:30',
          ),
        ],
      );
      final response = await createService(subjects: [historica])
          .tryResolve('¿Qué clases tengo hoy?');

      expect(response, isNot(contains('Clase histórica 2024')));
      expect(response, contains('No tienes clases registradas'));
    },
  );

  test(
    'asignaturas, profesores y salas de hoy usan solo bloques de hoy',
    () async {
      final math = Asignatura(
        id: 'mat',
        nombre: 'Matemáticas',
        profesor: 'Ana',
        sala: 'General',
        estado: EstadoAsignatura.enCurso,
        origen: OrigenAsignatura.manual,
        horario: const [
          BloqueHorario(
            dia: DiaSemana.martes,
            horaInicio: '09:00',
            horaFin: '10:00',
            sala: 'A-1',
          ),
          BloqueHorario(
            dia: DiaSemana.miercoles,
            horaInicio: '09:00',
            horaFin: '10:00',
            sala: 'B-2',
          ),
        ],
      );
      final history = Asignatura(
        id: 'hist',
        nombre: 'Historia',
        profesor: 'Luis',
        sala: 'C-3',
        estado: EstadoAsignatura.enCurso,
        origen: OrigenAsignatura.manual,
        horario: const [
          BloqueHorario(
            dia: DiaSemana.martes,
            horaInicio: '11:00',
            horaFin: '12:00',
          ),
        ],
      );
      final service = createService(subjects: [math, history]);
      final subjects = await service.tryResolve('¿Qué asignaturas tengo hoy?');
      final teachers = await service.tryResolve('¿Qué profesores tengo hoy?');
      final rooms = await service.tryResolve('¿En qué salas tengo clase hoy?');
      expect(subjects, contains('Matemáticas'));
      expect(subjects, isNot(contains('Historia')));
      expect(teachers, contains('Ana'));
      expect(teachers, isNot(contains('Luis')));
      expect(rooms, contains('B-2'));
      expect(rooms, isNot(contains('A-1')));
      expect(rooms, isNot(contains('General')));
      expect(rooms, isNot(contains('C-3')));
    },
  );

  test('hoy y mañana no incluyen evaluaciones de otros días', () async {
    final service = createService(
      evaluations: [
        _evaluation('hoy', 'Control hoy', DateTime(2026, 10, 14)),
        _evaluation('manana', 'Control mañana', DateTime(2026, 10, 15)),
        _evaluation('futura', 'Control futuro', DateTime(2026, 11, 15)),
      ],
    );
    final today = await service.tryResolve('¿Qué evaluaciones tengo hoy?');
    final tomorrow = await service.tryResolve(
      '¿Qué evaluaciones tengo mañana?',
    );
    expect(today, contains('Control hoy'));
    expect(today, isNot(contains('Control mañana')));
    expect(today, isNot(contains('Control futuro')));
    expect(tomorrow, contains('Control mañana'));
    expect(tomorrow, isNot(contains('Control hoy')));
  });

  test('esta semana, próxima semana y fecha exacta acotan tareas', () async {
    final service = createService(
      tasks: [
        _task('hoy', 'Entrega hoy', DateTime(2026, 10, 14)),
        _task('semana', 'Entrega viernes', DateTime(2026, 10, 16)),
        _task('proxima', 'Entrega próxima semana', DateTime(2026, 10, 20)),
        _task('lejana', 'Entrega futura', DateTime(2026, 11, 15)),
      ],
    );
    final week = await service.tryResolve('¿Qué tareas tengo esta semana?');
    final next = await service.tryResolve('¿Qué tareas tengo próxima semana?');
    final exact = await service.tryResolve('¿Qué tareas tengo el 20/10/2026?');
    expect(week, contains('Entrega hoy'));
    expect(week, contains('Entrega viernes'));
    expect(week, isNot(contains('Entrega próxima semana')));
    expect(week, isNot(contains('Entrega futura')));
    expect(next, contains('Entrega próxima semana'));
    expect(next, isNot(contains('Entrega viernes')));
    expect(exact, contains('Entrega próxima semana'));
    expect(exact, isNot(contains('Entrega hoy')));
  });

  test('próximas excluye eventos de hoy cuya hora ya pasó', () async {
    final service = createService(
      evaluations: [
        _evaluation(
          'pasada',
          'Prueba pasada',
          DateTime(2026, 10, 14),
          hora: '07:30',
        ),
        _evaluation(
          'futura',
          'Prueba futura',
          DateTime(2026, 10, 14),
          hora: '11:30',
        ),
      ],
    );
    final upcoming = await service.tryResolve('mis próximas evaluaciones');
    final today = await service.tryResolve('¿Qué evaluaciones tengo hoy?');
    expect(upcoming, isNot(contains('Prueba pasada')));
    expect(upcoming, contains('Prueba futura'));
    expect(today, contains('Prueba pasada'));
  });

  test('fecha inválida y período ambiguo derivan a Gemini', () {
    final service = createService();
    expect(
      service.classify('¿Qué evaluaciones tengo el 31/02/2026?'),
      AiDeterministicQueryKind.gemini,
    );
    expect(
      service.classify('¿Qué tareas tengo hoy y mañana?'),
      AiDeterministicQueryKind.gemini,
    );
    expect(
      service.classify('¿Qué tareas tengo entre el 14 y el 20?'),
      AiDeterministicQueryKind.gemini,
    );
    expect(
      service.classify('What assessments do I have on 11/12/2026?'),
      AiDeterministicQueryKind.gemini,
    );
  });

  test('asignatura inexistente no muestra profesores ajenos', () async {
    final service = createService();
    final response = await service.tryResolve('¿Qué profesor me hace Física?');
    final room = await service.tryResolve('¿En qué sala tengo Física?');
    final schedule = await service.tryResolve(
      '¿Qué horario tengo para Física?',
    );
    expect(response, contains('No encontré la asignatura'));
    expect(response, isNot(contains('Ana Pérez')));
    expect(room, contains('No encontré la asignatura'));
    expect(room, isNot(contains('B-12')));
    expect(schedule, contains('No encontré la asignatura'));
    expect(schedule, isNot(contains('Matemáticas')));
  });

  test('fecha escrita no se confunde con una asignatura', () async {
    final service = createService(
      tasks: [_task('t', 'Entrega exacta', DateTime(2026, 10, 20))],
    );
    final response = await service.tryResolve(
      '¿Qué tareas tengo para el 20 de octubre de 2026?',
    );
    expect(response, contains('Entrega exacta'));
    expect(response, isNot(contains('No encontré la asignatura')));
  });

  test(
    'asignaturas homónimas piden aclaración y sección precisa el filtro',
    () async {
      final first = Asignatura(
        id: 'mat-1',
        nombre: 'Matemáticas',
        profesor: 'Ana',
        seccion: '1',
        estado: EstadoAsignatura.enCurso,
        origen: OrigenAsignatura.manual,
      );
      final second = Asignatura(
        id: 'mat-2',
        nombre: 'Matemáticas',
        profesor: 'Luis',
        seccion: '2',
        estado: EstadoAsignatura.enCurso,
        origen: OrigenAsignatura.manual,
      );
      final service = createService(subjects: [first, second]);
      final ambiguous = await service.tryResolve(
        '¿Qué profesor tengo en Matemáticas?',
      );
      final precise = await service.tryResolve(
        '¿Qué profesor tengo en Matemáticas sección 2?',
      );
      expect(ambiguous, contains('varias asignaturas'));
      expect(ambiguous, isNot(contains('Matemáticas: Ana')));
      expect(precise, contains('Matemáticas: Luis'));
      expect(precise, isNot(contains('Matemáticas: Ana')));
    },
  );

  test('solicitud combinada responde tareas y evaluaciones', () async {
    final service = createService(
      tasks: [_task('t', 'Tarea de álgebra', DateTime(2026, 10, 15))],
      evaluations: [
        _evaluation('e', 'Control de álgebra', DateTime(2026, 10, 16)),
      ],
    );
    final response = await service.tryResolve(
      '¿Qué tareas y evaluaciones tengo esta semana?',
    );
    expect(
      service.classify('¿Qué tareas y evaluaciones tengo esta semana?'),
      AiDeterministicQueryKind.tasksAndEvaluations,
    );
    expect(response, contains('Tarea de álgebra'));
    expect(response, contains('Control de álgebra'));
  });

  test('mencionar dos asignaturas no reduce silenciosamente a una', () async {
    final physics = Asignatura(
      id: 'fisica',
      nombre: 'Física',
      profesor: 'Luis',
      estado: EstadoAsignatura.enCurso,
      origen: OrigenAsignatura.manual,
    );
    final service = createService(subjects: [subject, physics]);
    final answer = await service.tryResolve(
      '¿Qué profesores tengo en Matemáticas y Física?',
    );
    expect(answer, contains('varias asignaturas'));
    expect(answer, isNot(contains('Matemáticas: Ana Pérez')));
  });

  test('saludo inglés se responde en inglés', () async {
    final response = await createService().tryResolve('Hello');
    expect(response, startsWith('Hello!'));
  });

  test('consultas académicas locales en inglés mantienen el idioma', () async {
    final service = createService(
      evaluations: [_evaluation('e', 'Algebra exam', DateTime(2026, 10, 14))],
    );
    final assessments = await service.tryResolve(
      'What assessments do I have today?',
    );
    final teachers = await service.tryResolve('Who teaches Matemáticas?');
    final missing = await service.tryResolve('Who teaches Physics?');
    final schedule = await service.tryResolve('What classes do I have today?');
    expect(assessments, contains('Your assessments'));
    expect(assessments, contains('14 October 2026'));
    expect(teachers, contains('Registered teachers'));
    expect(missing, contains('could not find the subject'));
    expect(missing, isNot(contains('Ana Pérez')));
    expect(schedule, contains('Wednesday'));
  });

  test('timeout local se propaga sin convertirlo en respuesta', () async {
    final pending = Completer<List<Asignatura>>();
    final service = AiDeterministicQueryService(
      loadSubjects: () => pending.future,
      loadEvaluations: () async => const [],
      loadTasks: () async => const [],
      now: () => now,
      dataTimeout: const Duration(milliseconds: 20),
    );
    await expectLater(
      service.tryResolve('¿Cuáles son mis asignaturas?'),
      throwsA(isA<AiRequestTimeoutException>()),
    );
  });

  test('un fallo de datos se propaga para permitir reintento', () async {
    final service = AiDeterministicQueryService(
      loadSubjects: () => Future<List<Asignatura>>.error(
        StateError('detalle potencialmente sensible'),
      ),
      loadEvaluations: () async => const [],
      loadTasks: () async => const [],
      now: () => now,
    );

    await expectLater(
      service.tryResolve('¿Cuáles son mis asignaturas?'),
      throwsA(isA<AiLocalQueryException>()),
    );
    expect(await service.tryResolve('Hola'), contains('EducFlow AI'));
  });
}

Evaluacion _evaluation(String id, String title, DateTime date, {String? hora}) {
  return Evaluacion(
    id: id,
    titulo: title,
    asignaturaId: 'matematicas',
    tipo: TipoEvaluacion.prueba,
    fecha: date,
    hora: hora,
    creadaEn: date,
    actualizadaEn: date,
  );
}

Tarea _task(String id, String title, DateTime due) => Tarea(
  id: id,
  titulo: title,
  prioridad: PrioridadTarea.media,
  estado: EstadoTarea.pendiente,
  fechaEntrega: due,
  creadaEn: due,
  actualizadaEn: due,
);
