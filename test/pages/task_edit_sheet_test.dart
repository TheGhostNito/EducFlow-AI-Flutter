import 'package:eduflow_ai/models/asignatura.dart';
import 'package:eduflow_ai/models/tarea.dart';
import 'package:eduflow_ai/pages/tasks/widgets/task_edit_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tarea usa un bloque y guarda una fecha del mismo día otro mes', (
    tester,
  ) async {
    final DateTime initialDate = _futureInitialDate();
    final DateTime proposedDate = _nextTuesday(initialDate);
    final DateTime dateInAnotherMonth = _nextTuesday(
      DateTime(proposedDate.year, proposedDate.month + 1),
    );
    TaskEditResult? saved;
    await _openSheet(
      tester,
      subjects: const [_scheduledSubject],
      initialSubjectId: _scheduledSubject.id,
      initialDueDate: initialDate,
      onResult: (result) => saved = result,
    );

    await tester.enterText(find.byType(TextField).first, 'Informe final');
    await tester.ensureVisible(
      find.byKey(const ValueKey('task-schedule-class')),
    );
    await tester.tap(find.byKey(const ValueKey('task-schedule-class')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-class-block-1')));
    await tester.pumpAndSettle();

    expect(find.text(_dateLabel(proposedDate)), findsOneWidget);
    expect(find.textContaining('10:00'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('task-date-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${dateInAnotherMonth.day}'));
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();

    expect(find.text(_dateLabel(dateInAnotherMonth)), findsOneWidget);
    expect(
      find.byKey(const ValueKey('task-selected-class-block')),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Crear tarea'));
    await tester.tap(find.text('Crear tarea'));
    await tester.pumpAndSettle();

    expect(saved?.title, 'Informe final');
    expect(saved?.subjectId, _scheduledSubject.id);
    expect(saved?.dueDate, dateInAnotherMonth);
    expect(saved?.dueTime, '10:00');
  });

  testWidgets('tarea manual permite una fecha ajena al horario', (
    tester,
  ) async {
    final DateTime initialDate = _futureInitialDate();
    await _openSheet(
      tester,
      subjects: const [_scheduledSubject],
      initialSubjectId: _scheduledSubject.id,
      initialDueDate: initialDate,
    );

    await tester.ensureVisible(find.byKey(const ValueKey('task-date-field')));
    await tester.tap(find.byKey(const ValueKey('task-date-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('14'));
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();

    expect(
      find.text(_dateLabel(DateTime(initialDate.year, initialDate.month, 14))),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('task-selected-class-block')),
      findsNothing,
    );
  });

  testWidgets('editar una tarea no activa ni altera el horario por sí solo', (
    tester,
  ) async {
    final DateTime savedDate = DateTime(2026, 10, 21);
    await _openSheet(
      tester,
      subjects: const [_scheduledSubject],
      task: Tarea(
        id: 'task',
        titulo: 'Tarea existente',
        asignaturaId: 'scheduled-subject',
        prioridad: PrioridadTarea.media,
        estado: EstadoTarea.pendiente,
        fechaEntrega: savedDate,
        horaEntrega: '18:30',
        creadaEn: savedDate,
        actualizadaEn: savedDate,
      ),
    );

    expect(find.text('21/10/2026'), findsOneWidget);
    expect(find.textContaining('6:30'), findsWidgets);
    expect(
      find.byKey(const ValueKey('task-selected-class-block')),
      findsNothing,
    );
  });

  testWidgets('tarea sin bloques conserva el flujo manual', (tester) async {
    await _openSheet(
      tester,
      subjects: const [_subjectWithoutSchedule],
      initialSubjectId: _subjectWithoutSchedule.id,
    );

    expect(
      find.textContaining('no tiene horarios registrados'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<InkWell>(find.byKey(const ValueKey('task-schedule-class')))
          .onTap,
      isNull,
    );
  });

  testWidgets('sesión oculta y protege su identificador al editar', (
    tester,
  ) async {
    const marker = '[EDUFLOW_PLAN_ESTUDIO:plan-1:session-1]';
    TaskEditResult? saved;
    final date = DateTime(2026, 11, 24);
    await _openSheet(
      tester,
      subjects: const [_scheduledSubject],
      task: Tarea(
        id: 'study-session',
        titulo: 'Estudio: Repaso',
        descripcion: 'Actividad visible\n$marker',
        asignaturaId: _scheduledSubject.id,
        prioridad: PrioridadTarea.media,
        estado: EstadoTarea.pendiente,
        fechaEntrega: date,
        horaEntrega: '16:00',
        creadaEn: date,
        actualizadaEn: date,
      ),
      onResult: (result) => saved = result,
    );

    expect(find.text('Editar sesión de estudio'), findsOneWidget);
    expect(find.textContaining('EDUFLOW_PLAN_ESTUDIO'), findsNothing);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'Actividad corregida');
    await tester.ensureVisible(find.text('Guardar cambios'));
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    expect(saved?.description, 'Actividad corregida\n$marker');
  });

  testWidgets('cambiar la asignatura invalida el bloque de la tarea', (
    tester,
  ) async {
    await _openSheet(
      tester,
      subjects: const [_scheduledSubject, _subjectWithoutSchedule],
      initialSubjectId: _scheduledSubject.id,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('task-schedule-class')),
    );
    await tester.tap(find.byKey(const ValueKey('task-schedule-class')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-class-block-0')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('task-selected-class-block')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('task-subject-field')),
    );
    await tester.tap(find.byKey(const ValueKey('task-subject-field')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('task-subject-subject-without-schedule')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('task-selected-class-block')),
      findsNothing,
    );
    expect(
      find.textContaining('no tiene horarios registrados'),
      findsOneWidget,
    );
  });
}

const Asignatura _subjectWithoutSchedule = Asignatura(
  id: 'subject-without-schedule',
  nombre: 'Historia',
  estado: EstadoAsignatura.enCurso,
  origen: OrigenAsignatura.manual,
);

const Asignatura _scheduledSubject = Asignatura(
  id: 'scheduled-subject',
  nombre: 'Big Data',
  estado: EstadoAsignatura.enCurso,
  origen: OrigenAsignatura.manual,
  horario: [
    BloqueHorario(
      dia: DiaSemana.jueves,
      horaInicio: '11:30',
      horaFin: '13:50',
      sala: 'PV-210',
    ),
    BloqueHorario(
      dia: DiaSemana.martes,
      horaInicio: '10:00',
      horaFin: '11:20',
      sala: 'PV-308',
    ),
  ],
);

Future<void> _openSheet(
  WidgetTester tester, {
  required List<Asignatura> subjects,
  String? initialSubjectId,
  DateTime? initialDueDate,
  Tarea? task,
  ValueChanged<TaskEditResult?>? onResult,
}) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final TaskEditResult? result = await showTaskEditSheet(
                context: context,
                subjects: subjects,
                spanish: true,
                task: task,
                initialDueDate: initialDueDate ?? _futureInitialDate(),
                initialSubjectId: initialSubjectId,
              );
              onResult?.call(result);
            },
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

DateTime _futureInitialDate() {
  final DateTime now = DateTime.now();
  return DateTime(now.year, now.month + 2);
}

DateTime _nextTuesday(DateTime from) {
  return DateTime(
    from.year,
    from.month,
    from.day + (DateTime.tuesday - from.weekday + 7) % 7,
  );
}

String _dateLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';
