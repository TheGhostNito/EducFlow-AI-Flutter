class RamoMalla {
  RamoMalla({
    required this.id,
    required this.nombre,
    required this.semestre,
    this.codigo,
    this.creditos,
    this.estado = 'pendiente',
    this.requiereRevision = false,
    this.motivosRevision = const [],
    this.codigoDuplicadoVerificado = false,
  });

  final String id;
  String nombre;
  int semestre;
  String? codigo;
  int? creditos;
  String estado;
  bool requiereRevision;
  final List<String> motivosRevision;
  bool codigoDuplicadoVerificado;

  Map<String, dynamic> toPayload() => {
    'id': id,
    'nombre': nombre.trim(),
    'semestre': semestre,
    'codigo': codigo?.trim().isEmpty == true ? null : codigo?.trim(),
    'creditos': creditos,
    'requiere_revision': requiereRevision,
    'motivos_revision': motivosRevision,
  };

  factory RamoMalla.fromRow(Map<String, dynamic> row) => RamoMalla(
    id: row['id'].toString(),
    nombre: row['nombre'].toString(),
    semestre: (row['semestre'] as num).toInt(),
    codigo: row['codigo'] as String?,
    creditos: (row['creditos'] as num?)?.toInt(),
    estado: row['estado'] as String? ?? 'pendiente',
    requiereRevision: row['requiere_revision'] == true,
    motivosRevision: _reasons(
      row['motivos_revision'] as List? ?? const [],
      row['requiere_revision'] == true,
    ),
    codigoDuplicadoVerificado: row['codigo_duplicado_verificado'] == true,
  );

  static List<String> _reasons(List values, bool needsReview) {
    final reasons = [for (final value in values) value.toString()];
    if (needsReview && reasons.isEmpty) reasons.add('manual_verification');
    return reasons;
  }
}

class ElementoCurricularEspecial {
  ElementoCurricularEspecial({
    required this.nombre,
    required this.tipo,
    required this.semestre,
    this.codigo,
    this.creditos,
    this.motivosRevision = const [],
  });

  final String nombre;
  final String tipo;
  final int? semestre;
  final String? codigo;
  final int? creditos;
  final List<String> motivosRevision;
}

class MallaCurricular {
  MallaCurricular({
    required this.id,
    required this.ramos,
    this.archivoNombre,
    this.especiales = const [],
  });

  final String id;
  final String? archivoNombre;
  final List<RamoMalla> ramos;
  final List<ElementoCurricularEspecial> especiales;

  List<int> get semestres =>
      ramos.map((ramo) => ramo.semestre).toSet().toList()..sort();
}

/// Acepta las dos estrategias de extracción sin deduplicar los espacios.
/// Un esquema desconocido falla explícitamente para evitar guardar basura.
class MallaOcrParser {
  static MallaCurricular parse(dynamic response, {required String fileName}) {
    if (response is! Map) {
      throw const FormatException(
        'La respuesta OCR no contiene una malla válida.',
      );
    }
    final root = Map<String, dynamic>.from(response);
    if (root['ok'] == false) {
      throw const FormatException(
        'El OCR informó que no pudo procesar el archivo.',
      );
    }
    final payload = _findPayload(root);
    final groups = _first(payload, const [
      'semestres',
      'semesters',
      'periodos',
      'periods',
    ]);
    final ramos = <RamoMalla>[];
    if (groups is List) {
      for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
        final group = groups[groupIndex];
        if (group is! Map) continue;
        final semester =
            _integer(
              _first(group, const [
                'numero',
                'number',
                'semestre',
                'semester',
                'periodo',
                'index',
              ]),
            ) ??
            groupIndex + 1;
        final items = _first(group, const [
          'asignaturas',
          'subjects',
          'courses',
          'ramos',
          'materias',
        ]);
        if (items is List) {
          _append(ramos, items, semester);
        }
      }
    } else {
      final items = _first(payload, const [
        'asignaturas',
        'subjects',
        'courses',
        'ramos',
        'materias',
      ]);
      if (items is List) _append(ramos, items, null);
    }
    if (ramos.isEmpty) {
      throw const FormatException(
        'El OCR no detectó asignaturas reconocibles. Revisa el documento o inténtalo de nuevo.',
      );
    }
    final specials = <ElementoCurricularEspecial>[];
    final rawSpecials = root['specialCurricularElements'];
    if (rawSpecials is List) {
      for (final raw in rawSpecials) {
        if (raw is! Map) continue;
        final name = raw['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        specials.add(
          ElementoCurricularEspecial(
            nombre: name,
            tipo: raw['kind']?.toString() ?? 'other',
            semestre: _integer(raw['semester']),
            codigo: raw['code']?.toString(),
            creditos: _integer(raw['credits']),
            motivosRevision: [
              for (final reason in (raw['reviewReasons'] as List? ?? const []))
                reason.toString(),
            ],
          ),
        );
      }
    }
    return MallaCurricular(
      id: '',
      archivoNombre: fileName,
      ramos: ramos,
      especiales: specials,
    );
  }

  static Map<String, dynamic> _findPayload(Map<String, dynamic> root) {
    if (_hasCourses(root)) return root;
    for (final key in const [
      'malla',
      'curriculum',
      'result',
      'resultado',
      'data',
      'extraction',
      'extracted_data',
    ]) {
      final value = root[key];
      if (value is Map) {
        final found = _findPayload(Map<String, dynamic>.from(value));
        if (_hasCourses(found)) return found;
      }
    }
    return root;
  }

  static bool _hasCourses(Map<String, dynamic> value) => _first(value, const [
    'semestres',
    'semesters',
    'periodos',
    'periods',
    'asignaturas',
    'subjects',
    'courses',
    'ramos',
    'materias',
  ]) is List;

  static dynamic _first(Map value, List<String> keys) {
    for (final key in keys) {
      if (value.containsKey(key)) return value[key];
    }
    return null;
  }

  static int? _integer(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static void _append(List<RamoMalla> output, List items, int? semester) {
    for (final item in items) {
      if (item is! Map) continue;
      final name =
          _first(item, const [
            'nombre',
            'name',
            'asignatura',
            'subject',
            'course',
            'ramo',
          ])?.toString().trim() ??
          '';
      if (name.isEmpty) continue;
      final detectedSemester = _integer(
        _first(item, const ['semestre', 'semester', 'periodo']),
      );
      final finalSemester = detectedSemester ?? semester ?? 1;
      final code = _first(item, const [
        'codigo',
        'code',
        'sigla',
      ])?.toString().trim();
      final credits = _integer(
        _first(item, const ['creditos', 'credits', 'creditos_sct', 'sct']),
      );
      output.add(
        RamoMalla(
          id: 'ocr_${output.length + 1}',
          nombre: name,
          semestre: finalSemester,
          codigo: code?.isEmpty == true ? null : code,
          creditos: credits,
          requiereRevision:
              item['needsReview'] == true ||
              item['requiere_revision'] == true ||
              detectedSemester == null && semester == null ||
              finalSemester < 1,
          motivosRevision: RamoMalla._reasons(
            item['reviewReasons'] as List? ?? const [],
            item['needsReview'] == true || item['requiere_revision'] == true,
          ),
        ),
      );
    }
  }
}
