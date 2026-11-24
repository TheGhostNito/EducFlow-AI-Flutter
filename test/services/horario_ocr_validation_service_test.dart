import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:eduflow_ai/models/horario_ocr_result.dart';
import 'package:eduflow_ai/services/horario_ocr_extraction_service.dart';
import 'package:eduflow_ai/services/horario_ocr_document_service.dart';
import 'package:eduflow_ai/services/horario_ocr_validation_service.dart';
import 'package:eduflow_ai/services/ocr_document_service.dart';
import 'package:eduflow_ai/services/ocr_file_picker_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const validator = HorarioOcrValidationService();

  group('casos conocidos DUOC', () {
    for (final entry in [
      (
        file: 'test/fixtures/horario_duoc_2024_known.json',
        year: 2024,
        name: 'Proceso de Portafolio 3',
        dates: const ['2024-03-25', '2024-04-22', '2024-05-20', '2024-06-17'],
      ),
      (
        file: 'test/fixtures/horario_duoc_2025_known.json',
        year: 2025,
        name: 'Proceso de Portafolio 5',
        dates: const ['2025-03-27', '2025-04-24', '2025-05-22', '2025-06-19'],
      ),
    ]) {
      test('${entry.name} conserva solamente sus cuatro fechas', () {
        final raw = jsonDecode(File(entry.file).readAsStringSync());
        final result = validator.validate(
          Map<String, dynamic>.from(raw as Map),
          documentHash: 'fixture-${entry.year}',
          pageCount: 2,
        );
        final subject = result.subjects.single;

        expect(result.period.year, entry.year);
        expect(result.period.semester, 1);
        expect(subject.name, entry.name);
        expect(subject.weeklyBlocks, isEmpty);
        expect(
          subject.datedSessions.map((item) => _date(item.date!)),
          entry.dates,
        );
        expect(result.requiresHumanReview, isTrue);
      });
    }
  });

  test('une una tabla continuada solo con código y sección coincidentes', () {
    final raw = _validRaw();
    final first = Map<String, dynamic>.from(
      (raw['subjects'] as List).single as Map,
    );
    (raw['subjects'] as List).add({
      ...first,
      'subjectKey': 'subject_continuation',
      'sourcePages': [2],
      'weeklyBlocks': [_block('subject_continuation', day: 'martes', page: 2)],
    });

    final result = validator.validate(raw, documentHash: 'hash', pageCount: 2);

    expect(result.subjects, hasLength(1));
    expect(result.subjects.single.sourcePages, [1, 2]);
    expect(result.subjects.single.weeklyBlocks, hasLength(2));
    expect(
      result.issues.map((issue) => issue.code),
      contains('continued_subject_merged'),
    );
  });

  test('deduplica bloques y sesiones idénticas', () {
    final raw = _validRaw();
    final subject = (raw['subjects'] as List).single as Map<String, dynamic>;
    subject['weeklyBlocks'] = [_block('subject_1'), _block('subject_1')];
    subject['datedSessions'] = [_session('subject_1'), _session('subject_1')];

    final result = validator.validate(raw, documentHash: 'hash', pageCount: 2);

    expect(result.subjects.single.weeklyBlocks, hasLength(1));
    expect(result.subjects.single.datedSessions, hasLength(1));
  });

  test('rechaza un bloque visual asociado a otra asignatura', () {
    final raw = _validRaw();
    final subject = (raw['subjects'] as List).single as Map<String, dynamic>;
    subject['weeklyBlocks'] = [_block('subject_otra')];

    final result = validator.validate(raw, documentHash: 'hash', pageCount: 1);

    expect(result.subjects.single.weeklyBlocks, isEmpty);
    expect(
      result.issues.map((issue) => issue.code),
      contains('cross_subject_block_rejected'),
    );
    expect(result.hasBlockingIssues, isTrue);
  });

  test('marca códigos, horas y fechas ambiguas para revisión', () {
    final raw = _validRaw();
    final subject = (raw['subjects'] as List).single as Map<String, dynamic>;
    subject['code'] = '???';
    subject['weeklyBlocks'] = [
      _block('subject_1', start: '25:00', end: '08:00'),
    ];
    subject['datedSessions'] = [_session('subject_1', date: '2025-02-30')];

    final result = validator.validate(raw, documentHash: 'hash', pageCount: 1);
    final parsed = result.subjects.single;

    expect(parsed.pendingReasons, contains('subject_code_requires_review'));
    expect(
      parsed.weeklyBlocks.single.pendingReasons,
      contains('time_range_requires_review'),
    );
    expect(
      parsed.datedSessions.single.pendingReasons,
      contains('date_requires_review'),
    );
  });

  test('una sesión de otro año queda como error bloqueante', () {
    final raw = _validRaw();
    final subject = (raw['subjects'] as List).single as Map<String, dynamic>;
    subject['datedSessions'] = [_session('subject_1', date: '2024-04-22')];

    final result = validator.validate(raw, documentHash: 'hash', pageCount: 1);

    expect(
      result.issues.map((issue) => issue.code),
      contains('session_outside_period'),
    );
    expect(result.hasBlockingIssues, isTrue);
  });

  test('el contexto Vision conserva páginas y omite el parser de mallas', () {
    final context = HorarioOcrExtractionService.buildCompactVisionContext({
      'pageCount': 2,
      'text': 'Horario página uno\nHorario página dos',
      'courses': [
        {'name': 'resultado curricular que no corresponde'},
      ],
      'blocks': [
        {
          'page': 2,
          'text': 'Programación PGY1234 001D',
          'confidence': 0.91,
          'position': {'xMin': 10, 'yMin': 20},
        },
      ],
    });

    expect(context['pageCount'], 2);
    expect((context['blocks'] as List).single, containsPair('page', 2));
    expect(context, isNot(contains('courses')));
  });

  test('orquesta Vision y Gemini falsos sin llamadas externas', () async {
    final raw = _validRaw();
    final vision = _FakeVisionGateway();
    final model = _FakeModelClient(jsonEncode(raw));
    final service = HorarioOcrExtractionService(
      visionGateway: vision,
      modelClient: model,
    );
    final file = OcrPickedFile(
      name: 'horario.pdf',
      bytes: Uint8List.fromList([1, 2, 3]),
      mimeType: 'application/pdf',
      sizeBytes: 3,
    );

    final outcome = await service.extractWithDiagnostics(
      upload: const OcrDocumentResult(
        originalName: 'horario.pdf',
        bucket: 'ocr-temp',
        path: 'fake/horario.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 3,
      ),
      originalFile: file,
    );

    expect(vision.calls, 1);
    expect(model.calls, 1);
    expect(model.lastRequest?.mimeType, 'application/pdf');
    expect(outcome.result.subjects.single.name, 'Programación');
    expect(outcome.visionContext['text'], 'Programación');
    expect(jsonDecode(outcome.geminiJson), raw);
    expect(outcome.diagnostics.visionUnits, 2);
    expect(outcome.diagnostics.visionMonthlyUsed, 2);
    expect(outcome.diagnostics.visionDailyRemaining, 8);
  });

  test(
    'la ruta documental reutiliza carga y siempre solicita limpieza',
    () async {
      final documents = _FakeDocumentGateway();
      final extractor = _FakeExtractor(
        validator.validate(
          _validRaw(),
          documentHash: 'fake-hash',
          pageCount: 2,
        ),
      );
      final service = HorarioOcrDocumentService(
        documents: documents,
        extraction: extractor,
      );
      final file = OcrPickedFile(
        name: 'horario.pdf',
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'application/pdf',
        sizeBytes: 3,
      );

      final result = await service.extract(file);

      expect(result.documentHash, 'fake-hash');
      expect(documents.uploadCalls, 1);
      expect(documents.deletedPaths, ['fake/horario.pdf']);
      expect(extractor.calls, 1);
    },
  );

  test('el prompt exige revisión, evidencia y sesiones no recurrentes', () {
    final prompt = FirebaseHorarioOcrModelClient.buildPrompt({
      'pageCount': 2,
      'blocks': const [],
    });

    expect(prompt, contains('subjectKey'));
    expect(prompt, contains('continuar entre páginas'));
    expect(prompt, contains('no debe duplicarse como bloque semanal'));
    expect(prompt, contains('No generes recurrencias mensuales'));
    expect(prompt, contains('pendingReview'));
  });
}

Map<String, dynamic> _validRaw() => {
  'period': {
    'year': 2025,
    'semester': 1,
    'startDate': '2025-03-01',
    'endDate': '2025-07-31',
    'evidence': ['Primer semestre 2025'],
    'pendingReasons': <String>[],
  },
  'subjects': <Map<String, dynamic>>[
    {
      'subjectKey': 'subject_1',
      'name': 'Programación',
      'code': 'PGY1234',
      'section': '001D',
      'professor': '',
      'professorEmail': '',
      'sourcePages': [1],
      'evidence': ['Programación PGY1234 sección 001D'],
      'pendingReasons': <String>[],
      'weeklyBlocks': [_block('subject_1')],
      'datedSessions': <Map<String, dynamic>>[],
    },
  ],
  'pendingReview': <String>[],
};

Map<String, dynamic> _block(
  String subjectKey, {
  String day = 'lunes',
  String start = '08:30',
  String end = '10:00',
  int page = 1,
}) => {
  'subjectKey': subjectKey,
  'day': day,
  'startTime': start,
  'endTime': end,
  'room': 'A-101',
  'page': page,
  'evidence': ['$day $start-$end A-101'],
  'pendingReasons': <String>[],
};

Map<String, dynamic> _session(
  String subjectKey, {
  String date = '2025-04-24',
}) => {
  'subjectKey': subjectKey,
  'date': date,
  'startTime': '18:30',
  'endTime': '20:00',
  'room': 'A-101',
  'page': 2,
  'evidence': ['$date 18:30-20:00 A-101'],
  'pendingReasons': <String>[],
};

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

class _FakeVisionGateway implements HorarioOcrVisionGateway {
  int calls = 0;

  @override
  Future<HorarioOcrVisionResponse> extract(OcrDocumentResult upload) async {
    calls++;
    return const HorarioOcrVisionResponse(
      documentHash: 'fake-hash',
      pageCount: 2,
      payload: {
        'pageCount': 2,
        'cacheHit': false,
        'monthlyUsage': {'usedUnits': 2, 'remainingUnits': 798},
        'dailyUsage': {'usedUnits': 2, 'remainingUnits': 8},
        'text': 'Programación',
        'blocks': [
          {'page': 1, 'text': 'Programación PGY1234'},
        ],
      },
    );
  }
}

class _FakeModelClient implements HorarioOcrModelClient {
  _FakeModelClient(this.json);

  final String json;
  int calls = 0;
  HorarioOcrModelRequest? lastRequest;

  @override
  Future<HorarioOcrModelResponse> extract(
    HorarioOcrModelRequest request,
  ) async {
    calls++;
    lastRequest = request;
    return HorarioOcrModelResponse(json: json);
  }
}

class _FakeDocumentGateway implements OcrDocumentGateway {
  int uploadCalls = 0;
  final List<String> deletedPaths = [];

  @override
  Future<OcrPickedFile?> pickDocument() async => null;

  @override
  Future<OcrDocumentResult> upload(OcrPickedFile pickedFile) async {
    uploadCalls++;
    return const OcrDocumentResult(
      originalName: 'horario.pdf',
      bucket: 'ocr-temp',
      path: 'fake/horario.pdf',
      mimeType: 'application/pdf',
      sizeBytes: 3,
    );
  }

  @override
  Future<void> deleteUploadedFile(String path) async {
    deletedPaths.add(path);
  }
}

class _FakeExtractor implements HorarioOcrExtractor {
  _FakeExtractor(this.result);

  final HorarioOcrResult result;
  int calls = 0;

  @override
  Future<HorarioOcrResult> extract({
    required OcrDocumentResult upload,
    required OcrPickedFile originalFile,
  }) async {
    calls++;
    return result;
  }

  @override
  Future<HorarioOcrRunOutcome> extractWithDiagnostics({
    required OcrDocumentResult upload,
    required OcrPickedFile originalFile,
  }) async {
    calls++;
    return HorarioOcrRunOutcome(
      result: result,
      diagnostics: HorarioOcrRunDiagnostics(
        documentHash: result.documentHash,
        pageCount: result.pageCount,
        visionUnits: result.pageCount,
        visionCacheHit: false,
        visionMonthlyUsed: null,
        visionMonthlyRemaining: null,
        visionDailyUsed: null,
        visionDailyRemaining: null,
        geminiPromptTokens: null,
        geminiOutputTokens: null,
        geminiTotalTokens: null,
        geminiFinishReason: null,
      ),
    );
  }
}
