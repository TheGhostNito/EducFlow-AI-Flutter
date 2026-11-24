import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/horario_ocr_result.dart';
import 'ai_service.dart';
import 'horario_ocr_validation_service.dart';
import 'ocr_document_service.dart';
import 'ocr_file_picker_service.dart';

class HorarioOcrVisionResponse {
  const HorarioOcrVisionResponse({
    required this.documentHash,
    required this.pageCount,
    required this.payload,
  });

  final String documentHash;
  final int pageCount;
  final Map<String, dynamic> payload;
}

abstract interface class HorarioOcrVisionGateway {
  Future<HorarioOcrVisionResponse> extract(OcrDocumentResult upload);
}

class SupabaseHorarioOcrVisionGateway implements HorarioOcrVisionGateway {
  SupabaseHorarioOcrVisionGateway({FirebaseAuth? auth, SupabaseClient? client})
    : _auth = auth ?? FirebaseAuth.instance,
      _client = client ?? Supabase.instance.client;

  final FirebaseAuth _auth;
  final SupabaseClient _client;

  @override
  Future<HorarioOcrVisionResponse> extract(OcrDocumentResult upload) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Inicia sesión antes de procesar.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('No se pudo autenticar el procesamiento OCR.');
    }

    // Reutiliza el endpoint Vision ya protegido. El parser curricular que el
    // endpoint adjunta a la respuesta se ignora por completo en esta ruta.
    final response = await _client.functions.invoke(
      'ocr-process',
      body: {
        'bucket': upload.bucket,
        'path': upload.path,
        'mimeType': upload.mimeType,
      },
      headers: {'Authorization': 'Bearer $token'},
    );
    if (_auth.currentUser?.uid != user.uid) {
      throw StateError('La sesión cambió durante el procesamiento.');
    }
    if (response.data is! Map) {
      throw const FormatException('Vision devolvió una respuesta inválida.');
    }
    final payload = Map<String, dynamic>.from(response.data as Map);
    if (payload['ok'] != true) {
      throw StateError(
        payload['message']?.toString() ??
            payload['error']?.toString() ??
            'Vision no pudo procesar el horario.',
      );
    }
    final hash = payload['documentHash']?.toString().trim() ?? '';
    final pageCount = _integer(payload['pageCount']);
    if (hash.isEmpty || pageCount == null || pageCount < 1 || pageCount > 5) {
      throw const FormatException(
        'Vision no entregó identidad y páginas válidas para el documento.',
      );
    }
    return HorarioOcrVisionResponse(
      documentHash: hash,
      pageCount: pageCount,
      payload: payload,
    );
  }

  int? _integer(Object? value) {
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

class HorarioOcrModelRequest {
  const HorarioOcrModelRequest({
    required this.bytes,
    required this.mimeType,
    required this.visionContext,
  });

  final Uint8List bytes;
  final String mimeType;
  final Map<String, Object?> visionContext;
}

class HorarioOcrModelResponse {
  const HorarioOcrModelResponse({
    required this.json,
    this.promptTokens,
    this.outputTokens,
    this.totalTokens,
    this.finishReason,
  });

  final String json;
  final int? promptTokens;
  final int? outputTokens;
  final int? totalTokens;
  final String? finishReason;
}

class HorarioOcrRunDiagnostics {
  const HorarioOcrRunDiagnostics({
    required this.documentHash,
    required this.pageCount,
    required this.visionUnits,
    required this.visionCacheHit,
    required this.visionMonthlyUsed,
    required this.visionMonthlyRemaining,
    required this.visionDailyUsed,
    required this.visionDailyRemaining,
    required this.geminiPromptTokens,
    required this.geminiOutputTokens,
    required this.geminiTotalTokens,
    required this.geminiFinishReason,
  });

  final String documentHash;
  final int pageCount;
  final int visionUnits;
  final bool visionCacheHit;
  final int? visionMonthlyUsed;
  final int? visionMonthlyRemaining;
  final int? visionDailyUsed;
  final int? visionDailyRemaining;
  final int? geminiPromptTokens;
  final int? geminiOutputTokens;
  final int? geminiTotalTokens;
  final String? geminiFinishReason;
}

class HorarioOcrRunOutcome {
  const HorarioOcrRunOutcome({
    required this.result,
    required this.diagnostics,
    this.visionContext = const {},
    this.geminiJson = '',
  });

  final HorarioOcrResult result;
  final HorarioOcrRunDiagnostics diagnostics;

  /// Evidencia compacta de Vision utilizada como contexto por Gemini.
  /// No contiene el resultado del parser curricular de `ocr-process`.
  final Map<String, Object?> visionContext;

  /// Respuesta estructurada original de Gemini antes de la validación local.
  final String geminiJson;
}

abstract interface class HorarioOcrModelClient {
  Future<HorarioOcrModelResponse> extract(HorarioOcrModelRequest request);
}

class FirebaseHorarioOcrModelClient implements HorarioOcrModelClient {
  FirebaseHorarioOcrModelClient({GenerativeModel? model})
    : _model = model ?? _createModel();

  final GenerativeModel _model;

  static const int maxOutputTokens = 8192;

  static const String systemInstructionText = '''
Eres un extractor de horarios académicos de EducFlow AI.
Usa el documento visual y el contexto OCR de Google Cloud Vision como evidencia.
No inventes asignaturas, códigos, secciones, salas, días, horas, fechas ni períodos.
Los campos ausentes deben ser texto vacío, cero o listas vacías y deben incluir un pendingReason.
Devuelve únicamente JSON conforme al esquema solicitado.
Todo resultado requiere revisión humana antes de guardarse.
''';

  static final Schema _responseSchema = Schema.object(
    properties: {
      'period': Schema.object(
        properties: {
          'year': Schema.integer(),
          'semester': Schema.integer(),
          'startDate': Schema.string(),
          'endDate': Schema.string(),
          'evidence': Schema.array(items: Schema.string()),
          'pendingReasons': Schema.array(items: Schema.string()),
        },
      ),
      'subjects': Schema.array(
        items: Schema.object(
          properties: {
            'subjectKey': Schema.string(),
            'name': Schema.string(),
            'code': Schema.string(),
            'section': Schema.string(),
            'professor': Schema.string(),
            'professorEmail': Schema.string(),
            'sourcePages': Schema.array(items: Schema.integer()),
            'evidence': Schema.array(items: Schema.string()),
            'pendingReasons': Schema.array(items: Schema.string()),
            'weeklyBlocks': Schema.array(
              items: Schema.object(
                properties: {
                  'subjectKey': Schema.string(),
                  'day': Schema.string(),
                  'startTime': Schema.string(),
                  'endTime': Schema.string(),
                  'room': Schema.string(),
                  'page': Schema.integer(),
                  'evidence': Schema.array(items: Schema.string()),
                  'pendingReasons': Schema.array(items: Schema.string()),
                },
              ),
            ),
            'datedSessions': Schema.array(
              items: Schema.object(
                properties: {
                  'subjectKey': Schema.string(),
                  'date': Schema.string(),
                  'startTime': Schema.string(),
                  'endTime': Schema.string(),
                  'room': Schema.string(),
                  'page': Schema.integer(),
                  'evidence': Schema.array(items: Schema.string()),
                  'pendingReasons': Schema.array(items: Schema.string()),
                },
              ),
            ),
          },
        ),
      ),
      'pendingReview': Schema.array(items: Schema.string()),
    },
  );

  static GenerativeModel _createModel() =>
      FirebaseAI.googleAI().generativeModel(
        model: AiService.modelName,
        generationConfig: GenerationConfig(
          maxOutputTokens: maxOutputTokens,
          responseMimeType: 'application/json',
          responseSchema: _responseSchema,
          thinkingConfig: ThinkingConfig.withThinkingLevel(ThinkingLevel.low),
        ),
        systemInstruction: Content.system(systemInstructionText),
      );

  @visibleForTesting
  static Schema get responseSchemaForTesting => _responseSchema;

  @visibleForTesting
  static String buildPrompt(Map<String, Object?> visionContext) =>
      '''
Extrae el horario académico completo. Las tablas pueden continuar entre páginas.

Reglas obligatorias:
- Crea subjectKey estables: subject_1, subject_2, etc.
- Une filas entre páginas solo si nombre/código/sección sostienen la misma identidad.
- Cada bloque y sesión debe repetir exactamente el subjectKey de su asignatura.
- weeklyBlocks contiene solo recurrencias semanales explícitas.
- datedSessions contiene solo fechas concretas impresas en el documento.
- Una sesión fechada no debe duplicarse como bloque semanal por aparecer en la tabla principal.
- No generes recurrencias mensuales a partir de cuatro fechas.
- Normaliza días en español y horas como HH:mm.
- Normaliza fechas como YYYY-MM-DD usando únicamente el año demostrado.
- Conserva una sala diferente para cada bloque o sesión.
- Código, sección, profesor y sala son opcionales; no inventes valores ausentes.
- Conserva profesor y correo solo cuando estén impresos explícitamente.
- Un código de sede o establecimiento entre sección y sala es un dato distinto: no lo anexes a la sección ni a la sala.
- Puedes unir módulos adyacentes de la misma asignatura, día y sala solo si son consecutivos; conserva cualquier brecha real.
- Cita evidencia breve y página para cada asignatura, bloque y sesión.
- Si una asociación visual entre una fila y una asignatura no es inequívoca, no la asignes y agrégala a pendingReview.
- No guardes ni confirmes datos.

VISION:
${jsonEncode(visionContext)}
''';

  @override
  Future<HorarioOcrModelResponse> extract(
    HorarioOcrModelRequest request,
  ) async {
    final response = await _model.generateContent([
      Content.multi([
        InlineDataPart(request.mimeType, request.bytes),
        TextPart(buildPrompt(request.visionContext)),
      ]),
    ]);
    final finishReason = response.candidates.isEmpty
        ? null
        : response.candidates.first.finishReason?.toJson();
    if (finishReason == FinishReason.maxTokens.toJson()) {
      throw const FormatException(
        'Gemini interrumpió la extracción al alcanzar MAX_TOKENS.',
      );
    }
    return HorarioOcrModelResponse(
      json: response.text ?? '',
      promptTokens: response.usageMetadata?.promptTokenCount,
      outputTokens: response.usageMetadata?.candidatesTokenCount,
      totalTokens: response.usageMetadata?.totalTokenCount,
      finishReason: finishReason,
    );
  }
}

abstract interface class HorarioOcrExtractor {
  Future<HorarioOcrResult> extract({
    required OcrDocumentResult upload,
    required OcrPickedFile originalFile,
  });

  Future<HorarioOcrRunOutcome> extractWithDiagnostics({
    required OcrDocumentResult upload,
    required OcrPickedFile originalFile,
  });
}

class HorarioOcrExtractionService implements HorarioOcrExtractor {
  HorarioOcrExtractionService({
    HorarioOcrVisionGateway? visionGateway,
    HorarioOcrModelClient? modelClient,
    HorarioOcrValidationService? validationService,
  }) : _visionGateway = visionGateway ?? SupabaseHorarioOcrVisionGateway(),
       _modelClient = modelClient ?? FirebaseHorarioOcrModelClient(),
       _validationService =
           validationService ?? const HorarioOcrValidationService();

  final HorarioOcrVisionGateway _visionGateway;
  final HorarioOcrModelClient _modelClient;
  final HorarioOcrValidationService _validationService;

  @override
  Future<HorarioOcrResult> extract({
    required OcrDocumentResult upload,
    required OcrPickedFile originalFile,
  }) async {
    return (await extractWithDiagnostics(
      upload: upload,
      originalFile: originalFile,
    )).result;
  }

  @override
  Future<HorarioOcrRunOutcome> extractWithDiagnostics({
    required OcrDocumentResult upload,
    required OcrPickedFile originalFile,
  }) async {
    final vision = await _visionGateway.extract(upload);
    final context = buildCompactVisionContext(vision.payload);
    final model = await _modelClient.extract(
      HorarioOcrModelRequest(
        bytes: originalFile.bytes,
        mimeType: originalFile.mimeType,
        visionContext: context,
      ),
    );
    if (model.json.trim().isEmpty) {
      throw const FormatException('Gemini no devolvió JSON de horario.');
    }
    final decoded = jsonDecode(model.json);
    if (decoded is! Map) {
      throw const FormatException('Gemini no devolvió un objeto de horario.');
    }
    final result = _validationService.validate(
      Map<String, dynamic>.from(decoded),
      documentHash: vision.documentHash,
      pageCount: vision.pageCount,
    );
    final monthly = _usage(vision.payload['monthlyUsage']);
    final daily = _usage(vision.payload['dailyUsage']);
    return HorarioOcrRunOutcome(
      result: result,
      visionContext: Map<String, Object?>.unmodifiable(context),
      geminiJson: model.json,
      diagnostics: HorarioOcrRunDiagnostics(
        documentHash: vision.documentHash,
        pageCount: vision.pageCount,
        visionUnits: vision.pageCount,
        visionCacheHit: vision.payload['cacheHit'] == true,
        visionMonthlyUsed: monthly.used,
        visionMonthlyRemaining: monthly.remaining,
        visionDailyUsed: daily.used,
        visionDailyRemaining: daily.remaining,
        geminiPromptTokens: model.promptTokens,
        geminiOutputTokens: model.outputTokens,
        geminiTotalTokens: model.totalTokens,
        geminiFinishReason: model.finishReason,
      ),
    );
  }

  @visibleForTesting
  static Map<String, Object?> buildCompactVisionContext(
    Map<String, dynamic> payload,
  ) {
    final blocks = payload['blocks'] is List
        ? (payload['blocks'] as List)
        : const [];
    return {
      'pageCount': payload['pageCount'],
      'text': _boundedText(payload['text'], 30000),
      'blocks': [
        for (final value in blocks.take(1000))
          if (value is Map)
            {
              'page': value['page'],
              'text': _boundedText(value['text'], 800),
              'confidence': value['confidence'],
              if (value['position'] is Map) 'position': value['position'],
              if (value['words'] is List)
                'words': [
                  for (final word in (value['words'] as List).take(200))
                    if (word is Map)
                      {
                        'text': _boundedText(word['text'], 100),
                        'confidence': word['confidence'],
                        if (word['position'] is Map)
                          'position': word['position'],
                      },
                ],
            },
      ],
    };
  }

  static String _boundedText(Object? value, int maxLength) {
    final text = value?.toString().trim() ?? '';
    return text.length <= maxLength ? text : text.substring(0, maxLength);
  }

  static ({int? used, int? remaining}) _usage(Object? value) {
    if (value is! Map) return (used: null, remaining: null);
    return (
      used: _diagnosticInteger(value['usedUnits']),
      remaining: _diagnosticInteger(value['remainingUnits']),
    );
  }

  static int? _diagnosticInteger(Object? value) {
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
