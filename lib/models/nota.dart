enum PoliticaRedondeoNotas { masCercano, truncar }

enum EsquemaCalculoNotas { directo, presentacionExamen }

extension EsquemaCalculoNotasPersistencia on EsquemaCalculoNotas {
  String get valorPersistencia => switch (this) {
    EsquemaCalculoNotas.directo => 'directo',
    EsquemaCalculoNotas.presentacionExamen => 'presentacion_examen',
  };

  static EsquemaCalculoNotas desdePersistencia(Object? valor) {
    return valor?.toString() == 'presentacion_examen'
        ? EsquemaCalculoNotas.presentacionExamen
        : EsquemaCalculoNotas.directo;
  }
}

class ConfiguracionCalculoAsignatura {
  const ConfiguracionCalculoAsignatura({
    required this.asignaturaId,
    this.esquema = EsquemaCalculoNotas.directo,
    this.pesoPresentacion = 100,
    this.pesoExamen = 0,
    this.evaluacionExamenId,
  });

  final String asignaturaId;
  final EsquemaCalculoNotas esquema;
  final double pesoPresentacion;
  final double pesoExamen;
  final String? evaluacionExamenId;

  bool get usaExamenFinal => esquema == EsquemaCalculoNotas.presentacionExamen;

  bool get esValida {
    if (asignaturaId.trim().isEmpty ||
        !pesoPresentacion.isFinite ||
        !pesoExamen.isFinite ||
        pesoPresentacion < 0 ||
        pesoPresentacion > 100 ||
        pesoExamen < 0 ||
        pesoExamen > 100 ||
        (pesoPresentacion + pesoExamen - 100).abs() > 0.000001) {
      return false;
    }
    if (esquema == EsquemaCalculoNotas.directo) {
      return pesoPresentacion == 100 &&
          pesoExamen == 0 &&
          evaluacionExamenId == null;
    }
    return pesoPresentacion > 0 &&
        pesoExamen > 0 &&
        (evaluacionExamenId?.trim().isNotEmpty ?? false);
  }

  factory ConfiguracionCalculoAsignatura.directa(String asignaturaId) {
    return ConfiguracionCalculoAsignatura(asignaturaId: asignaturaId);
  }

  factory ConfiguracionCalculoAsignatura.fromMap(Map<String, dynamic> map) {
    final asignaturaId = map['asignatura_id']?.toString() ?? '';
    return ConfiguracionCalculoAsignatura(
      asignaturaId: asignaturaId,
      esquema: EsquemaCalculoNotasPersistencia.desdePersistencia(
        map['esquema'],
      ),
      pesoPresentacion: _double(map['peso_presentacion']) ?? 100,
      pesoExamen: _double(map['peso_examen']) ?? 0,
      evaluacionExamenId: _nullableText(map['evaluacion_examen_id']),
    );
  }

  Map<String, dynamic> toMap(String uid) {
    return {
      'usuario_uid': uid,
      'asignatura_id': asignaturaId,
      'esquema': esquema.valorPersistencia,
      'peso_presentacion': pesoPresentacion,
      'peso_examen': pesoExamen,
      'evaluacion_examen_id': evaluacionExamenId,
    };
  }
}

extension PoliticaRedondeoNotasPersistencia on PoliticaRedondeoNotas {
  String get valorPersistencia => switch (this) {
    PoliticaRedondeoNotas.masCercano => 'mas_cercano',
    PoliticaRedondeoNotas.truncar => 'truncar',
  };

  static PoliticaRedondeoNotas desdePersistencia(Object? valor) {
    return valor?.toString() == 'truncar'
        ? PoliticaRedondeoNotas.truncar
        : PoliticaRedondeoNotas.masCercano;
  }
}

class ConfiguracionNotas {
  const ConfiguracionNotas({
    required this.notaMinima,
    required this.notaMaxima,
    required this.notaAprobacion,
    required this.decimales,
    required this.politicaRedondeo,
  });

  static const ConfiguracionNotas predeterminada = ConfiguracionNotas(
    notaMinima: 1,
    notaMaxima: 7,
    notaAprobacion: 4,
    decimales: 1,
    politicaRedondeo: PoliticaRedondeoNotas.masCercano,
  );

  final double notaMinima;
  final double notaMaxima;
  final double notaAprobacion;
  final int decimales;
  final PoliticaRedondeoNotas politicaRedondeo;

  bool get esValida {
    return notaMinima.isFinite &&
        notaMaxima.isFinite &&
        notaAprobacion.isFinite &&
        notaMinima < notaMaxima &&
        notaAprobacion >= notaMinima &&
        notaAprobacion <= notaMaxima &&
        decimales >= 0 &&
        decimales <= 3;
  }

  ConfiguracionNotas copyWith({
    double? notaMinima,
    double? notaMaxima,
    double? notaAprobacion,
    int? decimales,
    PoliticaRedondeoNotas? politicaRedondeo,
  }) {
    return ConfiguracionNotas(
      notaMinima: notaMinima ?? this.notaMinima,
      notaMaxima: notaMaxima ?? this.notaMaxima,
      notaAprobacion: notaAprobacion ?? this.notaAprobacion,
      decimales: decimales ?? this.decimales,
      politicaRedondeo: politicaRedondeo ?? this.politicaRedondeo,
    );
  }

  factory ConfiguracionNotas.fromMap(Map<String, dynamic> map) {
    return ConfiguracionNotas(
      notaMinima: _double(map['nota_minima']) ?? predeterminada.notaMinima,
      notaMaxima: _double(map['nota_maxima']) ?? predeterminada.notaMaxima,
      notaAprobacion:
          _double(map['nota_aprobacion']) ?? predeterminada.notaAprobacion,
      decimales: _int(map['decimales']) ?? predeterminada.decimales,
      politicaRedondeo: PoliticaRedondeoNotasPersistencia.desdePersistencia(
        map['politica_redondeo'],
      ),
    );
  }

  Map<String, dynamic> toMap(String uid) {
    return {
      'usuario_uid': uid,
      'nota_minima': notaMinima,
      'nota_maxima': notaMaxima,
      'nota_aprobacion': notaAprobacion,
      'decimales': decimales,
      'politica_redondeo': politicaRedondeo.valorPersistencia,
    };
  }
}

class CalificacionEvaluacion {
  const CalificacionEvaluacion({
    required this.evaluacionId,
    required this.nota,
  });

  final String evaluacionId;
  final double nota;

  factory CalificacionEvaluacion.fromMap(Map<String, dynamic> map) {
    final double? nota = _double(map['nota']);
    if (nota == null || !nota.isFinite) {
      throw const FormatException('La calificación almacenada no es válida.');
    }
    return CalificacionEvaluacion(
      evaluacionId: map['evaluacion_id']?.toString() ?? '',
      nota: nota,
    );
  }

  Map<String, dynamic> toMap(String uid) {
    return {'usuario_uid': uid, 'evaluacion_id': evaluacionId, 'nota': nota};
  }
}

class ObjetivoNotaAsignatura {
  const ObjetivoNotaAsignatura({
    required this.asignaturaId,
    required this.notaObjetivo,
  });

  final String asignaturaId;
  final double notaObjetivo;

  factory ObjetivoNotaAsignatura.fromMap(Map<String, dynamic> map) {
    final double? nota = _double(map['nota_objetivo']);
    if (nota == null || !nota.isFinite) {
      throw const FormatException('El objetivo almacenado no es válido.');
    }
    return ObjetivoNotaAsignatura(
      asignaturaId: map['asignatura_id']?.toString() ?? '',
      notaObjetivo: nota,
    );
  }

  Map<String, dynamic> toMap(String uid) {
    return {
      'usuario_uid': uid,
      'asignatura_id': asignaturaId,
      'nota_objetivo': notaObjetivo,
    };
  }
}

double? _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String? _nullableText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
