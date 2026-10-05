enum PrioridadTarea { baja, media, alta }

enum EstadoTarea { pendiente, completada }

PrioridadTarea prioridadTareaDesdeValor(Object? value) {
  switch (value?.toString()) {
    case 'baja':
      return PrioridadTarea.baja;
    case 'media':
      return PrioridadTarea.media;
    case 'alta':
      return PrioridadTarea.alta;
    default:
      throw FormatException('Prioridad de tarea no válida: $value');
  }
}

EstadoTarea estadoTareaDesdeValor(Object? value) {
  switch (value?.toString()) {
    case 'pendiente':
      return EstadoTarea.pendiente;
    case 'completada':
      return EstadoTarea.completada;
    default:
      throw FormatException('Estado de tarea no válido: $value');
  }
}

extension PrioridadTareaPersistencia on PrioridadTarea {
  String get valorPersistencia {
    switch (this) {
      case PrioridadTarea.baja:
        return 'baja';
      case PrioridadTarea.media:
        return 'media';
      case PrioridadTarea.alta:
        return 'alta';
    }
  }
}

extension EstadoTareaPersistencia on EstadoTarea {
  String get valorPersistencia {
    switch (this) {
      case EstadoTarea.pendiente:
        return 'pendiente';
      case EstadoTarea.completada:
        return 'completada';
    }
  }
}

class Tarea {
  const Tarea({
    required this.id,
    required this.titulo,
    required this.prioridad,
    required this.estado,
    required this.creadaEn,
    required this.actualizadaEn,
    this.descripcion,
    this.asignaturaId,
    this.fechaEntrega,
    this.horaEntrega,
    this.completadaEn,
  });

  final String id;
  final String titulo;
  final String? descripcion;

  /// ID de la asignatura del mismo usuario.
  ///
  /// Puede ser null para tareas generales.
  final String? asignaturaId;

  final PrioridadTarea prioridad;
  final EstadoTarea estado;

  /// Día de entrega local, sin semántica de zona horaria.
  final DateTime? fechaEntrega;

  /// Hora opcional en formato interno HH:mm.
  final String? horaEntrega;

  final DateTime creadaEn;
  final DateTime actualizadaEn;
  final DateTime? completadaEn;

  bool get completada => estado == EstadoTarea.completada;
  bool get pendiente => estado == EstadoTarea.pendiente;
  bool get tieneFecha => fechaEntrega != null;
  bool get tieneHora => horaEntrega?.trim().isNotEmpty == true;
  bool get tieneAsignatura => asignaturaId?.trim().isNotEmpty == true;

  Tarea copyWith({
    String? id,
    String? titulo,
    String? descripcion,
    bool limpiarDescripcion = false,
    String? asignaturaId,
    bool limpiarAsignatura = false,
    PrioridadTarea? prioridad,
    EstadoTarea? estado,
    DateTime? fechaEntrega,
    bool limpiarFechaEntrega = false,
    String? horaEntrega,
    bool limpiarHoraEntrega = false,
    DateTime? creadaEn,
    DateTime? actualizadaEn,
    DateTime? completadaEn,
    bool limpiarCompletadaEn = false,
  }) {
    return Tarea(
      id: id ?? this.id,
      titulo: titulo ?? this.titulo,
      descripcion: limpiarDescripcion ? null : descripcion ?? this.descripcion,
      asignaturaId: limpiarAsignatura
          ? null
          : asignaturaId ?? this.asignaturaId,
      prioridad: prioridad ?? this.prioridad,
      estado: estado ?? this.estado,
      fechaEntrega: limpiarFechaEntrega
          ? null
          : fechaEntrega ?? this.fechaEntrega,
      horaEntrega: limpiarHoraEntrega ? null : horaEntrega ?? this.horaEntrega,
      creadaEn: creadaEn ?? this.creadaEn,
      actualizadaEn: actualizadaEn ?? this.actualizadaEn,
      completadaEn: limpiarCompletadaEn
          ? null
          : completadaEn ?? this.completadaEn,
    );
  }
}
