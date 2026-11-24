import 'dart:async';

import 'package:eduflow_ai/core/auth/session_controller.dart';
import 'package:eduflow_ai/core/config/app_environment_config.dart';
import 'package:eduflow_ai/core/config/developer_tools_config.dart';
import 'package:eduflow_ai/models/malla_curricular.dart';
import 'package:eduflow_ai/models/malla_import_review.dart';
import 'package:eduflow_ai/models/malla_multimodal_review.dart';
import 'package:eduflow_ai/pages/dashboard/dashboard_page.dart';
import 'package:eduflow_ai/pages/ocr/malla_curricular_page.dart';
import 'package:eduflow_ai/services/beta_notice_service.dart';
import 'package:eduflow_ai/services/malla_curricular_service.dart';
import 'package:eduflow_ai/services/malla_multimodal_persistence_service.dart';
import 'package:eduflow_ai/services/malla_multimodal_testing_fixture.dart';
import 'package:eduflow_ai/services/ocr_document_service.dart';
import 'package:eduflow_ai/services/ocr_file_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/firebase_auth_test_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FirebaseAuthTestHost().initialize(initialUid: 'testing-dashboard');
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://testing.invalid.supabase.co',
      publishableKey: 'sb_publishable_testing_only',
    );
  });

  testWidgets(
    'Inicio abre la malla Testing sin consultar asignaturas ni ejecutar IA',
    (tester) async {
      DeveloperToolsConfig.debugOverride = true;
      addTearDown(() => DeveloperToolsConfig.debugOverride = null);
      final session = _readySession();
      final malla = _FakeMallaGateway(testingEnabled: true);
      addTearDown(() async {
        session.controller.dispose();
        await session.auth.close();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardPage(
            sessionController: session.controller,
            betaNoticeService: const _NoBetaNotice(),
            initialLoadOverride: () async {},
            mallaCurricularService: malla,
          ),
        ),
      );
      await tester.pump();

      final access = find.byKey(const Key('home-testing-malla-access'));
      expect(access, findsOneWidget);
      await tester.tap(access);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(find.byType(MallaCurricularPage), findsOneWidget);
      expect(
        find.byKey(const Key('malla-testing-sample-access')),
        findsOneWidget,
      );
      expect(malla.multimodalLoads, 1);
      expect(malla.processCalls, 0);
      expect(malla.confirmCalls, 0);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Inicio oculta el acceso cuando el guard compartido lo rechaza', (
    tester,
  ) async {
    final session = _readySession();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardPage(
          sessionController: session.controller,
          betaNoticeService: const _NoBetaNotice(),
          initialLoadOverride: () async {},
          mallaCurricularService: _FakeMallaGateway(testingEnabled: false),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('home-testing-malla-access')), findsNothing);
    expect(find.text('Probar malla curricular (Testing)'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('guard compartido bloquea release y proyectos incorrectos', () {
    const policy = MallaMultimodalTestingConfig(requested: true);
    bool allows({
      bool debug = true,
      EducFlowEnvironment environment = EducFlowEnvironment.testing,
      String firebase = AppEnvironmentConfig.testingFirebaseProjectId,
      String supabase = AppEnvironmentConfig.testingSupabaseProjectRef,
      bool persistence = true,
    }) => policy.allows(
      firebaseProjectId: firebase,
      supabaseProjectRef: supabase,
      persistenceEnabled: persistence,
      debugMode: debug,
      android: true,
      appEnvironment: environment,
    );

    expect(allows(), isTrue);
    expect(allows(debug: false), isFalse);
    expect(allows(environment: EducFlowEnvironment.production), isFalse);
    expect(
      allows(firebase: AppEnvironmentConfig.productionFirebaseProjectId),
      isFalse,
    );
    expect(
      allows(supabase: AppEnvironmentConfig.productionSupabaseProjectRef),
      isFalse,
    );
    expect(allows(persistence: false), isFalse);
  });
}

({SessionController controller, StreamController<SessionUserIdentity?> auth})
_readySession() {
  const identity = SessionUserIdentity(
    uid: 'testing-dashboard',
    email: 'testing@example.test',
    displayName: 'Testing',
  );
  final auth = StreamController<SessionUserIdentity?>();
  return (
    controller: SessionController(
      currentUserProvider: () => identity,
      authChanges: auth.stream,
      sessionPreparation: (_, _, _) async {},
      signOutAction: () async {},
    ),
    auth: auth,
  );
}

class _NoBetaNotice implements BetaNoticeCoordinator {
  const _NoBetaNotice();

  @override
  Future<BetaNoticeReservation?> reserveIfShouldShow(
    String uid,
    BetaNoticeKind kind,
  ) async => null;

  @override
  Future<bool> markShown(
    BetaNoticeReservation reservation, {
    required bool Function() isValid,
  }) async => false;

  @override
  void release(BetaNoticeReservation reservation) {}
}

class _FakeMallaGateway implements MallaCurricularGateway {
  _FakeMallaGateway({required this.testingEnabled});

  final bool testingEnabled;
  int multimodalLoads = 0;
  int processCalls = 0;
  int confirmCalls = 0;

  @override
  bool get multimodalPersistenceEnabled => testingEnabled;

  @override
  bool get multimodalTestingSampleEnabled => testingEnabled;

  @override
  Future<MallaCurricular?> cargar() async => null;

  @override
  Future<MallaImportReview?> cargarRevisionMultimodal() async {
    multimodalLoads++;
    return null;
  }

  @override
  Future<bool> existe() async => false;

  @override
  Future<MallaCurricular> procesar(
    OcrDocumentResult upload, {
    required String fileName,
    required OcrPickedFile originalFile,
  }) async {
    processCalls++;
    throw StateError('El acceso Testing no debe ejecutar OCR.');
  }

  @override
  Future<MallaCurricular> confirmar(MallaCurricular preview) async {
    confirmCalls++;
    return preview;
  }

  @override
  Future<MallaImportReview> confirmarMultimodal(
    MallaImportReview review,
  ) async {
    confirmCalls++;
    return review;
  }

  @override
  Future<MallaImportReview> confirmarRelacionesAgrupadas({
    required MallaImportReview review,
    List<MallaPrerequisiteProposal> prerequisites = const [],
    List<MallaCertificationBatchSelection> certifications = const [],
  }) => throw StateError('El acceso Testing no debe gestionar relaciones.');

  @override
  Future<MallaImportReview> decidirPrerrequisito({
    required String mallaId,
    required String courseId,
    required String requiresCourseId,
    required MallaProposalDecision decision,
  }) => throw StateError('El acceso Testing no debe gestionar relaciones.');

  @override
  Future<MallaImportReview> decidirMembresiaCertificacion({
    required String mallaId,
    required String certificationId,
    required String courseId,
    required MallaProposalDecision decision,
  }) => throw StateError('El acceso Testing no debe gestionar relaciones.');

  @override
  Future<MallaImportReview> decidirRequisitoAcademico({
    required String mallaId,
    required String requirementId,
    required String type,
    required MallaProposalDecision decision,
  }) => throw StateError('El acceso Testing no debe gestionar requisitos.');

  @override
  Future<MallaImportReview> confirmarRamoSinCodigo({
    required String mallaId,
    required String ramoId,
  }) => throw StateError('El acceso Testing no debe confirmar asignaturas.');

  @override
  Future<MallaImportReview> editarRequisitoAcademico({
    required String mallaId,
    required MallaAcademicRequirement requirement,
    required String description,
    required int? minimumLevel,
  }) => throw StateError('El acceso Testing no debe editar requisitos.');

  @override
  Future<void> eliminarMallaConfirmada(String mallaId) =>
      throw StateError('El acceso Testing no debe eliminar mallas.');

  @override
  Future<void> cambiarEstado(RamoMalla ramo, String estado) async {}

  @override
  Future<MallaCurricular> editarRamo(
    MallaCurricular malla,
    RamoMalla ramo, {
    required bool confirmarRevision,
    required bool codigoDuplicadoVerificado,
    required bool confirmarSinCodigo,
  }) async => malla;
}
