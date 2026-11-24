import 'asignatura.dart';
import 'periodo_academico.dart';

class HorarioDocumentoOriginal {
  const HorarioDocumentoOriginal({
    required this.path,
    required this.nombre,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String path;
  final String nombre;
  final String mimeType;
  final int sizeBytes;
}

class HorarioImportacionSesion {
  const HorarioImportacionSesion({
    required this.fecha,
    required this.horaInicio,
    required this.horaFin,
    this.sala,
  });

  final DateTime fecha;
  final String horaInicio;
  final String horaFin;
  final String? sala;
}

class HorarioImportacionAsignatura {
  const HorarioImportacionAsignatura({
    required this.asignatura,
    required this.sesiones,
  });

  final Asignatura asignatura;
  final List<HorarioImportacionSesion> sesiones;
}

class HorarioImportacionPropuesta {
  const HorarioImportacionPropuesta({
    required this.documentHash,
    required this.nombreDocumento,
    required this.periodo,
    required this.asignaturas,
    this.documentoOriginal,
  });

  final String documentHash;
  final String nombreDocumento;
  final PeriodoAcademico periodo;
  final List<HorarioImportacionAsignatura> asignaturas;
  final HorarioDocumentoOriginal? documentoOriginal;

  int get bloques => asignaturas.fold(
    0,
    (total, item) => total + item.asignatura.horario.length,
  );

  int get sesiones =>
      asignaturas.fold(0, (total, item) => total + item.sesiones.length);
}

class HorarioImportacionResultado {
  const HorarioImportacionResultado({
    required this.importacionId,
    required this.periodoAcademicoId,
    required this.asignaturas,
    required this.bloques,
    required this.sesiones,
    required this.yaExistia,
  });

  final String importacionId;
  final String periodoAcademicoId;
  final int asignaturas;
  final int bloques;
  final int sesiones;
  final bool yaExistia;
}

class HorarioImportacionRegistro {
  const HorarioImportacionRegistro({
    required this.id,
    required this.documentHash,
    required this.nombreDocumento,
    required this.anio,
    required this.numeroPeriodo,
    required this.periodoAcademicoId,
    required this.asignaturas,
    required this.bloques,
    required this.sesiones,
    required this.creadaEn,
    this.documentoOriginal,
  });

  final String id;
  final String documentHash;
  final String nombreDocumento;
  final int anio;
  final int numeroPeriodo;
  final String periodoAcademicoId;
  final int asignaturas;
  final int bloques;
  final int sesiones;
  final DateTime? creadaEn;
  final HorarioDocumentoOriginal? documentoOriginal;
}

class HorarioImportacionEliminada {
  const HorarioImportacionEliminada({
    required this.importacionId,
    required this.asignaturasEliminadas,
    required this.periodoEliminado,
    this.documentoPath,
  });

  final String importacionId;
  final int asignaturasEliminadas;
  final bool periodoEliminado;
  final String? documentoPath;
}
