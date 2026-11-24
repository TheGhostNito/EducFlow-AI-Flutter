import 'dart:convert';
import 'dart:io';

import 'package:eduflow_ai/models/malla_curricular.dart';
import 'package:eduflow_ai/models/malla_review.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recuento de revisión coincide con tres respuestas OCR reales', () {
    for (final (name, expected) in [('duoc', 23), ('udp', 14), ('ucn', 7)]) {
      final json = jsonDecode(
        File('test/fixtures/ocr_v22_$name.json').readAsStringSync(),
      );
      final malla = MallaOcrParser.parse(json, fileName: '$name.pdf');
      expect(MallaReviewRules.pendingCount(malla), expected);
    }
  });

  test('resuelve solo los motivos cubiertos por datos o verificación', () {
    final ramo = RamoMalla(
      id: 'ocr_1',
      nombre: 'Ramo',
      semestre: 1,
      requiereRevision: true,
      motivosRevision: const ['credits_missing', 'low_ocr_confidence'],
    );
    expect(
      MallaReviewRules.remainingReasons(
        ramo,
        code: null,
        credits: 4,
        verifyOther: false,
      ),
      ['low_ocr_confidence'],
    );
    expect(
      MallaReviewRules.remainingReasons(
        ramo,
        code: null,
        credits: null,
        verifyOther: true,
      ),
      ['credits_missing'],
    );
  });

  test('solo retira code_missing con confirmación explícita', () {
    final ramo = RamoMalla(
      id: 'sin-codigo',
      nombre: 'Curso institucional',
      semestre: 3,
      creditos: 4,
      requiereRevision: true,
      motivosRevision: const ['code_missing'],
    );

    expect(
      MallaReviewRules.remainingReasons(
        ramo,
        code: null,
        credits: 4,
        verifyOther: false,
      ),
      ['code_missing'],
    );
    expect(
      MallaReviewRules.remainingReasons(
        ramo,
        code: null,
        credits: 4,
        verifyOther: false,
        verifyMissingCode: true,
      ),
      isEmpty,
    );
  });

  test('recuento vuelve a marcar créditos y código al vaciarlos', () {
    final ramo = RamoMalla(
      id: 'ocr_1',
      nombre: 'Ramo',
      semestre: 1,
      requiereRevision: true,
      motivosRevision: [
        'credits_missing',
        'code_missing',
        'low_ocr_confidence',
        'low_ocr_confidence',
      ],
    );
    final malla = MallaCurricular(id: 'saved', ramos: [ramo]);

    void edit(String? code, int? credits, {bool verifyOther = false}) {
      final reasons = MallaReviewRules.remainingReasons(
        ramo,
        code: code,
        credits: credits,
        verifyOther: verifyOther,
        deriveMissing: true,
      );
      ramo.codigo = code;
      ramo.creditos = credits;
      ramo.motivosRevision
        ..clear()
        ..addAll(reasons);
      ramo.requiereRevision = reasons.isNotEmpty;
    }

    edit('ABC', 5);
    expect(ramo.motivosRevision, ['low_ocr_confidence']);
    expect(MallaReviewRules.pendingCount(malla), 1);
    edit('ABC', 5, verifyOther: true);
    expect(MallaReviewRules.pendingCount(malla), 0);
    edit(null, null);
    expect(ramo.motivosRevision, ['credits_missing', 'code_missing']);
    expect(ramo.requiereRevision, isTrue);
    expect(MallaReviewRules.pendingCount(malla), 1);
    edit('ABC', 5);
    expect(ramo.motivosRevision, isEmpty);
    expect(ramo.requiereRevision, isFalse);
    expect(MallaReviewRules.pendingCount(malla), 0);
  });

  test('detecta duplicados sin deduplicar nombres ni modificar códigos', () {
    final first = RamoMalla(
      id: 'ocr_1',
      nombre: 'Electivo I',
      semestre: 1,
      codigo: 'abc',
    );
    final second = RamoMalla(
      id: 'ocr_2',
      nombre: 'Electivo II',
      semestre: 2,
      codigo: ' ABC ',
    );
    final malla = MallaCurricular(id: 'saved', ramos: [first, second]);
    expect(MallaReviewRules.pendingCount(malla), 2);
    expect(MallaReviewRules.duplicateNames(malla, first), ['Electivo II (S2)']);
    first.codigoDuplicadoVerificado = true;
    expect(MallaReviewRules.pendingCount(malla), 1);
    second.codigoDuplicadoVerificado = true;
    expect(MallaReviewRules.pendingCount(malla), 0);
    expect(first.codigo, 'abc');
    expect(second.codigo, ' ABC ');
  });

  test('revisión genérica requiere confirmación explícita', () {
    final ramo = RamoMalla(
      id: 'ocr_1',
      nombre: 'Ramo',
      semestre: 1,
      requiereRevision: true,
      motivosRevision: const ['low_ocr_confidence'],
    );
    final malla = MallaCurricular(id: 'saved', ramos: [ramo]);
    expect(
      MallaReviewRules.issuesFor(malla, ramo).single.priority,
      MallaReviewPriority.verification,
    );
    expect(MallaReviewRules.pendingCount(malla), 1);
    expect(
      MallaReviewRules.remainingReasons(
        ramo,
        code: null,
        credits: null,
        verifyOther: true,
      ),
      isEmpty,
    );
  });
}
