import 'package:flutter/foundation.dart';

import '../core/config/app_environment_config.dart';
import '../models/malla_curricular.dart';
import '../models/malla_import_review.dart';
import '../models/malla_multimodal_review.dart';
import 'malla_multimodal_persistence_service.dart';

class MallaMultimodalTestingConfig {
  const MallaMultimodalTestingConfig({required this.requested});

  static const environment = MallaMultimodalTestingConfig(
    requested: bool.fromEnvironment('EDUFLOW_MULTIMODAL_SAMPLE_ENABLED'),
  );

  final bool requested;

  bool allows({
    required String firebaseProjectId,
    required String supabaseProjectRef,
    required bool persistenceEnabled,
    bool? debugMode,
    bool? android,
    EducFlowEnvironment? appEnvironment,
  }) {
    final selectedEnvironment =
        appEnvironment ?? AppEnvironmentConfig.environment;
    final isAndroid =
        android ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
    return requested &&
        (debugMode ?? kDebugMode) &&
        isAndroid &&
        selectedEnvironment == EducFlowEnvironment.testing &&
        firebaseProjectId == AppEnvironmentConfig.testingFirebaseProjectId &&
        supabaseProjectRef == AppEnvironmentConfig.testingSupabaseProjectRef &&
        persistenceEnabled;
  }
}

class MallaMultimodalTestingFixture {
  const MallaMultimodalTestingFixture._();

  static const fileName = 'malla-ejemplo-testing.json';

  static bool isExample(MallaCurricular malla) =>
      malla.archivoNombre == fileName;

  static MallaImportReview create() {
    final courses = [
      RamoMalla(
        id: 'testing_programacion',
        nombre: 'Programación Aplicada',
        semestre: 1,
        codigo: 'TST1001',
        creditos: 6,
      ),
      RamoMalla(
        id: 'testing_datos',
        nombre: 'Fundamentos de Datos',
        semestre: 2,
        codigo: 'TST2001',
        creditos: 5,
      ),
      RamoMalla(
        id: 'testing_proyecto',
        nombre: 'Proyecto Integrador',
        semestre: 3,
        codigo: 'TST3001',
        creditos: 8,
      ),
      RamoMalla(
        id: 'testing_etica',
        nombre: 'Ética y Ciudadanía',
        semestre: 2,
        codigo: 'TST2002',
        creditos: 4,
        requiereRevision: true,
        motivosRevision: ['manual_verification'],
      ),
    ];

    final review = MallaImportReview(
      malla: MallaCurricular(id: '', archivoNombre: fileName, ramos: courses),
      periodType: 'semester',
      periodCount: 3,
      periodEvidence: const ['Tres columnas ficticias para prueba técnica'],
      geminiCourseIds: const {'testing_etica'},
      mergedCourseIds: const {'testing_datos'},
      courseChanges: [
        _courseChange(
          courses[0],
          category: 'specialty',
          categoryLabel: 'Especialidad',
          evidence: const ['Bloque ficticio validado para testing'],
        ),
        _courseChange(
          courses[1],
          category: 'specialty',
          categoryLabel: 'Especialidad',
          evidence: const ['Bloque ficticio validado para testing'],
        ),
        _courseChange(
          courses[2],
          category: 'capstone',
          categoryLabel: 'Proyecto final',
          evidence: const ['Bloque ficticio validado para testing'],
        ),
        _courseChange(
          courses[3],
          category: 'general_education',
          categoryLabel: 'Formación general',
          evidence: const ['Etiqueta ficticia pendiente de revisión'],
          attentionReasons: const ['manual_verification'],
        ),
      ],
      prerequisites: [
        MallaPrerequisiteProposal(
          courseId: 'testing_datos',
          requiresCourseId: 'testing_programacion',
          evidence: const ['Relación ficticia inequívoca'],
          pendingReasons: const [],
        )..decision = MallaProposalDecision.accepted,
        MallaPrerequisiteProposal(
          courseId: 'testing_proyecto',
          requiresCourseId: 'testing_datos',
          evidence: const ['Relación ficticia sugerida'],
          pendingReasons: const [],
        ),
        MallaPrerequisiteProposal(
          courseId: 'testing_etica',
          requiresCourseId: 'testing_programacion',
          evidence: const ['Relación ficticia descartada'],
          pendingReasons: const ['relation_rejected_during_review'],
        )..decision = MallaProposalDecision.rejected,
      ],
      certifications: [
        MallaCertificationProposal(
          id: 'testing_cert_datos',
          name: 'Certificación Ficticia en Datos',
          evidence: const ['Contenedor ficticio para testing'],
          memberships: [
            MallaCertificationMembershipProposal(
              courseId: 'testing_datos',
              basis: 'visual_container',
              evidence: const ['Membresía ficticia aceptada'],
            )..decision = MallaProposalDecision.accepted,
            MallaCertificationMembershipProposal(
              courseId: 'testing_proyecto',
              basis: 'visual_container_uncertain',
              evidence: const ['Membresía ficticia sugerida'],
            ),
            MallaCertificationMembershipProposal(
              courseId: 'testing_etica',
              basis: 'outside_container',
              evidence: const ['Asignatura ficticia fuera del contenedor'],
            )..decision = MallaProposalDecision.rejected,
          ],
        )..decision = MallaProposalDecision.accepted,
      ],
      academicRequirements: [
        MallaAcademicRequirementProposal(
          requirement: const MallaAcademicRequirement(
            id: 'testing_req_proyecto',
            type: 'capstone_eligibility',
            targetCourseId: 'testing_proyecto',
            targetLabel: 'Proyecto Integrador',
            description: 'Aprobar los dos primeros períodos',
            minimumLevel: 2,
            evidence: ['Nota académica ficticia para testing'],
            pendingReasons: ['requirement_confirmation_pending'],
          ),
        ),
      ],
      globalPending: const [],
      deduplicatedAdditionalCourses: const [],
    );

    // La misma validación que precede al RPC rechaza el fixture si deja de ser
    // compatible con el contrato de persistencia.
    const MallaMultimodalPersistenceCodec().encode(review);
    return review;
  }

  static MallaCourseChangeProposal _courseChange(
    RamoMalla course, {
    required String category,
    required String categoryLabel,
    required List<String> evidence,
    List<String> attentionReasons = const [],
  }) => MallaCourseChangeProposal(
    review: MallaCourseReview(
      courseId: course.id,
      proposedName: course.nombre,
      proposedCode: course.codigo,
      proposedCredits: course.creditos,
      proposedPeriod: course.semestre,
      category: category,
      categoryLabel: categoryLabel,
      prerequisiteStatus: 'unknown',
      evidence: evidence,
      pendingReasons: attentionReasons,
    ),
    originalName: course.nombre,
    originalCode: course.codigo,
    originalCredits: course.creditos,
    originalPeriod: course.semestre,
    automaticallyAppliedFields: const {},
    attentionReasons: attentionReasons,
  );
}
