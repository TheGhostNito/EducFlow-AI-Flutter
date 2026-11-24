import 'dart:async';

import 'package:eduflow_ai/models/malla_curricular.dart';
import 'package:eduflow_ai/core/config/developer_tools_config.dart';
import 'package:eduflow_ai/models/malla_import_review.dart';
import 'package:eduflow_ai/models/malla_multimodal_review.dart';
import 'package:eduflow_ai/models/malla_review.dart';
import 'package:eduflow_ai/pages/ocr/malla_curricular_page.dart';
import 'package:eduflow_ai/pages/ocr/malla_ui_failure.dart';
import 'package:eduflow_ai/services/malla_curricular_service.dart';
import 'package:eduflow_ai/services/malla_multimodal_persistence_service.dart';
import 'package:eduflow_ai/services/malla_multimodal_rls_diagnostic_service.dart';
import 'package:eduflow_ai/services/malla_multimodal_write_diagnostic_service.dart';
import 'package:eduflow_ai/services/ocr_document_service.dart';
import 'package:eduflow_ai/services/ocr_file_picker_service.dart';
import 'package:eduflow_ai/services/translation_service.dart';
import 'package:eduflow_ai/widgets/app_full_screen_loading.dart';
import 'package:eduflow_ai/widgets/app_scroll_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeMalla implements MallaCurricularGateway {
  Future<MallaCurricular?>? loadResult;
  Object? loadError;
  MallaCurricular? ocrResult;
  Object? processError;
  Completer<MallaCurricular>? processCompleter;
  int processCalls = 0;
  int confirmCalls = 0;
  Object? confirmError;
  int editCalls = 0;
  @override
  bool multimodalPersistenceEnabled = false;
  @override
  bool multimodalTestingSampleEnabled = false;
  MallaImportReview? loadedMultimodalReview;
  Future<MallaImportReview?>? multimodalLoadResult;
  int multimodalConfirmCalls = 0;
  Completer<void>? multimodalConfirmGate;
  int relationshipBatchCalls = 0;
  Object? relationshipBatchError;
  Completer<void>? relationshipBatchGate;
  final List<List<String>> prerequisiteBatches = [];
  final List<List<String>> membershipBatches = [];
  int prerequisiteDecisionCalls = 0;
  Object? prerequisiteDecisionError;
  Completer<MallaImportReview>? prerequisiteDecisionCompleter;
  final List<MallaProposalDecision> prerequisiteDecisions = [];
  int membershipDecisionCalls = 0;
  Object? membershipDecisionError;
  Completer<MallaImportReview>? membershipDecisionCompleter;
  final List<MallaProposalDecision> membershipDecisions = [];
  int requirementDecisionCalls = 0;
  Object? requirementDecisionError;
  Completer<MallaImportReview>? requirementDecisionCompleter;
  final List<MallaProposalDecision> requirementDecisions = [];
  int confirmWithoutCodeCalls = 0;
  bool? lastConfirmWithoutCode;
  int requirementEditCalls = 0;
  String? lastRequirementEditId;
  String? lastRequirementEditDescription;
  int? lastRequirementEditMinimumLevel;
  int deleteCalls = 0;
  Object? deleteError;
  Completer<void>? deleteCompleter;
  final List<String> deletedMallaIds = [];

  @override
  Future<bool> existe() async => loadResult != null;

  @override
  Future<MallaCurricular> editarRamo(
    MallaCurricular malla,
    RamoMalla ramo, {
    required bool confirmarRevision,
    required bool codigoDuplicadoVerificado,
    required bool confirmarSinCodigo,
  }) async {
    editCalls++;
    lastConfirmWithoutCode = confirmarSinCodigo;
    final index = malla.ramos.indexWhere((item) => item.id == ramo.id);
    final previous = malla.ramos[index];
    final oldCode = MallaReviewRules.normalizedCode(previous.codigo);
    final newCode = MallaReviewRules.normalizedCode(ramo.codigo);
    if (oldCode != newCode) {
      for (final other in malla.ramos) {
        final otherCode = MallaReviewRules.normalizedCode(other.codigo);
        if (other.id != ramo.id &&
            otherCode != null &&
            (otherCode == oldCode || otherCode == newCode)) {
          other.codigoDuplicadoVerificado = false;
        }
      }
    }
    ramo.estado = previous.estado;
    final remaining = MallaReviewRules.remainingReasons(
      previous,
      code: ramo.codigo,
      credits: ramo.creditos,
      verifyOther: confirmarRevision,
      verifyMissingCode: confirmarSinCodigo,
      deriveMissing: true,
    );
    ramo.motivosRevision
      ..clear()
      ..addAll(remaining);
    ramo.requiereRevision = remaining.isNotEmpty;
    ramo.codigoDuplicadoVerificado =
        codigoDuplicadoVerificado && oldCode == newCode;
    malla.ramos[index] = ramo;
    return malla;
  }

  @override
  Future<MallaImportReview> confirmarRamoSinCodigo({
    required String mallaId,
    required String ramoId,
  }) async {
    confirmWithoutCodeCalls++;
    final review = loadedMultimodalReview!;
    final course = review.courseById(ramoId)!;
    course.motivosRevision.remove('code_missing');
    course.requiereRevision = course.motivosRevision.isNotEmpty;
    return review;
  }

  @override
  Future<MallaImportReview> editarRequisitoAcademico({
    required String mallaId,
    required MallaAcademicRequirement requirement,
    required String description,
    required int? minimumLevel,
  }) async {
    requirementEditCalls++;
    lastRequirementEditId = requirement.id;
    lastRequirementEditDescription = description;
    lastRequirementEditMinimumLevel = minimumLevel;
    final review = loadedMultimodalReview!;
    final proposal = review.academicRequirements.singleWhere(
      (item) => item.requirement.id == requirement.id,
    );
    proposal.updateDetails(
      description: description,
      minimumLevel: minimumLevel,
    );
    return review;
  }

  @override
  Future<MallaCurricular?> cargar() async {
    if (loadError != null) throw loadError!;
    return await (loadResult ?? Future.value(null));
  }

  @override
  Future<MallaImportReview?> cargarRevisionMultimodal() async =>
      await (multimodalLoadResult ?? Future.value(loadedMultimodalReview));

  @override
  Future<MallaCurricular> procesar(
    OcrDocumentResult upload, {
    required String fileName,
    required OcrPickedFile originalFile,
  }) async {
    processCalls++;
    if (processError != null) throw processError!;
    final pending = processCompleter;
    if (pending != null) return pending.future;
    return ocrResult!;
  }

  @override
  Future<MallaCurricular> confirmar(MallaCurricular preview) async {
    confirmCalls++;
    if (confirmError != null) throw confirmError!;
    return preview;
  }

  @override
  Future<MallaImportReview> confirmarMultimodal(
    MallaImportReview review,
  ) async {
    multimodalConfirmCalls++;
    if (confirmError != null) throw confirmError!;
    final gate = multimodalConfirmGate;
    if (gate != null) await gate.future;
    return review;
  }

  @override
  Future<MallaImportReview> confirmarRelacionesAgrupadas({
    required MallaImportReview review,
    List<MallaPrerequisiteProposal> prerequisites = const [],
    List<MallaCertificationBatchSelection> certifications = const [],
  }) async {
    relationshipBatchCalls++;
    prerequisiteBatches.add([
      for (final item in prerequisites)
        '${item.courseId}>${item.requiresCourseId}',
    ]);
    membershipBatches.add([
      for (final selection in certifications)
        for (final item in selection.memberships)
          '${selection.certification.id}:${item.courseId}',
    ]);
    if (relationshipBatchError != null) throw relationshipBatchError!;
    final gate = relationshipBatchGate;
    if (gate != null) await gate.future;
    for (final item in prerequisites) {
      item.decision = MallaProposalDecision.accepted;
    }
    for (final selection in certifications) {
      selection.certification.decision = MallaProposalDecision.accepted;
      for (final membership in selection.memberships) {
        membership.decision = MallaProposalDecision.accepted;
      }
    }
    return review;
  }

  @override
  Future<MallaImportReview> decidirPrerrequisito({
    required String mallaId,
    required String courseId,
    required String requiresCourseId,
    required MallaProposalDecision decision,
  }) async {
    prerequisiteDecisionCalls++;
    prerequisiteDecisions.add(decision);
    if (prerequisiteDecisionError != null) {
      throw prerequisiteDecisionError!;
    }
    final pending = prerequisiteDecisionCompleter;
    if (pending != null) return pending.future;
    final review = loadedMultimodalReview!;
    final relation = review.prerequisites.singleWhere(
      (item) =>
          item.courseId == courseId &&
          item.requiresCourseId == requiresCourseId,
    );
    relation.decision = decision;
    return review;
  }

  @override
  Future<MallaImportReview> decidirMembresiaCertificacion({
    required String mallaId,
    required String certificationId,
    required String courseId,
    required MallaProposalDecision decision,
  }) async {
    membershipDecisionCalls++;
    membershipDecisions.add(decision);
    if (membershipDecisionError != null) throw membershipDecisionError!;
    final pending = membershipDecisionCompleter;
    if (pending != null) return pending.future;
    final review = loadedMultimodalReview!;
    final certification = review.certifications.singleWhere(
      (item) => item.id == certificationId,
    );
    final membership = certification.memberships.singleWhere(
      (item) => item.courseId == courseId,
    );
    membership.decision = decision;
    return review;
  }

  @override
  Future<MallaImportReview> decidirRequisitoAcademico({
    required String mallaId,
    required String requirementId,
    required String type,
    required MallaProposalDecision decision,
  }) async {
    requirementDecisionCalls++;
    requirementDecisions.add(decision);
    if (requirementDecisionError != null) throw requirementDecisionError!;
    final pending = requirementDecisionCompleter;
    if (pending != null) return pending.future;
    final review = loadedMultimodalReview!;
    final proposal = review.academicRequirements.singleWhere(
      (item) => item.requirement.id == requirementId,
    );
    proposal.decision = decision;
    return review;
  }

  @override
  Future<void> eliminarMallaConfirmada(String mallaId) async {
    deleteCalls++;
    deletedMallaIds.add(mallaId);
    if (deleteError != null) throw deleteError!;
    final pending = deleteCompleter;
    if (pending != null) await pending.future;
  }

  @override
  Future<void> cambiarEstado(RamoMalla ramo, String estado) async {
    ramo.estado = estado;
  }
}

class _FakeDocuments implements OcrDocumentGateway {
  _FakeDocuments({this.uploadCompleter, this.deleteError});

  final Completer<OcrDocumentResult>? uploadCompleter;
  final Object? deleteError;
  int uploads = 0;
  int deletes = 0;
  final List<String> deletedPaths = [];

  @override
  Future<OcrPickedFile?> pickDocument() async => OcrPickedFile(
    name: 'malla.pdf',
    bytes: Uint8List.fromList([1, 2, 3]),
    mimeType: 'application/pdf',
    sizeBytes: 3,
  );

  @override
  Future<OcrDocumentResult> upload(OcrPickedFile file) async {
    uploads++;
    return uploadCompleter?.future ??
        const OcrDocumentResult(
          originalName: 'malla.pdf',
          bucket: 'ocr-temp',
          path: 'uid/malla.pdf',
          mimeType: 'application/pdf',
          sizeBytes: 3,
        );
  }

  @override
  Future<void> deleteUploadedFile(String path) async {
    deletes++;
    deletedPaths.add(path);
    if (deleteError != null) throw deleteError!;
  }
}

class _FakeRlsDiagnostic implements MallaRlsDiagnosticGateway {
  _FakeRlsDiagnostic({required this.enabled});

  @override
  final bool enabled;
  int calls = 0;

  @override
  Future<MallaRlsDiagnosticResult> run(String foreignMallaId) async {
    calls++;
    return MallaRlsDiagnosticResult(
      ownMallaId: '11111111-1111-4111-8111-111111111111',
      foreignMallaId: foreignMallaId,
      ownRowsByTable: const {'mallas_curriculares': 1, 'ramos_malla': 4},
      foreignRowsHidden: const {
        'mallas_curriculares': true,
        'ramos_malla': true,
      },
    );
  }
}

class _DelayedRlsDiagnostic implements MallaRlsDiagnosticGateway {
  @override
  bool get enabled => true;

  final completer = Completer<MallaRlsDiagnosticResult>();

  @override
  Future<MallaRlsDiagnosticResult> run(String foreignMallaId) =>
      completer.future;
}

class _FakeWriteDiagnostic implements MallaWriteDiagnosticGateway {
  _FakeWriteDiagnostic({required this.enabled});

  @override
  final bool enabled;
  int calls = 0;

  @override
  Future<MallaWriteDiagnosticResult> run(String foreignMallaId) async {
    calls++;
    return MallaWriteDiagnosticResult(
      ownMallaId: '11111111-1111-4111-8111-111111111111',
      foreignMallaId: foreignMallaId,
      prerequisiteKey: 'testing_proyecto>testing_programacion',
      reviewState: 'pending',
      pendingCount: 2,
    );
  }
}

MallaImportReview _savedTestingReview() => MallaImportReview(
  malla: MallaCurricular(
    id: '11111111-1111-4111-8111-111111111111',
    archivoNombre: 'malla-ejemplo-testing.json',
    ramos: [
      RamoMalla(
        id: 'testing_course',
        nombre: 'Asignatura Testing',
        semestre: 1,
        codigo: 'TST1001',
        creditos: 5,
      ),
    ],
  ),
  periodType: 'semester',
  periodCount: 1,
  periodEvidence: const ['Un período'],
  geminiCourseIds: const {},
  courseChanges: const [],
  prerequisites: const [],
  certifications: const [],
  academicRequirements: const [],
  globalPending: const [],
  deduplicatedAdditionalCourses: const [],
);

MallaImportReview _savedAcademicReview({
  bool includeCertifications = true,
  bool includeAcademicRequirement = false,
  String requirementType = 'capstone_eligibility',
}) {
  final courses = [
    RamoMalla(
      id: 'base_confirmada',
      nombre: 'Programación Aplicada',
      semestre: 1,
      codigo: 'TST1001',
      creditos: 6,
    ),
    RamoMalla(
      id: 'base_sugerida',
      nombre: 'Fundamentos de Datos',
      semestre: 1,
      codigo: 'TST1002',
      creditos: 5,
    ),
    RamoMalla(
      id: 'destino',
      nombre: 'Proyecto Integrador',
      semestre: 2,
      codigo: 'TST2001',
      creditos: 8,
    ),
  ];
  final targetChange = MallaCourseChangeProposal(
    review: const MallaCourseReview(
      courseId: 'destino',
      proposedName: 'Proyecto Integrador',
      proposedCode: 'TST2001',
      proposedCredits: 8,
      proposedPeriod: 2,
      category: 'capstone',
      categoryLabel: 'Proyecto final',
      prerequisiteStatus: 'identified',
      evidence: ['Bloque académico confirmado'],
      pendingReasons: [],
    ),
    originalName: 'Proyecto Integrador',
    originalCode: 'TST2001',
    originalCredits: 8,
    originalPeriod: 2,
    automaticallyAppliedFields: const {},
    attentionReasons: const [],
  );
  final confirmedPrerequisite = MallaPrerequisiteProposal(
    courseId: 'destino',
    requiresCourseId: 'base_confirmada',
    evidence: const ['Flecha directa'],
    pendingReasons: const [],
  )..decision = MallaProposalDecision.accepted;
  final pendingPrerequisite = MallaPrerequisiteProposal(
    courseId: 'destino',
    requiresCourseId: 'base_sugerida',
    evidence: const ['Línea cercana'],
    pendingReasons: const ['ambiguous_arrow'],
  );
  final certification = MallaCertificationProposal(
    id: 'cert_testing',
    name: 'Certificado en Desarrollo',
    evidence: const ['Contenedor visible'],
    memberships: [
      MallaCertificationMembershipProposal(
        courseId: 'base_confirmada',
        basis: 'visual_container',
        evidence: const ['Dentro del contenedor'],
      )..decision = MallaProposalDecision.accepted,
      MallaCertificationMembershipProposal(
        courseId: 'base_sugerida',
        basis: 'visual_proximity',
        evidence: const ['Límite ambiguo'],
        pendingReasons: const ['ambiguous_membership'],
      ),
    ],
  )..decision = MallaProposalDecision.accepted;
  return MallaImportReview(
    malla: MallaCurricular(
      id: '11111111-1111-4111-8111-111111111111',
      archivoNombre: 'malla-persistida.pdf',
      ramos: courses,
    ),
    periodType: 'semester',
    periodCount: 2,
    periodEvidence: const [],
    geminiCourseIds: const {},
    courseChanges: [targetChange],
    prerequisites: [confirmedPrerequisite, pendingPrerequisite],
    certifications: includeCertifications ? [certification] : [],
    academicRequirements: includeAcademicRequirement
        ? [
            MallaAcademicRequirementProposal(
              requirement: MallaAcademicRequirement(
                id: 'testing_req_proyecto',
                type: requirementType,
                targetCourseId: 'destino',
                targetLabel: 'Proyecto Integrador',
                description: 'Aprobar los dos primeros períodos',
                minimumLevel: 2,
                evidence: const ['Nota académica visible'],
                pendingReasons: const ['requirement_confirmation_pending'],
              ),
            ),
          ]
        : const [],
    globalPending: const [],
    deduplicatedAdditionalCourses: const [],
  );
}

MallaImportReview _savedGroupedReview() {
  final review = _savedAcademicReview();
  review.prerequisites.last.decision = MallaProposalDecision.suggested;
  review.prerequisites.add(
    MallaPrerequisiteProposal(
      courseId: 'base_sugerida',
      requiresCourseId: 'base_confirmada',
      evidence: const ['Flecha directa adicional'],
      pendingReasons: const [],
    ),
  );
  final certification = review.certifications.single
    ..decision = MallaProposalDecision.suggested;
  certification.memberships.last.decision = MallaProposalDecision.suggested;
  certification.memberships.add(
    MallaCertificationMembershipProposal(
      courseId: 'destino',
      basis: 'visual_container',
      evidence: const ['Dentro del mismo contenedor'],
    ),
  );
  return review;
}

Future<void> _pickSemester(WidgetTester tester, int semester) async {
  final selector = find.byKey(const Key('malla-semester-selector'));
  await tester.ensureVisible(selector);
  await tester.pumpAndSettle();
  await tester.tap(selector);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Semestre $semester').last);
  await tester.pumpAndSettle();
}

Future<void> _expandPersistedSection(WidgetTester tester, Key key) async {
  final section = find.byKey(key);
  await tester.scrollUntilVisible(
    section,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.drag(find.byType(ListView).first, const Offset(0, 120));
  await tester.pumpAndSettle();
  final tile = find.descendant(
    of: section,
    matching: find.byType(ExpansionTile),
  );
  expect(tile, findsOneWidget);
  expect(tile.hitTestable(), findsOneWidget);
  await tester.tap(tile.hitTestable());
  await tester.pumpAndSettle();
}

Future<void> _openAcademicRequirement(WidgetTester tester, String title) async {
  await _expandPersistedSection(
    tester,
    const Key('malla-requirements-group-section'),
  );
  final finder = find.text(title);
  await tester.scrollUntilVisible(
    finder,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.drag(find.byType(ListView).first, const Offset(0, 120));
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openDeleteCurriculumDialog(WidgetTester tester) async {
  final access = find.byKey(const Key('malla-delete-saved'));
  await tester.scrollUntilVisible(
    access,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(access);
  await tester.pumpAndSettle();
}

Future<void> _startOcrProcessing(
  WidgetTester tester, {
  required _FakeMalla service,
  required _FakeDocuments documents,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MallaCurricularPage(service: service, documents: documents),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('malla-file-picker')));
  await tester.tap(find.byKey(const Key('malla-file-picker')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('malla-process-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('malla-process-button')));
  await tester.pump();
}

MallaCurricular _successfulOcrResult() => MallaCurricular(
  id: '',
  ramos: [RamoMalla(id: 'ocr_1', nombre: 'Álgebra', semestre: 1)],
);

void main() {
  setUp(() {
    TranslationService.instance.applyUserPreference('es');
    DeveloperToolsConfig.debugOverride = true;
  });
  tearDown(() => DeveloperToolsConfig.debugOverride = null);

  test('selector OCR conserva los tipos permitidos por extensión', () {
    expect(
      OcrFilePickerService.mimeTypeFromFileName('malla.PDF'),
      'application/pdf',
    );
    expect(
      OcrFilePickerService.mimeTypeFromFileName('captura.JPEG'),
      'image/jpeg',
    );
    expect(
      OcrFilePickerService.mimeTypeFromFileName('captura.png'),
      'image/png',
    );
    expect(
      OcrFilePickerService.mimeTypeFromFileName('captura.webp'),
      'image/webp',
    );
    expect(
      () => OcrFilePickerService.mimeTypeFromFileName('malla.txt'),
      throwsArgumentError,
    );
  });

  test('clasifica configuración, conexión, permisos y otros fallos', () {
    expect(
      MallaUiFailure.from(
        const PostgrestException(
          message: 'Could not find the table public.mallas_curriculares',
          code: 'PGRST205',
        ),
      ).kind,
      MallaFailureKind.setup,
    );
    expect(
      MallaUiFailure.from(TimeoutException('red')).kind,
      MallaFailureKind.connection,
    );
    expect(
      MallaUiFailure.from(
        const PostgrestException(message: 'denied', code: '42501'),
      ).kind,
      MallaFailureKind.permission,
    );
    expect(
      MallaUiFailure.from(
        const PostgrestException(message: 'payload inválido', code: '22023'),
      ).kind,
      MallaFailureKind.review,
    );
    expect(
      MallaUiFailure.from(
        const PostgrestException(message: 'malla existente', code: '23505'),
      ).kind,
      MallaFailureKind.duplicate,
    );
    expect(MallaUiFailure.from(Exception('otro')).kind, MallaFailureKind.other);
    final persistenceFailure = MallaUiFailure.from(
      MallaMultimodalIntegrityException(
        fileNameMismatch: false,
        differencePaths: const ['courses[0].review_state'],
      ),
    );
    expect(persistenceFailure.kind, MallaFailureKind.persistence);
    expect(
      persistenceFailure.title(true),
      'La malla se guardó, pero falta verificarla',
    );
    expect(persistenceFailure.title(true), isNot('No encontramos asignaturas'));
    expect(
      MallaUiFailure.fromLoad(Exception('transport')).kind,
      MallaFailureKind.connection,
    );
    expect(
      MallaUiFailure.fromLoad(
        const PostgrestException(message: 'unexpected', code: 'PGRST999'),
      ).kind,
      MallaFailureKind.other,
    );
    expect(
      MallaUiFailure.from(
        const StorageException('Forbidden', statusCode: '403'),
      ).kind,
      MallaFailureKind.permission,
    );
    const wrapped = PostgrestException(
      message: '{"code":"PGRST205","message":"Could not find the table \'public.mallas_curriculares\' in the schema cache"}',
      code: '404',
    );
    expect(MallaUiFailure.from(wrapped).kind, MallaFailureKind.setup);
    expect(MallaUiFailure.diagnosticCode(wrapped), 'PGRST205');
    expect(
      MallaUiFailure.from(
        const PostgrestException(
          message: '{"code":"PGRST205","message":"Could not find the table \'public.otra_tabla\' in the schema cache"}',
          code: '404',
        ),
      ).kind,
      MallaFailureKind.other,
    );
    expect(
      MallaUiFailure.from(
        const PostgrestException(message: 'Not found', code: '404'),
      ).kind,
      MallaFailureKind.other,
    );
  });

  testWidgets('carga inicial muestra progreso y luego estado vacío', (
    tester,
  ) async {
    final pending = Completer<MallaCurricular?>();
    final service = _FakeMalla()..loadResult = pending.future;
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('malla-file-picker')), findsNothing);
    expect(find.byType(AppScrollHeader), findsOneWidget);
    expect(find.text('Malla curricular'), findsWidgets);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Elegir PDF o imagen'), findsOneWidget);
    expect(find.text('Importación pendiente de habilitación'), findsNothing);
  });

  testWidgets('selector no dibuja splash circular y monta visor PDF', (
    tester,
  ) async {
    final service = _FakeMalla()..loadResult = Future.value(null);
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final picker = find.byKey(const Key('malla-file-picker'));
    final inkWell = tester.widget<InkWell>(picker);
    expect(inkWell.splashFactory, same(NoSplash.splashFactory));
    expect(inkWell.highlightColor, Colors.transparent);

    await tester.tap(picker);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('malla-pdf-preview')), findsOneWidget);
    expect(find.byType(PdfViewer), findsOneWidget);
    expect(find.byKey(const Key('malla-pdf-previous-page')), findsOneWidget);
    expect(find.byKey(const Key('malla-pdf-next-page')), findsOneWidget);
    expect(find.byKey(const Key('malla-pdf-zoom-out')), findsOneWidget);
    expect(find.byKey(const Key('malla-pdf-zoom-in')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.byKey(const Key('malla-process-button')), findsOneWidget);

    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    expect(viewer.params.errorBannerBuilder, isNotNull);
    final tapHandler = viewer.params.onGeneralTap;
    expect(tapHandler, isNotNull);
    final viewerContext = tester.element(find.byType(PdfViewer));
    final doubleTap = PdfViewerGeneralTapHandlerDetails(
      localPosition: const Offset(20, 20),
      documentPosition: const Offset(20, 20),
      type: PdfViewerGeneralTapType.doubleTap,
      tapOn: PdfViewerPart.background,
    );
    expect(tapHandler!(viewerContext, viewer.controller!, doubleTap), isTrue);
    expect(
      tapHandler(
        viewerContext,
        viewer.controller!,
        PdfViewerGeneralTapHandlerDetails(
          localPosition: const Offset(20, 20),
          documentPosition: const Offset(20, 20),
          type: PdfViewerGeneralTapType.tap,
          tapOn: PdfViewerPart.background,
        ),
      ),
      isFalse,
    );
    final fallback = viewer.params.errorBannerBuilder!(
      viewerContext,
      StateError('PDF inválido'),
      null,
      viewer.documentRef,
    );
    await tester.pumpWidget(MaterialApp(home: fallback));
    expect(find.byKey(const Key('malla-pdf-preview-fallback')), findsOneWidget);
  });

  testWidgets('limpia el temporal después de un OCR exitoso', (tester) async {
    final service = _FakeMalla()..ocrResult = _successfulOcrResult();
    final documents = _FakeDocuments();

    await _startOcrProcessing(tester, service: service, documents: documents);
    await tester.pumpAndSettle();

    expect(service.processCalls, 1);
    expect(documents.deletedPaths, ['uid/malla.pdf']);
    expect(find.text('Álgebra'), findsOneWidget);
  });

  testWidgets('limpia el temporal cuando el procesamiento OCR falla', (
    tester,
  ) async {
    final service = _FakeMalla()
      ..processError = StateError('fallo OCR simulado');
    final documents = _FakeDocuments();

    await _startOcrProcessing(tester, service: service, documents: documents);
    await tester.pumpAndSettle();

    expect(service.processCalls, 1);
    expect(documents.deletedPaths, ['uid/malla.pdf']);
    expect(find.text('Álgebra'), findsNothing);
  });

  testWidgets(
    'un fallo de limpieza o cambio de sesión no invalida un OCR exitoso',
    (tester) async {
      final service = _FakeMalla()..ocrResult = _successfulOcrResult();
      final documents = _FakeDocuments(
        deleteError: StateError('sesión distinta o temporal ya eliminado'),
      );

      await _startOcrProcessing(tester, service: service, documents: documents);
      await tester.pumpAndSettle();

      expect(documents.deletes, 1);
      expect(find.text('Álgebra'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desmontar durante la subida conserva la limpieza temporal', (
    tester,
  ) async {
    final upload = Completer<OcrDocumentResult>();
    final service = _FakeMalla()..ocrResult = _successfulOcrResult();
    final documents = _FakeDocuments(uploadCompleter: upload);

    await _startOcrProcessing(tester, service: service, documents: documents);
    expect(documents.uploads, 1);

    await tester.pumpWidget(const SizedBox());
    upload.complete(
      const OcrDocumentResult(
        originalName: 'malla.pdf',
        bucket: 'ocr-temp',
        path: 'uid/malla.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 3,
      ),
    );
    await tester.pumpAndSettle();

    expect(service.processCalls, 0);
    expect(documents.deletedPaths, ['uid/malla.pdf']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desmontar durante el procesamiento conserva la limpieza temporal',
    (tester) async {
      final processing = Completer<MallaCurricular>();
      final service = _FakeMalla()..processCompleter = processing;
      final documents = _FakeDocuments();

      await _startOcrProcessing(tester, service: service, documents: documents);
      expect(service.processCalls, 1);

      await tester.pumpWidget(const SizedBox());
      processing.complete(_successfulOcrResult());
      await tester.pumpAndSettle();

      expect(documents.deletedPaths, ['uid/malla.pdf']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('encabezado compacto conserva retroceso al desplazar', (
    tester,
  ) async {
    final saved = MallaCurricular(
      id: 'saved',
      ramos: [
        for (var i = 0; i < 20; i++)
          RamoMalla(id: 'r$i', nombre: 'Ramo $i', semestre: 1),
      ],
    );
    final service = _FakeMalla()..loadResult = Future.value(saved);
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -650));
    await tester.pumpAndSettle();
    final header = tester.widget<AppScrollHeader>(find.byType(AppScrollHeader));
    expect(header.progress, greaterThan(0.5));
    expect(header.opaqueBackground, isTrue);
    expect(
      find.byKey(const Key('malla-compact-back-button')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('malla-compact-back-button')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'título grande queda cubierto por encabezado opaco al desplazar',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final saved = MallaCurricular(
          id: 'saved',
          ramos: [
            for (var i = 0; i < 20; i++)
              RamoMalla(id: 'r$i', nombre: 'Ramo $i', semestre: 1),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: MallaCurricularPage(
              service: _FakeMalla()..loadResult = Future.value(saved),
              documents: _FakeDocuments(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final list = find.byType(ListView).first;
        final scroll = tester.widget<ListView>(list).controller!;
        final compact = find.byType(AppScrollHeader);
        expect(tester.widget<AppScrollHeader>(compact).progress, 0);
        scroll.jumpTo(23);
        await tester.pump();
        expect(tester.widget<AppScrollHeader>(compact).progress, 0);
        expect(
          tester
              .widget<Opacity>(
                find.byKey(const Key('malla-large-title-visibility')),
              )
              .opacity,
          1,
        );
        expect(
          find.byKey(const Key('malla-back-button')).hitTestable(),
          findsOneWidget,
        );

        scroll.jumpTo(24);
        await tester.pump();
        final header = tester.widget<AppScrollHeader>(compact);
        expect(header.progress, 1);
        expect(header.opaqueBackground, isTrue);
        expect(
          tester
              .widget<Opacity>(
                find.byKey(const Key('malla-large-title-visibility')),
              )
              .opacity,
          0,
        );
        expect(
          find.byKey(const Key('malla-compact-back-button')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets('retroceso compacto usa superficie de Perfil en ambos temas', (
    tester,
  ) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final saved = MallaCurricular(
        id: 'saved',
        ramos: [
          for (var i = 0; i < 18; i++)
            RamoMalla(id: 'r$i', nombre: 'Ramo $i', semestre: 1),
        ],
      );
      final service = _FakeMalla()..loadResult = Future.value(saved);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: MallaCurricularPage(
            service: service,
            documents: _FakeDocuments(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      final back = find.byKey(const Key('malla-compact-back-button'));
      final box = tester.widget<Container>(
        find.descendant(of: back, matching: find.byType(Container)).first,
      );
      expect(
        (box.decoration as BoxDecoration).color,
        brightness == Brightness.dark
            ? const Color(0xFF202631)
            : const Color(0xFFF4F5F8),
      );
      expect(back.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('tabla ausente no muestra SQL ni consume OCR', (tester) async {
    final service = _FakeMalla()
      ..loadError = const PostgrestException(
        message: "Could not find the table 'public.mallas_curriculares' in the schema cache",
        code: 'PGRST205',
      );
    final documents = _FakeDocuments();
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(service: service, documents: documents),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Importación pendiente de habilitación'), findsOneWidget);
    expect(find.textContaining('PGRST205'), findsNothing);
    expect(find.textContaining('public.mallas_curriculares'), findsNothing);
    expect(find.byKey(const Key('malla-file-picker')), findsNothing);
    expect(find.byKey(const Key('malla-process-button')), findsNothing);
    expect(documents.uploads, 0);
    expect(service.processCalls, 0);
    expect(find.text('Comprobar nuevamente'), findsNothing);
  });

  testWidgets('PGRST205 envuelto en 404 muestra configuración pendiente', (
    tester,
  ) async {
    final service = _FakeMalla()
      ..loadError = const PostgrestException(
        message: '{"code":"PGRST205","message":"Could not find the table \'public.mallas_curriculares\' in the schema cache"}',
        code: '404',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Importación pendiente de habilitación'), findsOneWidget);
    expect(find.text('No pudimos completar la operación'), findsNothing);
    expect(find.textContaining('PGRST205'), findsNothing);
    expect(find.textContaining('schema cache'), findsNothing);
    expect(find.text('Comprobar nuevamente'), findsNothing);
  });

  for (final caseData in [
    (
      const PostgrestException(message: 'permission denied', code: '42501'),
      'No pudimos verificar tu acceso',
    ),
    (TimeoutException('red'), 'Sin conexión con la malla'),
    (
      const PostgrestException(message: 'internal failure', code: 'PGRST999'),
      'No pudimos completar la operación',
    ),
  ]) {
    testWidgets('carga distingue ${caseData.$2} sin detalles técnicos', (
      tester,
    ) async {
      final service = _FakeMalla()..loadError = caseData.$1;
      await tester.pumpWidget(
        MaterialApp(
          home: MallaCurricularPage(
            service: service,
            documents: _FakeDocuments(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(caseData.$2), findsOneWidget);
      expect(find.text('Importación pendiente de habilitación'), findsNothing);
      expect(find.textContaining('PGRST999'), findsNothing);
      expect(find.textContaining('permission denied'), findsNothing);
      expect(find.textContaining('internal failure'), findsNothing);
    });
  }

  testWidgets('resultado OCR organiza revisión por semestre', (tester) async {
    final service = _FakeMalla()
      ..ocrResult = MallaCurricular(
        id: '',
        ramos: [
          RamoMalla(
            id: 'ocr_1',
            nombre: 'Álgebra',
            semestre: 1,
            requiereRevision: true,
            motivosRevision: const ['credits_missing'],
          ),
          RamoMalla(id: 'ocr_2', nombre: 'Física', semestre: 2),
        ],
      );
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('malla-file-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('malla-file-picker')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('malla-process-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('malla-process-button')));
    await tester.pumpAndSettle();
    expect(find.text('Álgebra'), findsOneWidget);
    expect(find.textContaining('Completa los créditos'), findsOneWidget);
    expect(find.text('Física'), findsNothing);
    await _pickSemester(tester, 2);
    await tester.pumpAndSettle();
    expect(find.text('Física'), findsOneWidget);
    expect(find.text('Álgebra'), findsNothing);
  });

  testWidgets('diagnóstico de desarrollo muestra y copia la revisión real', (
    tester,
  ) async {
    DeveloperToolsConfig.debugOverride = true;
    addTearDown(() => DeveloperToolsConfig.debugOverride = null);
    String? copiedText;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final service = _FakeMalla()
      ..ocrResult = MallaCurricular(
        id: '',
        ramos: [RamoMalla(id: 'ocr_1', nombre: 'Álgebra', semestre: 1)],
        multimodalDiagnostics: const MallaMultimodalDiagnostics(
          status: 'completed',
          geminiRequestExecuted: true,
          successful: true,
          cacheHit: false,
          fallbackToVision: false,
          elapsedMilliseconds: 420,
          promptTokens: 100,
          outputTokens: 25,
          totalTokens: 125,
        ),
        multimodalReview: const MallaMultimodalReview(
          model: 'gemini-3.5-flash',
          processorVersion: 'malla-multimodal-v1',
          documentHash: 'hash-controlado',
          periodType: 'bimester',
          periodCount: 6,
          periodEvidence: ['Seis encabezados visibles'],
          courseReviews: [
            MallaCourseReview(
              courseId: 'ocr_1',
              proposedName: null,
              proposedCode: null,
              proposedCredits: null,
              proposedPeriod: 2,
              category: 'mandatory',
              prerequisiteStatus: 'identified',
              evidence: ['Celda bajo Bimestre 2'],
              pendingReasons: [],
            ),
          ],
          prerequisites: [],
          certifications: [
            MallaCertificationReview(
              id: 'cert_1',
              name: 'Certificación base',
              courseIds: ['ocr_1'],
              evidence: ['Rótulo visible'],
            ),
          ],
          pendingReview: ['Confirmar categoría'],
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('malla-file-picker')));
    await tester.tap(find.byKey(const Key('malla-file-picker')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('malla-process-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('malla-process-button')));
    await tester.pumpAndSettle();

    final button = find.byKey(const Key('malla-multimodal-diagnostic-button'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, 120));
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('Diagnóstico Gemini'), findsOneWidget);
    expect(find.textContaining('"status": "completed"'), findsOneWidget);
    expect(find.textContaining('"type": "bimester"'), findsOneWidget);
    expect(find.textContaining('Certificación base'), findsWidgets);
    expect(find.textContaining('Confirmar categoría'), findsOneWidget);

    await tester.tap(find.byKey(const Key('malla-copy-multimodal-diagnostic')));
    await tester.pump();
    expect(find.text('Diagnóstico copiado.'), findsOneWidget);
    expect(copiedText, contains('"model": "gemini-3.5-flash"'));
  });

  testWidgets('fallback multimodal no expone el diagnóstico técnico', (
    tester,
  ) async {
    DeveloperToolsConfig.debugOverride = false;
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..ocrResult = MallaCurricular(
        id: '',
        ramos: [RamoMalla(id: 'ocr_1', nombre: 'Álgebra', semestre: 1)],
        multimodalDiagnostics: const MallaMultimodalDiagnostics(
          status: 'fallback_to_vision',
          geminiRequestExecuted: true,
          successful: false,
          cacheHit: false,
          fallbackToVision: true,
          elapsedMilliseconds: 700,
          model: 'gemini-3.5-flash',
          stage: 'generate_content',
          failure: 'access',
          errorCategory: 'access',
          httpStatus: 403,
        ),
      );

    await _startOcrProcessing(
      tester,
      service: service,
      documents: _FakeDocuments(),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('malla-multimodal-fallback-warning')),
      findsOneWidget,
    );
    expect(find.text('Revisión avanzada no completada'), findsOneWidget);
    expect(find.byKey(const Key('malla-integrated-review')), findsNothing);

    expect(
      find.byKey(const Key('malla-multimodal-diagnostic-button')),
      findsNothing,
    );
    expect(find.text('Diagnóstico Gemini'), findsNothing);
  });

  testWidgets(
    'Fase 2A integra propuestas localmente y bloquea persistencia parcial',
    (tester) async {
      final service = _FakeMalla()
        ..ocrResult = MallaCurricular(
          id: '',
          ramos: [
            RamoMalla(
              id: 'vision-1',
              nombre: 'Fundamentos de Antropología',
              codigo: 'FAA1001',
              creditos: 4,
              semestre: 1,
            ),
            RamoMalla(
              id: 'vision-2',
              nombre: 'Ética para el Trabajo',
              codigo: 'ETI2001',
              creditos: 4,
              semestre: 2,
            ),
          ],
          multimodalReview: const MallaMultimodalReview(
            model: 'gemini-3.5-flash',
            processorVersion: 'malla-multimodal-v4.2',
            documentHash: 'hash-fase-2a',
            periodType: 'bimester',
            periodCount: 8,
            periodEvidence: ['Ocho columnas visibles'],
            courseReviews: [],
            additionalCourses: [
              MallaAdditionalCourseProposal(
                id: 'gemini-course',
                proposedName: 'Curso de Formación Cristiana',
                proposedCode: null,
                proposedCredits: null,
                proposedPeriod: 1,
                category: 'institutional',
                categoryLabel: 'Formación Sello',
                evidence: ['Celda visible'],
                pendingReasons: ['code_uncertain'],
              ),
            ],
            prerequisites: [
              MallaPrerequisiteReview(
                courseId: 'vision-2',
                requiresCourseId: 'vision-1',
                evidence: ['Flecha visible'],
              ),
            ],
            certifications: [
              MallaCertificationReview(
                id: 'cert-1',
                name: 'Certificado en Arquitectura de Software',
                courseIds: ['vision-1'],
                evidence: ['Contenedor visible'],
                memberships: [
                  MallaCertificationMembership(
                    courseId: 'vision-1',
                    basis: 'container',
                    evidence: ['Dentro del contenedor'],
                  ),
                ],
              ),
            ],
            academicRequirements: [
              MallaAcademicRequirement(
                id: 'req-1',
                type: 'unknown',
                targetCourseId: 'vision-2',
                targetLabel: 'Ética para el Trabajo',
                description: 'Niveles previos aprobados',
                minimumLevel: 4,
                evidence: ['Nota visible'],
                pendingReasons: ['requirement_type_uncertain'],
              ),
            ],
            pendingReview: [],
          ),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: MallaCurricularPage(
            service: service,
            documents: _FakeDocuments(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('malla-file-picker')));
      await tester.tap(find.byKey(const Key('malla-file-picker')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('malla-process-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('malla-process-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('malla-integrated-review')), findsOneWidget);
      expect(find.text('Bimestres'), findsOneWidget);
      expect(find.text('Curso de Formación Cristiana'), findsNWidgets(2));
      expect(find.text('Revisión de IA'), findsWidgets);
      expect(find.text('Elementos que necesitan atención'), findsOneWidget);

      final additionalCourse = find.text('Curso de Formación Cristiana').last;
      await tester.ensureVisible(additionalCourse);
      await tester.pumpAndSettle();
      await tester.tap(additionalCourse);
      await tester.pumpAndSettle();
      expect(find.text('Referencia de la malla'), findsOneWidget);
      expect(find.text('Celda visible'), findsWidgets);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      final relationships = find.byKey(
        const Key('malla-relationship-proposals'),
      );
      await tester.ensureVisible(relationships);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, 140));
      await tester.pumpAndSettle();
      await tester.tap(relationships);
      await tester.pumpAndSettle();
      final prerequisiteGroup = find.byKey(
        const ValueKey('prerequisite-group-prerequisite-group-0-0'),
      );
      await tester.ensureVisible(prerequisiteGroup);
      await tester.tap(prerequisiteGroup);
      await tester.pumpAndSettle();
      expect(find.textContaining('es requisito de'), findsOneWidget);
      expect(find.byType(Checkbox), findsWidgets);
      expect(find.text('institutional'), findsNothing);
      expect(find.text('capstone_eligibility'), findsNothing);

      final confirm = tester.widget<FilledButton>(
        find.byKey(const Key('malla-confirm-import')),
      );
      expect(confirm.onPressed, isNull);
      expect(service.confirmCalls, 0);
      expect(
        find.text('Guardado disponible en la siguiente etapa'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'seis pendientes contabilizados muestran seis problemas corregibles',
    (tester) async {
      final service = _FakeMalla()
        ..ocrResult = MallaCurricular(
          id: '',
          ramos: [
            for (var index = 1; index <= 6; index++)
              RamoMalla(
                id: 'course-$index',
                nombre: 'Asignatura pendiente $index',
                semestre: 1,
                requiereRevision: true,
                motivosRevision: const ['code_missing'],
              ),
          ],
          multimodalReview: const MallaMultimodalReview(
            model: 'gemini-3.5-flash',
            processorVersion: 'malla-multimodal-v4.2',
            documentHash: 'hash-seis-pendientes',
            periodType: 'semester',
            periodCount: 8,
            periodEvidence: ['Ocho columnas visibles'],
            courseReviews: [],
            prerequisites: [],
            certifications: [],
            pendingReview: [],
          ),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: MallaCurricularPage(
            service: service,
            documents: _FakeDocuments(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('malla-file-picker')));
      await tester.tap(find.byKey(const Key('malla-file-picker')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('malla-process-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('malla-process-button')));
      await tester.pumpAndSettle();

      final problems = find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('malla-attention-problem-');
      });
      expect(problems, findsNWidgets(6));
      expect(find.text('Corregir'), findsNWidgets(6));

      final firstCorrection = find.text('Corregir').first;
      await tester.ensureVisible(firstCorrection);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, 120));
      await tester.pumpAndSettle();
      await tester.tap(firstCorrection);
      await tester.pumpAndSettle();
      expect(find.text('Corregir asignatura'), findsOneWidget);
      expect(service.confirmCalls, 0);
    },
  );

  testWidgets(
    'confirma ramo sin código y no ofrece agregar su especial duplicado',
    (tester) async {
      final service = _FakeMalla()
        ..multimodalPersistenceEnabled = true
        ..ocrResult = MallaCurricular(
          id: '',
          archivoNombre: 'malla.pdf',
          ramos: [
            RamoMalla(
              id: 'vision-christian',
              nombre: 'Curso de Formación Cristiana',
              semestre: 3,
              creditos: 4,
              requiereRevision: true,
              motivosRevision: const ['code_missing'],
            ),
          ],
          especiales: [
            ElementoCurricularEspecial(
              nombre: 'Curso de Formación Cristiana',
              tipo: 'uncoded_course',
              semestre: 3,
              creditos: 4,
            ),
          ],
          multimodalReview: const MallaMultimodalReview(
            model: 'gemini-3.5-flash',
            processorVersion: 'malla-multimodal-v4.5',
            documentHash: 'hash-uncoded-course',
            periodType: 'semester',
            periodCount: 8,
            periodEvidence: ['Ocho períodos visibles'],
            courseReviews: [],
            prerequisites: [],
            certifications: [],
            pendingReview: [],
          ),
        );

      await _startOcrProcessing(
        tester,
        service: service,
        documents: _FakeDocuments(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('malla-review-intro-start')));
      await tester.pumpAndSettle();

      expect(find.text('Otros elementos detectados'), findsNothing);
      expect(find.byTooltip('Añadir a la malla'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('malla-review-count')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );

      final correction = find.text('Corregir').first;
      await tester.ensureVisible(correction);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, 120));
      await tester.pumpAndSettle();
      await tester.tap(correction);
      await tester.pumpAndSettle();
      final verification = find.byKey(const Key('malla-verify-missing-code'));
      expect(verification, findsOneWidget);
      expect(find.text('Código opcional'), findsOneWidget);
      await tester.ensureVisible(verification);
      await tester.pumpAndSettle();
      await tester.tap(verification);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar corrección'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('malla-review-count')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      expect(find.text('Curso de Formación Cristiana'), findsOneWidget);
      expect(find.text('Otros elementos detectados'), findsNothing);
    },
  );

  testWidgets(
    'entorno autorizado confirma el borrador multimodal sin usar RPC Vision',
    (tester) async {
      final service = _FakeMalla()
        ..multimodalPersistenceEnabled = true
        ..ocrResult = MallaCurricular(
          id: '',
          archivoNombre: 'malla.pdf',
          ramos: [
            RamoMalla(
              id: 'vision-1',
              nombre: 'Programación',
              semestre: 1,
              codigo: 'INF1001',
              creditos: 6,
            ),
          ],
          multimodalReview: const MallaMultimodalReview(
            model: 'gemini-3.5-flash',
            processorVersion: 'malla-multimodal-v4.2',
            documentHash: 'hash-save',
            periodType: 'semester',
            periodCount: 8,
            periodEvidence: ['Ocho columnas'],
            courseReviews: [],
            prerequisites: [],
            certifications: [],
            pendingReview: [],
          ),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: MallaCurricularPage(
            service: service,
            documents: _FakeDocuments(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('malla-file-picker')));
      await tester.tap(find.byKey(const Key('malla-file-picker')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('malla-process-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('malla-process-button')));
      await tester.pumpAndSettle();

      expect(find.text('Tu malla está lista para revisar'), findsOneWidget);
      await tester.tap(find.byKey(const Key('malla-review-intro-start')));
      await tester.pumpAndSettle();

      final confirmFinder = find.byKey(const Key('malla-confirm-import'));
      final confirm = tester.widget<FilledButton>(confirmFinder);
      expect(confirm.onPressed, isNotNull);
      await tester.ensureVisible(confirmFinder);
      await tester.tap(confirmFinder);
      await tester.pumpAndSettle();
      expect(find.text('Confirmar malla'), findsOneWidget);
      await tester.tap(find.text('Confirmar y guardar'));
      await tester.pumpAndSettle();

      expect(service.multimodalConfirmCalls, 1);
      expect(service.confirmCalls, 0);
      expect(find.text('Malla guardada correctamente.'), findsOneWidget);
    },
  );

  testWidgets(
    'aviso inicial no se cierra accidentalmente ni confirma sugerencias',
    (tester) async {
      final service = _FakeMalla()
        ..multimodalPersistenceEnabled = true
        ..ocrResult = MallaCurricular(
          id: '',
          ramos: [
            RamoMalla(id: 'base', nombre: 'Base', semestre: 1),
            RamoMalla(id: 'capstone', nombre: 'Capstone', semestre: 2),
          ],
          multimodalReview: const MallaMultimodalReview(
            model: 'gemini-3.5-flash',
            processorVersion: 'malla-multimodal-v4.5',
            documentHash: 'hash-intro',
            periodType: 'semester',
            periodCount: 2,
            periodEvidence: ['Dos períodos visibles'],
            courseReviews: [],
            prerequisites: [
              MallaPrerequisiteReview(
                courseId: 'capstone',
                requiresCourseId: 'base',
                evidence: ['Flecha directa'],
              ),
            ],
            certifications: [],
            pendingReview: [],
          ),
        );

      await _startOcrProcessing(
        tester,
        service: service,
        documents: _FakeDocuments(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tu malla está lista para revisar'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Tu malla está lista para revisar'), findsOneWidget);
      expect(service.multimodalConfirmCalls, 0);

      await tester.tap(find.byKey(const Key('malla-review-intro-start')));
      await tester.pumpAndSettle();
      expect(find.text('Tu malla está lista para revisar'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('malla-suggestion-count')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('malla-confirm-import')))
            .onPressed,
        isNotNull,
      );
      expect(service.multimodalConfirmCalls, 0);
    },
  );

  testWidgets('corrige requisito antes de guardar conservándolo pendiente', (
    tester,
  ) async {
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..ocrResult = MallaCurricular(
        id: '',
        ramos: [RamoMalla(id: 'capstone', nombre: 'Capstone', semestre: 2)],
        multimodalReview: const MallaMultimodalReview(
          model: 'gemini-3.5-flash',
          processorVersion: 'malla-multimodal-v4.5',
          documentHash: 'hash-edit-requirement',
          periodType: 'semester',
          periodCount: 2,
          periodEvidence: ['Dos períodos visibles'],
          courseReviews: [],
          prerequisites: [],
          certifications: [],
          academicRequirements: [
            MallaAcademicRequirement(
              id: 'req-capstone',
              type: 'capstone_eligibility',
              targetCourseId: 'capstone',
              targetLabel: 'Capstone',
              description: 'Niveles I a VII aprobados',
              minimumLevel: 7,
              evidence: ['Nota original visible'],
              pendingReasons: ['requirement_level_conflict'],
            ),
          ],
          pendingReview: [],
        ),
      );

    await _startOcrProcessing(
      tester,
      service: service,
      documents: _FakeDocuments(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('malla-review-intro-start')));
    await tester.pumpAndSettle();

    final edit = find.byKey(const ValueKey('edit-requirement-req-capstone'));
    await tester.scrollUntilVisible(
      edit,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('academic-requirement-description')),
      'Niveles I a VI aprobados',
    );
    await tester.enterText(
      find.byKey(const Key('academic-requirement-minimum-level')),
      '6',
    );
    await tester.tap(find.byKey(const Key('academic-requirement-save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Niveles I a VI aprobados'), findsOneWidget);
    expect(find.text('Requiere revisión'), findsWidgets);
    expect(service.multimodalConfirmCalls, 0);
    expect(service.requirementDecisionCalls, 0);
  });

  testWidgets(
    'malla guardada con solo sugerencias no figura completamente revisada',
    (tester) async {
      final review = _savedAcademicReview(includeCertifications: false);
      review.prerequisites.first.decision = MallaProposalDecision.suggested;
      review.prerequisites.last.decision = MallaProposalDecision.rejected;
      final service = _FakeMalla()
        ..multimodalPersistenceEnabled = true
        ..loadResult = Future.value(review.malla)
        ..loadedMultimodalReview = review;

      await tester.pumpWidget(
        MaterialApp(
          home: MallaCurricularPage(
            service: service,
            documents: _FakeDocuments(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tu malla está completamente revisada.'), findsNothing);
      expect(find.textContaining('1 relación sugerida'), findsOneWidget);
      expect(find.byKey(const Key('malla-review-intro-start')), findsNothing);
      await tester.tap(find.text('Ver pendientes'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirma parcialmente un grupo y conserva exclusión para descarte individual',
    (tester) async {
      final service = _FakeMalla()
        ..multimodalPersistenceEnabled = true
        ..ocrResult = MallaCurricular(
          id: '',
          ramos: [
            RamoMalla(id: 'a', nombre: 'Fundamentos', semestre: 1),
            RamoMalla(id: 'b', nombre: 'Programación', semestre: 2),
            RamoMalla(id: 'c', nombre: 'Proyecto', semestre: 3),
            RamoMalla(id: 'd', nombre: 'Capstone', semestre: 4),
          ],
          multimodalReview: const MallaMultimodalReview(
            model: 'gemini-3.5-flash',
            processorVersion: 'malla-multimodal-v4.5',
            documentHash: 'hash-group-prerequisites',
            periodType: 'semester',
            periodCount: 4,
            periodEvidence: ['Cuatro períodos'],
            courseReviews: [],
            prerequisites: [
              MallaPrerequisiteReview(
                courseId: 'b',
                requiresCourseId: 'a',
                evidence: ['Flecha A a B'],
              ),
              MallaPrerequisiteReview(
                courseId: 'c',
                requiresCourseId: 'b',
                evidence: ['Flecha B a C'],
              ),
              MallaPrerequisiteReview(
                courseId: 'd',
                requiresCourseId: 'c',
                evidence: ['Flecha C a D'],
              ),
            ],
            certifications: [],
            pendingReview: [],
          ),
        );

      await _startOcrProcessing(
        tester,
        service: service,
        documents: _FakeDocuments(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('malla-review-intro-start')));
      await tester.pumpAndSettle();

      final relationships = find.byKey(
        const Key('malla-relationship-proposals'),
      );
      await tester.scrollUntilVisible(
        relationships,
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, 120));
      await tester.pumpAndSettle();
      await tester.tap(relationships);
      await tester.pumpAndSettle();

      final group = find.byKey(
        const ValueKey('prerequisite-group-prerequisite-group-0-0'),
      );
      await tester.ensureVisible(group);
      await tester.tap(group);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('select-prerequisite-b>c')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('confirm-prerequisite-group-prerequisite-group-0-0'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('malla-suggestion-count')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      final confirmImport = tester.widget<FilledButton>(
        find.byKey(const Key('malla-confirm-import')),
      );
      expect(confirmImport.onPressed, isNotNull);

      final excludedMenu = find.byKey(
        const ValueKey('grouped-prerequisite-menu-b>c'),
      );
      await tester.ensureVisible(excludedMenu);
      await tester.tap(excludedMenu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descartada').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('malla-suggestion-count')), findsNothing);
      expect(service.multimodalConfirmCalls, 0);
    },
  );

  testWidgets(
    'confirma certificación con membresías seleccionadas y conserva excluidas',
    (tester) async {
      final service = _FakeMalla()
        ..multimodalPersistenceEnabled = true
        ..ocrResult = MallaCurricular(
          id: '',
          ramos: [
            RamoMalla(id: 'a', nombre: 'Arquitectura', semestre: 1),
            RamoMalla(id: 'b', nombre: 'Integración', semestre: 2),
          ],
          multimodalReview: const MallaMultimodalReview(
            model: 'gemini-3.5-flash',
            processorVersion: 'malla-multimodal-v4.5',
            documentHash: 'hash-group-certification',
            periodType: 'semester',
            periodCount: 2,
            periodEvidence: ['Dos períodos'],
            courseReviews: [],
            prerequisites: [],
            certifications: [
              MallaCertificationReview(
                id: 'cert-architecture',
                name: 'Arquitectura de Software',
                courseIds: ['a', 'b'],
                evidence: ['Contenedor identificado'],
                memberships: [
                  MallaCertificationMembership(
                    courseId: 'a',
                    basis: 'container',
                    evidence: ['Dentro del contenedor'],
                  ),
                  MallaCertificationMembership(
                    courseId: 'b',
                    basis: 'container',
                    evidence: ['Dentro del contenedor'],
                  ),
                ],
              ),
            ],
            pendingReview: [],
          ),
        );

      await _startOcrProcessing(
        tester,
        service: service,
        documents: _FakeDocuments(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('malla-review-intro-start')));
      await tester.pumpAndSettle();

      final relationships = find.byKey(
        const Key('malla-relationship-proposals'),
      );
      await tester.scrollUntilVisible(
        relationships,
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, 120));
      await tester.pumpAndSettle();
      await tester.tap(relationships);
      await tester.pumpAndSettle();
      final group = find.byKey(
        const ValueKey('certification-group-cert-architecture'),
      );
      await tester.ensureVisible(group);
      await tester.tap(group);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('select-membership-cert-architecture-b')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('confirm-certification-group-cert-architecture'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('malla-suggestion-count')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(service.multimodalConfirmCalls, 0);
    },
  );

  testWidgets(
    'malla de ejemplo usa revisión y RPC multimodal sin OCR ni Gemini',
    (tester) async {
      final service = _FakeMalla()
        ..multimodalPersistenceEnabled = true
        ..multimodalTestingSampleEnabled = true;
      final documents = _FakeDocuments();

      await tester.pumpWidget(
        MaterialApp(
          home: MallaCurricularPage(service: service, documents: documents),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('malla-load-testing-sample')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('malla-load-testing-sample')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('malla-testing-sample-banner')),
        findsOneWidget,
      );
      expect(find.text('Programación Aplicada'), findsOneWidget);
      expect(documents.uploads, 0);
      expect(service.processCalls, 0);

      final confirmFinder = find.byKey(const Key('malla-confirm-import'));
      await tester.ensureVisible(confirmFinder);
      await tester.pumpAndSettle();
      await tester.tap(confirmFinder);
      await tester.pumpAndSettle();
      expect(find.text('Confirmar malla de ejemplo'), findsOneWidget);
      await tester.tap(find.text('Confirmar y guardar'));
      await tester.pumpAndSettle();

      expect(service.multimodalConfirmCalls, 1);
      expect(service.confirmCalls, 0);
      expect(documents.uploads, 0);
      expect(service.processCalls, 0);
      expect(find.text('Malla guardada correctamente.'), findsOneWidget);
      expect(
        find.byKey(const Key('malla-testing-sample-banner')),
        findsOneWidget,
      );
    },
  );

  testWidgets('acceso de ejemplo no aparece fuera del entorno autorizado', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: _FakeMalla(),
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('malla-load-testing-sample')), findsNothing);
    expect(find.textContaining('malla de ejemplo'), findsNothing);
  });

  testWidgets(
    'diagnóstico RLS usa la malla guardada y muestra informe seguro',
    (tester) async {
      final diagnostic = _FakeRlsDiagnostic(enabled: true);
      final service = _FakeMalla()
        ..multimodalPersistenceEnabled = true
        ..multimodalTestingSampleEnabled = true
        ..loadedMultimodalReview = _savedTestingReview();

      await tester.pumpWidget(
        MaterialApp(
          home: MallaCurricularPage(
            service: service,
            documents: _FakeDocuments(),
            rlsDiagnostic: diagnostic,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final access = find.byKey(const Key('malla-rls-diagnostic-access'));
      Future<void> openDiagnostic() async {
        await tester.ensureVisible(access);
        final scroll = tester
            .widget<ListView>(find.byType(ListView).first)
            .controller!;
        scroll.jumpTo(scroll.offset > 80 ? scroll.offset - 80 : 0);
        await tester.pumpAndSettle();
        await tester.tap(access);
        await tester.pumpAndSettle();
      }

      await openDiagnostic();
      expect(
        find.textContaining('11111111-1111-4111-8111-111111111111'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('malla-rls-foreign-id')),
        '22222222-2222-4222-8222-222222222222',
      );
      await tester.tap(find.byKey(const Key('malla-run-rls-diagnostic')));
      await tester.pumpAndSettle();

      expect(diagnostic.calls, 1);
      expect(find.byKey(const Key('malla-rls-result')), findsOneWidget);
      expect(find.textContaining('Resultado: APROBADO'), findsOneWidget);

      await tester.tap(find.byKey(const Key('malla-close-rls-diagnostic')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('malla-rls-result')), findsNothing);
      expect(tester.takeException(), isNull);

      await openDiagnostic();
      expect(find.byKey(const Key('malla-rls-foreign-id')), findsOneWidget);
      await tester.tap(find.byKey(const Key('malla-close-rls-diagnostic')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('diagnóstico RLS no actualiza widgets después de desmontarse', (
    tester,
  ) async {
    final diagnostic = _DelayedRlsDiagnostic();
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..multimodalTestingSampleEnabled = true
      ..loadedMultimodalReview = _savedTestingReview();

    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
          rlsDiagnostic: diagnostic,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final access = find.byKey(const Key('malla-rls-diagnostic-access'));
    await tester.ensureVisible(access);
    await tester.tap(access);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('malla-rls-foreign-id')),
      '22222222-2222-4222-8222-222222222222',
    );
    await tester.tap(find.byKey(const Key('malla-run-rls-diagnostic')));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    diagnostic.completer.complete(
      const MallaRlsDiagnosticResult(
        ownMallaId: '11111111-1111-4111-8111-111111111111',
        foreignMallaId: '22222222-2222-4222-8222-222222222222',
        ownRowsByTable: {'mallas_curriculares': 1},
        foreignRowsHidden: {'mallas_curriculares': true},
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('malla-rls-result')), findsNothing);
  });

  testWidgets('diagnóstico RLS permanece oculto si falta cualquier guardia', (
    tester,
  ) async {
    for (final configuration in [(true, false), (false, true)]) {
      final service = _FakeMalla()
        ..multimodalPersistenceEnabled = true
        ..multimodalTestingSampleEnabled = configuration.$1
        ..loadedMultimodalReview = _savedTestingReview();
      await tester.pumpWidget(
        MaterialApp(
          home: MallaCurricularPage(
            service: service,
            documents: _FakeDocuments(),
            rlsDiagnostic: _FakeRlsDiagnostic(enabled: configuration.$2),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('malla-rls-diagnostic-access')),
        findsNothing,
      );
    }
  });

  testWidgets(
    'diagnóstico de escritura usa la malla guardada y muestra informe seguro',
    (tester) async {
      final diagnostic = _FakeWriteDiagnostic(enabled: true);
      final service = _FakeMalla()
        ..multimodalPersistenceEnabled = true
        ..multimodalTestingSampleEnabled = true
        ..loadedMultimodalReview = _savedTestingReview();

      await tester.pumpWidget(
        MaterialApp(
          home: MallaCurricularPage(
            service: service,
            documents: _FakeDocuments(),
            writeDiagnostic: diagnostic,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final access = find.byKey(const Key('malla-write-diagnostic-access'));
      await tester.ensureVisible(access);
      await tester.tap(access);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('malla-write-foreign-id')),
        '22222222-2222-4222-8222-222222222222',
      );
      await tester.tap(find.byKey(const Key('malla-run-write-diagnostic')));
      await tester.pumpAndSettle();

      expect(diagnostic.calls, 1);
      expect(find.byKey(const Key('malla-write-result')), findsOneWidget);
      expect(find.textContaining('Resultado: APROBADO'), findsOneWidget);

      await tester.tap(find.byKey(const Key('malla-close-write-diagnostic')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('malla-write-result')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'diagnóstico de escritura permanece oculto si falta cualquier guardia',
    (tester) async {
      for (final configuration in [(true, false), (false, true)]) {
        final service = _FakeMalla()
          ..multimodalPersistenceEnabled = true
          ..multimodalTestingSampleEnabled = configuration.$1
          ..loadedMultimodalReview = _savedTestingReview();
        await tester.pumpWidget(
          MaterialApp(
            home: MallaCurricularPage(
              service: service,
              documents: _FakeDocuments(),
              writeDiagnostic: _FakeWriteDiagnostic(enabled: configuration.$2),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('malla-write-diagnostic-access')),
          findsNothing,
        );
      }
    },
  );

  testWidgets(
    'ficha persistida distingue prerrequisitos confirmados y por revisar',
    (tester) async {
      final service = _FakeMalla()
        ..multimodalPersistenceEnabled = true
        ..loadedMultimodalReview = _savedAcademicReview();

      await tester.pumpWidget(
        MaterialApp(
          home: MallaCurricularPage(
            service: service,
            documents: _FakeDocuments(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _pickSemester(tester, 2);
      final target = find.byKey(const ValueKey('malla-course-destino'));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('malla-course-academic-details')),
        findsOneWidget,
      );
      expect(find.text('Código: TST2001'), findsOneWidget);
      expect(find.text('Créditos: 8'), findsOneWidget);
      expect(find.byKey(const Key('malla-course-period')), findsOneWidget);
      expect(find.text('Categoría: Proyecto final'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('malla-course-prerequisite-base_confirmada')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('malla-course-prerequisite-base_sugerida')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey('malla-course-prerequisite-base_confirmada'),
          ),
          matching: find.text('Confirmado'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey('malla-course-prerequisite-base_sugerida'),
          ),
          matching: find.text('Por revisar'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      await _pickSemester(tester, 1);
      final noPrerequisites = find.byKey(
        const ValueKey('malla-course-base_confirmada'),
      );
      await tester.ensureVisible(noPrerequisites);
      await tester.tap(noPrerequisites);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('malla-course-prerequisites-empty')),
        findsOneWidget,
      );
    },
  );

  for (final decision in const [
    MallaProposalDecision.accepted,
    MallaProposalDecision.rejected,
  ]) {
    testWidgets('gestiona prerrequisito persistido ${decision.name}', (
      tester,
    ) async {
      final review = _savedAcademicReview();
      final service = _FakeMalla()
        ..multimodalPersistenceEnabled = true
        ..loadedMultimodalReview = review;
      await tester.pumpWidget(
        MaterialApp(
          home: MallaCurricularPage(
            service: service,
            documents: _FakeDocuments(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _pickSemester(tester, 2);
      await tester.tap(find.byKey(const ValueKey('malla-course-destino')));
      await tester.pumpAndSettle();

      final action = find.byKey(
        const ValueKey('malla-prerequisite-review-destino-base_sugerida'),
      );
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(
        find.text('Proyecto Integrador depende de Fundamentos de Datos.'),
        findsOneWidget,
      );
      expect(find.textContaining('Evidencia: Línea cercana'), findsOneWidget);

      await tester.tap(
        find.byKey(
          decision == MallaProposalDecision.accepted
              ? const Key('malla-prerequisite-confirm')
              : const Key('malla-prerequisite-reject'),
        ),
      );
      await tester.pumpAndSettle();

      expect(service.prerequisiteDecisionCalls, 1);
      expect(service.prerequisiteDecisions, [decision]);
      expect(review.prerequisites.last.decision, decision);
      expect(
        find.byKey(const Key('malla-course-academic-details')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('malla-review-count')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('malla-course-destino')));
      await tester.pumpAndSettle();
      final relation = find.byKey(
        const ValueKey('malla-course-prerequisite-base_sugerida'),
      );
      if (decision == MallaProposalDecision.accepted) {
        expect(relation, findsOneWidget);
        expect(
          find.descendant(of: relation, matching: find.text('Confirmado')),
          findsOneWidget,
        );
      } else {
        expect(relation, findsNothing);
      }
    });
  }

  testWidgets('fallo al gestionar prerrequisito conserva la revisión', (
    tester,
  ) async {
    final review = _savedAcademicReview();
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..loadedMultimodalReview = review
      ..prerequisiteDecisionError = const PostgrestException(
        message: 'usuario_firebase_no_valido',
        code: '42501',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _pickSemester(tester, 2);
    await tester.tap(find.byKey(const ValueKey('malla-course-destino')));
    await tester.pumpAndSettle();
    final action = find.byKey(
      const ValueKey('malla-prerequisite-review-destino-base_sugerida'),
    );
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('malla-prerequisite-reject')));
    await tester.pumpAndSettle();

    expect(service.prerequisiteDecisionCalls, 1);
    expect(review.prerequisites.last.decision, MallaProposalDecision.pending);
    expect(action, findsOneWidget);
    expect(find.textContaining('Vuelve a iniciar sesión'), findsOneWidget);
  });

  testWidgets('bloquea doble escritura mientras decide prerrequisito', (
    tester,
  ) async {
    final review = _savedAcademicReview();
    final completer = Completer<MallaImportReview>();
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..loadedMultimodalReview = review
      ..prerequisiteDecisionCompleter = completer;
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _pickSemester(tester, 2);
    await tester.tap(find.byKey(const ValueKey('malla-course-destino')));
    await tester.pumpAndSettle();
    final action = find.byKey(
      const ValueKey('malla-prerequisite-review-destino-base_sugerida'),
    );
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('malla-prerequisite-confirm')));
    await tester.pump();

    expect(service.prerequisiteDecisionCalls, 1);
    expect(tester.widget<TextButton>(action).onPressed, isNull);

    review.prerequisites.last.decision = MallaProposalDecision.accepted;
    completer.complete(review);
    await tester.pumpAndSettle();
    expect(service.prerequisiteDecisionCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'confirma parcialmente un grupo persistido sin descartar exclusiones',
    (tester) async {
      final review = _savedGroupedReview();
      final service = _FakeMalla()
        ..multimodalPersistenceEnabled = true
        ..loadedMultimodalReview = review;
      await tester.pumpWidget(
        MaterialApp(
          home: MallaCurricularPage(
            service: service,
            documents: _FakeDocuments(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _expandPersistedSection(
        tester,
        const Key('malla-prerequisites-section'),
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('malla-suggestion-count')),
          matching: find.text('5'),
        ),
        findsOneWidget,
      );

      final group = find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('prerequisite-group-prerequisite-group-');
      });
      await tester.ensureVisible(group);
      await tester.tap(group);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('select-prerequisite-base_confirmada>base_sugerida'),
        ),
      );
      await tester.pumpAndSettle();
      final confirm = find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('confirm-prerequisite-group-');
      });
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(service.relationshipBatchCalls, 1);
      expect(service.prerequisiteBatches.single, ['destino>base_sugerida']);
      expect(
        review.prerequisites.last.decision,
        MallaProposalDecision.suggested,
      );
      expect(review.prerequisites[1].decision, MallaProposalDecision.accepted);
      expect(
        find.descendant(
          of: find.byKey(const Key('malla-suggestion-count')),
          matching: find.text('4'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('confirma certificación persistida y membresías seleccionadas', (
    tester,
  ) async {
    final review = _savedGroupedReview();
    final certification = review.certifications.single;
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..loadedMultimodalReview = review;
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _expandPersistedSection(
      tester,
      const Key('malla-certifications-group-section'),
    );

    final group = find.byKey(
      const ValueKey('certification-group-cert_testing'),
    );
    await tester.ensureVisible(group);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, 120));
    await tester.pumpAndSettle();
    await tester.tap(group);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('select-membership-cert_testing-destino')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('confirm-certification-group-cert_testing')),
    );
    await tester.pumpAndSettle();

    expect(service.relationshipBatchCalls, 1);
    expect(service.membershipBatches.single, ['cert_testing:base_sugerida']);
    expect(certification.decision, MallaProposalDecision.accepted);
    expect(
      certification.memberships[1].decision,
      MallaProposalDecision.accepted,
    );
    expect(
      certification.memberships.last.decision,
      MallaProposalDecision.suggested,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('malla-suggestion-count')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('fallo agrupado conserva sugerencias y no muestra éxito', (
    tester,
  ) async {
    final review = _savedGroupedReview();
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..loadedMultimodalReview = review
      ..relationshipBatchError = const PostgrestException(
        message: 'usuario_firebase_no_valido',
        code: '42501',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _expandPersistedSection(
      tester,
      const Key('malla-prerequisites-section'),
    );
    final group = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('prerequisite-group-prerequisite-group-');
    });
    await tester.ensureVisible(group);
    await tester.tap(group);
    await tester.pumpAndSettle();
    final confirm = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('confirm-prerequisite-group-');
    });
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(service.relationshipBatchCalls, 1);
    expect(
      review.prerequisites.where(
        (item) => item.decision == MallaProposalDecision.suggested,
      ),
      hasLength(2),
    );
    expect(find.textContaining('Vuelve a iniciar sesión'), findsOneWidget);
    expect(find.textContaining('prerrequisitos confirmados'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('malla-suggestion-count')),
        matching: find.text('5'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('malla-persisted-group-saving')), findsNothing);
  });

  testWidgets(
    'certificaciones persistidas muestran membresías y estado vacío',
    (tester) async {
      final service = _FakeMalla()
        ..multimodalPersistenceEnabled = true
        ..loadedMultimodalReview = _savedAcademicReview();
      await tester.pumpWidget(
        MaterialApp(
          home: MallaCurricularPage(
            service: service,
            documents: _FakeDocuments(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _expandPersistedSection(
        tester,
        const Key('malla-certifications-group-section'),
      );

      final certification = find.byKey(
        const ValueKey('certification-group-cert_testing'),
      );
      await tester.ensureVisible(certification);
      await tester.tap(certification);
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey('grouped-membership-cert_testing-base_confirmada'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('grouped-membership-cert_testing-base_sugerida'),
        ),
        findsOneWidget,
      );

      final emptyService = _FakeMalla()
        ..multimodalPersistenceEnabled = true
        ..loadedMultimodalReview = _savedAcademicReview(
          includeCertifications: false,
        );
      await tester.pumpWidget(
        MaterialApp(
          home: MallaCurricularPage(
            key: const ValueKey('empty-certifications'),
            service: emptyService,
            documents: _FakeDocuments(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('certification-group-cert_testing')),
        findsNothing,
      );
    },
  );

  for (final decision in const [
    MallaProposalDecision.accepted,
    MallaProposalDecision.rejected,
  ]) {
    testWidgets('gestiona membresía persistida ${decision.name}', (
      tester,
    ) async {
      final review = _savedAcademicReview();
      final service = _FakeMalla()
        ..multimodalPersistenceEnabled = true
        ..loadedMultimodalReview = review;
      await tester.pumpWidget(
        MaterialApp(
          home: MallaCurricularPage(
            service: service,
            documents: _FakeDocuments(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _expandPersistedSection(
        tester,
        const Key('malla-certifications-group-section'),
      );
      final certification = find.byKey(
        const ValueKey('certification-group-cert_testing'),
      );
      await tester.ensureVisible(certification);
      await tester.tap(certification);
      await tester.pumpAndSettle();

      final action = find.byKey(
        const ValueKey('grouped-membership-menu-cert_testing-base_sugerida'),
      );
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .text(
              decision == MallaProposalDecision.accepted
                  ? 'Confirmada'
                  : 'Descartada',
            )
            .last,
      );
      await tester.pumpAndSettle();

      if (decision == MallaProposalDecision.accepted) {
        expect(service.relationshipBatchCalls, 1);
        expect(service.membershipBatches.single, [
          'cert_testing:base_sugerida',
        ]);
        expect(service.membershipDecisionCalls, 0);
      } else {
        expect(service.relationshipBatchCalls, 0);
        expect(service.membershipDecisionCalls, 1);
        expect(service.membershipDecisions, [decision]);
      }
      expect(review.certifications.single.memberships.last.decision, decision);
      expect(
        find.descendant(
          of: find.byKey(const Key('malla-review-count')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      final relation = find.byKey(
        const ValueKey('grouped-membership-cert_testing-base_sugerida'),
      );
      expect(relation, findsOneWidget);
    });
  }

  testWidgets('fallo al gestionar membresía conserva la revisión', (
    tester,
  ) async {
    final review = _savedAcademicReview();
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..loadedMultimodalReview = review
      ..membershipDecisionError = const PostgrestException(
        message: 'usuario_firebase_no_valido',
        code: '42501',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _expandPersistedSection(
      tester,
      const Key('malla-certifications-group-section'),
    );
    final certification = find.byKey(
      const ValueKey('certification-group-cert_testing'),
    );
    await tester.ensureVisible(certification);
    await tester.tap(certification);
    await tester.pumpAndSettle();
    final action = find.byKey(
      const ValueKey('grouped-membership-menu-cert_testing-base_sugerida'),
    );
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartada').last);
    await tester.pumpAndSettle();

    expect(service.membershipDecisionCalls, 1);
    expect(
      review.certifications.single.memberships.last.decision,
      MallaProposalDecision.pending,
    );
    expect(action, findsOneWidget);
    expect(find.textContaining('Vuelve a iniciar sesión'), findsOneWidget);
  });

  testWidgets('bloquea doble escritura mientras decide membresía', (
    tester,
  ) async {
    final review = _savedAcademicReview();
    final completer = Completer<void>();
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..loadedMultimodalReview = review
      ..relationshipBatchGate = completer;
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _expandPersistedSection(
      tester,
      const Key('malla-certifications-group-section'),
    );
    final certification = find.byKey(
      const ValueKey('certification-group-cert_testing'),
    );
    await tester.ensureVisible(certification);
    await tester.tap(certification);
    await tester.pumpAndSettle();
    final action = find.byKey(
      const ValueKey('grouped-membership-menu-cert_testing-base_sugerida'),
    );
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmada').last);
    await tester.pump();

    expect(service.relationshipBatchCalls, 1);
    expect(
      find.byKey(const Key('malla-persisted-group-saving')),
      findsOneWidget,
    );

    completer.complete();
    await tester.pumpAndSettle();
    expect(service.relationshipBatchCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no ofrece confirmar si la certificación no está aceptada', (
    tester,
  ) async {
    final review = _savedAcademicReview();
    review.certifications.single.decision = MallaProposalDecision.pending;
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..loadedMultimodalReview = review;
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _expandPersistedSection(
      tester,
      const Key('malla-certifications-group-section'),
    );
    final certification = find.byKey(
      const ValueKey('certification-group-cert_testing'),
    );
    await tester.ensureVisible(certification);
    await tester.tap(certification);
    await tester.pumpAndSettle();
    final action = find.byKey(
      const ValueKey('grouped-membership-menu-cert_testing-base_sugerida'),
    );
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(find.text('Confirmada'), findsNothing);
    expect(find.text('Descartada'), findsOneWidget);
  });

  for (final decision in const [
    MallaProposalDecision.accepted,
    MallaProposalDecision.rejected,
  ]) {
    testWidgets('gestiona requisito académico ${decision.name}', (
      tester,
    ) async {
      final review = _savedAcademicReview(includeAcademicRequirement: true);
      final service = _FakeMalla()
        ..multimodalPersistenceEnabled = true
        ..loadedMultimodalReview = review;
      await tester.pumpWidget(
        MaterialApp(
          home: MallaCurricularPage(
            service: service,
            documents: _FakeDocuments(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openAcademicRequirement(tester, 'Acceso a Capstone');

      expect(find.text('Aprobar los dos primeros períodos'), findsOneWidget);
      expect(
        find.text('Asignatura relacionada: Proyecto Integrador (TST2001)'),
        findsOneWidget,
      );
      expect(find.text('Nivel mínimo: 2'), findsOneWidget);
      expect(
        find.textContaining('Evidencia: Nota académica visible'),
        findsOneWidget,
      );
      final action = find.byKey(
        const ValueKey('malla-requirement-review-testing_req_proyecto'),
      );
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('Relacionado con: Proyecto Integrador'), findsOneWidget);

      await tester.tap(
        find.byKey(
          decision == MallaProposalDecision.accepted
              ? const Key('malla-requirement-confirm')
              : const Key('malla-requirement-reject'),
        ),
      );
      await tester.pumpAndSettle();

      expect(service.requirementDecisionCalls, 1);
      expect(service.requirementDecisions, [decision]);
      expect(review.academicRequirements.single.decision, decision);
      expect(
        find.descendant(
          of: find.byKey(const Key('malla-review-count')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      final requirement = find.byKey(
        const ValueKey('malla-academic-requirement-testing_req_proyecto'),
      );
      expect(requirement, findsOneWidget);
      expect(
        find.descendant(
          of: requirement,
          matching: find.text(
            decision == MallaProposalDecision.accepted
                ? 'Confirmado'
                : 'Rechazado',
          ),
        ),
        findsOneWidget,
      );
      expect(action, findsNothing);
    });
  }

  testWidgets('fallo al gestionar requisito conserva la condición', (
    tester,
  ) async {
    final review = _savedAcademicReview(includeAcademicRequirement: true);
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..loadedMultimodalReview = review
      ..requirementDecisionError = const PostgrestException(
        message: 'usuario_firebase_no_valido',
        code: '42501',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openAcademicRequirement(tester, 'Acceso a Capstone');
    final action = find.byKey(
      const ValueKey('malla-requirement-review-testing_req_proyecto'),
    );
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('malla-requirement-reject')));
    await tester.pumpAndSettle();

    expect(service.requirementDecisionCalls, 1);
    expect(
      review.academicRequirements.single.decision,
      MallaProposalDecision.pending,
    );
    expect(action, findsOneWidget);
    expect(find.textContaining('Vuelve a iniciar sesión'), findsOneWidget);
  });

  testWidgets('edita requisito persistido sin perder evidencia ni origen', (
    tester,
  ) async {
    final review = _savedAcademicReview(includeAcademicRequirement: true);
    final original = review.academicRequirements.single.requirement;
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..loadedMultimodalReview = review;
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openAcademicRequirement(tester, 'Acceso a Capstone');
    final edit = find.byKey(
      const ValueKey('malla-edit-requirement-testing_req_proyecto'),
    );
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('academic-requirement-description')),
      'Niveles I a VI aprobados',
    );
    await tester.enterText(
      find.byKey(const Key('academic-requirement-minimum-level')),
      '6',
    );
    await tester.tap(find.byKey(const Key('academic-requirement-save')));
    await tester.pumpAndSettle();

    final updated = review.academicRequirements.single;
    expect(service.requirementEditCalls, 1);
    expect(updated.requirement.id, original.id);
    expect(updated.requirement.source, original.source);
    expect(updated.requirement.evidence, original.evidence);
    expect(updated.requirement.description, 'Niveles I a VI aprobados');
    expect(updated.requirement.minimumLevel, 6);
    expect(updated.decision, MallaProposalDecision.pending);
    expect(find.text('Niveles I a VI aprobados'), findsOneWidget);
  });

  testWidgets(
    'distingue prácticas y conserva la descripción del ID elegido al recargar',
    (tester) async {
      final review = _savedAcademicReview(includeAcademicRequirement: true);
      review.academicRequirements
        ..clear()
        ..addAll([
          MallaAcademicRequirementProposal(
            requirement: const MallaAcademicRequirement(
              id: 'gemini_requirement_ac4e4ff0c503672615aa',
              type: 'practice_eligibility',
              targetCourseId: 'base_confirmada',
              targetLabel: 'Práctica Laboral',
              description: 'Requiere I a IV nivel aprobado',
              minimumLevel: 4,
              evidence: ['Rótulo conectado a PLY4614'],
              pendingReasons: ['requirement_confirmation_pending'],
            ),
          ),
          MallaAcademicRequirementProposal(
            requirement: const MallaAcademicRequirement(
              id: 'gemini_requirement_6e93db9c4251ce6fb50b',
              type: 'practice_eligibility',
              targetCourseId: 'base_sugerida',
              targetLabel: 'Práctica Profesional',
              description: 'Requiere I a IV nivel aprobado',
              minimumLevel: 6,
              evidence: ['Rótulo conectado a PPY4614'],
              pendingReasons: ['requirement_confirmation_pending'],
            ),
          ),
        ]);
      final service = _FakeMalla()
        ..multimodalPersistenceEnabled = true
        ..loadedMultimodalReview = review;

      Future<void> pumpPage() async {
        await tester.pumpWidget(
          MaterialApp(
            home: MallaCurricularPage(
              service: service,
              documents: _FakeDocuments(),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpPage();
      await _expandPersistedSection(
        tester,
        const Key('malla-requirements-group-section'),
      );
      expect(find.text('Programación Aplicada (TST1001)'), findsOneWidget);
      expect(find.text('Fundamentos de Datos (TST1002)'), findsOneWidget);

      final laboralTarget = find.text('Programación Aplicada (TST1001)');
      await tester.scrollUntilVisible(
        laboralTarget,
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, 120));
      await tester.pumpAndSettle();
      await tester.tap(laboralTarget);
      await tester.pumpAndSettle();
      final edit = find.byKey(
        const ValueKey(
          'malla-edit-requirement-gemini_requirement_ac4e4ff0c503672615aa',
        ),
      );
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('academic-requirement-description')),
        'Debe tener aprobados los niveles I a IV',
      );
      await tester.tap(find.byKey(const Key('academic-requirement-save')));
      await tester.pumpAndSettle();

      expect(
        service.lastRequirementEditId,
        'gemini_requirement_ac4e4ff0c503672615aa',
      );
      expect(
        service.lastRequirementEditDescription,
        'Debe tener aprobados los niveles I a IV',
      );
      expect(service.lastRequirementEditMinimumLevel, 4);
      expect(
        review.academicRequirements
            .singleWhere(
              (item) =>
                  item.requirement.id ==
                  'gemini_requirement_6e93db9c4251ce6fb50b',
            )
            .requirement
            .description,
        'Requiere I a IV nivel aprobado',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await pumpPage();
      await _expandPersistedSection(
        tester,
        const Key('malla-requirements-group-section'),
      );
      final reloadedLaboralTarget = find.text(
        'Programación Aplicada (TST1001)',
      );
      await tester.scrollUntilVisible(
        reloadedLaboralTarget,
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, 120));
      await tester.pumpAndSettle();
      await tester.tap(reloadedLaboralTarget);
      await tester.pumpAndSettle();
      expect(
        find.text('Debe tener aprobados los niveles I a IV'),
        findsOneWidget,
      );
      expect(
        review.academicRequirements
            .singleWhere(
              (item) =>
                  item.requirement.id ==
                  'gemini_requirement_ac4e4ff0c503672615aa',
            )
            .decision,
        MallaProposalDecision.pending,
      );
    },
  );

  testWidgets('confirma explícitamente un ramo persistido sin código', (
    tester,
  ) async {
    final review = _savedAcademicReview();
    final original = review.malla.ramos.first;
    final course = RamoMalla(
      id: original.id,
      nombre: original.nombre,
      semestre: original.semestre,
      creditos: original.creditos,
      estado: original.estado,
      requiereRevision: true,
      motivosRevision: ['code_missing'],
    );
    review.malla.ramos[0] = course;
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..loadedMultimodalReview = review;
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(ValueKey('malla-course-${course.id}'));
    await tester.scrollUntilVisible(
      card,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Corregir datos'));
    await tester.pumpAndSettle();
    final verification = find.byKey(const Key('malla-verify-missing-code'));
    expect(verification, findsOneWidget);
    await tester.ensureVisible(verification);
    await tester.tap(verification);
    await tester.tap(find.text('Guardar corrección'));
    await tester.pumpAndSettle();

    expect(service.editCalls, 1);
    expect(service.lastConfirmWithoutCode, isTrue);
    final savedCourse = review.courseById(course.id)!;
    expect(savedCourse.codigo, isNull);
    expect(savedCourse.motivosRevision, isNot(contains('code_missing')));
  });

  testWidgets('bloquea doble escritura mientras decide requisito', (
    tester,
  ) async {
    final review = _savedAcademicReview(includeAcademicRequirement: true);
    final completer = Completer<MallaImportReview>();
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..loadedMultimodalReview = review
      ..requirementDecisionCompleter = completer;
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openAcademicRequirement(tester, 'Acceso a Capstone');
    final action = find.byKey(
      const ValueKey('malla-requirement-review-testing_req_proyecto'),
    );
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('malla-requirement-confirm')));
    await tester.pump();

    expect(service.requirementDecisionCalls, 1);
    expect(tester.widget<TextButton>(action).onPressed, isNull);

    review.academicRequirements.single.decision =
        MallaProposalDecision.accepted;
    completer.complete(review);
    await tester.pumpAndSettle();
    expect(service.requirementDecisionCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tipo unknown no ofrece confirmación', (tester) async {
    final review = _savedAcademicReview(
      includeAcademicRequirement: true,
      requirementType: 'unknown',
    );
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..loadedMultimodalReview = review;
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openAcademicRequirement(tester, 'Tipo por comprobar');
    final action = find.byKey(
      const ValueKey('malla-requirement-review-testing_req_proyecto'),
    );
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('malla-requirement-confirm')), findsNothing);
    expect(find.byKey(const Key('malla-requirement-reject')), findsOneWidget);
    expect(find.textContaining('tipo siga sin identificar'), findsOneWidget);
  });

  testWidgets('requisitos académicos muestran estado vacío', (tester) async {
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..loadedMultimodalReview = _savedAcademicReview();
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _expandPersistedSection(
      tester,
      const Key('malla-requirements-group-section'),
    );
    expect(
      find.byKey(const Key('malla-academic-requirements-empty')),
      findsOneWidget,
    );
  });

  testWidgets('cancelar eliminación no realiza escrituras', (tester) async {
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..loadedMultimodalReview = _savedAcademicReview();
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openDeleteCurriculumDialog(tester);
    final scroll = tester
        .widget<ListView>(find.byType(ListView).first)
        .controller!;
    final offsetBeforeCancel = scroll.offset;

    expect(find.textContaining('Esta acción es permanente'), findsOneWidget);
    expect(
      find.textContaining('prerrequisitos, certificaciones, membresías'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('malla-delete-cancel')));
    await tester.pumpAndSettle();

    expect(service.deleteCalls, 0);
    expect(scroll.offset, offsetBeforeCancel);
    expect(find.byKey(const Key('malla-delete-saved')), findsOneWidget);
    expect(find.text('Elegir PDF o imagen'), findsNothing);
  });

  testWidgets('elimina malla y permite cargar una importación limpia', (
    tester,
  ) async {
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..multimodalTestingSampleEnabled = true
      ..loadedMultimodalReview = _savedAcademicReview(
        includeAcademicRequirement: true,
      );
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openDeleteCurriculumDialog(tester);
    await tester.tap(find.byKey(const Key('malla-delete-confirm')));
    await tester.pump();

    final overlay = find.byKey(const Key('malla-delete-progress-overlay'));
    expect(overlay, findsOneWidget);
    expect(
      tester.getSize(overlay),
      tester.view.physicalSize / tester.view.devicePixelRatio,
    );
    expect(
      find.descendant(of: overlay, matching: find.byType(AppFullScreenLoading)),
      findsOneWidget,
    );
    expect(find.text('Eliminando malla curricular…'), findsOneWidget);
    expect(
      find.text('Estamos eliminando la malla y sus datos asociados.'),
      findsOneWidget,
    );
    expect(find.text('Elegir PDF o imagen'), findsNothing);
    expect(service.deleteCalls, 1);
    expect(
      find.descendant(
        of: overlay,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: overlay,
        matching: find.byType(LinearProgressIndicator),
      ),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 799));
    expect(
      find.byKey(const Key('malla-delete-progress-overlay')),
      findsOneWidget,
    );
    expect(find.text('Elegir PDF o imagen'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    expect(service.deleteCalls, 1);
    expect(service.deletedMallaIds, ['11111111-1111-4111-8111-111111111111']);
    expect(find.text('Elegir PDF o imagen'), findsOneWidget);
    expect(
      find.byKey(const Key('malla-testing-sample-access')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('malla-certifications-section')), findsNothing);
    expect(
      find.byKey(const Key('malla-academic-requirements-section')),
      findsNothing,
    );

    final sampleAccess = find.byKey(const Key('malla-load-testing-sample'));
    await tester.ensureVisible(sampleAccess);
    await tester.tap(sampleAccess);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('malla-testing-sample-banner')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('malla-confirm-import')), findsOneWidget);
    expect(find.text('Certificado en Desarrollo'), findsNothing);
    expect(find.text('Nota académica visible'), findsNothing);
  });

  testWidgets('error de eliminación conserva la malla existente', (
    tester,
  ) async {
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..loadedMultimodalReview = _savedAcademicReview()
      ..deleteError = const PostgrestException(
        message: 'uid_firebase_no_valido',
        code: '42501',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openDeleteCurriculumDialog(tester);
    await tester.tap(find.byKey(const Key('malla-delete-confirm')));
    await tester.pumpAndSettle();

    expect(service.deleteCalls, 1);
    expect(find.byKey(const Key('malla-delete-saved')), findsOneWidget);
    expect(find.text('Elegir PDF o imagen'), findsNothing);
    expect(find.byKey(const Key('malla-progress')), findsNothing);
    expect(find.text('Eliminando malla curricular…'), findsNothing);
    expect(find.textContaining('Vuelve a iniciar sesión'), findsOneWidget);
  });

  testWidgets('bloquea doble pulsación durante la eliminación', (tester) async {
    final completer = Completer<void>();
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..loadedMultimodalReview = _savedAcademicReview()
      ..deleteCompleter = completer;
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openDeleteCurriculumDialog(tester);
    await tester.tap(find.byKey(const Key('malla-delete-confirm')));
    await tester.pump();

    expect(service.deleteCalls, 1);
    expect(
      find.byKey(const Key('malla-delete-progress-overlay')),
      findsOneWidget,
    );
    expect(find.text('Eliminando malla curricular…'), findsOneWidget);
    expect(
      find.text('Estamos eliminando la malla y sus datos asociados.'),
      findsOneWidget,
    );
    final access = find.byKey(const Key('malla-delete-saved'));
    expect(tester.widget<OutlinedButton>(access).onPressed, isNull);

    completer.complete();
    await tester.pumpAndSettle();
    expect(service.deleteCalls, 1);
    expect(find.byKey(const Key('malla-progress')), findsNothing);
    expect(find.text('Elegir PDF o imagen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'guardado usa carga inicial a pantalla completa y bloquea acciones',
    (tester) async {
      tester.view.physicalSize = const Size(390, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gate = Completer<void>();
      final service = _FakeMalla()
        ..multimodalPersistenceEnabled = true
        ..multimodalTestingSampleEnabled = true
        ..multimodalConfirmGate = gate;
      await tester.pumpWidget(
        MaterialApp(
          home: MallaCurricularPage(
            service: service,
            documents: _FakeDocuments(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('malla-load-testing-sample')));
      await tester.pumpAndSettle();
      final confirm = find.byKey(const Key('malla-confirm-import'));
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar y guardar'));
      await tester.pump();

      final overlay = find.byKey(const Key('malla-save-progress-overlay'));
      expect(overlay, findsOneWidget);
      expect(tester.getSize(overlay), const Size(390, 720));
      expect(
        find.descendant(
          of: overlay,
          matching: find.byType(AppFullScreenLoading),
        ),
        findsOneWidget,
      );
      expect(find.text('Guardando malla curricular…'), findsOneWidget);
      expect(
        find.text('Estamos guardando tus asignaturas y relaciones académicas.'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: overlay,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: overlay,
          matching: find.byType(LinearProgressIndicator),
        ),
        findsNothing,
      );
      expect(service.multimodalConfirmCalls, 1);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      gate.complete();
      await tester.pumpAndSettle();
      expect(overlay, findsNothing);
      expect(find.text('Malla guardada correctamente.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('guardado exitoso abre la malla persistida desde arriba', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..multimodalTestingSampleEnabled = true;
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('malla-load-testing-sample')));
    await tester.pumpAndSettle();

    final scroll = tester
        .widget<ListView>(find.byType(ListView).first)
        .controller!;
    final confirm = find.byKey(const Key('malla-confirm-import'));
    await tester.scrollUntilVisible(
      confirm,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar y guardar'));
    await tester.pumpAndSettle();

    expect(service.multimodalConfirmCalls, 1);
    expect(scroll.offset, scroll.position.minScrollExtent);
    expect(find.text('Malla curricular'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resumen pluraliza asignaturas, períodos y certificaciones', (
    tester,
  ) async {
    final singularService = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..loadedMultimodalReview = _savedTestingReview();
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: singularService,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final singularSummary = find.byKey(const Key('malla-count-summary'));
    expect(
      find.descendant(of: singularSummary, matching: find.text('Asignatura')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: singularSummary, matching: find.text('Semestre')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: singularSummary, matching: find.text('Asignaturas')),
      findsNothing,
    );
    expect(
      find.descendant(of: singularSummary, matching: find.text('Semestres')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    final pluralService = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..loadedMultimodalReview = _savedAcademicReview();
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: pluralService,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pluralSummary = find.byKey(const Key('malla-count-summary'));
    expect(
      find.descendant(of: pluralSummary, matching: find.text('Asignaturas')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: pluralSummary, matching: find.text('Semestres')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: pluralSummary, matching: find.text('Certificación')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: pluralSummary,
        matching: find.text('Certificaciones'),
      ),
      findsNothing,
    );
  });

  testWidgets('malla guardada expone cuatro secciones expandibles', (
    tester,
  ) async {
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..loadedMultimodalReview = _savedAcademicReview(
        includeAcademicRequirement: true,
      );
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const sectionKeys = [
      Key('malla-courses-group-section'),
      Key('malla-prerequisites-section'),
      Key('malla-certifications-group-section'),
      Key('malla-requirements-group-section'),
    ];
    for (var index = 0; index < sectionKeys.length; index++) {
      final key = sectionKeys[index];
      expect(find.byKey(key), findsOneWidget);
      final tile = find.descendant(
        of: find.byKey(key),
        matching: find.byType(ExpansionTile),
      );
      expect(tile, findsOneWidget);
      expect(tester.widget<ExpansionTile>(tile).initiallyExpanded, index == 0);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('cambio de cuenta no conserva la malla anterior', (tester) async {
    final delayedA = Completer<MallaImportReview?>();
    final reviewA = _savedAcademicReview();
    reviewA.malla.ramos.first.nombre = 'Asignatura exclusiva A';
    final reviewB = _savedAcademicReview();
    reviewB.malla.ramos.first.nombre = 'Asignatura exclusiva B';
    final serviceA = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..multimodalLoadResult = delayedA.future;
    final serviceB = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..loadedMultimodalReview = reviewB;

    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          key: const ValueKey('account-a'),
          service: serviceA,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          key: const ValueKey('account-b'),
          service: serviceB,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Asignatura exclusiva B'), findsOneWidget);
    expect(find.text('Asignatura exclusiva A'), findsNothing);

    delayedA.complete(reviewA);
    await tester.pumpAndSettle();
    expect(find.text('Asignatura exclusiva B'), findsOneWidget);
    expect(find.text('Asignatura exclusiva A'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final errorCase in [
    (
      const PostgrestException(
        message: 'usuario_firebase_no_valido',
        code: '42501',
      ),
      'No pudimos verificar tu acceso',
    ),
    (
      const PostgrestException(message: 'malla_ya_confirmada', code: '23505'),
      'Ya tienes una malla guardada',
    ),
  ]) {
    testWidgets('malla de ejemplo presenta ${errorCase.$2}', (tester) async {
      final service = _FakeMalla()
        ..multimodalPersistenceEnabled = true
        ..multimodalTestingSampleEnabled = true
        ..confirmError = errorCase.$1;

      await tester.pumpWidget(
        MaterialApp(
          home: MallaCurricularPage(
            service: service,
            documents: _FakeDocuments(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('malla-load-testing-sample')));
      await tester.pumpAndSettle();
      final confirmFinder = find.byKey(const Key('malla-confirm-import'));
      await tester.ensureVisible(confirmFinder);
      await tester.pumpAndSettle();
      await tester.tap(confirmFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar y guardar'));
      await tester.pumpAndSettle();

      expect(find.text(errorCase.$2), findsOneWidget);
      expect(service.multimodalConfirmCalls, 1);
      expect(service.confirmCalls, 0);
    });
  }

  testWidgets('fallo de integridad no informa una malla vacía', (tester) async {
    final service = _FakeMalla()
      ..multimodalPersistenceEnabled = true
      ..multimodalTestingSampleEnabled = true
      ..confirmError = MallaMultimodalIntegrityException(
        fileNameMismatch: false,
        differencePaths: const ['courses[0].review_state'],
      );

    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('malla-load-testing-sample')));
    await tester.pumpAndSettle();
    final confirmFinder = find.byKey(const Key('malla-confirm-import'));
    await tester.ensureVisible(confirmFinder);
    await tester.pumpAndSettle();
    await tester.tap(confirmFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar y guardar'));
    await tester.pumpAndSettle();

    expect(
      find.text('La malla se guardó, pero falta verificarla'),
      findsOneWidget,
    );
    expect(find.text('No encontramos asignaturas'), findsNothing);
    expect(service.multimodalConfirmCalls, 1);
  });

  testWidgets('edición repetida conserva borrador y libera el diálogo', (
    tester,
  ) async {
    const original = 'Diseño y Gestión de Requisitos';
    final service = _FakeMalla()
      ..ocrResult = MallaCurricular(
        id: '',
        ramos: [
          RamoMalla(
            id: 'ocr_1',
            nombre: original,
            codigo: 'TI111',
            creditos: 4,
            semestre: 1,
            requiereRevision: true,
          ),
        ],
      );
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('malla-file-picker')));
    await tester.tap(find.byKey(const Key('malla-file-picker')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('malla-process-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('malla-process-button')));
    await tester.pumpAndSettle();

    Future<void> openEdit() async {
      await tester.ensureVisible(
        find.text(service.ocrResult!.ramos.single.nombre),
      );
      await tester.tap(find.byTooltip('Opciones de asignatura'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar').last);
      await tester.pumpAndSettle();
      expect(find.text('Corregir asignatura'), findsOneWidget);
    }

    await openEdit();
    await tester.enterText(find.byType(TextField).at(0), 'Nombre temporal');
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tester.tap(find.text('Guardar corrección'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Nombre temporal'), findsOneWidget);

    await openEdit();
    await tester.enterText(find.byType(TextField).at(0), original);
    await tester.tap(find.text('Guardar corrección'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(original), findsOneWidget);

    await openEdit();
    await tester.enterText(find.byType(TextField).at(0), 'No guardar');
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(original), findsOneWidget);
    expect(find.text('No guardar'), findsNothing);
    expect(service.ocrResult!.ramos.single.codigo, 'TI111');
    expect(service.ocrResult!.ramos.single.creditos, 4);

    await openEdit();
    await tester.enterText(find.byType(TextField).at(1), 'TI222');
    await tester.enterText(find.byType(TextField).at(2), '6');
    await tester.enterText(find.byType(TextField).at(3), '2');
    await tester.tap(find.text('Guardar corrección'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(service.ocrResult!.ramos.single.creditos, 6);
    expect(service.ocrResult!.ramos.single.codigo, 'TI222');
    expect(service.ocrResult!.ramos.single.semestre, 2);
    expect(find.text(original), findsOneWidget);
    expect(service.confirmCalls, 0);
  });

  testWidgets(
    'formulario mantiene estilo y cierre con teclado en ambos temas',
    (tester) async {
      tester.view.physicalSize = const Size(390, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final ramo = RamoMalla(
          id: 'a',
          nombre: 'Ramo original',
          semestre: 1,
          codigo: 'ABC1',
          creditos: 5,
          requiereRevision: true,
          motivosRevision: ['low_ocr_confidence'],
        );
        final service = _FakeMalla()
          ..loadResult = Future.value(
            MallaCurricular(id: 'saved', ramos: [ramo]),
          );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: MallaCurricularPage(
              service: service,
              documents: _FakeDocuments(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Ramo original'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ramo original'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Corregir datos'));
        await tester.pumpAndSettle();
        final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
        expect(
          dialog.backgroundColor,
          brightness == Brightness.dark
              ? const Color(0xFF18181D)
              : Colors.white,
        );
        final field = tester.widget<TextField>(find.byType(TextField).first);
        expect(field.decoration!.filled, isTrue);
        expect(field.decoration!.focusedBorder, isA<OutlineInputBorder>());
        final checkbox = tester.widget<CheckboxListTile>(
          find.byType(CheckboxListTile).first,
        );
        expect(
          checkbox.tileColor,
          brightness == Brightness.dark
              ? const Color(0xFF202631)
              : const Color(0xFFFAFBFC),
        );
        expect(find.byType(OutlinedButton), findsWidgets);
        expect(find.byType(ElevatedButton), findsWidgets);
        await tester.enterText(find.byType(TextField).first, 'No guardar');
        tester.view.viewInsets = const FakeViewPadding(bottom: 290);
        await tester.pumpAndSettle();
        final input = tester.widget<EditableText>(
          find.byType(EditableText).first,
        );
        expect(input.focusNode.hasFocus, isTrue);
        await tester.tap(find.text('Corregir asignatura'));
        await tester.pumpAndSettle();
        expect(input.focusNode.hasFocus, isFalse);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('No guardar'), findsOneWidget);
        await tester.tap(find.byType(TextField).first);
        await tester.pumpAndSettle();
        expect(input.focusNode.hasFocus, isTrue);
        await tester.ensureVisible(find.byType(CheckboxListTile).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(CheckboxListTile).first);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          tester
              .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
              .value,
          isTrue,
        );
        await tester.ensureVisible(find.text('Cancelar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(ramo.nombre, 'Ramo original');
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets('fallo de configuración al confirmar bloquea otro guardado', (
    tester,
  ) async {
    final service = _FakeMalla()
      ..ocrResult = MallaCurricular(
        id: '',
        ramos: [RamoMalla(id: 'ocr_1', nombre: 'Álgebra', semestre: 1)],
      )
      ..confirmError = const PostgrestException(
        message: '{"code":"PGRST205","message":"Could not find the table \'public.mallas_curriculares\' in the schema cache"}',
        code: '404',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('malla-file-picker')));
    await tester.tap(find.byKey(const Key('malla-file-picker')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('malla-process-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('malla-process-button')));
    await tester.pumpAndSettle();
    final confirm = find.text('Revisar y confirmar importación');
    await tester.ensureVisible(confirm);
    await tester.drag(find.byType(ListView).first, const Offset(0, -140));
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar y guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Importación pendiente de habilitación'), findsOneWidget);
    expect(service.confirmCalls, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(
              FilledButton,
              'Revisar y confirmar importación',
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('malla guardada muestra estado persistido con texto', (
    tester,
  ) async {
    final service = _FakeMalla()
      ..loadResult = Future.value(
        MallaCurricular(
          id: 'saved',
          ramos: [
            RamoMalla(
              id: 'ocr_1',
              nombre: 'Cálculo',
              semestre: 1,
              estado: 'aprobada',
            ),
          ],
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cálculo'), findsOneWidget);
    expect(find.text('Aprobada'), findsOneWidget);
    expect(find.byKey(const Key('malla-file-picker')), findsNothing);
  });

  testWidgets('filtro de revisión sigue semestre y edición guardada', (
    tester,
  ) async {
    final saved = MallaCurricular(
      id: 'saved',
      ramos: [
        RamoMalla(
          id: 'a',
          nombre: 'Álgebra',
          semestre: 1,
          codigo: 'ALG1',
          creditos: null,
          requiereRevision: true,
          motivosRevision: const ['credits_missing'],
          estado: 'aprobada',
        ),
        RamoMalla(id: 'b', nombre: 'Física', semestre: 2),
        RamoMalla(
          id: 'c',
          nombre: 'Historia',
          semestre: 3,
          requiereRevision: true,
          motivosRevision: const ['low_ocr_confidence'],
        ),
      ],
    );
    final service = _FakeMalla()..loadResult = Future.value(saved);
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('2 elementos necesitan atención'),
      findsOneWidget,
    );
    await tester.tap(find.text('Solo por revisar'));
    await tester.pumpAndSettle();
    expect(find.text('Álgebra'), findsOneWidget);
    await _pickSemester(tester, 2);
    await tester.pumpAndSettle();
    expect(find.text('Física'), findsNothing);
    expect(find.text('Álgebra'), findsNothing);
    expect(
      find.textContaining('No hay ramos pendientes de revisión'),
      findsOneWidget,
    );
    await _pickSemester(tester, 3);
    await tester.pumpAndSettle();
    expect(find.text('Historia'), findsOneWidget);
    await tester.tap(find.text('Solo por revisar'));
    await tester.pumpAndSettle();
    expect(find.text('Historia'), findsOneWidget);
    await _pickSemester(tester, 1);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Álgebra'));
    await tester.drag(find.byType(ListView).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Álgebra'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Corregir datos'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(2), '5');
    await tester.tap(find.text('Guardar corrección'));
    await tester.pumpAndSettle();
    expect(service.editCalls, 1);
    expect(saved.ramos.first.estado, 'aprobada');
    expect(saved.ramos.first.creditos, 5);
    expect(find.textContaining('1 elemento necesita atención'), findsOneWidget);
    await tester.tap(find.text('Solo por revisar'));
    await tester.pumpAndSettle();
    expect(find.text('Álgebra'), findsNothing);
  });

  testWidgets('filtro y semestres funcionan en móvil claro y oscuro', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final saved = MallaCurricular(
        id: 'saved',
        ramos: [
          RamoMalla(
            id: 'a',
            nombre: 'Ramo por revisar',
            semestre: 1,
            motivosRevision: ['low_ocr_confidence'],
            requiereRevision: true,
          ),
          RamoMalla(id: 'b', nombre: 'Ramo sin revisión', semestre: 2),
        ],
      );
      final service = _FakeMalla()..loadResult = Future.value(saved);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: MallaCurricularPage(
            service: service,
            documents: _FakeDocuments(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final filter = find.byKey(const Key('malla-review-filter'));
      expect(tester.widget<FilterChip>(filter).showCheckmark, isFalse);
      await tester.ensureVisible(filter);
      await tester.pumpAndSettle();
      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(filter).selected, isTrue);
      expect(find.text('Ramo por revisar'), findsOneWidget);
      await _pickSemester(tester, 2);
      await tester.pumpAndSettle();
      expect(find.text('Semestre 2'), findsOneWidget);
      expect(
        find.text('No hay ramos pendientes de revisión en este semestre.'),
        findsOneWidget,
      );
      await tester.ensureVisible(filter);
      await tester.pumpAndSettle();
      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(find.text('Ramo sin revisión'), findsOneWidget);
      await _pickSemester(tester, 1);
      await tester.pumpAndSettle();
      expect(find.text('Ramo por revisar'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('filtro sin pendientes globales muestra estado vacío', (
    tester,
  ) async {
    final saved = MallaCurricular(
      id: 'saved',
      ramos: [RamoMalla(id: 'a', nombre: 'Ramo revisado', semestre: 1)],
    );
    final service = _FakeMalla()..loadResult = Future.value(saved);
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final filter = find.byKey(const Key('malla-review-filter'));
    await tester.ensureVisible(filter);
    await tester.pumpAndSettle();
    await tester.tap(filter);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(filter).selected, isTrue);
    expect(
      find.text('No hay ramos pendientes de revisión en este semestre.'),
      findsOneWidget,
    );
    await tester.tap(filter);
    await tester.pumpAndSettle();
    expect(find.text('Ramo revisado'), findsOneWidget);
  });

  testWidgets('estado académico usa opciones del perfil y conserva guardado', (
    tester,
  ) async {
    final ramo = RamoMalla(id: 'a', nombre: 'Ramo de prueba', semestre: 1);
    final service = _FakeMalla()
      ..loadResult = Future.value(MallaCurricular(id: 'saved', ramos: [ramo]));
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ramo de prueba'));
    await tester.tap(find.text('Ramo de prueba'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('malla-state-selector')));
    await tester.pumpAndSettle();
    expect(find.text('Estado académico'), findsWidgets);
    final darkBarriers = tester
        .widgetList<AnimatedModalBarrier>(find.byType(AnimatedModalBarrier))
        .where((barrier) => barrier.dismissible)
        .toList();
    expect(
      darkBarriers.where((barrier) => (barrier.color.value?.a ?? 0) > 0),
      hasLength(1),
    );
    final transparentBarriers = tester
        .widgetList<ModalBarrier>(find.byType(ModalBarrier))
        .where((barrier) => barrier.dismissible && barrier.color == null);
    expect(transparentBarriers, hasLength(1));
    await tester.tap(find.text('En curso').last);
    await tester.pumpAndSettle();
    expect(ramo.estado, 'en_curso');
    expect(tester.takeException(), isNull);
  });

  testWidgets('código repetido legítimo se confirma por ramo', (tester) async {
    final saved = MallaCurricular(
      id: 'saved',
      ramos: [
        RamoMalla(
          id: 'a',
          nombre: 'Electivo I',
          semestre: 1,
          codigo: 'ELE1',
          creditos: 5,
        ),
        RamoMalla(
          id: 'b',
          nombre: 'Electivo II',
          semestre: 1,
          codigo: 'ELE1',
          creditos: 5,
        ),
      ],
    );
    final service = _FakeMalla()..loadResult = Future.value(saved);
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('2 elementos necesitan atención'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Electivo I'));
    await tester.drag(find.byType(ListView).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Electivo I'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Electivo II'), findsWidgets);
    await tester.tap(find.text('Corregir datos'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.text('Confirmo que este código compartido es correcto'),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Confirmo que este código compartido es correcto'),
    );
    await tester.tap(find.text('Guardar corrección'));
    await tester.pumpAndSettle();
    expect(saved.ramos.first.codigoDuplicadoVerificado, isTrue);
    expect(saved.ramos.last.codigoDuplicadoVerificado, isFalse);
    expect(saved.ramos.first.codigo, 'ELE1');
    expect(find.textContaining('1 elemento necesita atención'), findsOneWidget);
  });

  testWidgets('cambiar de grupo duplicado deja la verificación pendiente', (
    tester,
  ) async {
    final saved = MallaCurricular(
      id: 'saved',
      ramos: [
        RamoMalla(
          id: 'a',
          nombre: 'Electivo A',
          semestre: 1,
          codigo: 'OLD',
          codigoDuplicadoVerificado: true,
        ),
        RamoMalla(
          id: 'b',
          nombre: 'Electivo B',
          semestre: 1,
          codigo: 'OLD',
          codigoDuplicadoVerificado: true,
        ),
        RamoMalla(
          id: 'c',
          nombre: 'Electivo C',
          semestre: 1,
          codigo: 'NEW',
          codigoDuplicadoVerificado: true,
        ),
      ],
    );
    final service = _FakeMalla()..loadResult = Future.value(saved);
    await tester.pumpWidget(
      MaterialApp(
        home: MallaCurricularPage(
          service: service,
          documents: _FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Electivo A'));
    await tester.tap(find.text('Electivo A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Corregir datos'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'NEW');
    await tester.pumpAndSettle();
    expect(
      find.text('Guarda el nuevo código para verificarlo después.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Guardar corrección'));
    await tester.pumpAndSettle();
    expect(service.editCalls, 1);
    expect(
      saved.ramos.map((ramo) => ramo.codigoDuplicadoVerificado),
      everyElement(isFalse),
    );
    expect(MallaReviewRules.pendingCount(saved), 2);
  });

  testWidgets('pantalla simplificada cabe en móvil claro y oscuro', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: MallaCurricularPage(
            service: _FakeMalla(),
            documents: _FakeDocuments(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('EDUCFLOW AI'), findsOneWidget);
      expect(find.text('Elegir PDF o imagen'), findsOneWidget);
      expect(find.text('Dale forma a tu malla'), findsNothing);
      expect(find.text('1 · Archivo'), findsNothing);
    }
  });
}
