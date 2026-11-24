import 'package:eduflow_ai/models/malla_curricular.dart';
import 'package:eduflow_ai/models/malla_import_review.dart';
import 'package:eduflow_ai/models/malla_multimodal_review.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Informática integra datos seguros y concentra pendientes reales', () {
    final source = MallaCurricular(
      id: '',
      ramos: [
        RamoMalla(
          id: 'vision-1',
          nombre: 'Fundamentos de Datos',
          codigo: 'DAT1001',
          creditos: null,
          semestre: 1,
          requiereRevision: true,
          motivosRevision: ['credits_missing', 'semester_uncertain'],
        ),
        RamoMalla(
          id: 'vision-2',
          nombre: 'Big Data',
          codigo: 'BIY7131',
          creditos: 6,
          semestre: 7,
        ),
      ],
      multimodalReview: _review(
        periodType: 'semester',
        periodCount: 8,
        courseReviews: const [
          MallaCourseReview(
            courseId: 'vision-1',
            proposedName: null,
            proposedCode: null,
            proposedCredits: 5,
            proposedPeriod: 2,
            category: 'specialty',
            categoryLabel: 'Especialidad',
            prerequisiteStatus: 'identified',
            evidence: ['Créditos y columna visibles'],
            pendingReasons: [],
          ),
        ],
        additionalCourses: const [
          MallaAdditionalCourseProposal(
            id: 'gemini-complete',
            proposedName: 'Minería de Datos',
            proposedCode: 'BIY7121',
            proposedCredits: 6,
            proposedPeriod: 7,
            category: 'specialty',
            categoryLabel: 'Especialidad',
            evidence: ['Celda completa visible'],
            pendingReasons: [],
          ),
          MallaAdditionalCourseProposal(
            id: 'gemini-incomplete',
            proposedName: 'Curso de Formación Cristiana',
            proposedCode: null,
            proposedCredits: null,
            proposedPeriod: 3,
            category: 'institutional',
            categoryLabel: 'Formación Sello',
            evidence: ['Celda visible'],
            pendingReasons: ['code_uncertain'],
          ),
        ],
        prerequisites: const [
          MallaPrerequisiteReview(
            courseId: 'vision-2',
            requiresCourseId: 'vision-1',
            evidence: ['Flecha visible'],
          ),
        ],
        certifications: const [
          MallaCertificationReview(
            id: 'cert-1',
            name: 'Certificación de datos',
            courseIds: ['vision-2'],
            evidence: ['Contenedor visible'],
            memberships: [
              MallaCertificationMembership(
                courseId: 'vision-2',
                basis: 'container',
                evidence: ['Dentro del contenedor'],
              ),
            ],
          ),
        ],
        requirements: const [
          MallaAcademicRequirement(
            id: 'req-1',
            type: 'capstone_eligibility',
            targetCourseId: 'vision-2',
            targetLabel: 'Capstone',
            description: 'Niveles previos aprobados',
            minimumLevel: 6,
            evidence: ['Nota visible'],
            pendingReasons: [],
          ),
        ],
      ),
    );

    final integrated = MallaImportReviewBuilder.integrate(source)!;

    expect(integrated.periodType, 'semester');
    expect(integrated.periodCount, 8);
    expect(integrated.malla.ramos, hasLength(4));
    expect(integrated.courseById('vision-1')!.creditos, 5);
    expect(integrated.courseById('vision-1')!.semestre, 2);
    expect(integrated.courseById('vision-1')!.requiereRevision, isFalse);
    expect(integrated.courseById('gemini-complete')!.requiereRevision, isFalse);
    expect(
      integrated.courseById('gemini-incomplete')!.requiereRevision,
      isTrue,
    );
    expect(integrated.categoryLabelFor('vision-1'), 'Especialidad');
    expect(integrated.pendingCount, 1);
    expect(
      integrated.prerequisites.single.decision,
      MallaProposalDecision.suggested,
    );
    expect(
      integrated.certifications.single.memberships.single.decision,
      MallaProposalDecision.suggested,
    );
    expect(
      integrated.academicRequirements.single.decision,
      MallaProposalDecision.suggested,
    );
    expect(source.ramos.first.creditos, isNull);
    expect(source.ramos.first.semestre, 1);
  });

  test('Control de Gestión conserva 18 bimestres y 35 asignaturas', () {
    final integrated = MallaImportReviewBuilder.integrate(
      MallaCurricular(
        id: '',
        ramos: [
          for (var index = 1; index <= 25; index++)
            RamoMalla(
              id: 'vision-$index',
              nombre: 'Asignatura Vision $index',
              codigo: 'VIS$index',
              creditos: 4,
              semestre: (index - 1) % 18 + 1,
            ),
        ],
        multimodalReview: _review(
          periodType: 'bimester',
          periodCount: 18,
          additionalCourses: [
            for (var index = 1; index <= 10; index++)
              MallaAdditionalCourseProposal(
                id: 'gemini-$index',
                proposedName: 'Asignatura recuperada $index',
                proposedCode: 'GEM$index',
                proposedCredits: 4,
                proposedPeriod: index,
                category: 'mandatory',
                categoryLabel: 'Obligatoria',
                evidence: const ['Celda completa visible'],
                pendingReasons: const [],
              ),
          ],
        ),
      ),
    )!;

    expect(integrated.periodType, 'bimester');
    expect(integrated.periodCount, 18);
    expect(integrated.malla.ramos, hasLength(35));
    expect(integrated.pendingCount, 0);
  });

  test('no sobrescribe contradicciones y las cuenta una sola vez por ramo', () {
    final integrated = MallaImportReviewBuilder.integrate(
      MallaCurricular(
        id: '',
        ramos: [
          RamoMalla(
            id: 'vision-1',
            nombre: 'Arquitectura de Software',
            codigo: 'ASY5001',
            creditos: 6,
            semestre: 5,
          ),
        ],
        multimodalReview: _review(
          periodType: 'semester',
          periodCount: 8,
          courseReviews: const [
            MallaCourseReview(
              courseId: 'vision-1',
              proposedName: 'Arquitectura Empresarial',
              proposedCode: 'ASY5002',
              proposedCredits: 5,
              proposedPeriod: 6,
              category: 'specialty',
              prerequisiteStatus: 'unknown',
              evidence: ['Celda visible'],
              pendingReasons: [],
            ),
          ],
        ),
      ),
    )!;

    final course = integrated.courseById('vision-1')!;
    expect(course.nombre, 'Arquitectura de Software');
    expect(course.codigo, 'ASY5001');
    expect(course.creditos, 6);
    expect(course.semestre, 5);
    expect(
      integrated.courseChanges.single.decision,
      MallaProposalDecision.pending,
    );
    expect(
      integrated.courseChanges.single.attentionReasons,
      containsAll([
        'gemini_name_conflict',
        'gemini_code_conflict',
        'gemini_credits_conflict',
        'gemini_period_conflict',
      ]),
    );
    expect(integrated.pendingCount, 1);
  });

  test('deduplica propuestas y remapea sus relaciones al ramo Vision', () {
    final integrated = MallaImportReviewBuilder.integrate(
      MallaCurricular(
        id: '',
        ramos: [
          RamoMalla(
            id: 'vision-1',
            nombre: 'Big Data',
            codigo: 'BIY7131',
            creditos: 6,
            semestre: 7,
          ),
          RamoMalla(
            id: 'vision-2',
            nombre: 'Proyecto',
            codigo: 'PRY8001',
            creditos: 8,
            semestre: 8,
          ),
        ],
        multimodalReview: _review(
          periodType: 'semester',
          periodCount: 8,
          additionalCourses: const [
            MallaAdditionalCourseProposal(
              id: 'gemini-duplicate',
              proposedName: 'Big Data duplicado',
              proposedCode: 'BIY-7131',
              proposedCredits: 6,
              proposedPeriod: 7,
              category: 'specialty',
              categoryLabel: 'Especialidad',
              evidence: ['Celda visible'],
              pendingReasons: [],
            ),
          ],
          prerequisites: const [
            MallaPrerequisiteReview(
              courseId: 'vision-2',
              requiresCourseId: 'gemini-duplicate',
              evidence: ['Flecha visible'],
            ),
          ],
        ),
      ),
    )!;

    expect(integrated.malla.ramos, hasLength(2));
    expect(integrated.deduplicatedAdditionalCourses, ['Big Data duplicado']);
    expect(integrated.prerequisites.single.requiresCourseId, 'vision-1');
  });

  test('integra un curso especial de Vision sin duplicarlo ni atribuirlo solo a Gemini', () {
    final integrated = MallaImportReviewBuilder.integrate(
      MallaCurricular(
        id: '',
        ramos: [RamoMalla(id: 'vision-1', nombre: 'Álgebra', semestre: 1)],
        especiales: [
          ElementoCurricularEspecial(
            nombre: 'Curso de Formación Cristiana',
            tipo: 'uncoded_course',
            semestre: 3,
            creditos: 4,
          ),
        ],
        multimodalReview: _review(
          periodType: 'semester',
          periodCount: 8,
          additionalCourses: const [
            MallaAdditionalCourseProposal(
              id: 'gemini-christian-course',
              proposedName: 'Curso de Formación Cristiana',
              proposedCode: null,
              proposedCredits: null,
              proposedPeriod: 3,
              category: 'institutional',
              categoryLabel: 'Formación general',
              evidence: ['Elemento especial visible en Vision y la imagen'],
              pendingReasons: ['code_uncertain'],
            ),
          ],
        ),
      ),
    )!;

    final course = integrated.courseById('gemini-christian-course')!;
    expect(integrated.malla.ramos, hasLength(2));
    expect(course.creditos, 4);
    expect(course.requiereRevision, isTrue);
    expect(course.motivosRevision, ['code_missing']);
    expect(integrated.sourceFor(course.id), MallaCourseSource.merged);
    expect(integrated.geminiCourseIds, isNot(contains(course.id)));
    expect(integrated.malla.especiales, isEmpty);
  });

  test(
    'Proceso de Portafolio conserva una sola asignatura y recupera 6 créditos',
    () {
      final integrated = MallaImportReviewBuilder.integrate(
        MallaCurricular(
          id: '',
          ramos: [
            RamoMalla(
              id: 'vision-portfolio',
              nombre: 'Proceso de Portafolio',
              codigo: 'APY4614',
              semestre: 1,
              requiereRevision: true,
              motivosRevision: ['credits_missing'],
            ),
          ],
          multimodalReview: _review(
            periodType: 'semester',
            periodCount: 8,
            courseReviews: const [
              MallaCourseReview(
                courseId: 'vision-portfolio',
                proposedName: null,
                proposedCode: null,
                proposedCredits: 6,
                proposedPeriod: null,
                category: 'specialty',
                categoryLabel: 'Especialidad',
                prerequisiteStatus: 'unknown',
                evidence: [
                  'Bloque horizontal único: PROCESO DE PORTAFOLIO, 6 CRÉDITOS, APY4614',
                ],
                pendingReasons: [],
              ),
            ],
          ),
        ),
      )!;

      expect(integrated.malla.ramos, hasLength(1));
      expect(integrated.courseById('vision-portfolio')!.creditos, 6);
      expect(
        integrated.courseById('vision-portfolio')!.motivosRevision,
        isNot(contains('credits_missing')),
      );
    },
  );

  test('oculta solo el elemento especial inequívocamente ya incorporado', () {
    final integrated = MallaImportReviewBuilder.integrate(
      MallaCurricular(
        id: '',
        ramos: [
          RamoMalla(
            id: 'vision-christian',
            nombre: 'Curso de Formación Cristiana',
            semestre: 3,
            creditos: 4,
            requiereRevision: true,
            motivosRevision: const ['code_missing'],
          ),
          RamoMalla(
            id: 'vision-similar',
            nombre: 'Curso de Formación Cristiana II',
            semestre: 3,
            creditos: 4,
          ),
        ],
        especiales: [
          ElementoCurricularEspecial(
            nombre: 'Curso de Formación Cristiana',
            tipo: 'uncoded_course',
            semestre: 3,
            creditos: 4,
          ),
          ElementoCurricularEspecial(
            nombre: 'Curso de Formación Cristiana',
            tipo: 'uncoded_course',
            semestre: 5,
            creditos: 4,
          ),
          ElementoCurricularEspecial(
            nombre: 'Curso de Formación Cristiana II',
            tipo: 'uncoded_course',
            semestre: 3,
            creditos: 6,
          ),
        ],
        multimodalReview: _review(periodType: 'semester', periodCount: 8),
      ),
    )!;

    expect(integrated.malla.ramos, hasLength(2));
    expect(integrated.malla.especiales, hasLength(2));
    expect(
      integrated.malla.especiales.map((item) => (item.nombre, item.semestre)),
      contains(('Curso de Formación Cristiana', 5)),
    );
    expect(
      integrated.malla.especiales.map((item) => item.creditos),
      contains(6),
    );
  });

  test('no deduplica propuestas con nombre igual pero período distinto', () {
    final integrated = MallaImportReviewBuilder.integrate(
      MallaCurricular(
        id: '',
        ramos: [
          RamoMalla(
            id: 'vision-workshop',
            nombre: 'Taller Integrado',
            semestre: 1,
            creditos: 4,
          ),
        ],
        multimodalReview: _review(
          periodType: 'semester',
          periodCount: 2,
          additionalCourses: const [
            MallaAdditionalCourseProposal(
              id: 'gemini-workshop-2',
              proposedName: 'Taller Integrado',
              proposedCode: null,
              proposedCredits: 4,
              proposedPeriod: 2,
              category: 'mandatory',
              categoryLabel: null,
              evidence: ['Otra celda visible en el segundo período'],
              pendingReasons: [],
            ),
          ],
        ),
      ),
    )!;

    expect(integrated.malla.ramos, hasLength(2));
    expect(integrated.courseById('gemini-workshop-2'), isNotNull);
    expect(integrated.deduplicatedAdditionalCourses, isEmpty);
  });

  test('conserva relaciones inciertas sin tratarlas como confirmadas', () {
    final integrated = MallaImportReviewBuilder.integrate(
      MallaCurricular(
        id: '',
        ramos: [
          RamoMalla(id: 'vision-1', nombre: 'Ramo A', semestre: 1),
          RamoMalla(id: 'vision-2', nombre: 'Ramo B', semestre: 2),
        ],
        multimodalReview: _review(
          periodType: 'semester',
          periodCount: 2,
          requirements: const [
            MallaAcademicRequirement(
              id: 'req-unknown',
              type: 'unknown',
              targetCourseId: 'vision-2',
              targetLabel: 'Ramo B',
              description: 'Condición académica visible',
              minimumLevel: null,
              evidence: ['Nota visible'],
              pendingReasons: ['requirement_type_uncertain'],
            ),
          ],
          certifications: const [
            MallaCertificationReview(
              id: 'cert-1',
              name: 'Certificación de prueba',
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
          pendingReview: const [
            'uncertain_prerequisite_relation:vision-2>vision-1:endpoint_ambiguo',
            'uncertain_certification_membership:cert-1:vision-2',
          ],
        ),
      ),
    )!;

    expect(
      integrated.prerequisites.single.decision,
      MallaProposalDecision.pending,
    );
    expect(integrated.prerequisites.single.pendingReasons, [
      'endpoint_ambiguo',
    ]);
    expect(integrated.certifications.single.memberships, hasLength(2));
    expect(
      integrated.certifications.single.memberships.last.decision,
      MallaProposalDecision.pending,
    );
    expect(integrated.globalPending, isEmpty);
    expect(
      integrated.academicRequirements.single.decision,
      MallaProposalDecision.pending,
    );
    expect(integrated.pendingCount, 3);
    integrated.prerequisites.single.decision = MallaProposalDecision.rejected;
    expect(integrated.pendingCount, 2);
  });

  test('respeta la corrección manual sin modificar Vision', () {
    final original = RamoMalla(
      id: 'vision-1',
      nombre: 'Ramo original',
      codigo: 'ORI1001',
      creditos: 4,
      semestre: 1,
    );
    final source = MallaCurricular(
      id: '',
      ramos: [original],
      multimodalReview: _review(
        periodType: 'semester',
        periodCount: 2,
        courseReviews: const [
          MallaCourseReview(
            courseId: 'vision-1',
            proposedName: null,
            proposedCode: null,
            proposedCredits: 5,
            proposedPeriod: null,
            category: 'unknown',
            prerequisiteStatus: 'unknown',
            evidence: ['Créditos visibles'],
            pendingReasons: [],
          ),
        ],
      ),
    );
    final integrated = MallaImportReviewBuilder.integrate(source)!;
    final draft = integrated.courseById('vision-1')!;

    expect(draft.creditos, 4);
    draft.creditos = 6;
    integrated.markCourseEdited(draft.id);

    expect(draft.creditos, 6);
    expect(original.creditos, 4);
    expect(
      integrated.courseChanges.single.decision,
      MallaProposalDecision.accepted,
    );
  });

  test(
    'aplica créditos respaldados aunque exista incertidumbre de otra categoría',
    () {
      final integrated = MallaImportReviewBuilder.integrate(
        MallaCurricular(
          id: '',
          ramos: [
            RamoMalla(
              id: 'vision-1',
              nombre: 'Ramo',
              semestre: 1,
              requiereRevision: true,
              motivosRevision: ['credits_missing'],
            ),
          ],
          multimodalReview: _review(
            periodType: 'semester',
            periodCount: 2,
            courseReviews: const [
              MallaCourseReview(
                courseId: 'vision-1',
                proposedName: null,
                proposedCode: null,
                proposedCredits: 6,
                proposedPeriod: null,
                category: 'unknown',
                prerequisiteStatus: 'unknown',
                evidence: ['Crédito 6 visible en la celda'],
                pendingReasons: ['layout_uncertain'],
              ),
            ],
          ),
        ),
      )!;

      final course = integrated.courseById('vision-1')!;
      expect(course.creditos, 6);
      expect(course.motivosRevision, isNot(contains('credits_missing')));
      expect(
        integrated.courseChanges.single.automaticallyAppliedFields,
        contains('credits'),
      );
      expect(course.requiereRevision, isTrue);
    },
  );

  test('limpia credits_missing obsoleto sin sobrescribir contradicciones', () {
    MallaImportReview integrate({
      required int current,
      required int proposed,
    }) => MallaImportReviewBuilder.integrate(
      MallaCurricular(
        id: '',
        ramos: [
          RamoMalla(
            id: 'vision-1',
            nombre: 'Ramo',
            semestre: 1,
            creditos: current,
            requiereRevision: true,
            motivosRevision: ['credits_missing'],
          ),
        ],
        multimodalReview: _review(
          periodType: 'semester',
          periodCount: 1,
          courseReviews: [
            MallaCourseReview(
              courseId: 'vision-1',
              proposedName: null,
              proposedCode: null,
              proposedCredits: proposed,
              proposedPeriod: null,
              category: 'mandatory',
              prerequisiteStatus: 'none',
              evidence: const ['Crédito visible'],
              pendingReasons: const [],
            ),
          ],
        ),
      ),
    )!;

    final matching = integrate(current: 6, proposed: 6);
    expect(matching.courseById('vision-1')!.motivosRevision, isEmpty);
    expect(matching.courseById('vision-1')!.requiereRevision, isFalse);

    final conflicting = integrate(current: 5, proposed: 6);
    expect(conflicting.courseById('vision-1')!.creditos, 5);
    expect(
      conflicting.courseById('vision-1')!.motivosRevision,
      contains('gemini_credits_conflict'),
    );
  });

  test(
    'editar un requisito conserva identidad y evidencia sin confirmarlo',
    () {
      final proposal = MallaAcademicRequirementProposal(
        requirement: const MallaAcademicRequirement(
          id: 'req-capstone',
          type: 'capstone_eligibility',
          targetCourseId: 'capstone',
          targetLabel: 'Capstone',
          description: 'Niveles I a VII aprobados',
          minimumLevel: 7,
          evidence: ['Nota original de Gemini'],
          pendingReasons: ['requirement_level_conflict'],
        ),
      );

      proposal.updateDetails(
        description: 'Niveles I a VI aprobados',
        minimumLevel: 6,
      );

      expect(proposal.requirement.id, 'req-capstone');
      expect(proposal.requirement.type, 'capstone_eligibility');
      expect(proposal.requirement.targetCourseId, 'capstone');
      expect(proposal.requirement.targetLabel, 'Capstone');
      expect(proposal.requirement.description, 'Niveles I a VI aprobados');
      expect(proposal.requirement.minimumLevel, 6);
      expect(proposal.requirement.evidence, ['Nota original de Gemini']);
      expect(
        proposal.requirement.pendingReasons,
        contains('manual_confirmation_required'),
      );
      expect(proposal.decision, MallaProposalDecision.pending);
    },
  );

  test('separa sugerencias de los elementos que necesitan atención', () {
    final integrated = MallaImportReviewBuilder.integrate(
      MallaCurricular(
        id: '',
        ramos: [
          RamoMalla(id: 'origen', nombre: 'Origen', semestre: 1),
          RamoMalla(id: 'destino', nombre: 'Destino', semestre: 2),
        ],
        multimodalReview: _review(
          periodType: 'semester',
          periodCount: 2,
          prerequisites: const [
            MallaPrerequisiteReview(
              courseId: 'destino',
              requiresCourseId: 'origen',
              evidence: ['Flecha directa'],
            ),
          ],
        ),
      ),
    )!;

    expect(integrated.pendingCount, 0);
    expect(integrated.suggestionCount, 1);
  });

  test('agrupa cadenas ramificadas sin inventar ni crear grupos excesivos', () {
    final courses = [
      for (var index = 0; index < 9; index++)
        RamoMalla(
          id: 'course-$index',
          nombre: 'Asignatura $index',
          semestre: index + 1,
        ),
    ];
    final relations = [
      for (var index = 1; index < 8; index++)
        MallaPrerequisiteProposal(
          courseId: 'course-$index',
          requiresCourseId: index == 4 ? 'course-1' : 'course-${index - 1}',
          evidence: const ['Flecha directa'],
          pendingReasons: const [],
        ),
      MallaPrerequisiteProposal(
        courseId: 'course-8',
        requiresCourseId: 'course-7',
        evidence: const [],
        pendingReasons: const ['arrow_uncertain'],
      ),
    ];
    final review = MallaImportReview(
      malla: MallaCurricular(id: '', ramos: courses),
      periodType: 'semester',
      periodCount: 9,
      periodEvidence: const [],
      geminiCourseIds: const {},
      courseChanges: const [],
      prerequisites: relations,
      certifications: const [],
      academicRequirements: const [],
      globalPending: const [],
      deduplicatedAdditionalCourses: const [],
    );

    final groups = review.prerequisiteGroups;
    final groupedRelations = groups
        .expand((group) => group.prerequisites)
        .toSet();

    expect(groups, hasLength(2));
    expect(groups.every((group) => group.prerequisites.length <= 6), isTrue);
    expect(groupedRelations, relations.take(7).toSet());
    expect(groupedRelations, isNot(contains(relations.last)));
  });

  test('confirma grupos completos y parciales conservando otros estados', () {
    MallaPrerequisiteProposal relation(String id) => MallaPrerequisiteProposal(
      courseId: 'target-$id',
      requiresCourseId: 'source-$id',
      evidence: const ['Flecha directa'],
      pendingReasons: const [],
    );
    final first = relation('1');
    final excluded = relation('2');
    final previouslyAccepted = relation('3')
      ..decision = MallaProposalDecision.accepted;
    final previouslyRejected = relation('4')
      ..decision = MallaProposalDecision.rejected;
    final pending = MallaPrerequisiteProposal(
      courseId: 'target-5',
      requiresCourseId: 'source-5',
      evidence: const [],
      pendingReasons: const ['arrow_uncertain'],
    );
    final review = MallaImportReview(
      malla: MallaCurricular(id: '', ramos: const []),
      periodType: 'semester',
      periodCount: 1,
      periodEvidence: const [],
      geminiCourseIds: const {},
      courseChanges: const [],
      prerequisites: [
        first,
        excluded,
        previouslyAccepted,
        previouslyRejected,
        pending,
      ],
      certifications: const [],
      academicRequirements: const [],
      globalPending: const [],
      deduplicatedAdditionalCourses: const [],
    );

    review.acceptSuggestedPrerequisites([first]);

    expect(first.decision, MallaProposalDecision.accepted);
    expect(excluded.decision, MallaProposalDecision.suggested);
    expect(previouslyAccepted.decision, MallaProposalDecision.accepted);
    expect(previouslyRejected.decision, MallaProposalDecision.rejected);
    expect(pending.decision, MallaProposalDecision.pending);
    expect(review.suggestionCount, 1);
    expect(review.pendingCount, 1);

    review.acceptSuggestedPrerequisites(review.prerequisites);
    expect(excluded.decision, MallaProposalDecision.accepted);
    expect(previouslyRejected.decision, MallaProposalDecision.rejected);
    expect(pending.decision, MallaProposalDecision.pending);
  });

  test('confirma certificación y solo las membresías seleccionadas', () {
    MallaCertificationMembershipProposal membership(String id) =>
        MallaCertificationMembershipProposal(
          courseId: id,
          basis: 'container',
          evidence: const ['Dentro del contenedor'],
        );
    final selected = membership('course-1');
    final excluded = membership('course-2');
    final rejected = membership('course-3')
      ..decision = MallaProposalDecision.rejected;
    final pending = MallaCertificationMembershipProposal(
      courseId: 'course-4',
      basis: 'uncertain',
      evidence: const [],
      pendingReasons: const ['membership_evidence_uncertain'],
    );
    final certification = MallaCertificationProposal(
      id: 'cert-1',
      name: 'Certificación',
      evidence: const ['Contenedor identificado'],
      memberships: [selected, excluded, rejected, pending],
    );
    final review = MallaImportReview(
      malla: MallaCurricular(id: '', ramos: const []),
      periodType: 'semester',
      periodCount: 1,
      periodEvidence: const [],
      geminiCourseIds: const {},
      courseChanges: const [],
      prerequisites: const [],
      certifications: [certification],
      academicRequirements: const [],
      globalPending: const [],
      deduplicatedAdditionalCourses: const [],
    );

    review.acceptCertificationSelection(certification, [selected]);

    expect(certification.decision, MallaProposalDecision.accepted);
    expect(selected.decision, MallaProposalDecision.accepted);
    expect(excluded.decision, MallaProposalDecision.suggested);
    expect(rejected.decision, MallaProposalDecision.rejected);
    expect(pending.decision, MallaProposalDecision.pending);
    expect(review.suggestionCount, 1);
    expect(review.pendingCount, 1);
  });

  test('no confirma membresías si la certificación padre sigue pendiente', () {
    final membership = MallaCertificationMembershipProposal(
      courseId: 'course-1',
      basis: 'container',
      evidence: const ['Dentro del contenedor'],
    );
    final certification = MallaCertificationProposal(
      id: 'cert-pending',
      name: 'Certificación incierta',
      evidence: const ['Contenedor parcial'],
      memberships: [membership],
      pendingReasons: const ['certification_uncertain'],
    );
    final review = MallaImportReview(
      malla: MallaCurricular(id: '', ramos: const []),
      periodType: 'semester',
      periodCount: 1,
      periodEvidence: const [],
      geminiCourseIds: const {},
      courseChanges: const [],
      prerequisites: const [],
      certifications: [certification],
      academicRequirements: const [],
      globalPending: const [],
      deduplicatedAdditionalCourses: const [],
    );

    review.acceptCertificationSelection(certification, [membership]);

    expect(certification.decision, MallaProposalDecision.pending);
    expect(membership.decision, MallaProposalDecision.suggested);
    expect(review.pendingCount, 1);
    expect(review.suggestionCount, 1);
  });

  test('seis pendientes del contador producen seis atenciones accesibles', () {
    final integrated = MallaImportReviewBuilder.integrate(
      MallaCurricular(
        id: '',
        ramos: [
          for (var index = 1; index <= 6; index++)
            RamoMalla(
              id: 'course-$index',
              nombre: 'Asignatura $index',
              semestre: 1,
              requiereRevision: true,
              motivosRevision: const ['code_missing'],
            ),
        ],
        multimodalReview: _review(periodType: 'semester', periodCount: 8),
      ),
    )!;

    expect(integrated.pendingCount, 6);
    expect(integrated.courseAttentionItems, hasLength(6));
    expect(
      integrated.courseAttentionItems.map((item) => item.courseId).toSet(),
      {for (var index = 1; index <= 6; index++) 'course-$index'},
    );
  });
}

MallaMultimodalReview _review({
  required String periodType,
  required int periodCount,
  List<MallaCourseReview> courseReviews = const [],
  List<MallaAdditionalCourseProposal> additionalCourses = const [],
  List<MallaPrerequisiteReview> prerequisites = const [],
  List<MallaCertificationReview> certifications = const [],
  List<MallaAcademicRequirement> requirements = const [],
  List<String> pendingReview = const [],
}) => MallaMultimodalReview(
  model: 'gemini-3.5-flash',
  processorVersion: 'malla-multimodal-v4.2',
  documentHash: 'hash',
  periodType: periodType,
  periodCount: periodCount,
  periodEvidence: const ['Organización visible'],
  courseReviews: courseReviews,
  additionalCourses: additionalCourses,
  prerequisites: prerequisites,
  certifications: certifications,
  academicRequirements: requirements,
  pendingReview: pendingReview,
);
