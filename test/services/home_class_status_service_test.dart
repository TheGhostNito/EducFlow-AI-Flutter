import 'package:eduflow_ai/models/asignatura.dart';
import 'package:eduflow_ai/services/home_class_status_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const HomeClassStatusService service = HomeClassStatusService();
  final DateTime monday = DateTime(2026, 9, 7);

  Asignatura subject(
    String id,
    String name,
    String start,
    String end, {
    String? room,
    String? blockRoom,
  }) {
    return Asignatura(
      id: id,
      nombre: name,
      estado: EstadoAsignatura.enCurso,
      origen: OrigenAsignatura.horario,
      sala: room,
      horario: [
        BloqueHorario(
          dia: DiaSemana.lunes,
          horaInicio: start,
          horaFin: end,
          sala: blockRoom,
        ),
      ],
    );
  }

  List<HomeClassEntry> mondayClasses() {
    return service.classesForDay(
      [
        subject('a', 'Programación', '08:30', '10:00', room: 'Sala X'),
        subject(
          'b',
          'Base de Datos',
          '11:00',
          '12:30',
          room: 'Sala general',
          blockRoom: 'Laboratorio 2',
        ),
        subject('c', 'Redes', '14:00', '15:30'),
      ],
      date: monday,
      missingRoomLabel: 'Sin sala',
      missingTeacherLabel: 'Sin profesor',
    );
  }

  test('minutos antes de la primera clase muestra solamente la próxima', () {
    final HomeClassStatus status = service.resolve(
      mondayClasses(),
      now: DateTime(2026, 9, 7, 8, 25),
    );

    expect(status.currentClass, isNull);
    expect(status.nextClass?.nombre, 'Programación');
  });

  test('a la hora exacta de inicio la clase queda en curso', () {
    final HomeClassStatus status = service.resolve(
      mondayClasses(),
      now: DateTime(2026, 9, 7, 8, 30),
    );

    expect(status.currentClass?.nombre, 'Programación');
    expect(status.nextClass?.nombre, 'Base de Datos');
  });

  test(
    'minutos después del inicio mantiene la clase en curso y la próxima',
    () {
      final HomeClassStatus status = service.resolve(
        mondayClasses(),
        now: DateTime(2026, 9, 7, 8, 34),
      );

      expect(status.currentClass?.nombre, 'Programación');
      expect(status.nextClass?.nombre, 'Base de Datos');
    },
  );

  test('un minuto antes del término mantiene la clase en curso', () {
    final HomeClassStatus status = service.resolve(
      mondayClasses(),
      now: DateTime(2026, 9, 7, 9, 59),
    );

    expect(status.currentClass?.nombre, 'Programación');
  });

  test('a la hora exacta de término deja solamente la próxima clase', () {
    final HomeClassStatus status = service.resolve(
      mondayClasses(),
      now: DateTime(2026, 9, 7, 10),
    );

    expect(status.currentClass, isNull);
    expect(status.nextClass?.nombre, 'Base de Datos');
  });

  test('en la ventana entre clases no adelanta el estado en curso', () {
    final HomeClassStatus status = service.resolve(
      mondayClasses(),
      now: DateTime(2026, 9, 7, 10, 45),
    );

    expect(status.currentClass, isNull);
    expect(status.nextClass?.nombre, 'Base de Datos');
  });

  test('a la hora exacta de inicio la segunda clase pasa a en curso', () {
    final HomeClassStatus status = service.resolve(
      mondayClasses(),
      now: DateTime(2026, 9, 7, 11),
    );

    expect(status.currentClass?.nombre, 'Base de Datos');
    expect(status.nextClass?.nombre, 'Redes');
  });

  test('durante la última clase no existe próxima clase', () {
    final HomeClassStatus status = service.resolve(
      mondayClasses(),
      now: DateTime(2026, 9, 7, 14, 30),
    );

    expect(status.currentClass?.nombre, 'Redes');
    expect(status.nextClass, isNull);
  });

  test('un día sin clases no tiene clase actual ni próxima', () {
    final List<HomeClassEntry> sundayClasses = service.classesForDay(
      [subject('a', 'Programación', '08:30', '10:00')],
      date: DateTime(2026, 9, 13),
      missingRoomLabel: 'Sin sala',
      missingTeacherLabel: 'Sin profesor',
    );
    final HomeClassStatus status = service.resolve(
      sundayClasses,
      now: DateTime(2026, 9, 13, 9),
    );

    expect(sundayClasses, isEmpty);
    expect(status.currentClass, isNull);
    expect(status.nextClass, isNull);
  });

  test('una clase sin sala conserva el texto de dato ausente', () {
    final HomeClassEntry classWithoutRoom = mondayClasses().singleWhere(
      (entry) => entry.nombre == 'Redes',
    );

    expect(classWithoutRoom.sala, 'Sin sala');
  });

  test('al regenerar las clases actualiza los sustitutos según el idioma', () {
    final List<Asignatura> subjects = [
      subject('sin-datos', 'Redes', '14:00', '15:30'),
    ];
    final HomeClassEntry spanish = service
        .classesForDay(
          subjects,
          date: monday,
          missingRoomLabel: 'Sin sala',
          missingTeacherLabel: 'Sin profesor',
        )
        .single;
    final HomeClassEntry english = service
        .classesForDay(
          subjects,
          date: monday,
          missingRoomLabel: 'No room',
          missingTeacherLabel: 'No teacher',
        )
        .single;

    expect((spanish.sala, spanish.profesor), ('Sin sala', 'Sin profesor'));
    expect((english.sala, english.profesor), ('No room', 'No teacher'));
  });

  test('la sala del bloque tiene prioridad sobre la sala de la asignatura', () {
    final HomeClassEntry databaseClass = mondayClasses().singleWhere(
      (entry) => entry.nombre == 'Base de Datos',
    );

    expect(databaseClass.sala, 'Laboratorio 2');
  });
}
