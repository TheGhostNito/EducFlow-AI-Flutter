import 'dart:convert';
import 'dart:typed_data';

import 'package:eduflow_ai/models/horario_importacion.dart';
import 'package:eduflow_ai/pages/schedule/horario_guardado_page.dart';
import 'package:eduflow_ai/services/horario_documento_original_service.dart';
import 'package:eduflow_ai/services/horario_importacion_service.dart';
import 'package:eduflow_ai/services/ocr_file_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('muestra el archivo original y elimina la importación elegida', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _FakeImportGateway(withDocument: true);
    final documents = _FakeDocumentGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: HorarioGuardadoPage(
          spanish: true,
          importacionGateway: gateway,
          documentoGateway: documents,
          writesEnabled: true,
          documentStorageEnabled: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('Descargar original'), findsOneWidget);
    expect(find.text('Programación aplicada'), findsNothing);

    await tester.tap(find.byKey(const Key('horario-guardado-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('horario-guardado-confirm-delete')));
    await tester.pumpAndSettle();

    expect(gateway.deletedId, _FakeImportGateway.importId);
    expect(documents.registered, isNull);
    expect(find.byKey(const Key('horario-guardado-empty')), findsOneWidget);
  });

  testWidgets('una importación anterior no altera datos y ofrece asociación', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HorarioGuardadoPage(
          spanish: true,
          importacionGateway: _FakeImportGateway(withDocument: false),
          documentoGateway: _FakeDocumentGateway(),
          writesEnabled: true,
          documentStorageEnabled: true,
          documentPicker: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('horario-guardado-legacy-document')),
      findsOneWidget,
    );
    expect(find.text('Documento original no disponible'), findsOneWidget);
    expect(find.text('Asociar documento original'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Descargar original'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });
}

class _FakeImportGateway implements HorarioImportacionGateway {
  _FakeImportGateway({required bool withDocument})
    : records = [_record(withDocument)];

  static const importId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final List<HorarioImportacionRegistro> records;
  String? deletedId;

  static HorarioImportacionRegistro _record(bool withDocument) =>
      HorarioImportacionRegistro(
        id: importId,
        documentHash: '${importId}aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        nombreDocumento: 'horario.png',
        anio: 2026,
        numeroPeriodo: 2,
        periodoAcademicoId: 'period-2026-2',
        asignaturas: 2,
        bloques: 1,
        sesiones: 1,
        creadaEn: DateTime(2026, 11, 22),
        documentoOriginal: withDocument
            ? const HorarioDocumentoOriginal(
                path: _FakeDocumentGateway.path,
                nombre: 'horario.png',
                mimeType: 'image/png',
                sizeBytes: 68,
              )
            : null,
      );

  @override
  Future<HorarioImportacionResultado> confirmar(
    HorarioImportacionPropuesta propuesta,
  ) => throw UnimplementedError();

  @override
  Future<HorarioImportacionEliminada> eliminar(String importacionId) async {
    deletedId = importacionId;
    records.clear();
    return HorarioImportacionEliminada(
      importacionId: importacionId,
      asignaturasEliminadas: 2,
      periodoEliminado: true,
      documentoPath: _FakeDocumentGateway.path,
    );
  }

  @override
  Future<List<HorarioImportacionRegistro>> listar() async =>
      List.unmodifiable(records);

  @override
  Future<List<String>> obtenerAsignaturaIds(String importacionId) async =>
      const [];
}

class _FakeDocumentGateway implements HorarioDocumentoOriginalGateway {
  static const path = 'test-user/${_FakeImportGateway.importId}/123456789.png';
  String? registered;

  @override
  Future<void> asociar({
    required String importacionId,
    required HorarioDocumentoOriginal documento,
  }) async {}

  @override
  Future<Uint8List> descargar(HorarioDocumentoOriginal documento) async =>
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );

  @override
  Future<void> registrarLimpieza(String path) async => registered = path;

  @override
  Future<HorarioDocumentoOriginal> subir({
    required OcrPickedFile file,
    required String importacionId,
  }) => throw UnimplementedError();
}
