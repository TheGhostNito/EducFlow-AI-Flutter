import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import 'ai_service.dart';
import 'malla_multimodal_review_service.dart';
import 'ocr_file_picker_service.dart';

class MallaMultimodalIsolationStep {
  const MallaMultimodalIsolationStep({
    required this.id,
    required this.executed,
    required this.successful,
    required this.elapsedMilliseconds,
    this.promptTokens,
    this.outputTokens,
    this.totalTokens,
    this.error,
  });

  final String id;
  final bool executed;
  final bool successful;
  final int elapsedMilliseconds;
  final int? promptTokens;
  final int? outputTokens;
  final int? totalTokens;
  final MallaMultimodalSafeError? error;

  Map<String, Object?> toJson() => {
    'id': id,
    'executed': executed,
    'successful': successful,
    'elapsedMilliseconds': elapsedMilliseconds,
    'tokens': {
      'prompt': promptTokens,
      'output': outputTokens,
      'total': totalTokens,
    },
    if (error case final value?)
      'error': {
        'category': value.category,
        'errorType': value.errorType,
        'httpStatus': value.httpStatus,
        'backendStatus': value.backendStatus,
        'technicalMessage': value.technicalMessage,
        'retryable': value.retryable,
      },
  };
}

class MallaMultimodalIsolationOutcome {
  const MallaMultimodalIsolationOutcome({
    required this.testA,
    required this.testB,
    required this.conclusion,
  });

  final MallaMultimodalIsolationStep testA;
  final MallaMultimodalIsolationStep testB;
  final String conclusion;

  Map<String, Object?> toJson() => {
    'developmentOnly': true,
    'provider': 'gemini_developer_api',
    'model': AiService.modelName,
    'testA': testA.toJson(),
    'testB': testB.toJson(),
    'conclusion': conclusion,
  };
}

class MallaMultimodalAcademicIsolationOutcome {
  const MallaMultimodalAcademicIsolationOutcome({
    required this.testD,
    required this.testE,
    required this.conclusion,
  });

  final MallaMultimodalIsolationStep testD;
  final MallaMultimodalIsolationStep testE;
  final String conclusion;

  Map<String, Object?> toJson() => {
    'developmentOnly': true,
    'provider': 'gemini_developer_api',
    'model': AiService.modelName,
    'testD': testD.toJson(),
    'testE': testE.toJson(),
    'conclusion': conclusion,
  };
}

abstract interface class MallaMultimodalIsolationClient {
  Future<MallaMultimodalModelResponse> runWithoutSchema(OcrPickedFile file);
  Future<MallaMultimodalModelResponse> runWithMinimalSchema(OcrPickedFile file);
}

abstract interface class MallaMultimodalAcademicIsolationClient {
  Future<MallaMultimodalModelResponse> runWithAcademicSchema(
    OcrPickedFile file,
  );
  Future<MallaMultimodalModelResponse> runWithAcademicContextAndMinimalSchema(
    OcrPickedFile file,
  );
}

class FirebaseMallaMultimodalIsolationClient
    implements
        MallaMultimodalIsolationClient,
        MallaMultimodalAcademicIsolationClient {
  FirebaseMallaMultimodalIsolationClient({
    GenerativeModel? plainModel,
    GenerativeModel? minimalSchemaModel,
    GenerativeModel? academicSchemaModel,
    GenerativeModel? academicContextModel,
  }) : _plainModel = plainModel ?? _createPlainModel(),
       _minimalSchemaModel = minimalSchemaModel ?? _createMinimalSchemaModel(),
       _academicSchemaModel =
           academicSchemaModel ?? _createAcademicSchemaModel(),
       _academicContextModel =
           academicContextModel ?? _createAcademicContextModel();

  final GenerativeModel _plainModel;
  final GenerativeModel _minimalSchemaModel;
  final GenerativeModel _academicSchemaModel;
  final GenerativeModel _academicContextModel;

  static const String _minimalPrompt =
      'Confirma brevemente que puedes observar el documento en el campo result.';

  static GenerativeModel _createPlainModel() =>
      FirebaseAI.googleAI().generativeModel(model: AiService.modelName);

  static GenerativeModel _createMinimalSchemaModel() =>
      FirebaseAI.googleAI().generativeModel(
        model: AiService.modelName,
        generationConfig: _minimalGenerationConfig,
      );

  static GenerativeModel _createAcademicSchemaModel() =>
      FirebaseAI.googleAI().generativeModel(
        model: AiService.modelName,
        generationConfig: _academicSchemaOnlyGenerationConfig,
      );

  static GenerativeModel _createAcademicContextModel() =>
      FirebaseAI.googleAI().generativeModel(
        model: AiService.modelName,
        generationConfig: _academicContextGenerationConfig,
        systemInstruction: Content.system(
          FirebaseMallaMultimodalModelClient.systemInstructionText,
        ),
      );

  static final GenerationConfig _minimalGenerationConfig = GenerationConfig(
    responseMimeType: 'application/json',
    responseSchema: Schema.object(properties: {'result': Schema.string()}),
  );

  static final GenerationConfig _academicSchemaOnlyGenerationConfig =
      GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema:
            FirebaseMallaMultimodalModelClient.academicResponseSchema,
      );

  static final GenerationConfig _academicContextGenerationConfig =
      GenerationConfig(
        maxOutputTokens:
            FirebaseMallaMultimodalModelClient.multimodalMaxOutputTokens,
        responseMimeType: 'application/json',
        responseSchema: Schema.object(properties: {'result': Schema.string()}),
        thinkingConfig: ThinkingConfig.withThinkingLevel(ThinkingLevel.low),
      );

  @visibleForTesting
  static GenerationConfig get minimalGenerationConfigForTesting =>
      _minimalGenerationConfig;

  @visibleForTesting
  static GenerationConfig get academicSchemaOnlyConfigForTesting =>
      _academicSchemaOnlyGenerationConfig;

  @visibleForTesting
  static GenerationConfig get academicContextConfigForTesting =>
      _academicContextGenerationConfig;

  @override
  Future<MallaMultimodalModelResponse> runWithoutSchema(OcrPickedFile file) =>
      _generate(
        _plainModel,
        file,
        'Describe en una frase breve qué tipo de documento académico aparece.',
      );

  @override
  Future<MallaMultimodalModelResponse> runWithMinimalSchema(
    OcrPickedFile file,
  ) => _generate(_minimalSchemaModel, file, _minimalPrompt);

  @override
  Future<MallaMultimodalModelResponse> runWithAcademicSchema(
    OcrPickedFile file,
  ) => _generate(_academicSchemaModel, file, _minimalPrompt);

  @override
  Future<MallaMultimodalModelResponse> runWithAcademicContextAndMinimalSchema(
    OcrPickedFile file,
  ) => _generate(
    _academicContextModel,
    file,
    FirebaseMallaMultimodalModelClient.buildAcademicPrompt(
      candidates: _controlledCandidates,
      visionPayload: _controlledVisionPayload,
    ),
  );

  static const List<Map<String, Object?>> _controlledCandidates = [
    {
      'courseId': 'control_1',
      'name': 'Asignatura de control',
      'code': 'CTRL101',
      'credits': 4,
      'period': 1,
      'needsReview': false,
    },
  ];

  static const Map<String, dynamic> _controlledVisionPayload = {
    'ok': true,
    'courses': [
      {
        'id': 'control_1',
        'name': 'Asignatura de control',
        'code': 'CTRL101',
        'credits': 4,
        'semester': 1,
        'sourceBlocks': [
          {'text': 'Asignatura de control', 'x': 10, 'y': 10},
        ],
      },
    ],
  };

  static Future<MallaMultimodalModelResponse> _generate(
    GenerativeModel model,
    OcrPickedFile file,
    String prompt,
  ) async {
    final response = await model.generateContent([
      Content.multi([
        InlineDataPart(file.mimeType, file.bytes),
        TextPart(prompt),
      ]),
    ]);
    final text = response.text;
    if (text == null || text.trim().isEmpty) {
      throw const FormatException('Gemini devolvió contenido vacío.');
    }
    final usage = response.usageMetadata;
    return MallaMultimodalModelResponse(
      json: text,
      promptTokens: usage?.promptTokenCount,
      outputTokens: usage?.candidatesTokenCount,
      totalTokens: usage?.totalTokenCount,
    );
  }
}

class MallaMultimodalIsolationService {
  MallaMultimodalIsolationService({MallaMultimodalIsolationClient? client})
    : _client = client ?? FirebaseMallaMultimodalIsolationClient();

  final MallaMultimodalIsolationClient _client;

  Future<MallaMultimodalIsolationOutcome> run(OcrPickedFile file) async {
    if (!kDebugMode) {
      throw StateError(
        'El aislamiento A/B solo está disponible en desarrollo.',
      );
    }
    final testA = await _execute(
      'A_image_without_schema',
      () => _client.runWithoutSchema(file),
    );
    if (!testA.successful) {
      return MallaMultimodalIsolationOutcome(
        testA: testA,
        testB: const MallaMultimodalIsolationStep(
          id: 'B_image_with_minimal_schema',
          executed: false,
          successful: false,
          elapsedMilliseconds: 0,
        ),
        conclusion: 'A falló: revisar modelo, proveedor, App Check o contenido adjunto. B no se ejecutó.',
      );
    }

    final testB = await _execute(
      'B_image_with_minimal_schema',
      () => _client.runWithMinimalSchema(file),
      validator: _validateMinimalResponse,
    );
    return MallaMultimodalIsolationOutcome(
      testA: testA,
      testB: testB,
      conclusion: testB.successful
          ? 'A y B funcionan: el rechazo se concentra en el esquema o prompt académico completo.'
          : 'A funciona y B falla: el rechazo se concentra en la salida estructurada mínima o su soporte en el SDK.',
    );
  }

  static Future<MallaMultimodalIsolationStep> _execute(
    String id,
    Future<MallaMultimodalModelResponse> Function() action, {
    void Function(String response)? validator,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await action();
      validator?.call(response.json);
      stopwatch.stop();
      return MallaMultimodalIsolationStep(
        id: id,
        executed: true,
        successful: true,
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
        promptTokens: response.promptTokens,
        outputTokens: response.outputTokens,
        totalTokens: response.totalTokens,
      );
    } catch (error) {
      stopwatch.stop();
      return MallaMultimodalIsolationStep(
        id: id,
        executed: true,
        successful: false,
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
        error: MallaMultimodalSafeError.inspect(error),
      );
    }
  }

  static void _validateMinimalResponse(String response) {
    final decoded = jsonDecode(response);
    if (decoded is! Map || decoded['result'] is! String) {
      throw const FormatException(
        'La respuesta del esquema mínimo no contiene result.',
      );
    }
  }
}

class MallaMultimodalAcademicIsolationService {
  MallaMultimodalAcademicIsolationService({
    MallaMultimodalAcademicIsolationClient? client,
  }) : _client = client ?? FirebaseMallaMultimodalIsolationClient();

  final MallaMultimodalAcademicIsolationClient _client;

  Future<MallaMultimodalAcademicIsolationOutcome> run(
    OcrPickedFile file,
  ) async {
    if (!kDebugMode) {
      throw StateError(
        'El aislamiento D/E solo está disponible en desarrollo.',
      );
    }
    final testD = await MallaMultimodalIsolationService._execute(
      'D_image_with_academic_schema',
      () => _client.runWithAcademicSchema(file),
      validator: _validateAcademicResponse,
    );
    if (!testD.successful) {
      return MallaMultimodalAcademicIsolationOutcome(
        testD: testD,
        testE: const MallaMultimodalIsolationStep(
          id: 'E_academic_context_with_minimal_schema',
          executed: false,
          successful: false,
          elapsedMilliseconds: 0,
        ),
        conclusion: 'D falló: el rechazo queda aislado en el esquema académico remoto. E no se ejecutó.',
      );
    }

    return MallaMultimodalAcademicIsolationOutcome(
      testD: testD,
      testE: const MallaMultimodalIsolationStep(
        id: 'E_academic_context_with_minimal_schema',
        executed: false,
        successful: false,
        elapsedMilliseconds: 0,
      ),
      conclusion: 'D funciona con el esquema académico simplificado. E no se ejecutó para evitar una segunda solicitud innecesaria.',
    );
  }

  static void _validateAcademicResponse(String response) {
    final decoded = jsonDecode(response);
    if (decoded is! Map ||
        decoded['periodType'] is! String ||
        decoded['periodCount'] is! num ||
        decoded['periodEvidence'] is! List ||
        decoded['courseReviews'] is! List ||
        decoded['additionalCourses'] is! List ||
        decoded['prerequisites'] is! List ||
        decoded['certifications'] is! List ||
        decoded['academicRequirements'] is! List ||
        decoded['pendingReview'] is! List) {
      throw const FormatException(
        'La respuesta D no cumple la estructura académica raíz.',
      );
    }
  }
}
