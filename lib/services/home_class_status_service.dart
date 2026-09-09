import '../models/asignatura.dart';

class HomeClassEntry {
  const HomeClassEntry({
    required this.asignaturaId,
    required this.nombre,
    required this.sala,
    required this.profesor,
    required this.horaInicio,
    required this.horaFin,
  });

  final String asignaturaId;
  final String nombre;
  final String sala;
  final String profesor;
  final String horaInicio;
  final String horaFin;
}

class HomeClassStatus {
  const HomeClassStatus({this.currentClass, this.nextClass});

  final HomeClassEntry? currentClass;
  final HomeClassEntry? nextClass;
}

class HomeClassStatusService {
  const HomeClassStatusService();

  List<HomeClassEntry> classesForDay(
    List<Asignatura> subjects, {
    required DateTime date,
    required String missingRoomLabel,
    required String missingTeacherLabel,
  }) {
    final DiaSemana? weekday = _weekday(date.weekday);
    if (weekday == null) return const [];

    final List<HomeClassEntry> classes = [];
    for (final Asignatura subject in subjects) {
      for (final BloqueHorario block in subject.horario) {
        if (block.dia != weekday) continue;

        final String blockRoom = block.sala?.trim() ?? '';
        final String subjectRoom = subject.sala?.trim() ?? '';
        final String teacher = subject.profesor?.trim() ?? '';

        classes.add(
          HomeClassEntry(
            asignaturaId: subject.id,
            nombre: subject.nombre,
            sala: blockRoom.isNotEmpty
                ? blockRoom
                : subjectRoom.isNotEmpty
                ? subjectRoom
                : missingRoomLabel,
            profesor: teacher.isNotEmpty ? teacher : missingTeacherLabel,
            horaInicio: block.horaInicio,
            horaFin: block.horaFin,
          ),
        );
      }
    }

    classes.sort((a, b) {
      final int aStart = _timeInMinutes(a.horaInicio) ?? 24 * 60;
      final int bStart = _timeInMinutes(b.horaInicio) ?? 24 * 60;
      return aStart.compareTo(bStart);
    });
    return classes;
  }

  HomeClassStatus resolve(
    List<HomeClassEntry> classes, {
    required DateTime now,
  }) {
    final int currentMinute = now.hour * 60 + now.minute;
    HomeClassEntry? currentClass;
    HomeClassEntry? nextClass;

    for (final HomeClassEntry entry in classes) {
      final int? start = _timeInMinutes(entry.horaInicio);
      final int? end = _timeInMinutes(entry.horaFin);
      if (start == null || end == null || end <= start) continue;

      if (currentClass == null &&
          start <= currentMinute &&
          currentMinute < end) {
        currentClass = entry;
      }

      if (nextClass == null && start > currentMinute) {
        nextClass = entry;
      }
    }

    return HomeClassStatus(currentClass: currentClass, nextClass: nextClass);
  }

  int? _timeInMinutes(String value) {
    final List<String> parts = value.trim().split(':');
    if (parts.length != 2) return null;
    final int? hour = int.tryParse(parts[0]);
    final int? minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }

  DiaSemana? _weekday(int weekday) {
    return switch (weekday) {
      DateTime.monday => DiaSemana.lunes,
      DateTime.tuesday => DiaSemana.martes,
      DateTime.wednesday => DiaSemana.miercoles,
      DateTime.thursday => DiaSemana.jueves,
      DateTime.friday => DiaSemana.viernes,
      DateTime.saturday => DiaSemana.sabado,
      _ => null,
    };
  }
}
