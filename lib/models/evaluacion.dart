import 'package:cloud_firestore/cloud_firestore.dart';

enum TipoEvaluacion { prueba, examen, control, quiz, presentacion, otro }

extension TipoEvaluacionFirestore on TipoEvaluacion {
  String get firestoreValue {
    switch (this) {
      case TipoEvaluacion.prueba:
        return 'prueba';

      case TipoEvaluacion.examen:
        return 'examen';

      case TipoEvaluacion.control:
        return 'control';

      case TipoEvaluacion.quiz:
        return 'quiz';

      case TipoEvaluacion.presentacion:
        return 'presentacion';

      case TipoEvaluacion.otro:
        return 'otro';
    }
  }

  static TipoEvaluacion fromFirestore(String? value) {
    switch (value) {
      case 'examen':
        return TipoEvaluacion.examen;

      case 'control':
        return TipoEvaluacion.control;

      case 'quiz':
        return TipoEvaluacion.quiz;

      case 'presentacion':
        return TipoEvaluacion.presentacion;

      case 'otro':
        return TipoEvaluacion.otro;

      case 'prueba':
      default:
        return TipoEvaluacion.prueba;
    }
  }
}

class Evaluacion {
  const Evaluacion({
    required this.id,
    required this.titulo,
    required this.asignaturaId,
    required this.tipo,
    required this.fecha,
    required this.creadaEn,
    required this.actualizadaEn,
    this.descripcion,
    this.hora,
    this.ponderacion,
  });

  final String id;

  final String titulo;

  final String asignaturaId;

  final TipoEvaluacion tipo;

  /// Día de la evaluación.
  final DateTime fecha;

  /// Hora interna siempre HH:mm.
  final String? hora;

  final String? descripcion;

  /// Porcentaje entre 0 y 100.
  ///
  /// Ejemplo:
  /// 25 = 25%
  final double? ponderacion;

  final DateTime creadaEn;

  final DateTime actualizadaEn;

  bool get tieneHora => hora?.trim().isNotEmpty == true;

  bool get tieneDescripcion => descripcion?.trim().isNotEmpty == true;

  bool get tienePonderacion => ponderacion != null;

  Evaluacion copyWith({
    String? titulo,
    String? asignaturaId,
    TipoEvaluacion? tipo,
    DateTime? fecha,
    String? hora,
    String? descripcion,
    double? ponderacion,
    DateTime? actualizadaEn,
    bool limpiarHora = false,
    bool limpiarDescripcion = false,
    bool limpiarPonderacion = false,
  }) {
    return Evaluacion(
      id: id,
      titulo: titulo ?? this.titulo,
      asignaturaId: asignaturaId ?? this.asignaturaId,
      tipo: tipo ?? this.tipo,
      fecha: fecha ?? this.fecha,
      hora: limpiarHora ? null : hora ?? this.hora,
      descripcion: limpiarDescripcion ? null : descripcion ?? this.descripcion,
      ponderacion: limpiarPonderacion ? null : ponderacion ?? this.ponderacion,
      creadaEn: creadaEn,
      actualizadaEn: actualizadaEn ?? this.actualizadaEn,
    );
  }

  factory Evaluacion.fromMap(String id, Map<String, dynamic> data) {
    final Timestamp? fechaTimestamp = data['fecha'] as Timestamp?;

    final Timestamp? creadaTimestamp = data['creadaEn'] as Timestamp?;

    final Timestamp? actualizadaTimestamp = data['actualizadaEn'] as Timestamp?;

    final DateTime ahora = DateTime.now();

    return Evaluacion(
      id: id,
      titulo: (data['titulo'] as String? ?? '').trim(),
      asignaturaId: (data['asignaturaId'] as String? ?? '').trim(),
      tipo: TipoEvaluacionFirestore.fromFirestore(data['tipo'] as String?),
      fecha: fechaTimestamp?.toDate() ?? ahora,
      hora: (data['hora'] as String?)?.trim(),
      descripcion: (data['descripcion'] as String?)?.trim(),
      ponderacion: (data['ponderacion'] as num?)?.toDouble(),
      creadaEn: creadaTimestamp?.toDate() ?? ahora,
      actualizadaEn: actualizadaTimestamp?.toDate() ?? ahora,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'titulo': titulo,
      'asignaturaId': asignaturaId,
      'tipo': tipo.firestoreValue,
      'fecha': Timestamp.fromDate(DateTime(fecha.year, fecha.month, fecha.day)),
      'hora': hora,
      'descripcion': descripcion,
      'ponderacion': ponderacion,
      'creadaEn': Timestamp.fromDate(creadaEn),
      'actualizadaEn': Timestamp.fromDate(actualizadaEn),
    };
  }
}
