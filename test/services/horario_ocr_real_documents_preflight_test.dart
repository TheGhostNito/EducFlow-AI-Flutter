import 'dart:convert';
import 'dart:io';

import 'package:eduflow_ai/services/horario_ocr_validation_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/horario_ocr_reference_comparator.dart';

void main() {
  const privateDirectory = 'test/private/horarios';
  final referenceFile = File(
    '$privateDirectory/educflow_horarios_duoc_2024_2025_referencia.json',
  );
  final reference = Map<String, dynamic>.from(
    jsonDecode(referenceFile.readAsStringSync()) as Map,
  );
  final documents = (reference['documentos'] as List)
      .map((value) => Map<String, dynamic>.from(value as Map))
      .toList();
  const validator = HorarioOcrValidationService();
  const comparator = HorarioOcrReferenceComparator();

  test('los dos PDF privados están disponibles y no exceden 10 MB', () {
    expect(documents, hasLength(2));
    for (final document in documents) {
      final file = File('$privateDirectory/${document['archivo_original']}');
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(0));
      expect(file.lengthSync(), lessThanOrEqualTo(10 * 1024 * 1024));
      expect(file.readAsBytesSync().take(5), [0x25, 0x50, 0x44, 0x46, 0x2d]);
      expect(document['paginas'], 2);
    }
  });

  test('ocr-process conserva texto y geometría de todas las páginas PDF', () {
    final source = File('supabase/functions/ocr-process/index.ts')
        .readAsStringSync();

    expect(source, contains('files:annotate'));
    expect(source, contains('DOCUMENT_TEXT_DETECTION'));
    expect(source, contains('length: pdfPageCount'));
    expect(source, contains('fullTextAnnotation?.text'));
    expect(source, contains('fullTextAnnotation?.pages'));
    expect(source, contains('logicalPageNumber'));
    expect(source, contains('boundingBox: block.boundingBox'));
    expect(source, contains('words: wordItems'));
    expect(source, contains('position: metrics'));
    expect(source, contains('runWithTemporaryCleanup'));
  });

  for (final document in documents) {
    final year = document['anio'] as int;
    test('el contrato admite todos los datos verificados de $year', () {
      final raw = _geminiShapeFromReference(document);
      final result = validator.validate(
        raw,
        documentHash: 'preflight-$year',
        pageCount: 2,
      );
      final comparison = comparator.compare(actual: result, expected: document);

      expect(result.subjects, hasLength(6));
      expect(comparison.issueCodes, isEmpty);
      final portfolio = result.subjects.singleWhere(
        (subject) => subject.datedSessions.isNotEmpty,
      );
      expect(portfolio.professor, isNotNull);
      expect(portfolio.weeklyBlocks, isEmpty);
      expect(portfolio.datedSessions, hasLength(4));
      expect(result.period.startDate, isNull);
      expect(result.period.endDate, isNull);
      if (year == 2025) {
        expect(
          portfolio.datedSessions.every((session) => session.room == null),
          isTrue,
        );
      }
    });
  }

  test('el comparador detecta sala inventada y período inventado', () {
    final document = documents.singleWhere((item) => item['anio'] == 2025);
    final raw = _geminiShapeFromReference(document);
    final period = raw['period'] as Map<String, dynamic>;
    period['startDate'] = '2025-03-01';
    final portfolio = (raw['subjects'] as List<Map<String, dynamic>>)
        .singleWhere((item) => (item['datedSessions'] as List).isNotEmpty);
    final firstSession = (portfolio['datedSessions'] as List).first as Map;
    firstSession['room'] = 'SALA INVENTADA';
    final result = validator.validate(
      raw,
      documentHash: 'negative-2025',
      pageCount: 2,
    );
    final comparison = comparator.compare(actual: result, expected: document);

    expect(comparison.issueCodes, contains('invented_period_start'));
    expect(
      comparison.issueCodes.any((code) => code.startsWith('session_mismatch')),
      isTrue,
    );
  });
}

Map<String, dynamic> _geminiShapeFromReference(Map<String, dynamic> document) {
  final subjects = (document['asignaturas'] as List).cast<Map>().toList();
  return {
    'period': {
      'year': document['anio'],
      'semester': document['numero'],
      'startDate': document['fecha_inicio_periodo'] ?? '',
      'endDate': document['fecha_fin_periodo'] ?? '',
      'evidence': ['período verificado en referencia local'],
      'pendingReasons': <String>[],
    },
    'subjects': <Map<String, dynamic>>[
      for (var index = 0; index < subjects.length; index++)
        _subjectShape(subjects[index], index),
    ],
    'pendingReview': <String>[],
  };
}

Map<String, dynamic> _subjectShape(Map value, int index) {
  final subject = Map<String, dynamic>.from(value);
  final key = 'subject_${index + 1}';
  final dated = subject['interpretacion'] == 'sesiones_fechadas_no_semanal';
  return {
    'subjectKey': key,
    'name': subject['nombre_documento'],
    'code': subject['sigla'],
    'section': subject['seccion'],
    'professor': subject['profesor'] ?? '',
    'professorEmail': subject['correo_profesor'] ?? '',
    'sourcePages': [1, 2],
    'evidence': ['asignatura verificada en referencia local'],
    'pendingReasons': <String>[],
    'weeklyBlocks': dated
        ? <Map<String, dynamic>>[]
        : <Map<String, dynamic>>[
            for (final raw in (subject['modulos_semanales_visibles'] as List))
              _blockShape(Map<String, dynamic>.from(raw as Map), key),
          ],
    'datedSessions': dated
        ? <Map<String, dynamic>>[
            for (final raw in (subject['sesiones_fechadas'] as List))
              _sessionShape(Map<String, dynamic>.from(raw as Map), key),
          ]
        : <Map<String, dynamic>>[],
  };
}

Map<String, dynamic> _blockShape(Map<String, dynamic> value, String key) => {
  'subjectKey': key,
  'day': value['dia'],
  'startTime': value['inicio'],
  'endTime': value['fin'],
  'room': value['sala'] ?? '',
  'page': 1,
  'evidence': ['módulo verificado en referencia local'],
  'pendingReasons': <String>[],
};

Map<String, dynamic> _sessionShape(Map<String, dynamic> value, String key) => {
  'subjectKey': key,
  'date': value['fecha'],
  'startTime': value['inicio'],
  'endTime': value['fin'],
  'room': value['sala'] ?? '',
  'page': 2,
  'evidence': ['sesión verificada en referencia local'],
  'pendingReasons': <String>[],
};
