enum NivelEducativoPerfil {
  vacio,
  basica,
  media,
  tecnico,
  superior,
  curso,
  otro,
}

extension NivelEducativoPerfilExtension on NivelEducativoPerfil {
  String get valorFirestore {
    switch (this) {
      case NivelEducativoPerfil.vacio:
        return '';

      case NivelEducativoPerfil.basica:
        return 'basica';

      case NivelEducativoPerfil.media:
        return 'media';

      case NivelEducativoPerfil.tecnico:
        return 'tecnico';

      case NivelEducativoPerfil.superior:
        return 'superior';

      case NivelEducativoPerfil.curso:
        return 'curso';

      case NivelEducativoPerfil.otro:
        return 'otro';
    }
  }
}

NivelEducativoPerfil nivelEducativoDesdeFirestore(dynamic valor) {
  switch (valor?.toString()) {
    case 'basica':
      return NivelEducativoPerfil.basica;

    case 'media':
      return NivelEducativoPerfil.media;

    case 'tecnico':
      return NivelEducativoPerfil.tecnico;

    case 'superior':
      return NivelEducativoPerfil.superior;

    case 'curso':
      return NivelEducativoPerfil.curso;

    case 'otro':
      return NivelEducativoPerfil.otro;

    default:
      return NivelEducativoPerfil.vacio;
  }
}

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

class PerfilUsuario {
  const PerfilUsuario({
    required this.uid,
    required this.nombre,
    required this.correoPrincipal,
    required this.correoInstitucional,
    required this.nivelEducativo,
    required this.nombreEstablecimiento,
    required this.tipoEstablecimiento,
    required this.cursoActual,
    required this.carrera,
    required this.semestreActual,
    required this.anioIngreso,
    required this.sede,
    required this.jornada,
    required this.estadoAcademico,
    required this.idioma,
    required this.perfilCompleto,
  });

  final String uid;

  final String nombre;

  final String correoPrincipal;

  final String correoInstitucional;

  final NivelEducativoPerfil nivelEducativo;

  final String nombreEstablecimiento;

  final String tipoEstablecimiento;

  final String cursoActual;

  final String carrera;

  final int? semestreActual;

  final int? anioIngreso;

  final String sede;

  final String jornada;

  final String estadoAcademico;

  final String idioma;

  final bool perfilCompleto;

  factory PerfilUsuario.fromMap(
    Map<String, dynamic> data, {
    required String uidFallback,
  }) {
    return PerfilUsuario(
      uid: data['uid']?.toString() ?? uidFallback,

      nombre: data['nombre']?.toString() ?? '',

      correoPrincipal: data['correoPrincipal']?.toString() ?? '',

      correoInstitucional: data['correoInstitucional']?.toString() ?? '',

      nivelEducativo: nivelEducativoDesdeFirestore(data['nivelEducativo']),

      nombreEstablecimiento: data['nombreEstablecimiento']?.toString() ?? '',

      tipoEstablecimiento: data['tipoEstablecimiento']?.toString() ?? '',

      cursoActual: data['cursoActual']?.toString() ?? '',

      carrera: data['carrera']?.toString() ?? '',

      semestreActual: _intNullable(data['semestreActual']),

      anioIngreso: _intNullable(data['anioIngreso']),

      sede: data['sede']?.toString() ?? '',

      jornada: data['jornada']?.toString() ?? '',

      estadoAcademico: data['estadoAcademico']?.toString() ?? '',

      idioma: data['idioma']?.toString() == 'en' ? 'en' : 'es',

      perfilCompleto: data['perfilCompleto'] is bool
          ? data['perfilCompleto'] as bool
          : false,
    );
  }
}

class ActualizarPerfilUsuario {
  const ActualizarPerfilUsuario({
    required this.nombre,
    required this.correoInstitucional,
    required this.nivelEducativo,
    required this.nombreEstablecimiento,
    required this.tipoEstablecimiento,
    required this.cursoActual,
    required this.carrera,
    required this.semestreActual,
    required this.anioIngreso,
    required this.sede,
    required this.jornada,
    required this.estadoAcademico,
    required this.idioma,
  });

  final String nombre;

  final String correoInstitucional;

  final NivelEducativoPerfil nivelEducativo;

  final String nombreEstablecimiento;

  final String tipoEstablecimiento;

  final String cursoActual;

  final String carrera;

  final int? semestreActual;

  final int? anioIngreso;

  final String sede;

  final String jornada;

  final String estadoAcademico;

  final String idioma;
}
