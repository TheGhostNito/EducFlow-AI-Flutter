import 'dart:convert';
import 'dart:typed_data';

import 'package:eduflow_ai/services/malla_multimodal_isolation_service.dart';
import 'package:eduflow_ai/services/malla_multimodal_review_service.dart';
import 'package:eduflow_ai/services/ocr_file_picker_service.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeIsolationClient implements MallaMultimodalIsolationClient {
  _FakeIsolationClient({required this.resultA, required this.resultB});

  final Object resultA;
  final Object resultB;
  int callsA = 0;
  int callsB = 0;

  @override
  Future<MallaMultimodalModelResponse> runWithoutSchema(
    OcrPickedFile file,
  ) async {
    callsA++;
    return _resolve(resultA);
  }

  @override
  Future<MallaMultimodalModelResponse> runWithMinimalSchema(
    OcrPickedFile file,
  ) async {
    callsB++;
    return _resolve(resultB);
  }

  static MallaMultimodalModelResponse _resolve(Object result) {
    if (result is Object Function()) throw result();
    return MallaMultimodalModelResponse(
      json: result as String,
      promptTokens: 10,
      outputTokens: 2,
      totalTokens: 12,
    );
  }
}

class _FakeAcademicIsolationClient
    implements MallaMultimodalAcademicIsolationClient {
  _FakeAcademicIsolationClient({required this.resultD, required this.resultE});

  final Object resultD;
  final Object resultE;
  int callsD = 0;
  int callsE = 0;

  @override
  Future<MallaMultimodalModelResponse> runWithAcademicSchema(
    OcrPickedFile file,
  ) async {
    callsD++;
    return _FakeIsolationClient._resolve(resultD);
  }

  @override
  Future<MallaMultimodalModelResponse> runWithAcademicContextAndMinimalSchema(
    OcrPickedFile file,
  ) async {
    callsE++;
    return _FakeIsolationClient._resolve(resultE);
  }
}

void main() {
  test('A no usa esquema y B serializa solo un objeto mínimo', () {
    final config = FirebaseMallaMultimodalIsolationClient
        .minimalGenerationConfigForTesting
        .toJson();
    final schema = config['responseSchema'] as Map<String, Object>;
    final properties = schema['properties'] as Map<String, Object>;

    expect(config.keys, {'responseMimeType', 'responseSchema'});
    expect(config['responseMimeType'], 'application/json');
    expect(properties.keys, {'result'});
    expect(schema['required'], ['result']);
  });

  test('D reutiliza exactamente el esquema C sin otros parámetros', () {
    final configD = FirebaseMallaMultimodalIsolationClient
        .academicSchemaOnlyConfigForTesting
        .toJson();
    final configC = FirebaseMallaMultimodalModelClient
        .generationConfigForTesting
        .toJson();

    expect(configD.keys, {'responseMimeType', 'responseSchema'});
    expect(configD['responseMimeType'], 'application/json');
    expect(
      jsonEncode(configD['responseSchema']),
      jsonEncode(configC['responseSchema']),
    );
    expect(configD['maxOutputTokens'], isNull);
  });

  test('E conserva contexto C pero usa el esquema mínimo de B', () {
    final config = FirebaseMallaMultimodalIsolationClient
        .academicContextConfigForTesting
        .toJson();
    final schema = config['responseSchema'] as Map<String, Object>;
    final properties = schema['properties'] as Map<String, Object>;

    expect(config['maxOutputTokens'], 12288);
    expect(config['responseMimeType'], 'application/json');
    expect(config['thinkingConfig'], {'thinkingLevel': 'LOW'});
    expect(properties.keys, {'result'});
  });

  test('si A falla no consume la solicitud B', () async {
    final client = _FakeIsolationClient(
      resultA: () => ServerException('Request contains an invalid argument.'),
      resultB: jsonEncode({'result': 'ok'}),
    );
    final outcome = await MallaMultimodalIsolationService(client: client)
        .run(_file);

    expect(outcome.testA.successful, isFalse);
    expect(outcome.testB.executed, isFalse);
    expect(client.callsA, 1);
    expect(client.callsB, 0);
    expect(outcome.conclusion, startsWith('A falló'));
  });

  test('si A funciona ejecuta B y valida su JSON mínimo', () async {
    final client = _FakeIsolationClient(
      resultA: 'Documento académico',
      resultB: jsonEncode({'result': 'visible'}),
    );
    final outcome = await MallaMultimodalIsolationService(client: client)
        .run(_file);

    expect(outcome.testA.successful, isTrue);
    expect(outcome.testB.successful, isTrue);
    expect(outcome.testB.totalTokens, 12);
    expect(client.callsA, 1);
    expect(client.callsB, 1);
    expect(outcome.conclusion, startsWith('A y B funcionan'));
  });

  test('distingue cuando solo falla la salida estructurada mínima', () async {
    final client = _FakeIsolationClient(
      resultA: 'Documento académico',
      resultB: () => ServerException('INVALID_ARGUMENT response schema'),
    );
    final outcome = await MallaMultimodalIsolationService(client: client)
        .run(_file);

    expect(outcome.testA.successful, isTrue);
    expect(outcome.testB.successful, isFalse);
    expect(outcome.testB.error!.category, 'invalid_request');
    expect(outcome.testB.error!.retryable, isFalse);
    expect(outcome.conclusion, startsWith('A funciona y B falla'));
  });

  test('si D falla no consume la solicitud E', () async {
    final client = _FakeAcademicIsolationClient(
      resultD: () => ServerException('INVALID_ARGUMENT response schema'),
      resultE: jsonEncode({'result': 'ok'}),
    );
    final outcome = await MallaMultimodalAcademicIsolationService(
      client: client,
    ).run(_file);

    expect(outcome.testD.successful, isFalse);
    expect(outcome.testE.executed, isFalse);
    expect(client.callsD, 1);
    expect(client.callsE, 0);
    expect(outcome.conclusion, startsWith('D falló'));
  });

  test('si D funciona no consume la solicitud E', () async {
    final client = _FakeAcademicIsolationClient(
      resultD: jsonEncode(_academicResponse),
      resultE: jsonEncode({'result': 'ok'}),
    );
    final outcome = await MallaMultimodalAcademicIsolationService(
      client: client,
    ).run(_file);

    expect(outcome.testD.successful, isTrue);
    expect(outcome.testE.executed, isFalse);
    expect(client.callsD, 1);
    expect(client.callsE, 0);
    expect(outcome.conclusion, startsWith('D funciona'));
  });
}

const _academicResponse = <String, Object?>{
  'periodType': 'unknown',
  'periodCount': 0,
  'periodEvidence': <String>[],
  'courseReviews': <Object?>[],
  'additionalCourses': <Object?>[],
  'prerequisites': <Object?>[],
  'certifications': <Object?>[],
  'academicRequirements': <Object?>[],
  'pendingReview': <Object?>[],
};

final _file = OcrPickedFile(
  name: 'control.jpg',
  bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]),
  mimeType: 'image/jpeg',
  sizeBytes: 4,
);
