enum TipoNotificacionApp { tarea, evaluacion, clase, recordatorio, sistema }

enum GrupoNotificacionApp { reciente, anterior }

class NotificacionApp {
  const NotificacionApp({
    required this.id,
    required this.tipo,
    required this.grupo,
    required this.titulo,
    required this.mensaje,
    required this.fechaEvento,
    this.horaEvento,
    this.referenciaId,
    this.asignaturaId,
    this.bloqueIndex,
    this.leida = false,
    this.ocultada = false,
  });

  /// ID estable que luego usaremos para guardar leído/oculto en Firestore.
  final String id;

  final TipoNotificacionApp tipo;
  final GrupoNotificacionApp grupo;

  final String titulo;
  final String mensaje;

  /// Fecha académica a la que pertenece la notificación.
  final DateTime fechaEvento;

  /// Hora interna HH:mm cuando corresponde.
  final String? horaEvento;

  /// ID de la tarea/evaluación/asignatura que originó el aviso.
  final String? referenciaId;

  /// Útil para abrir directamente la asignatura relacionada.
  final String? asignaturaId;

  /// Solo se usa para una clase concreta del horario.
  final int? bloqueIndex;

  /// Estos dos estados se completarán en el siguiente paso
  /// desde Firestore, por usuario.
  final bool leida;
  final bool ocultada;

  DateTime get momentoOrden {
    final String hora = horaEvento?.trim() ?? '';

    if (hora.isEmpty) {
      return DateTime(
        fechaEvento.year,
        fechaEvento.month,
        fechaEvento.day,
        23,
        59,
      );
    }

    final List<String> partes = hora.split(':');

    if (partes.length != 2) {
      return DateTime(
        fechaEvento.year,
        fechaEvento.month,
        fechaEvento.day,
        23,
        59,
      );
    }

    final int horas = int.tryParse(partes[0]) ?? 23;
    final int minutos = int.tryParse(partes[1]) ?? 59;

    return DateTime(
      fechaEvento.year,
      fechaEvento.month,
      fechaEvento.day,
      horas,
      minutos,
    );
  }

  NotificacionApp copyWith({
    TipoNotificacionApp? tipo,
    GrupoNotificacionApp? grupo,
    String? titulo,
    String? mensaje,
    DateTime? fechaEvento,
    String? horaEvento,
    String? referenciaId,
    String? asignaturaId,
    int? bloqueIndex,
    bool? leida,
    bool? ocultada,
  }) {
    return NotificacionApp(
      id: id,
      tipo: tipo ?? this.tipo,
      grupo: grupo ?? this.grupo,
      titulo: titulo ?? this.titulo,
      mensaje: mensaje ?? this.mensaje,
      fechaEvento: fechaEvento ?? this.fechaEvento,
      horaEvento: horaEvento ?? this.horaEvento,
      referenciaId: referenciaId ?? this.referenciaId,
      asignaturaId: asignaturaId ?? this.asignaturaId,
      bloqueIndex: bloqueIndex ?? this.bloqueIndex,
      leida: leida ?? this.leida,
      ocultada: ocultada ?? this.ocultada,
    );
  }
}
