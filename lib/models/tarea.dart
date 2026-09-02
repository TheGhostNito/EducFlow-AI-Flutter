import 'package:cloud_firestore/cloud_firestore.dart';

enum PrioridadTarea { baja, media, alta }

enum EstadoTarea { pendiente, completada }

// ===========================================================
// CONVERSIÓN ENUMS
// ===========================================================

PrioridadTarea prioridadTareaDesdeFirestore(dynamic value) {
  switch (value?.toString()) {
    case 'baja':
      return PrioridadTarea.baja;

    case 'alta':
      return PrioridadTarea.alta;

    case 'media':
    default:
      return PrioridadTarea.media;
  }
}

EstadoTarea estadoTareaDesdeFirestore(dynamic value) {
  switch (value?.toString()) {
    case 'completada':
      return EstadoTarea.completada;

    case 'pendiente':
    default:
      return EstadoTarea.pendiente;
  }
}

extension PrioridadTareaFirestore on PrioridadTarea {
  String get valorFirestore {
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

extension EstadoTareaFirestore on EstadoTarea {
  String get valorFirestore {
    switch (this) {
      case EstadoTarea.pendiente:
        return 'pendiente';

      case EstadoTarea.completada:
        return 'completada';
    }
  }
}

// ===========================================================
// HELPERS
// ===========================================================

DateTime? _dateTimeNullable(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is Timestamp) {
    return value.toDate();
  }

  if (value is DateTime) {
    return value;
  }

  if (value is String) {
    return DateTime.tryParse(value);
  }

  return null;
}

// ===========================================================
// TAREA
// ===========================================================

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

  // =========================================================
  // DATOS PRINCIPALES
  // =========================================================

  final String titulo;

  final String? descripcion;

  /// ID de usuarios/{uid}/asignaturas/{id}.
  ///
  /// Puede ser null para tareas generales.
  final String? asignaturaId;

  final PrioridadTarea prioridad;

  final EstadoTarea estado;

  // =========================================================
  // ENTREGA
  // =========================================================

  /// Día de entrega.
  ///
  /// Se guarda como Timestamp en Firestore.
  /// Puede ser null si la tarea no tiene fecha límite.
  final DateTime? fechaEntrega;

  /// Hora opcional en formato interno HH:mm.
  ///
  /// Ejemplo:
  /// 14:30
  ///
  /// La visualización 12/24 h se realiza mediante
  /// TimeFormatService, igual que en Horario.
  final String? horaEntrega;

  // =========================================================
  // AUDITORÍA
  // =========================================================

  final DateTime creadaEn;

  final DateTime actualizadaEn;

  final DateTime? completadaEn;

  // =========================================================
  // DATOS DERIVADOS
  // =========================================================

  bool get completada => estado == EstadoTarea.completada;

  bool get pendiente => estado == EstadoTarea.pendiente;

  bool get tieneFecha => fechaEntrega != null;

  bool get tieneHora => horaEntrega?.trim().isNotEmpty == true;

  bool get tieneAsignatura => asignaturaId?.trim().isNotEmpty == true;

  // =========================================================
  // COPY WITH
  // =========================================================

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

  // =========================================================
  // FIRESTORE -> DART
  // =========================================================

  factory Tarea.fromMap({
    required String id,
    required Map<String, dynamic> data,
  }) {
    final DateTime ahora = DateTime.now();

    return Tarea(
      id: id,

      titulo: data['titulo']?.toString() ?? '',

      descripcion: data['descripcion']?.toString(),

      asignaturaId: data['asignaturaId']?.toString(),

      prioridad: prioridadTareaDesdeFirestore(data['prioridad']),

      estado: estadoTareaDesdeFirestore(data['estado']),

      fechaEntrega: _dateTimeNullable(data['fechaEntrega']),

      horaEntrega: data['horaEntrega']?.toString(),

      creadaEn: _dateTimeNullable(data['creadaEn']) ?? ahora,

      actualizadaEn: _dateTimeNullable(data['actualizadaEn']) ?? ahora,

      completadaEn: _dateTimeNullable(data['completadaEn']),
    );
  }

  // =========================================================
  // DART -> FIRESTORE
  // =========================================================

  Map<String, dynamic> toMap() {
    return {
      'titulo': titulo,
      'descripcion': descripcion,
      'asignaturaId': asignaturaId,
      'prioridad': prioridad.valorFirestore,
      'estado': estado.valorFirestore,
      'fechaEntrega': fechaEntrega == null
          ? null
          : Timestamp.fromDate(fechaEntrega!),
      'horaEntrega': horaEntrega,
      'creadaEn': Timestamp.fromDate(creadaEn),
      'actualizadaEn': Timestamp.fromDate(actualizadaEn),
      'completadaEn': completadaEn == null
          ? null
          : Timestamp.fromDate(completadaEn!),
    };
  }
}
