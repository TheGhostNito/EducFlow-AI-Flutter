import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/malla_curricular.dart';
import '../models/malla_multimodal_review.dart';
import 'ai_failure_diagnostics.dart';
import 'ai_service.dart';
import 'ocr_file_picker_service.dart';

typedef MallaMultimodalLogger = void Function(
  String event,
  Map<String, Object?> data,
);

abstract interface class MallaMultimodalCache {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SharedPreferencesMallaMultimodalCache implements MallaMultimodalCache {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async {
    await (await SharedPreferences.getInstance()).setString(key, value);
  }
}

class MallaMultimodalModelRequest {
  const MallaMultimodalModelRequest({
    required this.bytes,
    required this.mimeType,
    required this.visionPayload,
    required this.candidates,
  });

  final Uint8List bytes;
  final String mimeType;
  final Map<String, dynamic> visionPayload;
  final List<Map<String, Object?>> candidates;
}

class MallaMultimodalModelResponse {
  const MallaMultimodalModelResponse({
    required this.json,
    this.promptTokens,
    this.outputTokens,
    this.thinkingTokens,
    this.totalTokens,
    this.finishReason,
    this.responseLength,
    this.truncated = false,
  });

  final String json;
  final int? promptTokens;
  final int? outputTokens;
  final int? thinkingTokens;
  final int? totalTokens;
  final String? finishReason;
  final int? responseLength;
  final bool truncated;
}

abstract interface class MallaMultimodalModelClient {
  Future<MallaMultimodalModelResponse> review(
    MallaMultimodalModelRequest request,
  );
}

class MallaMultimodalClientException implements Exception {
  const MallaMultimodalClientException({
    required this.stage,
    required this.cause,
  });

  final String stage;
  final Object cause;
}

class MallaMultimodalSafeError {
  const MallaMultimodalSafeError({
    required this.category,
    required this.errorType,
    required this.retryable,
    this.httpStatus,
    this.backendStatus,
    this.technicalMessage,
  });

  final String category;
  final String errorType;
  final bool retryable;
  final int? httpStatus;
  final String? backendStatus;
  final String? technicalMessage;

  static MallaMultimodalSafeError inspect(Object error) {
    final diagnostics = AiFailureDiagnostics.from(error);
    final rawMessage = switch (error) {
      FirebaseAIException value => value.message,
      FirebaseAISdkException value => value.message,
      FormatException value => value.message,
      _ => error.toString(),
    };
    final message = rawMessage.toLowerCase();
    final httpStatus = _httpStatus(rawMessage) ?? diagnostics.httpStatus;
    final backendStatus =
        _backendStatus(rawMessage) ?? diagnostics.backendStatus;
    final category = _category(
      error,
      message,
      httpStatus: httpStatus,
      backendStatus: backendStatus,
      fallback: diagnostics.category,
    );
    final retryable = switch (category) {
      'invalid_request' || 'response_json' || 'access' => false,
      'quota' || 'service' || 'connectivity' => true,
      _ => diagnostics.retryable,
    };
    return MallaMultimodalSafeError(
      category: category,
      errorType: diagnostics.errorType,
      retryable: retryable,
      httpStatus: httpStatus,
      backendStatus: backendStatus,
      technicalMessage: _sanitize(rawMessage),
    );
  }

  static String _category(
    Object error,
    String message, {
    required int? httpStatus,
    required String? backendStatus,
    required AiFailureCategory fallback,
  }) {
    if (error is FormatException) return 'response_json';
    if (fallback == AiFailureCategory.quotaExceeded ||
        httpStatus == 429 ||
        backendStatus == 'RESOURCE_EXHAUSTED') {
      return 'quota';
    }
    if (const {
          AiFailureCategory.invalidApiKey,
          AiFailureCategory.permissionDenied,
          AiFailureCategory.appCheck,
        }.contains(fallback) ||
        httpStatus == 401 ||
        httpStatus == 403 ||
        backendStatus == 'PERMISSION_DENIED' ||
        backendStatus == 'UNAUTHENTICATED') {
      return 'access';
    }
    if (httpStatus == 400 ||
        httpStatus == 413 ||
        backendStatus == 'INVALID_ARGUMENT' ||
        message.contains('invalid argument') ||
        message.contains('invalid value') ||
        message.contains('request too large') ||
        message.contains('response schema') ||
        message.contains('response_schema') ||
        message.contains('inline data') ||
        message.contains('inlinedata') ||
        message.contains('mime type')) {
      return 'invalid_request';
    }
    if (fallback == AiFailureCategory.connectivity ||
        fallback == AiFailureCategory.timeout) {
      return 'connectivity';
    }
    if (const {
          AiFailureCategory.serviceNotEnabled,
          AiFailureCategory.modelUnavailable,
          AiFailureCategory.unsupportedLocation,
          AiFailureCategory.server,
        }.contains(fallback) ||
        backendStatus == 'INTERNAL' ||
        backendStatus == 'UNAVAILABLE') {
      return 'service';
    }
    return fallback.name;
  }

  static int? _httpStatus(String message) {
    final server = RegExp(r'Server Error \[(\d{3})\]').firstMatch(message);
    if (server != null) return int.tryParse(server.group(1)!);
    final explicit = RegExp(
      r'\b(?:HTTP|status(?: code)?)\s*[:=]?\s*(\d{3})\b',
      caseSensitive: false,
    ).firstMatch(message);
    return explicit == null ? null : int.tryParse(explicit.group(1)!);
  }

  static String? _backendStatus(String message) {
    const statuses = [
      'INVALID_ARGUMENT',
      'PERMISSION_DENIED',
      'UNAUTHENTICATED',
      'RESOURCE_EXHAUSTED',
      'FAILED_PRECONDITION',
      'NOT_FOUND',
      'DEADLINE_EXCEEDED',
      'UNAVAILABLE',
      'INTERNAL',
    ];
    final upper = message.toUpperCase();
    for (final status in statuses) {
      if (upper.contains(status)) return status;
    }
    return null;
  }

  static String? _sanitize(String message) {
    var safe = message.trim();
    if (safe.isEmpty) return null;
    safe = safe
        .replaceAll(RegExp(r'AIza[0-9A-Za-z_-]{20,}'), '[api-key-redacted]')
        .replaceAll(
          RegExp(r'Bearer\s+\S+', caseSensitive: false),
          'Bearer [redacted]',
        )
        .replaceAll(RegExp(r'[A-Za-z0-9+/_=-]{80,}'), '[large-value-redacted]')
        .replaceAll(
          RegExp(r'projects/[^/\s"}]+', caseSensitive: false),
          'projects/[redacted]',
        )
        .replaceAll(
          RegExp(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}'),
          '[email-redacted]',
        );
    return safe.length <= 500 ? safe : '${safe.substring(0, 500)}…';
  }
}

class FirebaseMallaMultimodalModelClient implements MallaMultimodalModelClient {
  FirebaseMallaMultimodalModelClient({GenerativeModel? model})
    : _model = model ?? _createModel();

  final GenerativeModel _model;

  static const int multimodalMaxOutputTokens = 12288;

  static GenerativeModel _createModel() =>
      FirebaseAI.googleAI().generativeModel(
        model: AiService.modelName,
        generationConfig: _generationConfig,
        systemInstruction: Content.system(systemInstructionText),
      );

  static const String systemInstructionText = '''
Eres un revisor académico de EducFlow AI. Contrasta el documento visual con la salida de Google Cloud Vision.
Usa exclusivamente los courseId entregados para cursos existentes. Solo propón cursos adicionales cuando sean claramente visibles y no estén en VISION.
No inventes asignaturas, códigos, créditos, períodos, prerrequisitos, categorías ni certificaciones.
Las propuestas deben incluir evidencia visible concreta. Si no existe evidencia suficiente, usa texto vacío, -1, unknown o pendingReasons según el tipo del campo.
No elimines información de Vision. Devuelve únicamente JSON conforme al esquema.
''';

  static final GenerationConfig _generationConfig = GenerationConfig(
    maxOutputTokens: multimodalMaxOutputTokens,
    responseMimeType: 'application/json',
    responseSchema: _responseSchema,
    thinkingConfig: ThinkingConfig.withThinkingLevel(ThinkingLevel.medium),
  );

  @visibleForTesting
  static GenerationConfig get generationConfigForTesting => _generationConfig;

  static Schema get academicResponseSchema => _responseSchema;

  @override
  Future<MallaMultimodalModelResponse> review(
    MallaMultimodalModelRequest request,
  ) async {
    final prompt = buildAcademicPrompt(
      candidates: request.candidates,
      visionPayload: request.visionPayload,
    );
    late final GenerateContentResponse response;
    try {
      response = await _model.generateContent([
        Content.multi([
          InlineDataPart(request.mimeType, request.bytes),
          TextPart(prompt),
        ]),
      ]);
    } catch (error) {
      throw MallaMultimodalClientException(
        stage: 'generate_content',
        cause: error,
      );
    }
    final text = response.text ?? '';
    final usage = response.usageMetadata;
    final finishReason = response.candidates.isEmpty
        ? null
        : response.candidates.first.finishReason?.toJson();
    return MallaMultimodalModelResponse(
      json: text,
      promptTokens: usage?.promptTokenCount,
      outputTokens: usage?.candidatesTokenCount,
      thinkingTokens: usage?.thoughtsTokenCount,
      totalTokens: usage?.totalTokenCount,
      finishReason: finishReason,
      responseLength: text.length,
      truncated: finishReason == FinishReason.maxTokens.toJson(),
    );
  }

  static String buildAcademicPrompt({
    required List<Map<String, Object?>> candidates,
    required Map<String, dynamic> visionPayload,
  }) {
    final context = buildCompactVisionContext(
      candidates: candidates,
      visionPayload: visionPayload,
    );
    return '''
Revisa toda la malla usando el archivo visual como fuente primaria y VISION como referencia OCR.
Devuelve solo correcciones de cursos y hallazgos relevantes; no repitas cursos sin cambios. Certificaciones, membresías y conexiones sí deben inventariarse completas.

La respuesta debe ser compacta: no repitas una misma evidencia en dos campos, no narres el proceso, usa códigos breves en pendingReasons y limita cada evidencia a una frase factual. En prerequisites, sourceAnchor, targetArrowhead y pathContinuity son la evidencia completa: no agregues otra copia. En memberships, boundaryEvidence es la evidencia completa. En los demás objetos usa como máximo una evidencia por hecho, salvo que exista una contradicción real.

Antes de responder realiza obligatoriamente estas pasadas visuales sobre toda la página:
1. Recorre títulos y límites de todos los contenedores de certificación. Registra títulos en visualAudit.certificationTitles y total en visualAudit.certificationContainerCount.
2. Para cada certificación, identifica cada asignatura dentro de sus límites. Conserva límites dudosos como pending, sin omitir el contenedor.
3. Haz primero un inventario ligero de todas las líneas y puntas entre cajas de asignaturas, sin exigir todavía una conclusión. Registra en visualAudit.coursePrerequisiteConnectionCount toda conexión candidata entre cursos, incluso si uno de sus extremos o su recorrido requiere revisión; excluye requisitos de práctica, niveles y Capstone.
4. Devuelve en prerequisites todas las conexiones del inventario, no solo las confirmadas. courseId, requiresCourseId, certainty y ambiguous son suficientes para conservar una candidatura. Completa sourceAnchor, targetArrowhead y pathContinuity cuando sean verificables; si falta alguno, omítelo y conserva la relación con ambiguous true, certainty uncertain y un pendingReason. No descartes una candidatura por no poder demostrar toda su geometría. Antes de marcar courseArrowsInspected true comprueba que cada conexión inventariada esté en prerequisites; si no puedes completar el inventario, usa false y explica la causa en unresolvedVisualSignals.
5. Inspecciona por separado requisitos de niveles aprobados, práctica y Capstone y devuélvelos únicamente en academicRequirements.

Marca certificationContainersInspected y courseArrowsInspected como true solo después de completar ambas pasadas. Si una pasada no puede completarse, déjala en false y explica la causa en visualAudit.unresolvedVisualSignals y pendingReview.

Reglas:
- Usa únicamente los courseId de VISION.
- Propuestas de nombre, código, créditos o período requieren evidencia visual; usa texto vacío o -1 si no aplican.
- Acepta un prerrequisito solo si la línea conecta inequívocamente ambas asignaturas y la dirección se reconoce por la punta. En bifurcaciones sigue la rama completa. Una línea que cruza o pasa cerca no conecta el ramo.
- Distingue conectores de bordes de contenedores, separadores de períodos continuos o segmentados y líneas decorativas. La alineación horizontal, la proximidad, compartir fila o pertenecer al mismo certificado no constituyen un prerrequisito. En un cruce no cambies de línea salvo que exista una unión visual explícita. Una relación confirmada requiere que sourceAnchor nombre el ramo de origen y el borde exacto del que sale la línea, targetArrowhead nombre el ramo de destino y el borde donde termina la punta, y pathContinuity describa el recorrido continuo entre ambos.
- En prerequisites usa certainty confirmed solo con extremos y dirección inequívocos; en otro caso usa uncertain y pendingReasons. No incluyas un campo evidence adicional.
- Usa prerequisiteStatus exactamente identified, none o unknown. Usa none solo si el documento declara explícitamente que no hay prerrequisitos y copia esa evidencia literal en prerequisiteStatusEvidence; la ausencia de flechas significa unknown.
- En certificaciones usa basis container, legend o explicit_label. Con container compara los cuatro bordes: boundaryStatus inside solo si la caja está íntegramente dentro; outside si queda fuera o sobrepasa el límite; uncertain si no se distingue. Después de revisar el interior, inspecciona las cajas inmediatamente vecinas por cada borde: una caja situada en un rectángulo adyacente separado sigue outside aunque esté alineada o conectada por una flecha. boundaryEvidence debe ser una frase breve que nombre ramo y certificación; no agregues otro campo evidence a la membresía. Conserva uncertain con pendingReasons, excluye outside y registra los vecinos exteriores en excludedNearbyCourseIds. No deduzcas membresía por flechas o proximidad.
- No incluyas cursos externos al contenedor aunque una línea pase cerca o los conecte con un miembro.
- Conserva en categoryLabel el nombre visible de la categoría. Usa specialty para Especialidades e institutional para Formación Sello; no las conviertas en mandatory o elective.
- Indica semester, bimester, trimester, quarter, annual, other o unknown.
- courseReviews contiene solo correcciones, categorías, estados o dudas relevantes.
- additionalCourses contiene cursos claramente visibles que no estén en VISION.courses. Los elementos de VISION.specialElements no están ausentes: si deben integrarse como curso, propón el mismo elemento sin inventar otro y cita esa coincidencia en la evidencia. Usa proposalKey new_1, new_2, etc.; incluye nombre, código, período y evidencia, y pendingReasons si algún dato es ambiguo.
- Una caja con nombre y créditos visibles puede ser una asignatura aunque no muestre código: propón una sola vez el elemento, deja proposedCode vacío y agrega code_missing a pendingReasons. Un bloque horizontal que atraviesa varios períodos pero muestra un único nombre, código y créditos representa una sola asignatura, no una copia por período.
- Prerrequisitos y certificaciones pueden referir courseId existentes o proposalKey adicionales. Flutter reemplazará proposalKey por IDs temporales seguros.
- academicRequirements representa nivel aprobado, práctica o Capstone. Sigue el conector hasta el destino exacto; conserva literalmente el rango visible en una sola evidencia y usa su último nivel como minimumLevel. No deduzcas por proximidad ni conviertas estas condiciones en prerrequisitos. Usa type approved_level, completed_periods, practice_eligibility, capstone_eligibility, other o unknown; si es ambiguo, conserva unknown pendiente.
- Usa certifications vacío solo cuando la pasada completa encuentre cero contenedores titulados. Usa prerequisites vacío solo cuando la pasada completa encuentre cero conexiones candidatas entre asignaturas. Los conteos y títulos de visualAudit deben ser coherentes con los arreglos entregados.

VISION:
${jsonEncode(context)}
''';
  }

  @visibleForTesting
  static Map<String, Object?> buildCompactVisionContext({
    required List<Map<String, Object?>> candidates,
    required Map<String, dynamic> visionPayload,
  }) {
    final rawCourses = _findCourseMaps(visionPayload);
    final unused = <int>{
      for (var index = 0; index < rawCourses.length; index++) index,
    };
    return {
      'courses': [
        for (var index = 0; index < candidates.length; index++)
          _compactCourse(
            candidates[index],
            _matchRawCourse(candidates[index], rawCourses, unused, index),
          ),
      ],
      if (_compactSpecialElements(visionPayload) case final specials
          when specials.isNotEmpty)
        'specialElements': specials,
    };
  }

  static Map<String, Object?> _compactCourse(
    Map<String, Object?> candidate,
    Map<String, dynamic>? raw,
  ) {
    final geometry = raw == null ? const <String, Object?>{} : _geometry(raw);
    final evidence = raw == null ? const <Object?>[] : _evidence(raw);
    return {
      'courseId': candidate['courseId'],
      'name': candidate['name'],
      'code': candidate['code'],
      'credits': candidate['credits'],
      'period': candidate['period'],
      'needsReview': candidate['needsReview'],
      if (geometry.isNotEmpty) 'position': geometry,
      if (evidence.isNotEmpty) 'evidence': evidence,
    };
  }

  static Map<String, dynamic>? _matchRawCourse(
    Map<String, Object?> candidate,
    List<Map<String, dynamic>> rawCourses,
    Set<int> unused,
    int fallbackIndex,
  ) {
    final candidateCode = _normalized(candidate['code']);
    final candidateName = _normalized(candidate['name']);
    int? match;
    if (candidateCode != null) {
      match = unused.cast<int?>().firstWhere(
        (index) =>
            _normalized(_firstValue(rawCourses[index!], _codeKeys)) ==
            candidateCode,
        orElse: () => null,
      );
    }
    if (match == null && candidateName != null) {
      match = unused.cast<int?>().firstWhere(
        (index) =>
            _normalized(_firstValue(rawCourses[index!], _nameKeys)) ==
            candidateName,
        orElse: () => null,
      );
    }
    if (match == null && unused.contains(fallbackIndex)) match = fallbackIndex;
    if (match == null || !unused.remove(match)) return null;
    return rawCourses[match];
  }

  static List<Map<String, dynamic>> _findCourseMaps(dynamic value) {
    final found = <Map<String, dynamic>>[];
    void visit(dynamic node, {String? parentKey}) {
      if (node is Map) {
        final map = Map<String, dynamic>.from(node);
        if (_looksLikeCourse(map) && _courseListKeys.contains(parentKey)) {
          found.add(map);
          return;
        }
        for (final entry in map.entries) {
          visit(entry.value, parentKey: entry.key);
        }
      } else if (node is List) {
        for (final item in node) {
          visit(item, parentKey: parentKey);
        }
      }
    }

    visit(value);
    return found;
  }

  static bool _looksLikeCourse(Map<String, dynamic> value) =>
      _firstValue(value, _nameKeys) != null;

  static List<Object?> _evidence(Map<String, dynamic> raw) {
    final result = <Object?>[];
    for (final key in const ['evidence', 'sourceBlocks', 'sourceBlock']) {
      final values = raw[key] is List ? raw[key] as List : [raw[key]];
      for (final value in values) {
        if (result.length >= 4) return result;
        if (value is String) {
          final text = _bounded(value, 300);
          if (text != null) result.add(text);
        } else if (value is Map) {
          final map = Map<String, dynamic>.from(value);
          final text = _bounded(
            _firstValue(map, const ['text', 'description'])?.toString(),
            300,
          );
          final geometry = _geometry(map);
          if (text != null || geometry.isNotEmpty) {
            final evidence = <String, Object?>{...geometry};
            if (text != null) evidence['text'] = text;
            result.add(evidence);
          }
        }
      }
    }
    return result;
  }

  static Map<String, Object?> _geometry(Map<String, dynamic> raw) {
    final result = <String, Object?>{};
    for (final key in _geometryKeys) {
      final value = raw[key];
      if (value is num || value is String && value.length <= 40) {
        result[key] = value;
      } else if (value is Map) {
        final nested = _geometry(Map<String, dynamic>.from(value));
        if (nested.isNotEmpty) result[key] = nested;
      } else if (value is List) {
        final points = <Object?>[];
        for (final point in value.take(8)) {
          if (point is Map) {
            final compact = _geometry(Map<String, dynamic>.from(point));
            if (compact.isNotEmpty) points.add(compact);
          }
        }
        if (points.isNotEmpty) result[key] = points;
      }
    }
    return result;
  }

  static List<Map<String, Object?>> _compactSpecialElements(
    Map<String, dynamic> payload,
  ) {
    final raw = payload['specialCurricularElements'];
    if (raw is! List) return const [];
    return [
      for (final value in raw.take(100))
        if (value is Map)
          {
            for (final key in const [
              'name',
              'kind',
              'semester',
              'code',
              'credits',
              'reviewReasons',
            ])
              if (value[key] != null) key: value[key],
          },
    ];
  }

  static Object? _firstValue(Map<String, dynamic> value, List<String> keys) {
    for (final key in keys) {
      if (value[key] != null) return value[key];
    }
    return null;
  }

  static String? _normalized(Object? value) {
    final text = value?.toString().trim().toLowerCase();
    return text == null || text.isEmpty ? null : text;
  }

  static String? _bounded(String? value, int maxLength) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    return text.length <= maxLength ? text : text.substring(0, maxLength);
  }

  static const _courseListKeys = {
    'courses',
    'asignaturas',
    'subjects',
    'ramos',
    'materias',
  };
  static const _nameKeys = [
    'name',
    'nombre',
    'asignatura',
    'subject',
    'course',
    'ramo',
  ];
  static const _codeKeys = ['code', 'codigo', 'sigla'];
  static const _geometryKeys = [
    'page',
    'pageIndex',
    'x',
    'y',
    'left',
    'top',
    'right',
    'bottom',
    'width',
    'height',
    'row',
    'column',
    'semesterColumnX',
    'boundingBox',
    'vertices',
    'polygon',
  ];

  static final Schema _responseSchema = Schema.object(
    properties: {
      'periodType': Schema.string(),
      'periodCount': Schema.integer(),
      'periodEvidence': Schema.array(items: Schema.string()),
      'courseReviews': Schema.array(
        items: Schema.object(
          properties: {
            'courseId': Schema.string(),
            'proposedName': Schema.string(),
            'proposedCode': Schema.string(),
            'proposedCredits': Schema.integer(),
            'proposedPeriod': Schema.integer(),
            'category': Schema.string(),
            'categoryLabel': Schema.string(),
            'prerequisiteStatus': Schema.string(),
            'prerequisiteStatusEvidence': Schema.array(items: Schema.string()),
            'evidence': Schema.array(items: Schema.string()),
            'pendingReasons': Schema.array(items: Schema.string()),
          },
        ),
      ),
      'additionalCourses': Schema.array(
        items: Schema.object(
          properties: {
            'proposalKey': Schema.string(),
            'proposedName': Schema.string(),
            'proposedCode': Schema.string(),
            'proposedCredits': Schema.integer(),
            'proposedPeriod': Schema.integer(),
            'category': Schema.string(),
            'categoryLabel': Schema.string(),
            'evidence': Schema.array(items: Schema.string()),
            'pendingReasons': Schema.array(items: Schema.string()),
          },
        ),
      ),
      'prerequisites': Schema.array(
        items: Schema.object(
          properties: {
            'courseId': Schema.string(),
            'requiresCourseId': Schema.string(),
            'certainty': Schema.string(),
            'sourceAnchor': Schema.string(),
            'targetArrowhead': Schema.string(),
            'pathContinuity': Schema.string(),
            'ambiguous': Schema.boolean(),
            'pendingReasons': Schema.array(items: Schema.string()),
          },
          optionalProperties: [
            'sourceAnchor',
            'targetArrowhead',
            'pathContinuity',
          ],
        ),
      ),
      'certifications': Schema.array(
        items: Schema.object(
          properties: {
            'id': Schema.string(),
            'name': Schema.string(),
            'memberships': Schema.array(
              items: Schema.object(
                properties: {
                  'courseId': Schema.string(),
                  'basis': Schema.string(),
                  'boundaryStatus': Schema.string(),
                  'boundaryEvidence': Schema.string(),
                  'pendingReasons': Schema.array(items: Schema.string()),
                },
              ),
            ),
            'excludedNearbyCourseIds': Schema.array(items: Schema.string()),
            'evidence': Schema.array(items: Schema.string()),
          },
        ),
      ),
      'academicRequirements': Schema.array(
        items: Schema.object(
          properties: {
            'requirementKey': Schema.string(),
            'type': Schema.string(),
            'targetCourseId': Schema.string(),
            'targetLabel': Schema.string(),
            'description': Schema.string(),
            'minimumLevel': Schema.integer(),
            'evidence': Schema.array(items: Schema.string()),
            'pendingReasons': Schema.array(items: Schema.string()),
          },
        ),
      ),
      'visualAudit': Schema.object(
        properties: {
          'certificationContainersInspected': Schema.boolean(),
          'certificationContainerCount': Schema.integer(),
          'certificationTitles': Schema.array(items: Schema.string()),
          'courseArrowsInspected': Schema.boolean(),
          'coursePrerequisiteConnectionCount': Schema.integer(),
          'unresolvedVisualSignals': Schema.array(items: Schema.string()),
        },
      ),
      'pendingReview': Schema.array(items: Schema.string()),
    },
  );
}

enum MallaMultimodalFailureKind {
  access,
  quota,
  service,
  invalidRequest,
  invalidResponse,
  unavailable,
}

class MallaMultimodalReviewOutcome {
  const MallaMultimodalReviewOutcome({
    required this.diagnostics,
    this.review,
    this.failure,
    this.cacheHit = false,
  });

  final MallaMultimodalDiagnostics diagnostics;
  final MallaMultimodalReview? review;
  final MallaMultimodalFailureKind? failure;
  final bool cacheHit;
}

class MallaMultimodalReviewService {
  MallaMultimodalReviewService({
    MallaMultimodalModelClient? client,
    MallaMultimodalCache? cache,
    MallaMultimodalLogger? logger,
  }) : _client = client ?? FirebaseMallaMultimodalModelClient(),
       _cache = cache ?? SharedPreferencesMallaMultimodalCache(),
       _logger = logger ?? _defaultLogger;

  static const String processorVersion = 'malla-multimodal-v4.10';

  final MallaMultimodalModelClient _client;
  final MallaMultimodalCache _cache;
  final MallaMultimodalLogger _logger;

  Future<MallaMultimodalReviewOutcome> review({
    required String uid,
    required OcrPickedFile file,
    required Map<String, dynamic> visionPayload,
    required MallaCurricular visionResult,
  }) async {
    final documentHash = sha256.convert(file.bytes).toString();
    final key = _cacheKey(uid, documentHash);
    final stopwatch = Stopwatch()..start();
    var stage = 'cache_lookup';
    MallaMultimodalModelResponse? modelResponse;

    try {
      final cached = await _cache.read(key);
      if (cached != null) {
        final normalized = MallaMultimodalReviewValidator.validate(
          jsonDecode(cached),
          visionResult: visionResult,
          model: AiService.modelName,
          processorVersion: processorVersion,
          documentHash: documentHash,
        );
        _logger('malla_multimodal_cache_hit', {
          'model': AiService.modelName,
          'processorVersion': processorVersion,
        });
        stopwatch.stop();
        return MallaMultimodalReviewOutcome(
          review: normalized,
          cacheHit: true,
          diagnostics: MallaMultimodalDiagnostics(
            status: 'cache_hit',
            geminiRequestExecuted: false,
            successful: true,
            cacheHit: true,
            fallbackToVision: false,
            elapsedMilliseconds: stopwatch.elapsedMilliseconds,
            provider: 'gemini_developer_api',
            model: AiService.modelName,
            stage: 'cache_lookup',
            attachmentMimeType: file.mimeType,
            attachmentBytes: file.bytes.length,
            structuredOutput: true,
          ),
        );
      }
    } catch (_) {
      _logger('malla_multimodal_cache_invalid', {
        'model': AiService.modelName,
        'processorVersion': processorVersion,
      });
    }

    try {
      stage = 'generate_content';
      final response = modelResponse = await _client.review(
        MallaMultimodalModelRequest(
          bytes: file.bytes,
          mimeType: file.mimeType,
          visionPayload: visionPayload,
          candidates: [
            for (final course in visionResult.ramos)
              {
                'courseId': course.id,
                'name': course.nombre,
                'code': course.codigo,
                'credits': course.creditos,
                'period': course.semestre,
                'needsReview': course.requiereRevision,
              },
          ],
        ),
      );
      if (response.truncated) {
        stage = 'response_truncated';
        throw const FormatException(
          'Gemini interrumpió la respuesta al alcanzar MAX_TOKENS.',
        );
      }
      if (response.json.trim().isEmpty) {
        stage = 'response_content';
        throw const FormatException('Gemini no devolvió JSON de revisión.');
      }
      stage = 'response_json_decode';
      final decoded = jsonDecode(response.json);
      stage = 'response_validation';
      final review = MallaMultimodalReviewValidator.validate(
        decoded,
        visionResult: visionResult,
        model: AiService.modelName,
        processorVersion: processorVersion,
        documentHash: documentHash,
      );
      try {
        await _cache.write(key, jsonEncode(review.toJson()));
      } catch (_) {
        _logger('malla_multimodal_cache_write_failed', {
          'model': AiService.modelName,
          'processorVersion': processorVersion,
        });
      }
      stopwatch.stop();
      _logger('malla_multimodal_request_completed', {
        'model': AiService.modelName,
        'processorVersion': processorVersion,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'promptTokens': response.promptTokens,
        'outputTokens': response.outputTokens,
        'thinkingTokens': response.thinkingTokens,
        'totalTokens': response.totalTokens,
        'finishReason': response.finishReason,
        'responseLength': response.responseLength,
        'truncated': response.truncated,
      });
      return MallaMultimodalReviewOutcome(
        review: review,
        diagnostics: MallaMultimodalDiagnostics(
          status: 'completed',
          geminiRequestExecuted: true,
          successful: true,
          cacheHit: false,
          fallbackToVision: false,
          elapsedMilliseconds: stopwatch.elapsedMilliseconds,
          provider: 'gemini_developer_api',
          model: AiService.modelName,
          stage: 'completed',
          attachmentMimeType: file.mimeType,
          attachmentBytes: file.bytes.length,
          structuredOutput: true,
          promptTokens: response.promptTokens,
          outputTokens: response.outputTokens,
          thinkingTokens: response.thinkingTokens,
          totalTokens: response.totalTokens,
          finishReason: response.finishReason,
          responseLength: response.responseLength,
          truncated: response.truncated,
        ),
      );
    } catch (error) {
      stopwatch.stop();
      final rootError = error is MallaMultimodalClientException
          ? error.cause
          : error;
      final failureStage = error is MallaMultimodalClientException
          ? error.stage
          : stage;
      final safeError = MallaMultimodalSafeError.inspect(rootError);
      final failure = switch (safeError.category) {
        'access' => MallaMultimodalFailureKind.access,
        'quota' => MallaMultimodalFailureKind.quota,
        'service' => MallaMultimodalFailureKind.service,
        'invalid_request' => MallaMultimodalFailureKind.invalidRequest,
        'response_json' => MallaMultimodalFailureKind.invalidResponse,
        _ => MallaMultimodalFailureKind.unavailable,
      };
      _logger('malla_multimodal_request_failed', {
        'model': AiService.modelName,
        'processorVersion': processorVersion,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'failure': failure.name,
        'stage': failureStage,
        'errorCategory': safeError.category,
        'httpStatus': safeError.httpStatus,
        'backendStatus': safeError.backendStatus,
        'promptTokens': modelResponse?.promptTokens,
        'outputTokens': modelResponse?.outputTokens,
        'thinkingTokens': modelResponse?.thinkingTokens,
        'totalTokens': modelResponse?.totalTokens,
        'finishReason': modelResponse?.finishReason,
        'responseLength': modelResponse?.responseLength,
        'truncated': modelResponse?.truncated,
      });
      return MallaMultimodalReviewOutcome(
        failure: failure,
        diagnostics: MallaMultimodalDiagnostics(
          status: 'fallback_to_vision',
          geminiRequestExecuted: true,
          successful: false,
          cacheHit: false,
          fallbackToVision: true,
          elapsedMilliseconds: stopwatch.elapsedMilliseconds,
          provider: 'gemini_developer_api',
          model: AiService.modelName,
          stage: failureStage,
          attachmentMimeType: file.mimeType,
          attachmentBytes: file.bytes.length,
          structuredOutput: true,
          promptTokens: modelResponse?.promptTokens,
          outputTokens: modelResponse?.outputTokens,
          thinkingTokens: modelResponse?.thinkingTokens,
          totalTokens: modelResponse?.totalTokens,
          finishReason: modelResponse?.finishReason,
          responseLength: modelResponse?.responseLength,
          truncated: modelResponse?.truncated,
          failure: failure.name,
          errorCategory: safeError.category,
          errorType: safeError.errorType,
          httpStatus: safeError.httpStatus,
          backendStatus: safeError.backendStatus,
          technicalMessage: safeError.technicalMessage,
          retryable: safeError.retryable,
        ),
      );
    }
  }

  static String _cacheKey(String uid, String documentHash) {
    final identity = sha256
        .convert(
          utf8.encode(
            '$uid|$documentHash|${AiService.modelName}|$processorVersion',
          ),
        )
        .toString();
    return 'malla_multimodal_cache_$identity';
  }

  static void _defaultLogger(String event, Map<String, Object?> data) {
    if (kDebugMode) debugPrint('$event ${jsonEncode(data)}');
  }
}

class MallaMultimodalReviewValidator {
  static const _periodTypes = {
    'semester',
    'bimester',
    'trimester',
    'quarter',
    'annual',
    'other',
    'unknown',
  };
  static const _categories = {
    'mandatory',
    'elective',
    'specialty',
    'institutional',
    'general',
    'other',
    'unknown',
  };
  static const _prerequisiteStatuses = {'identified', 'none', 'unknown'};
  static MallaMultimodalReview validate(
    dynamic raw, {
    required MallaCurricular visionResult,
    required String model,
    required String processorVersion,
    required String documentHash,
  }) {
    if (raw is! Map) {
      throw const FormatException('La revisión Gemini no contiene un objeto.');
    }
    final root = _normalizeRemoteContract(Map<String, dynamic>.from(raw));
    final rawPeriod = root['periodOrganization'];
    final rawVisualAudit = root['visualAudit'];
    if (rawPeriod is! Map ||
        rawVisualAudit is! Map ||
        rawPeriod['type'] is! String ||
        _integer(rawPeriod['count']) == null ||
        rawPeriod['evidence'] is! List ||
        root['courseReviews'] is! List ||
        root['additionalCourses'] is! List ||
        root['prerequisites'] is! List ||
        root['certifications'] is! List ||
        root['academicRequirements'] is! List ||
        root['pendingReview'] is! List) {
      throw const FormatException(
        'La revisión Gemini no cumple el contrato estructurado.',
      );
    }
    final visualAuditMap = _map(rawVisualAudit);
    final certificationContainersInspected =
        visualAuditMap['certificationContainersInspected'] == true;
    final certificationContainerCount = _integer(
      visualAuditMap['certificationContainerCount'],
    );
    final certificationTitles = _strings(
      visualAuditMap['certificationTitles'],
      maxItems: 100,
    );
    final courseArrowsInspected =
        visualAuditMap['courseArrowsInspected'] == true;
    final coursePrerequisiteConnectionCount = _integer(
      visualAuditMap['coursePrerequisiteConnectionCount'],
    );
    final unresolvedVisualSignals = _strings(
      visualAuditMap['unresolvedVisualSignals'],
      maxItems: 100,
    );
    final normalizedCertificationTitles = certificationTitles
        .map(_normalizeWords)
        .where((value) => value.isNotEmpty)
        .toSet();
    if (!certificationContainersInspected || !courseArrowsInspected) {
      throw const FormatException(
        'Gemini no completó la inspección visual de certificaciones y flechas.',
      );
    }
    if (certificationContainerCount == null ||
        certificationContainerCount < 0 ||
        certificationContainerCount > 100 ||
        coursePrerequisiteConnectionCount == null ||
        coursePrerequisiteConnectionCount < 0 ||
        coursePrerequisiteConnectionCount > 1000 ||
        certificationContainerCount != normalizedCertificationTitles.length) {
      throw const FormatException(
        'La auditoría visual de Gemini contiene conteos incoherentes.',
      );
    }
    final validIds = {for (final course in visionResult.ramos) course.id};
    final coursesById = {
      for (final course in visionResult.ramos) course.id: course,
    };
    final knownCodes = <String>{};
    final knownNames = <String>{};
    for (final course in visionResult.ramos) {
      final code = _normalizedCode(course.codigo);
      final name = _normalizedName(course.nombre);
      if (code != null) knownCodes.add(code);
      if (name != null) knownNames.add(name);
    }
    final issues = <String>[];
    final period = _map(root['periodOrganization']);
    var periodType = _text(period['type']) ?? 'unknown';
    var periodCount = _integer(period['count']) ?? 0;
    final periodEvidence = _strings(period['evidence']);
    if (!_periodTypes.contains(periodType)) periodType = 'unknown';
    if (periodCount < 0 || periodCount > 30) periodCount = 0;
    if (periodType != 'unknown' && periodEvidence.isEmpty) {
      issues.add('period_organization_without_evidence');
      periodType = 'unknown';
    }

    final courses = <MallaCourseReview>[];
    final reviewedIds = <String>{};
    for (final value in _list(root['courseReviews']).take(500)) {
      final item = _map(value);
      final id = _text(item['courseId']);
      if (id == null || !validIds.contains(id)) {
        issues.add('unknown_course_reference');
        continue;
      }
      if (!reviewedIds.add(id)) {
        issues.add('duplicate_course_review:$id');
        continue;
      }
      final evidence = _strings(item['evidence']);
      var name = _boundedText(item['proposedName'], 300);
      var code = _boundedText(item['proposedCode'], 64);
      var credits = _integer(item['proposedCredits']);
      var proposedPeriod = _integer(item['proposedPeriod']);
      var categoryLabel = _boundedText(item['categoryLabel'], 160);
      var category = _normalizeCategory(item['category'], categoryLabel);
      var prerequisiteStatus = _text(item['prerequisiteStatus']) ?? 'unknown';
      var prerequisiteStatusEvidence = _strings(
        item['prerequisiteStatusEvidence'],
      );
      final pendingReasons = _strings(item['pendingReasons']).toSet();
      if (credits != null && (credits < 0 || credits > 999)) credits = null;
      if (proposedPeriod != null &&
          (proposedPeriod < 1 ||
              proposedPeriod > 30 ||
              periodCount > 0 && proposedPeriod > periodCount)) {
        proposedPeriod = null;
        issues.add('invalid_period_proposal:$id');
      }
      if (!_prerequisiteStatuses.contains(prerequisiteStatus)) {
        prerequisiteStatus = 'unknown';
      }
      if (prerequisiteStatus == 'none' &&
          !_confirmsNoPrerequisites(prerequisiteStatusEvidence)) {
        prerequisiteStatus = 'unknown';
        prerequisiteStatusEvidence = const [];
        pendingReasons.add('prerequisite_absence_not_confirmed');
        issues.add('prerequisite_none_without_explicit_evidence:$id');
      }
      final claimEvidence = {
        ...evidence,
        ...prerequisiteStatusEvidence,
      }.take(8).toList();
      final hasClaim =
          name != null ||
          code != null ||
          credits != null ||
          proposedPeriod != null ||
          category != 'unknown' ||
          categoryLabel != null ||
          prerequisiteStatus != 'unknown';
      if (hasClaim && claimEvidence.isEmpty) {
        name = null;
        code = null;
        credits = null;
        proposedPeriod = null;
        category = 'unknown';
        categoryLabel = null;
        prerequisiteStatus = 'unknown';
        prerequisiteStatusEvidence = const [];
        issues.add('course_claim_without_evidence:$id');
      }
      courses.add(
        MallaCourseReview(
          courseId: id,
          proposedName: name,
          proposedCode: code,
          proposedCredits: credits,
          proposedPeriod: proposedPeriod,
          category: category,
          categoryLabel: categoryLabel,
          prerequisiteStatus: prerequisiteStatus,
          prerequisiteStatusEvidence: prerequisiteStatusEvidence,
          evidence: claimEvidence,
          pendingReasons: pendingReasons.toList(),
        ),
      );
    }

    final additionalCourses = <MallaAdditionalCourseProposal>[];
    final proposalReferences = <String, String>{};
    final proposalIds = <String>{};
    final proposalCodes = <String>{};
    final proposalNames = <String>{};
    for (final value in _list(root['additionalCourses']).take(200)) {
      final item = _map(value);
      final proposalKey = _boundedText(item['proposalKey'], 40);
      final cachedId = _boundedText(item['id'], 64);
      final validProposalKey =
          proposalKey != null &&
          RegExp(r'^new_[A-Za-z0-9_-]{1,32}$').hasMatch(proposalKey);
      final validCachedId =
          cachedId != null &&
          RegExp(r'^gemini_proposal_[a-f0-9]{20}$').hasMatch(cachedId);
      final name = _boundedText(item['proposedName'], 300);
      final code = _boundedText(item['proposedCode'], 64);
      final normalizedName = _normalizedName(name);
      final normalizedCode = _normalizedCode(code);
      final evidence = _strings(item['evidence']);
      final pendingReasons = _strings(item['pendingReasons']).toSet();
      if ((!validProposalKey && !validCachedId) ||
          validProposalKey && proposalReferences.containsKey(proposalKey) ||
          validCachedId && proposalIds.contains(cachedId) ||
          name == null ||
          normalizedName == null ||
          evidence.isEmpty) {
        issues.add('invalid_additional_course');
        continue;
      }
      if (knownNames.contains(normalizedName) ||
          !proposalNames.add(normalizedName) ||
          normalizedCode != null &&
              (knownCodes.contains(normalizedCode) ||
                  !proposalCodes.add(normalizedCode))) {
        issues.add('duplicate_additional_course');
        continue;
      }

      var credits = _integer(item['proposedCredits']);
      if (credits != null && (credits < 0 || credits > 999)) credits = null;
      var proposedPeriod = _integer(item['proposedPeriod']);
      if (proposedPeriod == null ||
          proposedPeriod < 1 ||
          proposedPeriod > 30 ||
          periodCount > 0 && proposedPeriod > periodCount) {
        proposedPeriod = null;
        pendingReasons.add('period_uncertain');
      }
      if (code == null) pendingReasons.add('code_uncertain');
      final categoryLabel = _boundedText(item['categoryLabel'], 160);
      final category = _normalizeCategory(item['category'], categoryLabel);
      final id = validCachedId
          ? cachedId
          : _temporaryProposalId(
              documentHash: documentHash,
              proposalKey: proposalKey!,
              name: normalizedName,
              code: normalizedCode,
              period: proposedPeriod,
            );
      proposalIds.add(id);
      if (validProposalKey) proposalReferences[proposalKey] = id;
      proposalReferences[id] = id;
      additionalCourses.add(
        MallaAdditionalCourseProposal(
          id: id,
          proposedName: name,
          proposedCode: code,
          proposedCredits: credits,
          proposedPeriod: proposedPeriod,
          category: category,
          categoryLabel: categoryLabel,
          evidence: evidence,
          pendingReasons: pendingReasons.toList(),
        ),
      );
    }

    String? resolveReference(dynamic rawReference) {
      final reference = _text(rawReference);
      if (reference == null) return null;
      if (validIds.contains(reference)) return reference;
      return proposalReferences[reference];
    }

    final prerequisites = <MallaPrerequisiteReview>[];
    final relationKeys = <String>{};
    for (final value in _list(root['prerequisites']).take(1000)) {
      final item = _map(value);
      final courseId = resolveReference(item['courseId']);
      final requiredId = resolveReference(item['requiresCourseId']);
      final sourceAnchor = _boundedText(item['sourceAnchor'], 500);
      final targetArrowhead = _boundedText(item['targetArrowhead'], 500);
      final pathContinuity = _boundedText(item['pathContinuity'], 700);
      final ambiguous = item['ambiguous'] != false;
      final evidence = {
        ..._strings(item['evidence']),
        ?sourceAnchor,
        ?targetArrowhead,
        ?pathContinuity,
      }.take(12).toList();
      final relationPending = _strings(item['pendingReasons']).toSet();
      var certainty = _normalizePrerequisiteCertainty(item['certainty']);
      final key = '$courseId>$requiredId';
      final pathSupported =
          courseId != null &&
          requiredId != null &&
          _supportsPrerequisitePath(
            sourceAnchor: sourceAnchor,
            targetArrowhead: targetArrowhead,
            pathContinuity: pathContinuity,
            course: coursesById[courseId],
            requiredCourse: coursesById[requiredId],
          );
      if (ambiguous || !pathSupported) {
        certainty = 'uncertain';
        relationPending.add(
          ambiguous ? 'relation_path_ambiguous' : 'relation_path_not_verified',
        );
      }
      if (certainty != 'confirmed') {
        relationPending.add('relation_direction_uncertain');
      }
      if (evidence.isEmpty) relationPending.add('relation_evidence_missing');
      if (courseId != null &&
          requiredId != null &&
          evidence.isNotEmpty &&
          !_supportsPrerequisite(
            evidence: evidence,
            course: coursesById[courseId],
            requiredCourse: coursesById[requiredId],
          )) {
        relationPending.add('relation_evidence_uncertain');
      }
      if (courseId == null ||
          requiredId == null ||
          courseId == requiredId ||
          !relationKeys.add(key)) {
        issues.add('invalid_prerequisite_relation');
        continue;
      }
      prerequisites.add(
        MallaPrerequisiteReview(
          courseId: courseId,
          requiresCourseId: requiredId,
          evidence: evidence,
          certainty: certainty,
          pendingReasons: relationPending.toList(),
        ),
      );
    }

    final prerequisiteEvidence = <String, List<String>>{};
    final incomingRelationIds = <String>{};
    final outgoingRelationIds = <String>{};
    for (final relation in prerequisites) {
      incomingRelationIds.add(relation.courseId);
      outgoingRelationIds.add(relation.requiresCourseId);
      if (relation.certainty != 'confirmed' ||
          relation.pendingReasons.isNotEmpty) {
        continue;
      }
      prerequisiteEvidence
          .putIfAbsent(relation.courseId, () => <String>[])
          .addAll(relation.evidence);
    }
    for (var index = 0; index < courses.length; index++) {
      final course = courses[index];
      final acceptedEvidence = prerequisiteEvidence[course.courseId];
      var status = course.prerequisiteStatus;
      final pending = course.pendingReasons
          .where((reason) => reason != 'prerequisite_relation_not_confirmed')
          .toSet();
      if (acceptedEvidence != null && acceptedEvidence.isNotEmpty) {
        if (status == 'none') {
          issues.add('prerequisite_status_conflict:${course.courseId}');
        }
        status = 'identified';
      } else if (status == 'identified') {
        status = 'unknown';
        final hasIncomingRelation = incomingRelationIds.contains(
          course.courseId,
        );
        final hasOnlyOutgoingRelations =
            !hasIncomingRelation &&
            outgoingRelationIds.contains(course.courseId);
        if (!hasIncomingRelation && !hasOnlyOutgoingRelations) {
          pending.add('prerequisite_relation_missing');
        }
      }
      courses[index] = MallaCourseReview(
        courseId: course.courseId,
        proposedName: course.proposedName,
        proposedCode: course.proposedCode,
        proposedCredits: course.proposedCredits,
        proposedPeriod: course.proposedPeriod,
        category: course.category,
        categoryLabel: course.categoryLabel,
        prerequisiteStatus: status,
        prerequisiteStatusEvidence: status == 'none'
            ? course.prerequisiteStatusEvidence
            : acceptedEvidence ?? course.prerequisiteStatusEvidence,
        evidence: {...course.evidence, ...?acceptedEvidence}.take(8).toList(),
        pendingReasons: pending.toList(),
      );
    }
    for (final entry in prerequisiteEvidence.entries) {
      if (!validIds.contains(entry.key) || reviewedIds.contains(entry.key)) {
        continue;
      }
      reviewedIds.add(entry.key);
      courses.add(
        MallaCourseReview(
          courseId: entry.key,
          proposedName: null,
          proposedCode: null,
          proposedCredits: null,
          proposedPeriod: null,
          category: 'unknown',
          categoryLabel: null,
          prerequisiteStatus: 'identified',
          prerequisiteStatusEvidence: entry.value.take(8).toList(),
          evidence: entry.value.take(8).toList(),
          pendingReasons: const [],
        ),
      );
    }

    final certifications = <MallaCertificationReview>[];
    final certificationIds = <String>{};
    for (final value in _list(root['certifications']).take(100)) {
      final item = _map(value);
      final id = _boundedText(item['id'], 64);
      final name = _boundedText(item['name'], 160);
      final evidence = _strings(item['evidence']);
      final excludedNearbyCourseIds = _list(item['excludedNearbyCourseIds'])
          .map(resolveReference)
          .whereType<String>()
          .toSet();
      final memberships = <MallaCertificationMembership>[];
      final membershipIds = <String>{};
      for (final rawMembership in _list(item['memberships']).take(500)) {
        final membership = _map(rawMembership);
        final rawCourseId = _text(membership['courseId']);
        final courseId = resolveReference(rawCourseId);
        final basis = _normalizeCertificationBasis(membership['basis']);
        final boundaryStatus = _normalizeCertificationBoundaryStatus(
          membership['boundaryStatus'],
        );
        final boundaryEvidence = _boundedText(
          membership['boundaryEvidence'],
          700,
        );
        final membershipEvidence = {
          ..._strings(membership['evidence']),
          ?boundaryEvidence,
        }.take(10).toList();
        final membershipPending = _strings(membership['pendingReasons'])
            .toSet();
        if (courseId == null || !membershipIds.add(courseId)) {
          issues.add(
            'uncertain_certification_membership:${id ?? 'unknown'}:${rawCourseId ?? 'unknown'}',
          );
          continue;
        }
        if (excludedNearbyCourseIds.contains(courseId) ||
            boundaryStatus == 'outside') {
          issues.add(
            'certification_membership_outside:${id ?? 'unknown'}:$courseId',
          );
          continue;
        }
        if (basis == null) membershipPending.add('membership_basis_uncertain');
        if (boundaryStatus != 'inside') {
          membershipPending.add('membership_boundary_uncertain');
        }
        if (membershipEvidence.isEmpty) {
          membershipPending.add('membership_evidence_missing');
        } else if (!_supportsCertificationMembership(
          evidence: membershipEvidence,
          basis: basis,
          course: coursesById[courseId],
          certificationName: name,
          boundaryStatus: boundaryStatus,
        )) {
          membershipPending.add('membership_evidence_uncertain');
        }
        memberships.add(
          MallaCertificationMembership(
            courseId: courseId,
            basis: basis ?? 'pending_review',
            evidence: membershipEvidence,
            pendingReasons: membershipPending.toList(),
          ),
        );
      }
      if (id == null ||
          name == null ||
          !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) ||
          !certificationIds.add(id) ||
          memberships.isEmpty ||
          evidence.isEmpty) {
        issues.add('invalid_certification');
        continue;
      }
      certifications.add(
        MallaCertificationReview(
          id: id,
          name: name,
          courseIds: memberships.map((item) => item.courseId).toList(),
          evidence: evidence,
          memberships: memberships,
        ),
      );
    }

    final validatedCertificationTitles = certifications
        .map((item) => _normalizeWords(item.name))
        .toSet();
    if (certificationContainerCount != certifications.length ||
        !validatedCertificationTitles.containsAll(
          normalizedCertificationTitles,
        )) {
      throw const FormatException(
        'Gemini detectó certificaciones, pero no entregó todas sus estructuras válidas.',
      );
    }
    if ((coursePrerequisiteConnectionCount == 0 && prerequisites.isNotEmpty) ||
        (coursePrerequisiteConnectionCount > 0 && prerequisites.isEmpty)) {
      throw const FormatException(
        'Gemini detectó conexiones entre asignaturas, pero no entregó todos los prerrequisitos.',
      );
    }

    final academicRequirements = <MallaAcademicRequirement>[];
    final requirementReferences = <String>{};
    for (final value in _list(root['academicRequirements']).take(100)) {
      final item = _map(value);
      final requirementKey = _boundedText(item['requirementKey'], 40);
      final cachedId = _boundedText(item['id'], 64);
      final validRequirementKey =
          requirementKey != null &&
          RegExp(r'^req_[A-Za-z0-9_-]{1,32}$').hasMatch(requirementKey);
      final validCachedId =
          cachedId != null &&
          RegExp(r'^gemini_requirement_[a-f0-9]{20}$').hasMatch(cachedId);
      var description = _boundedText(item['description'], 500);
      final evidence = _strings(item['evidence']);
      final targetLabel = _boundedText(item['targetLabel'], 160);
      final rawTargetId = _text(item['targetCourseId']);
      final targetCourseId = resolveReference(rawTargetId);
      final pendingReasons = _strings(item['pendingReasons']).toSet();
      final type = _normalizeAcademicRequirementType(item['type']);
      if (type == 'unknown') pendingReasons.add('requirement_type_uncertain');
      if (rawTargetId != null && targetCourseId == null) {
        pendingReasons.add('requirement_target_unresolved');
      }
      var minimumLevel = _integer(item['minimumLevel']);
      if (minimumLevel != null && (minimumLevel < 1 || minimumLevel > 30)) {
        minimumLevel = null;
        pendingReasons.add('minimum_level_uncertain');
      }
      final evidenceLevel = _explicitApprovedLevel(evidence);
      final descriptionLevel = description == null
          ? null
          : _explicitApprovedLevel([description]);
      if (evidenceLevel != null) {
        if (minimumLevel != null && minimumLevel != evidenceLevel ||
            descriptionLevel != null && descriptionLevel != evidenceLevel) {
          pendingReasons.add('requirement_level_conflict');
        }
        if (description != null &&
            descriptionLevel != null &&
            descriptionLevel != evidenceLevel) {
          description = _replaceApprovedLevel(description, evidenceLevel);
        }
        minimumLevel = evidenceLevel;
      } else if (minimumLevel != null &&
          descriptionLevel != null &&
          minimumLevel != descriptionLevel) {
        pendingReasons.add('requirement_level_conflict');
      }
      if (evidence.isNotEmpty &&
          !_supportsAcademicRequirement(
            evidence: evidence,
            type: type,
            targetLabel: targetLabel,
            targetCourse: targetCourseId == null
                ? null
                : coursesById[targetCourseId],
          )) {
        pendingReasons.add('requirement_evidence_uncertain');
      }
      final reference = validCachedId ? cachedId : requirementKey;
      if ((!validRequirementKey && !validCachedId) ||
          reference == null ||
          !requirementReferences.add(reference) ||
          description == null ||
          evidence.isEmpty ||
          targetCourseId == null && targetLabel == null) {
        issues.add('invalid_academic_requirement');
        continue;
      }
      final id = validCachedId
          ? cachedId
          : _temporaryRequirementId(
              documentHash: documentHash,
              requirementKey: requirementKey!,
              description: description,
            );
      academicRequirements.add(
        MallaAcademicRequirement(
          id: id,
          type: type,
          targetCourseId: targetCourseId,
          targetLabel: targetLabel,
          description: description,
          minimumLevel: minimumLevel,
          evidence: evidence,
          pendingReasons: pendingReasons.toList(),
        ),
      );
    }

    return MallaMultimodalReview(
      model: model,
      processorVersion: processorVersion,
      documentHash: documentHash,
      periodType: periodType,
      periodCount: periodCount,
      periodEvidence: periodEvidence,
      courseReviews: courses,
      additionalCourses: additionalCourses,
      prerequisites: prerequisites,
      certifications: certifications,
      academicRequirements: academicRequirements,
      pendingReview: {
        ..._strings(root['pendingReview'], maxItems: 100),
        for (final signal in unresolvedVisualSignals)
          'unresolved_visual_signal:$signal',
        ...issues,
      }.toList(),
      visualAudit: MallaVisualAudit(
        certificationContainersInspected: certificationContainersInspected,
        certificationContainerCount: certificationContainerCount,
        certificationTitles: certificationTitles,
        courseArrowsInspected: courseArrowsInspected,
        coursePrerequisiteConnectionCount: coursePrerequisiteConnectionCount,
        unresolvedVisualSignals: unresolvedVisualSignals,
      ),
    );
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static Map<String, dynamic> _normalizeRemoteContract(
    Map<String, dynamic> root,
  ) {
    if (root['periodOrganization'] is Map) return root;
    if (!root.containsKey('periodType') ||
        !root.containsKey('periodCount') ||
        !root.containsKey('periodEvidence')) {
      return root;
    }
    return {
      ...root,
      'periodOrganization': {
        'type': root['periodType'],
        'count': root['periodCount'],
        'evidence': root['periodEvidence'],
      },
    };
  }

  static List<dynamic> _list(dynamic value) => value is List ? value : const [];

  static String? _text(dynamic value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  static String? _boundedText(dynamic value, int maxLength) {
    final text = _text(value);
    if (text == null || text.length > maxLength) return null;
    return text;
  }

  static String _normalizeWords(String value) => value
      .toLowerCase()
      .replaceAll(RegExp('[áàäâ]'), 'a')
      .replaceAll(RegExp('[éèëê]'), 'e')
      .replaceAll(RegExp('[íìïî]'), 'i')
      .replaceAll(RegExp('[óòöô]'), 'o')
      .replaceAll(RegExp('[úùüû]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  static String? _normalizedName(String? value) {
    if (value == null) return null;
    final normalized = _normalizeWords(value);
    return normalized.isEmpty ? null : normalized;
  }

  static String? _normalizedCode(String? value) {
    if (value == null) return null;
    final normalized = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return normalized.isEmpty ? null : normalized;
  }

  static String _normalizeCategory(dynamic rawCategory, String? label) {
    final raw = _normalizeWords(_text(rawCategory) ?? '');
    final visible = _normalizeWords(label ?? '');
    final combined = '$raw $visible';
    if (combined.contains('especialidad') || combined.contains('specialty')) {
      return 'specialty';
    }
    if (combined.contains('formacion sello') ||
        combined.contains('institutional') ||
        combined.contains('institution')) {
      return 'institutional';
    }
    if (combined.contains('obligatori') || combined.contains('mandatory')) {
      return 'mandatory';
    }
    if (combined.contains('electiv') || combined.contains('elective')) {
      return 'elective';
    }
    if (combined.contains('formacion general') || combined == 'general') {
      return 'general';
    }
    if (_categories.contains(raw)) return raw;
    return label == null ? 'unknown' : 'other';
  }

  static String _normalizePrerequisiteCertainty(dynamic value) {
    final normalized = _normalizeWords(_text(value) ?? '');
    const confirmed = {
      'confirmed',
      'certain',
      'clear',
      'explicit',
      'unequivocal',
      'confirmado',
      'cierto',
      'claro',
      'explicito',
      'inequivoco',
    };
    return confirmed.contains(normalized) ? 'confirmed' : 'uncertain';
  }

  static String? _normalizeCertificationBasis(dynamic value) {
    final normalized = _normalizeWords(_text(value) ?? '').replaceAll(' ', '_');
    const aliases = {
      'container': 'container',
      'inside_container': 'container',
      'within_container': 'container',
      'visual_container': 'container',
      'enclosure': 'container',
      'grouped_inside': 'container',
      'legend': 'legend',
      'color_legend': 'legend',
      'legend_color': 'legend',
      'explicit_label': 'explicit_label',
      'label': 'explicit_label',
      'labeled': 'explicit_label',
      'explicit_text': 'explicit_label',
    };
    return aliases[normalized];
  }

  static String _normalizeCertificationBoundaryStatus(dynamic value) {
    final normalized = _normalizeWords(_text(value) ?? '').replaceAll(' ', '_');
    const aliases = {
      'inside': 'inside',
      'fully_inside': 'inside',
      'within': 'inside',
      'dentro': 'inside',
      'integramente_dentro': 'inside',
      'outside': 'outside',
      'fuera': 'outside',
      'external': 'outside',
      'uncertain': 'uncertain',
      'ambiguous': 'uncertain',
      'incierto': 'uncertain',
    };
    return aliases[normalized] ?? 'uncertain';
  }

  static String _normalizeAcademicRequirementType(dynamic value) {
    final normalized = _normalizeWords(_text(value) ?? '').replaceAll(' ', '_');
    const aliases = {
      'approved_level': 'approved_level',
      'approved_levels': 'approved_level',
      'level_approval': 'approved_level',
      'levels_approved': 'approved_level',
      'nivel_aprobado': 'approved_level',
      'completed_periods': 'completed_periods',
      'completed_semesters': 'completed_periods',
      'completed_bimesters': 'completed_periods',
      'practice_eligibility': 'practice_eligibility',
      'internship_eligibility': 'practice_eligibility',
      'practice_requirement': 'practice_eligibility',
      'capstone_eligibility': 'capstone_eligibility',
      'capstone_requirement': 'capstone_eligibility',
      'other': 'other',
      'unknown': 'unknown',
    };
    return aliases[normalized] ?? 'unknown';
  }

  static bool _supportsCertificationMembership({
    required List<String> evidence,
    required String? basis,
    required RamoMalla? course,
    required String? certificationName,
    required String boundaryStatus,
  }) {
    if (basis == null || course == null || certificationName == null) {
      return false;
    }
    final text = _normalizeWords(evidence.join(' '));
    final courseMentioned = _mentionsAny(text, [
      course.id,
      course.codigo,
      course.nombre,
    ]);
    final certificationMentioned = _mentionsAny(text, [certificationName]);
    final basisSupported = switch (basis) {
      'container' =>
        boundaryStatus == 'inside' &&
            const [
              'cuatro bordes',
              '4 bordes',
              'completamente dentro',
              'integramente dentro',
              'totalmente dentro',
              'contenido dentro',
              'dentro del contenedor',
              'fully inside',
              'all four edges',
              'fully enclosed',
              'entirely inside',
              'inside the container',
            ].any(text.contains),
      'legend' => const ['leyenda', 'legend', 'color'].any(text.contains),
      'explicit_label' => const [
        'etiqueta',
        'label',
        'rotulo',
        'titulo',
      ].any(text.contains),
      _ => false,
    };
    return courseMentioned && certificationMentioned && basisSupported;
  }

  static bool _supportsPrerequisitePath({
    required String? sourceAnchor,
    required String? targetArrowhead,
    required String? pathContinuity,
    required RamoMalla? course,
    required RamoMalla? requiredCourse,
  }) {
    if (sourceAnchor == null ||
        targetArrowhead == null ||
        pathContinuity == null ||
        course == null ||
        requiredCourse == null) {
      return false;
    }
    final source = _normalizeWords(sourceAnchor);
    final target = _normalizeWords(targetArrowhead);
    final path = _normalizeWords(pathContinuity);
    final sourceSupported =
        _mentionsAny(source, [
          requiredCourse.id,
          requiredCourse.codigo,
          requiredCourse.nombre,
        ]) &&
        const [
          'borde',
          'edge',
          'sale',
          'nace',
          'starts',
          'origin',
        ].any(source.contains);
    final targetSupported =
        _mentionsAny(target, [course.id, course.codigo, course.nombre]) &&
        const [
          'punta',
          'arrowhead',
          'termina',
          'ends',
          'llega',
          'entra',
        ].any(target.contains);
    final continuousPath = const [
      'continu',
      'direct',
      'recorrido',
      'path',
      'trayecto',
    ].any(path.contains);
    final adjacencyOnly = const [
      'solo por proximidad',
      'solo por alineacion',
      'sin continuidad',
      'borde del contenedor',
      'container border',
      'period separator',
      'separador de periodo',
    ].any(path.contains);
    return sourceSupported &&
        targetSupported &&
        continuousPath &&
        !adjacencyOnly;
  }

  static bool _supportsPrerequisite({
    required List<String> evidence,
    required RamoMalla? course,
    required RamoMalla? requiredCourse,
  }) {
    if (course == null || requiredCourse == null) return false;
    final rawText = evidence.join(' ');
    final text = _normalizeWords(rawText);
    final courseMentioned = _mentionsAny(text, [
      course.id,
      course.codigo,
      course.nombre,
    ]);
    final requiredMentioned = _mentionsAny(text, [
      requiredCourse.id,
      requiredCourse.codigo,
      requiredCourse.nombre,
    ]);
    final hasConnectorWord = const [
      'flecha',
      'arrow',
      'conector',
      'connector',
      'linea',
      'line',
    ].any(text.contains);
    final hasDirectionWord = const [
      'desde',
      'hacia',
      'from',
      'hasta',
      'termina',
      'punta',
      'direction',
    ].any(text.contains);
    final hasForwardArrow = RegExp(r'(?:-{1,2}>|→|⟶|➜|⇒|⟹)').hasMatch(rawText);
    final hasBackwardArrow = RegExp(r'(?:<-{1,2}|←|⟵|⇐|⟸)').hasMatch(rawText);
    final courseIndex = _firstReferenceIndex(text, course);
    final requiredIndex = _firstReferenceIndex(text, requiredCourse);
    final forwardOrder =
        requiredIndex != null &&
        courseIndex != null &&
        requiredIndex < courseIndex;
    final backwardOrder =
        requiredIndex != null &&
        courseIndex != null &&
        courseIndex < requiredIndex;
    final arrowSupportsDirection =
        hasForwardArrow && forwardOrder || hasBackwardArrow && backwardOrder;
    final directConnector = const [
      'directa',
      'directo',
      'direct',
    ].any(text.contains);
    final wordsSupportDirection =
        hasConnectorWord &&
        (hasDirectionWord || directConnector && forwardOrder);
    return courseMentioned &&
        requiredMentioned &&
        (arrowSupportsDirection || wordsSupportDirection);
  }

  static int? _firstReferenceIndex(String text, RamoMalla course) {
    final aliases = <String>{
      for (final value in [course.id, course.codigo, course.nombre])
        if (_normalizeWords(value ?? '') case final normalized
            when normalized.isNotEmpty)
          normalized,
    }.toList()..sort((left, right) => right.length.compareTo(left.length));
    int? result;
    for (final alias in aliases) {
      final index = text.indexOf(alias);
      if (index >= 0 && (result == null || index < result)) result = index;
    }
    return result;
  }

  static bool _supportsAcademicRequirement({
    required List<String> evidence,
    required String type,
    required String? targetLabel,
    required RamoMalla? targetCourse,
  }) {
    final text = _normalizeWords(evidence.join(' '));
    final targetMentioned = _mentionsAny(text, [
      targetLabel,
      targetCourse?.codigo,
      targetCourse?.nombre,
    ]);
    if (!targetMentioned) return false;
    return switch (type) {
      'approved_level' || 'completed_periods' =>
        const [
              'nivel',
              'level',
              'semestre',
              'semester',
              'periodo',
              'period',
            ].any(text.contains) &&
            const [
              'aprobado',
              'approved',
              'completado',
              'completed',
            ].any(text.contains),
      'practice_eligibility' => const [
        'practica',
        'practice',
        'internship',
      ].any(text.contains),
      'capstone_eligibility' => const [
        'capstone',
        'proyecto final',
        'final project',
      ].any(text.contains),
      'other' => const [
        'requisito',
        'requirement',
        'condicion',
        'condition',
      ].any(text.contains),
      _ => false,
    };
  }

  static bool _mentionsAny(String normalizedText, Iterable<String?> values) {
    for (final value in values) {
      if (value == null) continue;
      final normalizedWords = _normalizeWords(value);
      if (normalizedWords.isNotEmpty &&
          normalizedText.contains(normalizedWords)) {
        return true;
      }
      final normalizedCode = _normalizedCode(value)?.toLowerCase();
      if (normalizedCode != null &&
          normalizedText.replaceAll(' ', '').contains(normalizedCode)) {
        return true;
      }
    }
    return false;
  }

  static int? _explicitApprovedLevel(List<String> evidence) {
    for (final item in evidence) {
      final text = _normalizeWords(item);
      final hasAcademicCue = const [
        'nivel',
        'level',
        'aprobado',
        'approved',
        'completado',
        'completed',
      ].any(text.contains);
      if (!hasAcademicCue) continue;
      final range = RegExp(
        r'\b([ivx]{1,5}|\d{1,2})\s+(?:a|al|hasta|to)\s+([ivx]{1,5}|\d{1,2})\b',
      ).firstMatch(text);
      final value = _levelNumber(range?.group(2));
      if (value != null && value >= 1 && value <= 30) return value;
    }
    return null;
  }

  static int? _levelNumber(String? value) {
    if (value == null) return null;
    final numeric = int.tryParse(value);
    if (numeric != null) return numeric;
    const romanValues = {'i': 1, 'v': 5, 'x': 10};
    var total = 0;
    var previous = 0;
    for (final symbol in value.split('').reversed) {
      final current = romanValues[symbol];
      if (current == null) return null;
      if (current < previous) {
        total -= current;
      } else {
        total += current;
        previous = current;
      }
    }
    return total;
  }

  static String _replaceApprovedLevel(String description, int level) {
    final range = RegExp(
      r'\b([IVXivx]{1,5}|\d{1,2})(\s+(?:a|al|hasta|to)\s+)([IVXivx]{1,5}|\d{1,2})\b',
      caseSensitive: false,
    );
    return description.replaceFirstMapped(range, (match) {
      final currentEnd = match.group(3)!;
      final replacement = int.tryParse(currentEnd) == null
          ? _romanLevel(level)
          : level.toString();
      return '${match.group(1)}${match.group(2)}$replacement';
    });
  }

  static String _romanLevel(int value) {
    const symbols = <(int, String)>[
      (10, 'X'),
      (9, 'IX'),
      (5, 'V'),
      (4, 'IV'),
      (1, 'I'),
    ];
    var remaining = value;
    final result = StringBuffer();
    for (final (amount, symbol) in symbols) {
      while (remaining >= amount) {
        result.write(symbol);
        remaining -= amount;
      }
    }
    return result.toString();
  }

  static bool _confirmsNoPrerequisites(List<String> evidence) {
    for (final item in evidence) {
      final normalized = _normalizeWords(item);
      if (normalized.contains('sin prerrequisito') ||
          normalized.contains('no requiere prerrequisito') ||
          normalized.contains('ningun prerrequisito') ||
          normalized.contains('prerequisite none') ||
          normalized.contains('no prerequisites') ||
          normalized.contains('prerrequisitos no requeridos')) {
        return true;
      }
    }
    return false;
  }

  static String _temporaryProposalId({
    required String documentHash,
    required String proposalKey,
    required String name,
    required String? code,
    required int? period,
  }) {
    final digest = sha256
        .convert(
          utf8.encode(
            '$documentHash|$proposalKey|$name|${code ?? ''}|${period ?? -1}',
          ),
        )
        .toString();
    return 'gemini_proposal_${digest.substring(0, 20)}';
  }

  static String _temporaryRequirementId({
    required String documentHash,
    required String requirementKey,
    required String description,
  }) {
    final digest = sha256
        .convert(utf8.encode('$documentHash|$requirementKey|$description'))
        .toString();
    return 'gemini_requirement_${digest.substring(0, 20)}';
  }

  static int? _integer(dynamic value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    return null;
  }

  static List<String> _strings(dynamic value, {int maxItems = 8}) {
    if (value is! List) return const [];
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item.length <= 300)
        .take(maxItems)
        .toSet()
        .toList();
  }
}
