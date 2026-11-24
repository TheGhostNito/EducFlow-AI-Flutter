enum TipoPeriodoAcademico { semestre }

enum EstadoPeriodoAcademico { activo, historico }

class PeriodoAcademico {
  PeriodoAcademico({
    required this.id,
    required this.anio,
    required this.tipo,
    required this.numero,
    required this.nombre,
    DateTime? fechaInicio,
    DateTime? fechaFin,
    this.institucion,
    this.estado = EstadoPeriodoAcademico.activo,
  }) : fechaInicio = fechaInicio == null ? null : _soloFecha(fechaInicio),
       fechaFin = fechaFin == null ? null : _soloFecha(fechaFin) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'El período debe tener un ID.');
    }
    if (anio < 1) {
      throw ArgumentError.value(anio, 'anio', 'El año debe ser positivo.');
    }
    if (numero < 1) {
      throw ArgumentError.value(
        numero,
        'numero',
        'El número del período debe ser positivo.',
      );
    }
    if (nombre.trim().isEmpty) {
      throw ArgumentError.value(
        nombre,
        'nombre',
        'El período debe tener un nombre.',
      );
    }
    if (this.fechaInicio != null &&
        this.fechaFin != null &&
        this.fechaFin!.isBefore(this.fechaInicio!)) {
      throw ArgumentError('La fecha final no puede ser anterior a la inicial.');
    }
  }

  final String id;
  final int anio;
  final TipoPeriodoAcademico tipo;
  final int numero;
  final String nombre;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;
  final String? institucion;
  final EstadoPeriodoAcademico estado;

  bool get tieneFechasCompletas => fechaInicio != null && fechaFin != null;

  bool contiene(DateTime fecha) {
    final normalizada = _soloFecha(fecha);
    final inicio = fechaInicio;
    final fin = fechaFin;
    return (inicio == null || !normalizada.isBefore(inicio)) &&
        (fin == null || !normalizada.isAfter(fin));
  }

  bool seSuperponeCon(PeriodoAcademico otro) {
    final inicio = fechaInicio;
    final fin = fechaFin;
    final otroInicio = otro.fechaInicio;
    final otroFin = otro.fechaFin;
    if (inicio == null ||
        fin == null ||
        otroInicio == null ||
        otroFin == null) {
      return false;
    }
    return !fin.isBefore(otroInicio) && !otroFin.isBefore(inicio);
  }

  static DateTime _soloFecha(DateTime fecha) {
    return DateTime(fecha.year, fecha.month, fecha.day);
  }
}
