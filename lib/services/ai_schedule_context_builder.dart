import '../models/asignatura.dart';
import '../models/periodo_academico.dart';
import '../models/sesion_clase.dart';

class AiScheduleContextBuilder {
  const AiScheduleContextBuilder();

  Map<String, Object?> build({
    required List<Asignatura> subjects,
    required List<PeriodoAcademico> periods,
    required List<SesionClase> sessions,
    required DateTime now,
  }) {
    final periodsById = {for (final period in periods) period.id: period};
    final subjectsById = {for (final subject in subjects) subject.id: subject};
    final weeklyClasses = <Map<String, Object?>>[];

    for (final subject in subjects) {
      final period = periodsById[subject.periodoAcademicoId];
      if (subject.periodoAcademicoId?.trim().isNotEmpty == true &&
          period == null) {
        continue;
      }
      for (final block in subject.horario) {
        final blockRoom = block.sala?.trim() ?? '';
        final subjectRoom = subject.sala?.trim() ?? '';
        weeklyClasses.add({
          'asignatura': subject.nombre,
          'sigla': _nullable(subject.sigla),
          'dia': block.dia.valorFirestore,
          'horaInicio': block.horaInicio,
          'horaFin': block.horaFin,
          'sala': blockRoom.isNotEmpty
              ? blockRoom
              : subjectRoom.isNotEmpty
              ? subjectRoom
              : null,
          'profesor': _nullable(subject.profesor),
          'seccion': _nullable(subject.seccion),
          'periodo': period?.nombre,
          'fechaInicioPeriodo': _dateNullable(period?.fechaInicio),
          'fechaFinPeriodo': _dateNullable(period?.fechaFin),
        });
      }
    }

    weeklyClasses.sort((a, b) {
      final day = _dayOrder(a['dia']?.toString() ?? '')
          .compareTo(_dayOrder(b['dia']?.toString() ?? ''));
      if (day != 0) return day;
      return (a['horaInicio']?.toString() ?? '').compareTo(
        b['horaInicio']?.toString() ?? '',
      );
    });

    final windowStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 1));
    final windowEnd = windowStart.add(const Duration(days: 61));
    final datedSessions =
        sessions
            .where(
              (session) =>
                  !session.fecha.isBefore(windowStart) &&
                  session.fecha.isBefore(windowEnd),
            )
            .map((session) {
              final subject = subjectsById[session.asignaturaId];
              final period = periodsById[session.periodoAcademicoId];
              return <String, Object?>{
                'asignatura': subject?.nombre ?? 'Asignatura no disponible',
                'sigla': _nullable(subject?.sigla),
                'fecha': _date(session.fecha),
                'horaInicio': session.horaInicio,
                'horaFin': session.horaFin,
                'sala': _nullable(session.sala ?? subject?.sala),
                'periodo': period?.nombre,
              };
            })
            .toList()
          ..sort((a, b) {
            final date = (a['fecha']?.toString() ?? '').compareTo(
              b['fecha']?.toString() ?? '',
            );
            if (date != 0) return date;
            return (a['horaInicio']?.toString() ?? '').compareTo(
              b['horaInicio']?.toString() ?? '',
            );
          });

    return {
      'exito': true,
      'estado': weeklyClasses.isEmpty && datedSessions.isEmpty
          ? 'sin_horario_registrado'
          : 'horario_disponible',
      'sinDatos': weeklyClasses.isEmpty && datedSessions.isEmpty,
      'fechaActual':
          '${_date(now)}T'
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}',
      'cantidadBloquesSemanales': weeklyClasses.length,
      'clasesSemanales': weeklyClasses,
      'cantidadSesionesConFecha': datedSessions.length,
      'sesionesConFechaProximos60Dias': datedSessions,
    };
  }

  static String? _nullable(String? value) {
    final clean = value?.trim() ?? '';
    return clean.isEmpty ? null : clean;
  }

  static String? _dateNullable(DateTime? value) =>
      value == null ? null : _date(value);

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static int _dayOrder(String value) => switch (value) {
    'lunes' => 1,
    'martes' => 2,
    'miercoles' => 3,
    'jueves' => 4,
    'viernes' => 5,
    'sabado' => 6,
    _ => 7,
  };
}
