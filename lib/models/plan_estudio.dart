class SesionPlanEstudio {
  const SesionPlanEstudio({
    required this.id,
    required this.titulo,
    required this.actividad,
    required this.fecha,
    required this.horaInicio,
    required this.duracionMinutos,
  });

  final String id;
  final String titulo;
  final String actividad;
  final DateTime fecha;
  final String horaInicio;
  final int duracionMinutos;

  DateTime get inicio => DateTime(
    fecha.year,
    fecha.month,
    fecha.day,
    int.parse(horaInicio.substring(0, 2)),
    int.parse(horaInicio.substring(3, 5)),
  );

  DateTime get fin => inicio.add(Duration(minutes: duracionMinutos));

  Map<String, Object?> toJson() => {
    'id': id,
    'titulo': titulo,
    'actividad': actividad,
    'fecha': _fechaSql(fecha),
    'horaInicio': horaInicio,
    'duracionMinutos': duracionMinutos,
  };
}

class PlanEstudioPropuesto {
  const PlanEstudioPropuesto({
    required this.id,
    required this.titulo,
    required this.objetivo,
    required this.asignaturaId,
    required this.asignaturaNombre,
    required this.sesiones,
    required this.revision,
    this.evaluacionId,
  });

  final String id;
  final String titulo;
  final String objetivo;
  final String asignaturaId;
  final String asignaturaNombre;
  final String? evaluacionId;
  final List<SesionPlanEstudio> sesiones;
  final int revision;

  int get duracionTotalMinutos =>
      sesiones.fold<int>(0, (total, sesion) => total + sesion.duracionMinutos);

  Map<String, Object?> toJson() => {
    'id': id,
    'titulo': titulo,
    'objetivo': objetivo,
    'asignaturaId': asignaturaId,
    'asignaturaNombre': asignaturaNombre,
    if (evaluacionId != null) 'evaluacionId': evaluacionId,
    'revision': revision,
    'sesiones': sesiones.map((sesion) => sesion.toJson()).toList(),
  };
}

class ResultadoGuardadoPlanEstudio {
  const ResultadoGuardadoPlanEstudio({
    required this.creadas,
    required this.yaExistentes,
  });

  final int creadas;
  final int yaExistentes;

  int get total => creadas + yaExistentes;
}

String fechaPlanEstudioSql(DateTime fecha) => _fechaSql(fecha);

String _fechaSql(DateTime fecha) =>
    '${fecha.year.toString().padLeft(4, '0')}-'
    '${fecha.month.toString().padLeft(2, '0')}-'
    '${fecha.day.toString().padLeft(2, '0')}';
