enum OrigenSesionClase { manual, horario }

class SesionClase {
  SesionClase({
    required this.id,
    required this.asignaturaId,
    required this.periodoAcademicoId,
    required DateTime fecha,
    required this.horaInicio,
    required this.horaFin,
    this.sala,
    this.origen = OrigenSesionClase.manual,
  }) : fecha = DateTime(fecha.year, fecha.month, fecha.day) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'La sesión debe tener un ID.');
    }
    if (asignaturaId.trim().isEmpty) {
      throw ArgumentError.value(
        asignaturaId,
        'asignaturaId',
        'La sesión debe pertenecer a una asignatura.',
      );
    }
    if (periodoAcademicoId.trim().isEmpty) {
      throw ArgumentError.value(
        periodoAcademicoId,
        'periodoAcademicoId',
        'La sesión debe pertenecer a un período.',
      );
    }

    final inicio = horaEnMinutos(horaInicio);
    final fin = horaEnMinutos(horaFin);
    if (inicio == null || fin == null || fin <= inicio) {
      throw ArgumentError('La sesión debe tener un rango horario válido.');
    }
  }

  final String id;
  final String asignaturaId;
  final String periodoAcademicoId;
  final DateTime fecha;
  final String horaInicio;
  final String horaFin;
  final String? sala;
  final OrigenSesionClase origen;

  static int? horaEnMinutos(String hora) {
    final partes = hora.trim().split(':');
    if (partes.length != 2) return null;

    final horas = int.tryParse(partes[0]);
    final minutos = int.tryParse(partes[1]);
    if (horas == null ||
        minutos == null ||
        horas < 0 ||
        horas > 23 ||
        minutos < 0 ||
        minutos > 59) {
      return null;
    }
    return (horas * 60) + minutos;
  }
}
