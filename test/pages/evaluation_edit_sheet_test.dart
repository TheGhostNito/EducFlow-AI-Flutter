import 'package:eduflow_ai/models/asignatura.dart';
import 'package:eduflow_ai/models/evaluacion.dart';
import 'package:eduflow_ai/pages/calendar/widgets/evaluation_edit_sheet.dart';
import 'package:eduflow_ai/widgets/academic_schedule_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('propone el mismo día o el siguiente bloque semanal', () {
    expect(
      suggestEvaluationDateForClassDay(DateTime(2026, 10, 6), DiaSemana.martes),
      DateTime(2026, 10, 6),
    );
    expect(
      suggestEvaluationDateForClassDay(DateTime(2026, 10, 8), DiaSemana.martes),
      DateTime(2026, 10, 13),
    );
    expect(
      suggestAcademicDateForDay(DateTime(2026, 12, 31), DiaSemana.martes),
      DateTime(2027, 1, 5),
    );
    expect(
      academicDateMatchesBlock(
        DateTime(2027, 1, 5),
        _subjectWithSchedule.horario[1],
      ),
      isTrue,
    );
    expect(
      academicDateMatchesBlock(
        DateTime(2027, 1, 6),
        _subjectWithSchedule.horario[1],
      ),
      isFalse,
    );
    expect(
      academicDateIsSelectable(
        DateTime(2026, 10, 6),
        _subjectWithSchedule.horario[1],
        notBefore: DateTime(2026, 10, 8),
      ),
      isFalse,
    );
  });

  testWidgets('mantiene la entrada manual si la asignatura no tiene horario', (
    tester,
  ) async {
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
          .widget<InkWell>(
            find.byKey(const ValueKey('evaluation-schedule-class')),
          )
          .onTap,
      isNull,
    );
    expect(find.byKey(const ValueKey('evaluation-date-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('evaluation-time-field')), findsOneWidget);
  });

  testWidgets('permite elegir entre varios bloques y propone fecha y hora', (
    tester,
  ) async {
    final DateTime initialDate = _futureInitialDate();
    final DateTime proposedDate = _nextTuesday(initialDate);
    await _openSheet(
      tester,
      subjects: const [_subjectWithSchedule],
      initialSubjectId: _subjectWithSchedule.id,
      initialDate: initialDate,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('evaluation-schedule-class')),
    );
    await tester.tap(find.byKey(const ValueKey('evaluation-schedule-class')));
    await tester.pumpAndSettle();

    expect(find.text('Lunes'), findsOneWidget);
    expect(find.text('Martes'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('evaluation-class-block-1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('evaluation-selected-class-block')),
      findsOneWidget,
    );
    expect(find.text(_dateLabel(proposedDate)), findsOneWidget);
    expect(find.textContaining('10:00'), findsWidgets);
    expect(find.textContaining('PV-308'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('evaluation-schedule-manual')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('evaluation-selected-class-block')),
      findsNothing,
    );
    expect(find.text(_dateLabel(proposedDate)), findsOneWidget);
    expect(
      tester
          .widget<InkWell>(find.byKey(const ValueKey('evaluation-date-field')))
          .onTap,
      isNotNull,
    );
  });

  testWidgets('cambiar de asignatura invalida el bloque seleccionado', (
    tester,
  ) async {
    await _openSheet(
      tester,
      subjects: const [_subjectWithSchedule, _subjectWithoutSchedule],
      initialSubjectId: _subjectWithSchedule.id,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('evaluation-schedule-class')),
    );
    await tester.tap(find.byKey(const ValueKey('evaluation-schedule-class')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('evaluation-class-block-0')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('evaluation-selected-class-block')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('evaluation-subject-field')),
    );
    await tester.tap(find.byKey(const ValueKey('evaluation-subject-field')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('evaluation-subject-subject-without-schedule')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('evaluation-selected-class-block')),
      findsNothing,
    );
    expect(
      find.textContaining('no tiene horarios registrados'),
      findsOneWidget,
    );
  });

  testWidgets('el calendario del bloque permite elegir el mismo día otro mes', (
    tester,
  ) async {
    final DateTime initialDate = _futureInitialDate();
    final DateTime proposedDate = _nextTuesday(initialDate);
    final DateTime dateInAnotherMonth = _nextTuesday(
      DateTime(proposedDate.year, proposedDate.month + 1),
    );
    await _openSheet(
      tester,
      subjects: const [_subjectWithSchedule],
      initialSubjectId: _subjectWithSchedule.id,
      initialDate: initialDate,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('evaluation-schedule-class')),
    );
    await tester.tap(find.byKey(const ValueKey('evaluation-schedule-class')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('evaluation-class-block-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('evaluation-date-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${dateInAnotherMonth.day}'));
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();

    expect(find.text(_dateLabel(dateInAnotherMonth)), findsOneWidget);
    expect(find.textContaining('10:00'), findsWidgets);
    expect(
      find.byKey(const ValueKey('evaluation-selected-class-block')),
      findsOneWidget,
    );
  });

  testWidgets('editar no reemplaza accidentalmente la fecha y hora guardadas', (
    tester,
  ) async {
    final DateTime savedDate = DateTime(2026, 10, 20);
    await _openSheet(
      tester,
      subjects: const [_subjectWithSchedule],
      evaluation: Evaluacion(
        id: 'evaluation',
        titulo: 'Evaluación existente',
        asignaturaId: 'subject-with-schedule',
        tipo: TipoEvaluacion.prueba,
        fecha: savedDate,
        hora: '14:00',
        creadaEn: savedDate,
        actualizadaEn: savedDate,
      ),
    );

    expect(find.text('20/10/2026'), findsOneWidget);
    expect(find.textContaining('2:00'), findsWidgets);
    expect(
      find.byKey(const ValueKey('evaluation-selected-class-block')),
      findsNothing,
    );
  });
}

const Asignatura _subjectWithoutSchedule = Asignatura(
  id: 'subject-without-schedule',
  nombre: 'Historia',
  estado: EstadoAsignatura.enCurso,
  origen: OrigenAsignatura.manual,
);

const Asignatura _subjectWithSchedule = Asignatura(
  id: 'subject-with-schedule',
  nombre: 'Matemática',
  estado: EstadoAsignatura.enCurso,
  origen: OrigenAsignatura.manual,
  horario: [
    BloqueHorario(dia: DiaSemana.lunes, horaInicio: '08:30', horaFin: '09:50'),
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
  DateTime? initialDate,
  Evaluacion? evaluation,
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
            onPressed: () => showEvaluationEditSheet(
              context: context,
              subjects: subjects,
              spanish: true,
              initialDate: initialDate ?? _futureInitialDate(),
              initialSubjectId: initialSubjectId,
              evaluation: evaluation,
            ),
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
