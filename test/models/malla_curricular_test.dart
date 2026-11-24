import 'dart:convert';
import 'dart:io';

import 'package:eduflow_ai/models/malla_curricular.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/ocr_v22_$name.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('DUOC code_based conserva nulos y elemento especial separado', () {
    final malla = MallaOcrParser.parse(fixture('duoc'), fileName: 'duoc.jpg');
    expect(malla.ramos, hasLength(41));
    expect(malla.semestres, orderedEquals([1, 2, 3, 4, 5, 6, 7, 8]));
    expect(malla.ramos.where((ramo) => ramo.creditos == null), hasLength(22));
    expect(malla.ramos.where((ramo) => ramo.requiereRevision), hasLength(23));
    expect(malla.especiales, hasLength(1));
    expect(malla.especiales.single.creditos, 4);
    expect(malla.especiales.single.codigo, isNull);
  });

  test('UDP layout_based conserva ocho electivos profesionales separados', () {
    final malla = MallaOcrParser.parse(fixture('udp'), fileName: 'udp.pdf');
    expect(malla.ramos, hasLength(58));
    expect(malla.semestres, hasLength(11));
    final electives = malla.ramos
        .where((ramo) => ramo.nombre == 'Electivo Profesional')
        .toList();
    expect(electives, hasLength(8));
    expect(electives.map((ramo) => ramo.id).toSet(), hasLength(8));
    expect(electives.every((ramo) => ramo.creditos == null), isTrue);
    expect(
      electives.every((ramo) => ramo.motivosRevision.contains('elective_slot')),
      isTrue,
    );
    expect(malla.ramos.where((ramo) => ramo.requiereRevision), hasLength(14));
  });

  test('UCN layout_based conserva los diez semestres de dos bandas', () {
    final malla = MallaOcrParser.parse(fixture('ucn'), fileName: 'ucn.pdf');
    expect(malla.ramos, hasLength(59));
    expect(malla.semestres, orderedEquals([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]));
    expect(malla.ramos.where((ramo) => ramo.requiereRevision), hasLength(7));
    expect(malla.ramos.every((ramo) => ramo.codigo == null), isTrue);
    expect(malla.ramos.every((ramo) => ramo.creditos == null), isTrue);
  });

  test('correcciones generan el payload final sin deduplicar', () {
    final malla = MallaOcrParser.parse(fixture('udp'), fileName: 'udp.pdf');
    final first = malla.ramos.first;
    first.nombre = 'Nombre corregido';
    first.semestre = 2;
    first.creditos = 6;
    malla.ramos.removeLast();
    malla.ramos.add(RamoMalla(id: 'manual_1', nombre: 'Omitida', semestre: 11));
    expect(first.toPayload()['nombre'], 'Nombre corregido');
    expect(first.toPayload()['semestre'], 2);
    expect(first.toPayload()['creditos'], 6);
    expect(malla.ramos, hasLength(58));
    expect(malla.ramos.last.toPayload()['creditos'], isNull);
  });

  test('rechaza respuestas vacías y fallidas', () {
    expect(
      () => MallaOcrParser.parse({'ok': false, 'courses': []}, fileName: 'x'),
      throwsFormatException,
    );
    expect(
      () => MallaOcrParser.parse({'ok': true, 'courses': []}, fileName: 'x'),
      throwsFormatException,
    );
  });

  test(
    'los payloads de las tres respuestas reales respetan los límites SQL',
    () {
      const requiredFields = {
        'id',
        'nombre',
        'semestre',
        'codigo',
        'creditos',
        'requiere_revision',
        'motivos_revision',
      };
      final idPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
      final reasonPattern = RegExp(r'^[A-Za-z0-9_:-]{1,120}$');
      final controlCharacters = RegExp(r'[\x00-\x1F\x7F]');
      for (final sample in const ['duoc', 'udp', 'ucn']) {
        final malla = MallaOcrParser.parse(
          fixture(sample),
          fileName: '$sample.pdf',
        );
        expect(malla.ramos.length, lessThanOrEqualTo(500));
        for (final ramo in malla.ramos) {
          final payload = ramo.toPayload();
          expect(payload.keys.toSet(), requiredFields);
          expect(idPattern.hasMatch(payload['id'] as String), isTrue);
          expect(controlCharacters.hasMatch(payload['id'] as String), isFalse);
          expect(
            (payload['nombre'] as String).length,
            inInclusiveRange(1, 300),
          );
          expect(
            controlCharacters.hasMatch(payload['nombre'] as String),
            isFalse,
          );
          expect(payload['semestre'], inInclusiveRange(1, 30));
          final code = payload['codigo'] as String?;
          if (code != null) {
            expect(code.length, lessThanOrEqualTo(64));
            expect(controlCharacters.hasMatch(code), isFalse);
          }
          final credits = payload['creditos'] as int?;
          if (credits != null) expect(credits, inInclusiveRange(0, 999));
          final reasons = (payload['motivos_revision'] as List).cast<String>();
          expect(reasons.length, lessThanOrEqualTo(12));
          expect(
            utf8.encode(jsonEncode(reasons)).length,
            lessThanOrEqualTo(2048),
          );
          for (final reason in reasons) {
            expect(reasonPattern.hasMatch(reason), isTrue);
            expect(controlCharacters.hasMatch(reason), isFalse);
          }
        }
      }
      for (final id in const ['ocr_500', 'manual_500', 'special_500']) {
        expect(idPattern.hasMatch(id), isTrue);
      }
    },
  );
}
