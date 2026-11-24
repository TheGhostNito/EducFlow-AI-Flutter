import 'dart:typed_data';

import 'package:eduflow_ai/models/horario_ocr_result.dart';
import 'package:eduflow_ai/models/horario_importacion.dart';
import 'package:eduflow_ai/core/navigation/main_navigation.dart';
import 'package:eduflow_ai/pages/schedule/horario_ocr_diagnostic_page.dart';
import 'package:eduflow_ai/services/horario_ocr_document_service.dart';
import 'package:eduflow_ai/services/horario_importacion_service.dart';
import 'package:eduflow_ai/services/horario_ocr_extraction_service.dart';
import 'package:eduflow_ai/services/ocr_file_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/firebase_auth_test_host.dart';

void main() {
  setUpAll(() async {
    await FirebaseAuthTestHost().initialize();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'https://ubjmdfwkjgblnjgmufpc.supabase.co',
      publishableKey: 'sb_publishable_DmUj02VfZSkZOzoR11oq5A_TumX6rfA',
    );
  });

  testWidgets('el flujo oficial oculta herramientas técnicas de diagnóstico', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: HorarioOcrDiagnosticPage(spanish: true, gateway: _FakeGateway()),
      ),
    );

    expect(find.text('Importar horario'), findsWidgets);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('horario-import-delete')), findsNothing);
    expect(find.byKey(const Key('horario-ocr-vision-result')), findsNothing);
    expect(find.byKey(const Key('horario-ocr-gemini-result')), findsNothing);
  });

  testWidgets(
    'muestra Vision, Gemini y Portafolio como sesiones fechadas sin guardar',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final gateway = _FakeGateway();
      await tester.pumpWidget(
        MaterialApp(
          home: HorarioOcrDiagnosticPage(
            spanish: true,
            gateway: gateway,
            showDeveloperDiagnostics: true,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('horario-ocr-select-document')));
      await tester.pumpAndSettle();

      expect(find.text('horario_2024.png'), findsOneWidget);
      expect(gateway.pickCalls, 1);

      await tester.tap(find.byKey(const Key('horario-ocr-process-document')));
      await tester.pumpAndSettle();

      expect(gateway.extractCalls, 1);
      expect(
        find.text('Período detectado: semestre 1 de 2024'),
        findsOneWidget,
      );
      expect(find.text('Proceso de Portafolio 3'), findsOneWidget);
      expect(find.text('Sesiones con fecha específica'), findsOneWidget);
      expect(find.text('Clases semanales'), findsNothing);

      expect(find.text('Google Cloud Vision'), findsOneWidget);
      expect(find.text('Gemini'), findsOneWidget);
      expect(
        find.textContaining('no existe una acción de guardado'),
        findsOneWidget,
      );
      expect(find.textContaining('Guardar'), findsNothing);

      await tester.tap(find.byKey(const Key('horario-ocr-open-review')));
      await tester.pumpAndSettle();
      expect(find.text('Revisar horario'), findsOneWidget);
      expect(find.text('Proceso de Portafolio 3'), findsWidgets);
      expect(
        find.byKey(const ValueKey('horario-review-session-date-0-3')),
        findsOneWidget,
      );
    },
  );

  testWidgets('elimina únicamente la importación elegida tras confirmar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final imports = _FakeImportGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: HorarioOcrDiagnosticPage(
          spanish: true,
          gateway: _FakeGateway(),
          importacionGateway: imports,
          writesEnabled: true,
          showDeveloperDiagnostics: true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('horario-import-delete')));
    await tester.pumpAndSettle();
    expect(find.text('horario-2024.pdf'), findsOneWidget);
    await tester.tap(find.text('horario-2024.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('horario-import-confirm-delete')));
    await tester.pumpAndSettle();

    expect(imports.deleteCalls, 1);
    expect(imports.deletedId, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    expect(find.textContaining('6 asignaturas importadas'), findsOneWidget);
  });

  testWidgets('Ver mi horario cierra el flujo y selecciona Horario', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final imports = _FakeImportGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: MainNavigation(
          sectionBuilder: (context, section, payload) {
            if (section == SeccionPrincipal.horario) {
              return const Center(child: Text('HORARIO DESTINO'));
            }
            return Center(
              child: Builder(
                builder: (context) => FilledButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => HorarioOcrDiagnosticPage(
                        spanish: true,
                        gateway: _FakeGateway(),
                        importacionGateway: imports,
                        writesEnabled: true,
                      ),
                    ),
                  ),
                  child: const Text('Abrir importación'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Abrir importación'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('horario-ocr-select-document')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('horario-ocr-process-document')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('horario-review-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('horario-review-save-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('horario-review-confirm-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver mi horario'));
    await tester.pumpAndSettle();

    expect(imports.confirmCalls, 1);
    expect(find.text('HORARIO DESTINO'), findsOneWidget);
    expect(find.text('Importar horario'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _FakeGateway implements HorarioOcrDocumentGateway {
  int pickCalls = 0;
  int extractCalls = 0;

  @override
  Future<OcrPickedFile?> pickDocument() async {
    pickCalls++;
    return OcrPickedFile(
      name: 'horario_2024.png',
      bytes: Uint8List.fromList(const [1, 2, 3]),
      mimeType: 'image/png',
      sizeBytes: 3,
    );
  }

  @override
  Future<HorarioOcrRunOutcome> extractWithDiagnostics(
    OcrPickedFile file,
  ) async {
    extractCalls++;
    return HorarioOcrRunOutcome(
      visionContext: const {
        'pageCount': 2,
        'text': 'Proceso de Portafolio 3 15/03/2024',
        'blocks': [],
      },
      geminiJson: '''
        {"period":{"year":2024,"semester":1},"subjects":[{"name":"Proceso de Portafolio 3"}]}
      ''',
      result: HorarioOcrResult(
        documentHash: 'hash-2024',
        pageCount: 2,
        period: const HorarioOcrPeriod(
          year: 2024,
          semester: 1,
          evidence: ['Primer semestre 2024'],
          pendingReasons: [],
        ),
        subjects: [
          HorarioOcrSubject(
            key: 'subject_1',
            name: 'Proceso de Portafolio 3',
            code: 'APY4461',
            section: '001D',
            professor: 'Docente de prueba',
            professorEmail: null,
            weeklyBlocks: const [],
            datedSessions: [
              HorarioOcrDatedSession(
                subjectKey: 'subject_1',
                date: DateTime(2024, 3, 15),
                startTime: '10:01',
                endTime: '11:20',
                room: 'LAB-1',
                page: 2,
                evidence: const ['15/03/2024'],
                pendingReasons: const [],
              ),
              HorarioOcrDatedSession(
                subjectKey: 'subject_1',
                date: DateTime(2024, 4, 12),
                startTime: '10:01',
                endTime: '11:20',
                room: 'LAB-1',
                page: 2,
                evidence: const ['12/04/2024'],
                pendingReasons: const [],
              ),
              HorarioOcrDatedSession(
                subjectKey: 'subject_1',
                date: DateTime(2024, 5, 17),
                startTime: '10:01',
                endTime: '11:20',
                room: 'LAB-1',
                page: 2,
                evidence: const ['17/05/2024'],
                pendingReasons: const [],
              ),
              HorarioOcrDatedSession(
                subjectKey: 'subject_1',
                date: DateTime(2024, 6, 14),
                startTime: '10:01',
                endTime: '11:20',
                room: 'LAB-1',
                page: 2,
                evidence: const ['14/06/2024'],
                pendingReasons: const [],
              ),
            ],
            sourcePages: const [1, 2],
            evidence: const ['Proceso de Portafolio 3'],
            pendingReasons: const [],
          ),
        ],
        issues: const [],
        pendingReview: const ['Confirmar visualmente antes de guardar.'],
      ),
      diagnostics: const HorarioOcrRunDiagnostics(
        documentHash: 'hash-2024',
        pageCount: 2,
        visionUnits: 2,
        visionCacheHit: false,
        visionMonthlyUsed: 2,
        visionMonthlyRemaining: 798,
        visionDailyUsed: 2,
        visionDailyRemaining: 8,
        geminiPromptTokens: 120,
        geminiOutputTokens: 80,
        geminiTotalTokens: 200,
        geminiFinishReason: 'STOP',
      ),
    );
  }
}

class _FakeImportGateway implements HorarioImportacionGateway {
  int deleteCalls = 0;
  int confirmCalls = 0;
  String? deletedId;

  @override
  Future<HorarioImportacionResultado> confirmar(
    HorarioImportacionPropuesta propuesta,
  ) async {
    confirmCalls++;
    return const HorarioImportacionResultado(
      importacionId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      periodoAcademicoId: 'horario-periodo-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      asignaturas: 1,
      bloques: 0,
      sesiones: 4,
      yaExistia: false,
    );
  }

  @override
  Future<HorarioImportacionEliminada> eliminar(String importacionId) async {
    deleteCalls++;
    deletedId = importacionId;
    return HorarioImportacionEliminada(
      importacionId: importacionId,
      asignaturasEliminadas: 6,
      periodoEliminado: true,
    );
  }

  @override
  Future<List<HorarioImportacionRegistro>> listar() async => [
    HorarioImportacionRegistro(
      id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      documentHash:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      nombreDocumento: 'horario-2024.pdf',
      anio: 2024,
      numeroPeriodo: 1,
      periodoAcademicoId: 'horario-periodo-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      asignaturas: 6,
      bloques: 7,
      sesiones: 4,
      creadaEn: DateTime(2026, 11, 22),
    ),
  ];

  @override
  Future<List<String>> obtenerAsignaturaIds(String importacionId) async =>
      const [];
}
