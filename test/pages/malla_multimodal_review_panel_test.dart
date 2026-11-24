import 'package:eduflow_ai/models/malla_curricular.dart';
import 'package:eduflow_ai/models/malla_import_review.dart';
import 'package:eduflow_ai/pages/ocr/widgets/malla_multimodal_review_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'muestra membresías inciertas dentro del grupo para revisión manual',
    (tester) async {
      final membership = MallaCertificationMembershipProposal(
        courseId: 'course-1',
        basis: 'container',
        evidence: const [
          'course-1 está dentro del contenedor Certificado en Datos',
        ],
        pendingReasons: const ['membership_evidence_uncertain'],
      );
      final review = MallaImportReview(
        malla: MallaCurricular(
          id: '',
          ramos: [
            RamoMalla(
              id: 'course-1',
              nombre: 'Inteligencia de Negocios',
              semestre: 1,
            ),
          ],
        ),
        periodType: 'semester',
        periodCount: 1,
        periodEvidence: const [],
        geminiCourseIds: const {},
        courseChanges: const [],
        prerequisites: [
          MallaPrerequisiteProposal(
            courseId: 'course-1',
            requiresCourseId: 'course-0',
            evidence: const ['Recorrido parcial visible'],
            pendingReasons: const ['relation_path_ambiguous'],
          ),
        ],
        certifications: [
          MallaCertificationProposal(
            id: 'cert-datos',
            name: 'Certificado en Datos',
            evidence: const ['Contenedor titulado visible'],
            memberships: [membership],
          ),
        ],
        academicRequirements: const [],
        globalPending: const [],
        deduplicatedAdditionalCourses: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MallaMultimodalReviewPanel(
                review: review,
                spanish: true,
                onCourseDecision: (_, _) {},
                onPrerequisiteDecision: (_, _) {},
                onConfirmPrerequisiteGroup: (_) {},
                onMembershipDecision: (_, _) {},
                onCertificationDecision: (_, _) {},
                onConfirmCertificationGroup: (_, _) {},
                onRequirementDecision: (_, _) {},
                onEditRequirement: (_) {},
                onResolveGlobal: (_) {},
                onEditCourse: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('malla-attention-problem-prerequisite-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('malla-attention-problem-membership-cert-datos-0'),
        ),
        findsOneWidget,
      );

      final relationships = find.byKey(
        const Key('malla-relationship-proposals'),
      );
      await tester.ensureVisible(relationships);
      await tester.tap(relationships);
      await tester.pumpAndSettle();

      final certification = find.byKey(
        const ValueKey('certification-group-cert-datos'),
      );
      await tester.ensureVisible(certification);
      await tester.tap(certification);
      await tester.pumpAndSettle();

      expect(find.text('1 asignaturas · 0 seleccionadas'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('grouped-membership-cert-datos-course-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('grouped-membership-menu-cert-datos-course-1'),
        ),
        findsOneWidget,
      );
    },
  );
}
