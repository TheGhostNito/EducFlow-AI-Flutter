// =========================================================
// ESTADO DE LA ASIGNATURA
// =========================================================

enum EstadoAsignatura {
  registrada,
  pendiente,
  enCurso,
  aprobada,
  reprobada,
  convalidada,
}

extension EstadoAsignaturaExtension on EstadoAsignatura {
  String get valorFirestore {
    switch (this) {
      case EstadoAsignatura.registrada:
        return 'registrada';

      case EstadoAsignatura.pendiente:
        return 'pendiente';

      case EstadoAsignatura.enCurso:
        return 'en_curso';

      case EstadoAsignatura.aprobada:
        return 'aprobada';

      case EstadoAsignatura.reprobada:
        return 'reprobada';

      case EstadoAsignatura.convalidada:
        return 'convalidada';
    }
  }
}

EstadoAsignatura estadoAsignaturaDesdeFirestore(dynamic valor) {
  switch (valor?.toString()) {
    case 'pendiente':
      return EstadoAsignatura.pendiente;

    case 'en_curso':
      return EstadoAsignatura.enCurso;

    case 'aprobada':
      return EstadoAsignatura.aprobada;

    case 'reprobada':
      return EstadoAsignatura.reprobada;

    case 'convalidada':
      return EstadoAsignatura.convalidada;

    case 'registrada':
    default:
      return EstadoAsignatura.registrada;
  }
}

// =========================================================
// ORIGEN DE LA ASIGNATURA
// =========================================================

enum OrigenAsignatura { manual, malla, horario }

extension OrigenAsignaturaExtension on OrigenAsignatura {
  String get valorFirestore {
    switch (this) {
      case OrigenAsignatura.manual:
        return 'manual';

      case OrigenAsignatura.malla:
        return 'malla';

      case OrigenAsignatura.horario:
        return 'horario';
    }
  }
}

OrigenAsignatura origenAsignaturaDesdeFirestore(dynamic valor) {
  switch (valor?.toString()) {
    case 'malla':
      return OrigenAsignatura.malla;

    case 'horario':
      return OrigenAsignatura.horario;

    case 'manual':
    default:
      return OrigenAsignatura.manual;
  }
}

// =========================================================
// DÍAS DE LA SEMANA
// =========================================================

enum DiaSemana { lunes, martes, miercoles, jueves, viernes, sabado }

extension DiaSemanaExtension on DiaSemana {
  String get valorFirestore {
    switch (this) {
      case DiaSemana.lunes:
        return 'lunes';

      case DiaSemana.martes:
        return 'martes';

      case DiaSemana.miercoles:
        return 'miercoles';

      case DiaSemana.jueves:
        return 'jueves';

      case DiaSemana.viernes:
        return 'viernes';

      case DiaSemana.sabado:
        return 'sabado';
    }
  }
}

DiaSemana? diaSemanaDesdeFirestore(dynamic valor) {
  switch (valor?.toString()) {
    case 'lunes':
      return DiaSemana.lunes;

    case 'martes':
      return DiaSemana.martes;

    case 'miercoles':
      return DiaSemana.miercoles;

    case 'jueves':
      return DiaSemana.jueves;

    case 'viernes':
      return DiaSemana.viernes;

    case 'sabado':
      return DiaSemana.sabado;

    default:
      return null;
  }
}

// =========================================================
// BLOQUE DE HORARIO
// =========================================================

class BloqueHorario {
  const BloqueHorario({
    required this.dia,
    required this.horaInicio,
    required this.horaFin,
    this.sala,
  });

  final DiaSemana dia;

  final String horaInicio;

  final String horaFin;

  /// Sala específica de este bloque.
  ///
  /// Si queda vacía, la aplicación puede usar
  /// [Asignatura.sala] como sala predeterminada.
  final String? sala;

  factory BloqueHorario.fromMap(Map<String, dynamic> data) {
    final DiaSemana? dia = diaSemanaDesdeFirestore(data['dia']);

    if (dia == null) {
      throw FormatException('Día de horario no válido: ${data['dia']}');
    }

    return BloqueHorario(
      dia: dia,
      horaInicio: data['horaInicio']?.toString() ?? '',
      horaFin: data['horaFin']?.toString() ?? '',
      sala: data['sala']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'dia': dia.valorFirestore,
      'horaInicio': horaInicio,
      'horaFin': horaFin,
      'sala': sala?.trim().isNotEmpty == true ? sala!.trim() : null,
    };
  }
}

// =========================================================
// HELPERS
// =========================================================

int? _intNullable(dynamic valor) {
  if (valor == null) {
    return null;
  }

  if (valor is int) {
    return valor;
  }

  if (valor is num) {
    return valor.toInt();
  }

  return int.tryParse(valor.toString());
}

List<String> _listaStrings(dynamic valor) {
  if (valor is! List) {
    return const [];
  }

  return valor.map((elemento) => elemento.toString()).toList();
}

List<BloqueHorario> _listaHorario(dynamic valor) {
  if (valor is! List) {
    return const [];
  }

  final List<BloqueHorario> bloques = [];

  for (final dynamic elemento in valor) {
    if (elemento is! Map) {
      continue;
    }

    try {
      bloques.add(BloqueHorario.fromMap(Map<String, dynamic>.from(elemento)));
    } catch (_) {
      // Si un bloque antiguo o corrupto
      // no tiene un día válido, simplemente
      // no se utiliza.
    }
  }

  return bloques;
}

// =========================================================
// ASIGNATURA
// =========================================================

class Asignatura {
  const Asignatura({
    required this.id,
    required this.nombre,
    required this.estado,
    required this.origen,
    this.profesor,
    this.correoProfesor,
    this.sala,
    this.periodo,
    this.horario = const [],
    this.sigla,
    this.seccion,
    this.creditos,
    this.semestreMalla,
    this.cursoNivel,
    this.anioAcademico,
    this.modalidad,
    this.lugar,
    this.institucion,
    this.prerrequisitosIds = const [],
    this.asignaturasSiguientesIds = const [],
  });

  final String id;

  // =======================================================
  // DATOS COMUNES
  // =======================================================

  final String nombre;

  final String? profesor;

  final String? correoProfesor;

  final String? sala;

  final String? periodo;

  final List<BloqueHorario> horario;

  final EstadoAsignatura estado;

  final OrigenAsignatura origen;

  // =======================================================
  // SUPERIOR / TÉCNICA
  // =======================================================

  final String? sigla;

  final String? seccion;

  final int? creditos;

  final int? semestreMalla;

  // =======================================================
  // BÁSICA / MEDIA
  // =======================================================

  final String? cursoNivel;

  final int? anioAcademico;

  // =======================================================
  // CURSOS / OTROS
  // =======================================================

  final String? modalidad;

  final String? lugar;

  final String? institucion;

  // =======================================================
  // RELACIONES
  // =======================================================

  final List<String> prerrequisitosIds;

  final List<String> asignaturasSiguientesIds;

  // =======================================================
  // FIRESTORE → DART
  // =======================================================

  factory Asignatura.fromMap({
    required String id,
    required Map<String, dynamic> data,
  }) {
    return Asignatura(
      id: id,

      nombre: data['nombre']?.toString() ?? '',

      profesor: data['profesor']?.toString(),

      correoProfesor: data['correoProfesor']?.toString(),

      sala: data['sala']?.toString(),

      periodo: data['periodo']?.toString(),

      horario: _listaHorario(data['horario']),

      estado: estadoAsignaturaDesdeFirestore(data['estado']),

      origen: origenAsignaturaDesdeFirestore(data['origen']),

      sigla: data['sigla']?.toString(),

      seccion: data['seccion']?.toString(),

      creditos: _intNullable(data['creditos']),

      semestreMalla: _intNullable(data['semestreMalla']),

      cursoNivel: data['cursoNivel']?.toString(),

      anioAcademico: _intNullable(data['anioAcademico']),

      modalidad: data['modalidad']?.toString(),

      lugar: data['lugar']?.toString(),

      institucion: data['institucion']?.toString(),

      prerrequisitosIds: _listaStrings(data['prerrequisitosIds']),

      asignaturasSiguientesIds: _listaStrings(data['asignaturasSiguientesIds']),
    );
  }

  // =======================================================
  // DART → FIRESTORE
  // =======================================================

  Map<String, dynamic> toMap() {
    return {
      'id': id,

      'nombre': nombre.trim(),

      'profesor': profesor?.trim().isNotEmpty == true ? profesor!.trim() : null,

      'correoProfesor': correoProfesor?.trim().isNotEmpty == true
          ? correoProfesor!.trim().toLowerCase()
          : null,

      'sala': sala?.trim().isNotEmpty == true ? sala!.trim() : null,

      'periodo': periodo?.trim().isNotEmpty == true ? periodo!.trim() : null,

      'horario': horario.map((bloque) => bloque.toMap()).toList(),

      'estado': estado.valorFirestore,

      'origen': origen.valorFirestore,

      'sigla': sigla?.trim().isNotEmpty == true ? sigla!.trim() : null,

      'seccion': seccion?.trim().isNotEmpty == true ? seccion!.trim() : null,

      'creditos': creditos,

      'semestreMalla': semestreMalla,

      'cursoNivel': cursoNivel?.trim().isNotEmpty == true
          ? cursoNivel!.trim()
          : null,

      'anioAcademico': anioAcademico,

      'modalidad': modalidad?.trim().isNotEmpty == true
          ? modalidad!.trim()
          : null,

      'lugar': lugar?.trim().isNotEmpty == true ? lugar!.trim() : null,

      'institucion': institucion?.trim().isNotEmpty == true
          ? institucion!.trim()
          : null,

      'prerrequisitosIds': prerrequisitosIds,

      'asignaturasSiguientesIds': asignaturasSiguientesIds,
    };
  }
}
