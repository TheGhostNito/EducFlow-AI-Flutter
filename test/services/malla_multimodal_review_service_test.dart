import 'dart:convert';
import 'dart:typed_data';

import 'package:eduflow_ai/models/malla_curricular.dart';
import 'package:eduflow_ai/models/malla_import_review.dart';
import 'package:eduflow_ai/services/malla_multimodal_review_service.dart';
import 'package:eduflow_ai/services/ocr_file_picker_service.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeModelClient implements MallaMultimodalModelClient {
  _FakeModelClient(this.result);

  final Object result;
  int calls = 0;
  MallaMultimodalModelRequest? lastRequest;

  @override
  Future<MallaMultimodalModelResponse> review(
    MallaMultimodalModelRequest request,
  ) async {
    calls++;
    lastRequest = request;
    if (result is Object Function()) throw (result as Object Function())();
    return MallaMultimodalModelResponse(
      json: jsonEncode(result),
      promptTokens: 120,
      outputTokens: 30,
      totalTokens: 150,
    );
  }
}

class _RawModelClient implements MallaMultimodalModelClient {
  _RawModelClient({
    required this.json,
    required this.finishReason,
    required this.truncated,
  });

  final String json;
  final String finishReason;
  final bool truncated;

  @override
  Future<MallaMultimodalModelResponse> review(
    MallaMultimodalModelRequest request,
  ) async => MallaMultimodalModelResponse(
    json: json,
    promptTokens: 900,
    outputTokens: 1800,
    thinkingTokens: 240,
    totalTokens: 2940,
    finishReason: finishReason,
    responseLength: json.length,
    truncated: truncated,
  );
}

class _MemoryCache implements MallaMultimodalCache {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  group('MallaMultimodalReviewService', () {
    test(
      'serializa solo parámetros admitidos para la solicitud estructurada',
      () {
        final config = FirebaseMallaMultimodalModelClient
            .generationConfigForTesting
            .toJson();
        final serialized = jsonEncode(config);

        expect(config['temperature'], isNull);
        expect(config['maxOutputTokens'], 12288);
        expect(config['responseMimeType'], 'application/json');
        expect(config['thinkingConfig'], {'thinkingLevel': 'MEDIUM'});
        final responseSchema = config['responseSchema']! as Map;
        final properties = responseSchema['properties']! as Map;
        final prerequisites = properties['prerequisites']! as Map;
        final prerequisiteItems = prerequisites['items']! as Map;
        final prerequisiteProperties = prerequisiteItems['properties']! as Map;
        final requiredPrerequisiteProperties =
            (prerequisiteItems['required']! as List).cast<String>();
        expect(prerequisiteProperties, isNot(contains('evidence')));
        expect(
          requiredPrerequisiteProperties,
          containsAll([
            'courseId',
            'requiresCourseId',
            'certainty',
            'ambiguous',
          ]),
        );
        for (final optionalEvidenceField in [
          'sourceAnchor',
          'targetArrowhead',
          'pathContinuity',
        ]) {
          expect(
            requiredPrerequisiteProperties,
            isNot(contains(optionalEvidenceField)),
          );
        }
        final certifications = properties['certifications']! as Map;
        final certificationItems = certifications['items']! as Map;
        final certificationProperties =
            certificationItems['properties']! as Map;
        final memberships = certificationProperties['memberships']! as Map;
        final membershipItems = memberships['items']! as Map;
        final membershipProperties = membershipItems['properties']! as Map;
        expect(membershipProperties, isNot(contains('evidence')));
        expect(serialized, isNot(contains('"minimum"')));
        expect(serialized, isNot(contains('"maximum"')));
        expect(serialized, contains('"periodType"'));
        expect(serialized, contains('"periodCount"'));
        expect(serialized, contains('"periodEvidence"'));
        expect(serialized, contains('"courseReviews"'));
        expect(serialized, contains('"additionalCourses"'));
        expect(serialized, contains('"proposalKey"'));
        expect(serialized, contains('"categoryLabel"'));
        expect(serialized, contains('"prerequisiteStatusEvidence"'));
        expect(serialized, contains('"certainty"'));
        expect(serialized, contains('"sourceAnchor"'));
        expect(serialized, contains('"targetArrowhead"'));
        expect(serialized, contains('"pathContinuity"'));
        expect(serialized, contains('"ambiguous"'));
        expect(serialized, contains('"memberships"'));
        expect(serialized, contains('"boundaryStatus"'));
        expect(serialized, contains('"boundaryEvidence"'));
        expect(serialized, contains('"excludedNearbyCourseIds"'));
        expect(serialized, contains('"academicRequirements"'));
        expect(serialized, contains('"prerequisites"'));
        expect(serialized, contains('"certifications"'));
        expect(serialized, contains('"visualAudit"'));
        expect(serialized, contains('"certificationContainerCount"'));
        expect(serialized, contains('"coursePrerequisiteConnectionCount"'));
        expect(serialized, contains('"evidence"'));
        expect(serialized, isNot(contains('"periodOrganization"')));
        expect(serialized, isNot(contains('"enum"')));
        expect(serialized, isNot(contains('"nullable"')));
        expect(serialized, isNot(contains('"maxItems"')));
      },
    );

    test(
      'reduce Vision sin perder identidad, período, posición ni evidencia',
      () {
        final candidates = [
          {
            'courseId': 'course-1',
            'name': 'Álgebra',
            'code': 'MAT101',
            'credits': 4,
            'period': 1,
            'needsReview': false,
          },
        ];
        final payload = <String, dynamic>{
          'ok': true,
          'requestId': 'operational-metadata',
          'rawText': 'TEXTO_BRUTO_QUE_NO_DEBE_ENVIARSE' * 100,
          'pages': [
            {'fullTextAnnotation': 'OCR_GLOBAL_DUPLICADO' * 100},
          ],
          'courses': [
            {
              'name': 'Álgebra',
              'code': 'MAT101',
              'credits': 4,
              'semester': 1,
              'confidence': 0.72,
              'boundingBox': {
                'vertices': [
                  {'x': 10, 'y': 20},
                  {'x': 110, 'y': 20},
                ],
              },
              'sourceBlocks': [
                {'text': 'MAT101 Álgebra 4 SCT', 'x': 10, 'y': 20, 'page': 1},
              ],
            },
          ],
          'specialCurricularElements': [
            {
              'name': 'Certificación de datos',
              'kind': 'certification',
              'semester': 4,
              'internalMetadata': 'omitido',
            },
          ],
        };

        final context =
            FirebaseMallaMultimodalModelClient.buildCompactVisionContext(
              candidates: candidates,
              visionPayload: payload,
            );
        final serialized = jsonEncode(context);
        final course = (context['courses']! as List).single as Map;

        expect(course['courseId'], 'course-1');
        expect(course['name'], 'Álgebra');
        expect(course['code'], 'MAT101');
        expect(course['credits'], 4);
        expect(course['period'], 1);
        expect(course['position'], isA<Map>());
        expect(course['evidence'], isA<List>());
        expect(serialized, contains('MAT101 Álgebra 4 SCT'));
        expect(serialized, contains('Certificación de datos'));
        expect(serialized, isNot(contains('confidence')));
        expect(serialized, isNot(contains('requestId')));
        expect(serialized, isNot(contains('TEXTO_BRUTO')));
        expect(serialized, isNot(contains('OCR_GLOBAL_DUPLICADO')));
        expect(serialized, isNot(contains('internalMetadata')));
        expect(serialized.length, lessThan(jsonEncode(payload).length ~/ 10));
      },
    );

    test('el prompt exige auditoría visual completa y no serializa Vision completo', () {
      final prompt = FirebaseMallaMultimodalModelClient.buildAcademicPrompt(
        candidates: const [
          {
            'courseId': 'course-1',
            'name': 'Álgebra',
            'code': 'MAT101',
            'credits': 4,
            'period': 1,
            'needsReview': false,
          },
        ],
        visionPayload: {
          'courses': [
            {'name': 'Álgebra', 'code': 'MAT101'},
          ],
          'rawText': 'NO_INCLUIR',
        },
      );

      expect(prompt, contains('Revisa toda la malla'));
      expect(prompt, contains('pasadas visuales'));
      expect(prompt, contains('visualAudit.certificationTitles'));
      expect(prompt, contains('coursePrerequisiteConnectionCount'));
      expect(prompt, contains('No descartes una candidatura'));
      expect(prompt, contains('La respuesta debe ser compacta'));
      expect(prompt, contains('no agregues otro campo evidence'));
      expect(prompt, contains('todas las conexiones del inventario'));
      expect(prompt, contains('suficientes para conservar una candidatura'));
      expect(prompt, contains('course-1'));
      expect(prompt, contains('certifications vacío solo'));
      expect(prompt, contains('Usa none solo si'));
      expect(prompt, isNot(contains('NO_INCLUIR')));
      expect(prompt, isNot(contains('RESPUESTA_COMPLETA_VISION')));
    });

    test(
      'normaliza el contrato remoto plano sin perder datos académicos',
      () async {
        final outcome =
            await _service(
              _FakeModelClient(
                _flatResponse(
                  periodType: 'bimester',
                  periodCount: 4,
                  courseReviews: [
                    _flatCourseReview(
                      'course-2',
                      proposedCredits: 6,
                      proposedPeriod: 3,
                      category: 'mandatory',
                    ),
                  ],
                  prerequisites: [_prerequisite('course-2', 'course-1')],
                  certifications: [
                    _certification('cert_datos', 'Certificación de datos', [
                      'course-1',
                      'course-2',
                    ]),
                  ],
                ),
              ),
            ).review(
              uid: 'user-1',
              file: _file,
              visionPayload: _visionPayload,
              visionResult: _vision,
            );

        final review = outcome.review!;
        expect(review.periodType, 'bimester');
        expect(review.periodCount, 4);
        expect(review.courseReviews.single.proposedCredits, 6);
        expect(review.courseReviews.single.proposedPeriod, 3);
        expect(review.prerequisites, hasLength(1));
        expect(review.certifications.single.courseIds, [
          'course-1',
          'course-2',
        ]);
      },
    );

    test('rechaza una revisión aparentemente completa que omite certificaciones detectadas', () async {
      final outcome =
          await _service(
            _FakeModelClient(
              _response(
                visualAudit: {
                  ..._visualAuditFor(const [], const []),
                  'certificationContainerCount': 1,
                  'certificationTitles': const [
                    'Certificado en Programación de Software',
                  ],
                },
              ),
            ),
          ).review(
            uid: 'user-1',
            file: _file,
            visionPayload: _visionPayload,
            visionResult: _vision,
          );

      expect(outcome.review, isNull);
      expect(outcome.failure, MallaMultimodalFailureKind.invalidResponse);
      expect(outcome.diagnostics.stage, 'response_validation');
      expect(outcome.diagnostics.fallbackToVision, isTrue);
    });

    test(
      'rechaza conexiones visuales contadas pero ausentes de prerequisites',
      () async {
        final outcome =
            await _service(
              _FakeModelClient(
                _response(
                  visualAudit: {
                    ..._visualAuditFor(const [], const []),
                    'coursePrerequisiteConnectionCount': 1,
                  },
                ),
              ),
            ).review(
              uid: 'user-1',
              file: _file,
              visionPayload: _visionPayload,
              visionResult: _vision,
            );

        expect(outcome.review, isNull);
        expect(outcome.failure, MallaMultimodalFailureKind.invalidResponse);
        expect(outcome.diagnostics.stage, 'response_validation');
      },
    );

    test(
      'conserva el inventario completo de ocho certificaciones DUOC',
      () async {
        const names = [
          'Certificado en Análisis y Planificación de Requerimientos Informáticos',
          'Certificado en Programación de Software',
          'Certificado en Análisis y Desarrollo de Modelos de Datos',
          'Certificado en Calidad de Software',
          'Certificado en Gestión de Proyectos Informáticos',
          'Certificado en Inteligencia de Negocios',
          'Certificado en Arquitectura de Software',
          'Certificado Internacional en Inglés Intermedio Alto',
        ];
        final certifications = [
          for (var index = 0; index < names.length; index++)
            _certification('cert_${index + 1}', names[index], const [
              'course-1',
            ]),
        ];
        final outcome =
            await _service(
              _FakeModelClient(_response(certifications: certifications)),
            ).review(
              uid: 'user-1',
              file: _file,
              visionPayload: _visionPayload,
              visionResult: _vision,
            );

        expect(outcome.failure, isNull);
        expect(outcome.review!.certifications, hasLength(8));
        expect(outcome.review!.visualAudit!.certificationContainerCount, 8);
        expect(outcome.review!.visualAudit!.certificationTitles, names);
      },
    );

    test('convierte centinelas remotos a propuestas ausentes', () async {
      final outcome =
          await _service(
            _FakeModelClient(
              _flatResponse(courseReviews: [_flatCourseReview('course-1')]),
            ),
          ).review(
            uid: 'user-1',
            file: _file,
            visionPayload: _visionPayload,
            visionResult: _vision,
          );

      final course = outcome.review!.courseReviews.single;
      expect(course.proposedName, isNull);
      expect(course.proposedCode, isNull);
      expect(course.proposedCredits, isNull);
      expect(course.proposedPeriod, isNull);
    });

    test(
      'valida una organización semestral y propuestas con evidencia',
      () async {
        final client = _FakeModelClient(
          _response(
            periodType: 'semester',
            periodCount: 2,
            courseReviews: [
              _courseReview('course-1', proposedPeriod: 1, proposedCredits: 5),
              _courseReview('course-2', proposedPeriod: 2),
            ],
          ),
        );
        final outcome = await _service(client).review(
          uid: 'user-1',
          file: _file,
          visionPayload: _visionPayload,
          visionResult: _vision,
        );

        expect(outcome.failure, isNull);
        expect(outcome.diagnostics.geminiRequestExecuted, isTrue);
        expect(outcome.diagnostics.successful, isTrue);
        expect(outcome.diagnostics.totalTokens, 150);
        expect(outcome.review!.periodType, 'semester');
        expect(outcome.review!.periodCount, 2);
        expect(outcome.review!.courseReviews, hasLength(2));
        expect(outcome.review!.courseReviews.first.proposedCredits, 5);
        expect(client.lastRequest!.bytes, orderedEquals(_file.bytes));
        expect(client.lastRequest!.mimeType, 'application/pdf');
        expect(client.lastRequest!.visionPayload, _visionPayload);
        expect(client.lastRequest!.candidates.map((item) => item['courseId']), [
          'course-1',
          'course-2',
          'course-3',
        ]);
      },
    );

    test('conserva una distribución bimestral explícita', () async {
      final outcome =
          await _service(
            _FakeModelClient(_response(periodType: 'bimester', periodCount: 6)),
          ).review(
            uid: 'user-1',
            file: _file,
            visionPayload: _visionPayload,
            visionResult: _vision,
          );

      expect(outcome.review!.periodType, 'bimester');
      expect(outcome.review!.periodCount, 6);
    });

    test(
      'acepta prerrequisitos evidenciados y descarta referencias inválidas',
      () async {
        final response = _response(
          prerequisites: [
            _prerequisite('course-2', 'course-1'),
            _prerequisite('course-1', 'course-1'),
            _prerequisite('course-3', 'invented-course'),
          ],
        );
        final outcome = await _service(_FakeModelClient(response)).review(
          uid: 'user-1',
          file: _file,
          visionPayload: _visionPayload,
          visionResult: _vision,
        );

        expect(outcome.review!.prerequisites, hasLength(1));
        expect(outcome.review!.prerequisites.single.courseId, 'course-2');
        expect(
          outcome.review!.prerequisites.single.requiresCourseId,
          'course-1',
        );
        expect(
          outcome.review!.pendingReview,
          contains('invalid_prerequisite_relation'),
        );
      },
    );

    test('deja flechas ambiguas pendientes sin aceptar la relación', () async {
      final outcome =
          await _service(
            _FakeModelClient(
              _flatResponse(
                prerequisites: [
                  _prerequisite(
                    'course-2',
                    'course-1',
                    certainty: 'uncertain',
                    evidence: const ['La línea pasa cerca del ramo'],
                    pendingReasons: const ['endpoint_ambiguo'],
                  ),
                ],
              ),
            ),
          ).review(
            uid: 'user-1',
            file: _file,
            visionPayload: _visionPayload,
            visionResult: _vision,
          );

      expect(outcome.review!.prerequisites, hasLength(1));
      expect(
        outcome.review!.prerequisites.single.pendingReasons,
        containsAll(['endpoint_ambiguo', 'relation_direction_uncertain']),
      );
      expect(outcome.review!.prerequisites.single.certainty, 'uncertain');
    });

    test('no confirma proximidad o alineación sin extremos y recorrido verificables', () async {
      final relation = _prerequisite('course-2', 'course-1')
        ..remove('sourceAnchor')
        ..remove('targetArrowhead')
        ..remove('pathContinuity')
        ..['evidence'] = [
          'course-1 y course-2 están alineados dentro del mismo contenedor',
        ];
      final outcome =
          await _service(
            _FakeModelClient(_flatResponse(prerequisites: [relation])),
          ).review(
            uid: 'user-1',
            file: _file,
            visionPayload: _visionPayload,
            visionResult: _vision,
          );

      final prerequisite = outcome.review!.prerequisites.single;
      expect(prerequisite.certainty, 'uncertain');
      expect(
        prerequisite.pendingReasons,
        containsAll([
          'relation_path_not_verified',
          'relation_direction_uncertain',
        ]),
      );
    });

    test(
      'acepta una flecha inequívoca con vocabulario seguro equivalente',
      () async {
        final outcome =
            await _service(
              _FakeModelClient(
                _flatResponse(
                  prerequisites: [
                    _prerequisite('course-2', 'course-1', certainty: 'clear'),
                  ],
                ),
              ),
            ).review(
              uid: 'user-1',
              file: _file,
              visionPayload: _visionPayload,
              visionResult: _vision,
            );

        expect(outcome.review!.prerequisites, hasLength(1));
        expect(outcome.review!.prerequisites.single.courseId, 'course-2');
      },
    );

    test(
      'acepta códigos unidos por flecha directa y no advierte al ramo origen',
      () async {
        final outcome =
            await _service(
              _FakeModelClient(
                _flatResponse(
                  courseReviews: [
                    _courseReview('course-1', prerequisiteStatus: 'identified'),
                    _courseReview('course-2', prerequisiteStatus: 'identified'),
                  ],
                  prerequisites: [
                    _prerequisite(
                      'course-2',
                      'course-1',
                      evidence: const ['MAT101 → MAT102'],
                    ),
                  ],
                ),
              ),
            ).review(
              uid: 'user-1',
              file: _file,
              visionPayload: _visionPayload,
              visionResult: _vision,
            );

        final review = outcome.review!;
        expect(review.prerequisites.single.pendingReasons, isEmpty);
        final source = review.courseReviews.firstWhere(
          (item) => item.courseId == 'course-1',
        );
        final destination = review.courseReviews.firstWhere(
          (item) => item.courseId == 'course-2',
        );
        expect(source.prerequisiteStatus, 'unknown');
        expect(source.pendingReasons, isEmpty);
        expect(destination.prerequisiteStatus, 'identified');
        expect(
          review.pendingReview,
          isNot(contains('prerequisite_status_without_relation:course-1')),
        );
      },
    );

    test('una relación pendiente produce una sola atención', () async {
      final outcome =
          await _service(
            _FakeModelClient(
              _flatResponse(
                courseReviews: [
                  _courseReview('course-2', prerequisiteStatus: 'identified'),
                ],
                prerequisites: [
                  _prerequisite(
                    'course-2',
                    'course-1',
                    certainty: 'uncertain',
                    evidence: const ['MAT101 → MAT102'],
                  ),
                ],
              ),
            ),
          ).review(
            uid: 'user-1',
            file: _file,
            visionPayload: _visionPayload,
            visionResult: _vision,
          );

      final integrated = MallaImportReviewBuilder.integrate(
        MallaCurricular(
          id: _vision.id,
          ramos: _vision.ramos,
          multimodalReview: outcome.review,
        ),
      )!;
      expect(
        integrated.prerequisites.single.decision,
        MallaProposalDecision.pending,
      );
      expect(integrated.courseAttentionItems, isEmpty);
      expect(integrated.globalPending, isEmpty);
      expect(integrated.pendingCount, 1);
    });

    test(
      'hace coherente prerequisiteStatus con relaciones aceptadas',
      () async {
        final outcome =
            await _service(
              _FakeModelClient(
                _flatResponse(
                  courseReviews: [
                    _flatCourseReview(
                      'course-2',
                      prerequisiteStatus: 'none',
                      prerequisiteStatusEvidence: const [
                        'El documento indica sin prerrequisitos',
                      ],
                    ),
                    _flatCourseReview(
                      'course-3',
                      prerequisiteStatus: 'identified',
                    ),
                  ],
                  prerequisites: [_prerequisite('course-2', 'course-1')],
                ),
              ),
            ).review(
              uid: 'user-1',
              file: _file,
              visionPayload: _visionPayload,
              visionResult: _vision,
            );

        expect(
          outcome.review!.courseReviews.first.prerequisiteStatus,
          'identified',
        );
        expect(
          outcome.review!.courseReviews.last.prerequisiteStatus,
          'unknown',
        );
        expect(
          outcome.review!.courseReviews.last.pendingReasons,
          contains('prerequisite_relation_missing'),
        );
        expect(
          outcome.review!.pendingReview,
          contains('prerequisite_status_conflict:course-2'),
        );
        expect(
          outcome.review!.pendingReview,
          isNot(contains('prerequisite_status_without_relation:course-3')),
        );
      },
    );

    test(
      'distingue ausencia confirmada de prerrequisitos desconocidos',
      () async {
        final outcome =
            await _service(
              _FakeModelClient(
                _flatResponse(
                  courseReviews: [
                    _flatCourseReview(
                      'course-1',
                      prerequisiteStatus: 'none',
                      prerequisiteStatusEvidence: const [
                        'El documento indica sin prerrequisitos',
                      ],
                      evidence: const [
                        'El documento indica sin prerrequisitos',
                      ],
                    ),
                    _flatCourseReview(
                      'course-2',
                      prerequisiteStatus: 'unknown',
                      evidence: const [],
                    ),
                  ],
                ),
              ),
            ).review(
              uid: 'user-1',
              file: _file,
              visionPayload: _visionPayload,
              visionResult: _vision,
            );

        expect(outcome.review!.courseReviews.first.prerequisiteStatus, 'none');
        expect(
          outcome.review!.courseReviews.last.prerequisiteStatus,
          'unknown',
        );
      },
    );

    test(
      'no interpreta ausencia de flechas como ausencia de prerrequisitos',
      () async {
        final outcome =
            await _service(
              _FakeModelClient(
                _flatResponse(
                  courseReviews: [
                    _flatCourseReview(
                      'course-1',
                      prerequisiteStatus: 'none',
                      evidence: const ['No se observan flechas entrantes'],
                    ),
                  ],
                ),
              ),
            ).review(
              uid: 'user-1',
              file: _file,
              visionPayload: _visionPayload,
              visionResult: _vision,
            );

        final review = outcome.review!.courseReviews.single;
        expect(review.prerequisiteStatus, 'unknown');
        expect(
          review.pendingReasons,
          contains('prerequisite_absence_not_confirmed'),
        );
      },
    );

    test(
      'valida categorías y certificaciones asociadas a cursos existentes',
      () async {
        final response = _response(
          courseReviews: [
            _courseReview('course-1', category: 'mandatory'),
            _courseReview('course-3', category: 'elective'),
          ],
          certifications: [
            _certification('cert_datos', 'Certificación de datos', [
              'course-1',
              'course-3',
            ]),
          ],
        );
        final outcome = await _service(_FakeModelClient(response)).review(
          uid: 'user-1',
          file: _file,
          visionPayload: _visionPayload,
          visionResult: _vision,
        );

        expect(outcome.review!.courseReviews.first.category, 'mandatory');
        expect(outcome.review!.courseReviews.last.category, 'elective');
        expect(outcome.review!.certifications.single.id, 'cert_datos');
        expect(outcome.review!.certifications.single.courseIds, [
          'course-1',
          'course-3',
        ]);
      },
    );

    test('una flecha no acredita pertenencia a una certificación', () async {
      final outcome =
          await _service(
            _FakeModelClient(
              _flatResponse(
                certifications: [
                  {
                    'id': 'cert_arquitectura',
                    'name': 'Certificado en Arquitectura de Software',
                    'memberships': [
                      {
                        'courseId': 'course-1',
                        'basis': 'container',
                        'evidence': ['Ramo dentro del contenedor'],
                      },
                      {
                        'courseId': 'course-2',
                        'basis': 'arrow',
                        'evidence': ['Una flecha llega desde el contenedor'],
                      },
                    ],
                    'evidence': ['Contenedor y título visibles'],
                  },
                ],
              ),
            ),
          ).review(
            uid: 'user-1',
            file: _file,
            visionPayload: _visionPayload,
            visionResult: _vision,
          );

      expect(outcome.review!.certifications.single.courseIds, [
        'course-1',
        'course-2',
      ]);
      expect(
        outcome.review!.certifications.single.memberships.last.pendingReasons,
        contains('membership_basis_uncertain'),
      );
    });

    test(
      'acepta membresía respaldada por contenedor con formato equivalente',
      () async {
        final outcome =
            await _service(
              _FakeModelClient(
                _flatResponse(
                  certifications: [
                    _certification(
                      'cert_datos',
                      'Certificado en Datos',
                      ['course-1'],
                      basis: 'within_container',
                      membershipEvidence: const [
                        'course-1 dentro del contenedor',
                      ],
                    ),
                  ],
                ),
              ),
            ).review(
              uid: 'user-1',
              file: _file,
              visionPayload: _visionPayload,
              visionResult: _vision,
            );

        expect(outcome.review!.certifications, hasLength(1));
        expect(
          outcome.review!.certifications.single.memberships.single.basis,
          'container',
        );
        expect(
          outcome
              .review!
              .certifications
              .single
              .memberships
              .single
              .pendingReasons,
          isEmpty,
        );
      },
    );

    test(
      'completa relaciones y membresías con la evidencia compacta del esquema',
      () async {
        final prerequisite = _prerequisite('course-2', 'course-1')
          ..remove('evidence');
        final certification = _certification(
          'cert_datos',
          'Certificado en Datos',
          ['course-1'],
        );
        final memberships = certification['memberships']! as List;
        (memberships.single as Map).remove('evidence');

        final outcome =
            await _service(
              _FakeModelClient(
                _flatResponse(
                  prerequisites: [prerequisite],
                  certifications: [certification],
                ),
              ),
            ).review(
              uid: 'user-1',
              file: _file,
              visionPayload: _visionPayload,
              visionResult: _vision,
            );

        expect(outcome.failure, isNull);
        expect(outcome.review!.prerequisites.single.pendingReasons, isEmpty);
        expect(
          outcome
              .review!
              .certifications
              .single
              .memberships
              .single
              .pendingReasons,
          isEmpty,
        );
      },
    );

    test(
      'acepta totalmente dentro como evidencia estructurada de contención',
      () async {
        final certification = _certification(
          'cert_datos',
          'Certificado en Datos',
          ['course-1'],
        );
        final membership =
            (certification['memberships']! as List).single
                as Map<String, Object?>;
        membership
          ..remove('evidence')
          ..['boundaryEvidence'] = 'course-1 está totalmente dentro del contenedor Certificado en Datos';

        final outcome =
            await _service(
              _FakeModelClient(_flatResponse(certifications: [certification])),
            ).review(
              uid: 'user-1',
              file: _file,
              visionPayload: _visionPayload,
              visionResult: _vision,
            );

        final parsed = outcome.review!.certifications.single.memberships.single;
        expect(parsed.pendingReasons, isEmpty);
        expect(parsed.evidence.single, contains('totalmente dentro'));
      },
    );

    test(
      'excluye un ramo cercano que queda fuera del contenedor certificado',
      () async {
        final certification = _certification(
          'cert_arquitectura',
          'Certificado en Arquitectura de Software',
          ['course-1', 'course-2'],
          excludedNearbyCourseIds: const ['course-2'],
        );
        final memberships = certification['memberships']! as List;
        final outside = memberships.last as Map<String, Object?>;
        outside['boundaryStatus'] = 'outside';
        outside['boundaryEvidence'] = 'course-2 queda fuera del borde derecho del Certificado en Arquitectura de Software';

        final outcome =
            await _service(
              _FakeModelClient(_flatResponse(certifications: [certification])),
            ).review(
              uid: 'user-1',
              file: _file,
              visionPayload: _visionPayload,
              visionResult: _vision,
            );

        expect(outcome.review!.certifications.single.courseIds, ['course-1']);
        expect(
          outcome.review!.pendingReview,
          contains(
            'certification_membership_outside:cert_arquitectura:course-2',
          ),
        );
      },
    );

    test(
      'representa requisitos de nivel sin crear prerrequisitos entre ramos',
      () async {
        final outcome =
            await _service(
              _FakeModelClient(
                _flatResponse(
                  academicRequirements: [
                    _academicRequirement(
                      key: 'req_capstone',
                      type: 'capstone_eligibility',
                      targetCourseId: 'course-3',
                      targetLabel: 'Capstone',
                    ),
                    _academicRequirement(
                      key: 'req_practica',
                      type: 'practice_eligibility',
                    ),
                  ],
                ),
              ),
            ).review(
              uid: 'user-1',
              file: _file,
              visionPayload: _visionPayload,
              visionResult: _vision,
            );

        expect(outcome.review!.prerequisites, isEmpty);
        expect(outcome.review!.academicRequirements, hasLength(2));
        expect(
          outcome.review!.academicRequirements.first.targetCourseId,
          'course-3',
        );
        expect(
          outcome.review!.academicRequirements.last.targetLabel,
          'Práctica profesional',
        );
        expect(
          outcome.review!.academicRequirements.first.pendingReasons,
          contains('requirement_evidence_uncertain'),
        );
        expect(
          outcome.review!.academicRequirements.every(
            (item) => item.id.startsWith('gemini_requirement_'),
          ),
          isTrue,
        );
      },
    );

    test(
      'normaliza tipos seguros y conserva unknown sin crear relaciones',
      () async {
        final outcome =
            await _service(
              _FakeModelClient(
                _flatResponse(
                  academicRequirements: [
                    _academicRequirement(type: 'level_approval'),
                    _academicRequirement(
                      key: 'req_2',
                      type: 'condicion_visual_ambigua',
                      targetLabel: 'Capstone',
                    ),
                  ],
                ),
              ),
            ).review(
              uid: 'user-1',
              file: _file,
              visionPayload: _visionPayload,
              visionResult: _vision,
            );

        expect(outcome.review!.prerequisites, isEmpty);
        expect(
          outcome.review!.academicRequirements.first.type,
          'approved_level',
        );
        expect(outcome.review!.academicRequirements.last.type, 'unknown');
        expect(
          outcome.review!.academicRequirements.last.pendingReasons,
          contains('requirement_type_uncertain'),
        );
      },
    );

    test('usa el nivel explícito de la evidencia y marca descripciones contradictorias', () async {
      final outcome =
          await _service(
            _FakeModelClient(
              _flatResponse(
                academicRequirements: [
                  _academicRequirement(
                    key: 'req_level_conflict',
                    type: 'capstone_eligibility',
                    targetCourseId: 'course-3',
                    targetLabel: 'Taller',
                    description: 'Tener aprobados los niveles I a VII',
                    minimumLevel: 7,
                    evidence: const [
                      'Burbuja I a VI NIVEL APROBADO con flecha hacia Taller',
                    ],
                  ),
                ],
              ),
            ),
          ).review(
            uid: 'user-1',
            file: _file,
            visionPayload: _visionPayload,
            visionResult: _vision,
          );

      final requirement = outcome.review!.academicRequirements.single;
      expect(requirement.minimumLevel, 6);
      expect(requirement.description, 'Tener aprobados los niveles I a VI');
      expect(
        requirement.pendingReasons,
        contains('requirement_level_conflict'),
      );
    });

    test(
      'combina 25 candidatos con 10 propuestas evidenciadas en 18 bimestres',
      () async {
        final vision = MallaCurricular(
          id: 'preview',
          ramos: [
            for (var index = 1; index <= 25; index++)
              RamoMalla(
                id: 'course-$index',
                nombre: 'Asignatura Vision $index',
                codigo: 'VIS$index',
                creditos: 4,
                semestre: (index - 1) % 18 + 1,
              ),
          ],
        );
        final response = _flatResponse(
          periodType: 'bimester',
          periodCount: 18,
          courseReviews: [
            _flatCourseReview(
              'course-1',
              category: 'specialty',
              categoryLabel: 'Especialidades',
              evidence: const ['Leyenda morada visible'],
            ),
            _flatCourseReview(
              'course-2',
              category: 'institutional',
              categoryLabel: 'Formación Sello',
              evidence: const ['Leyenda amarilla visible'],
            ),
          ],
          additionalCourses: [
            for (var index = 1; index <= 10; index++)
              _additionalCourse(
                index,
                name: 'Asignatura omitida $index',
                code: 'OMI$index',
                period: index + 8,
              ),
          ],
        );
        final outcome = await _service(_FakeModelClient(response)).review(
          uid: 'user-1',
          file: _file,
          visionPayload: _visionPayload,
          visionResult: vision,
        );

        final review = outcome.review!;
        expect(vision.ramos, hasLength(25));
        expect(review.additionalCourses, hasLength(10));
        expect(vision.ramos.length + review.additionalCourses.length, 35);
        expect(review.periodType, 'bimester');
        expect(review.periodCount, 18);
        expect(
          review.additionalCourses.map((item) => item.proposedPeriod),
          orderedEquals([9, 10, 11, 12, 13, 14, 15, 16, 17, 18]),
        );
        expect(
          review.additionalCourses.map((item) => item.id).toSet(),
          hasLength(10),
        );
        expect(
          review.additionalCourses.every(
            (item) => item.id.startsWith('gemini_proposal_'),
          ),
          isTrue,
        );
        expect(review.courseReviews.first.category, 'specialty');
        expect(review.courseReviews.first.categoryLabel, 'Especialidades');
        expect(review.courseReviews.last.category, 'institutional');
        expect(review.courseReviews.last.categoryLabel, 'Formación Sello');
        expect(review.prerequisites, isEmpty);
        expect(review.certifications, isEmpty);
        expect(vision.withMultimodalReview(review).ramos, same(vision.ramos));
      },
    );

    test('descarta propuestas duplicadas o sin evidencia', () async {
      final outcome =
          await _service(
            _FakeModelClient(
              _flatResponse(
                additionalCourses: [
                  _additionalCourse(1, name: 'Álgebra', code: 'NUEVO1'),
                  _additionalCourse(
                    2,
                    name: 'Nombre alternativo',
                    code: 'MAT101',
                  ),
                  _additionalCourse(
                    3,
                    name: 'Sin evidencia',
                    code: 'NUEVO3',
                    evidence: const [],
                  ),
                  _additionalCourse(4, name: 'Curso nuevo', code: 'NUEVO4'),
                  _additionalCourse(5, name: 'Curso nuevo', code: 'NUEVO5'),
                ],
              ),
            ),
          ).review(
            uid: 'user-1',
            file: _file,
            visionPayload: _visionPayload,
            visionResult: _vision,
          );

      expect(outcome.review!.additionalCourses, hasLength(1));
      expect(outcome.review!.additionalCourses.single.proposedCode, 'NUEVO4');
      expect(
        outcome.review!.pendingReview,
        containsAll([
          'duplicate_additional_course',
          'invalid_additional_course',
        ]),
      );
    });

    test('conserva propuestas ambiguas como pendientes de revisión', () async {
      final outcome =
          await _service(
            _FakeModelClient(
              _flatResponse(
                additionalCourses: [
                  _additionalCourse(
                    1,
                    name: 'Asignatura parcialmente legible',
                    code: '',
                    period: -1,
                    pendingReasons: const ['nombre_parcial'],
                  ),
                ],
              ),
            ),
          ).review(
            uid: 'user-1',
            file: _file,
            visionPayload: _visionPayload,
            visionResult: _vision,
          );

      final proposal = outcome.review!.additionalCourses.single;
      expect(proposal.proposedCode, isNull);
      expect(proposal.proposedPeriod, isNull);
      expect(proposal.requiresManualReview, isTrue);
      expect(
        proposal.pendingReasons,
        containsAll(['nombre_parcial', 'period_uncertain', 'code_uncertain']),
      );
    });

    test(
      'normaliza etiquetas institucionales sin perder el nombre visible',
      () async {
        final outcome =
            await _service(
              _FakeModelClient(
                _flatResponse(
                  courseReviews: [
                    _flatCourseReview(
                      'course-1',
                      category: 'other',
                      categoryLabel: 'Especialidades',
                    ),
                    _flatCourseReview(
                      'course-2',
                      category: 'unknown',
                      categoryLabel: 'Formación Sello',
                    ),
                  ],
                ),
              ),
            ).review(
              uid: 'user-1',
              file: _file,
              visionPayload: _visionPayload,
              visionResult: _vision,
            );

        expect(outcome.review!.courseReviews.first.category, 'specialty');
        expect(
          outcome.review!.courseReviews.first.categoryLabel,
          'Especialidades',
        );
        expect(outcome.review!.courseReviews.last.category, 'institutional');
        expect(
          outcome.review!.courseReviews.last.categoryLabel,
          'Formación Sello',
        );
      },
    );

    test(
      'resuelve relaciones de propuestas sin aceptar referencias inventadas',
      () async {
        final outcome =
            await _service(
              _FakeModelClient(
                _flatResponse(
                  additionalCourses: [
                    _additionalCourse(1, name: 'Curso nuevo'),
                  ],
                  prerequisites: [
                    _prerequisite('new_1', 'course-1'),
                    _prerequisite('new_inventado', 'course-1'),
                  ],
                  certifications: [
                    _certification('cert_nueva', 'Certificación visible', [
                      'course-1',
                      'new_1',
                    ]),
                  ],
                ),
              ),
            ).review(
              uid: 'user-1',
              file: _file,
              visionPayload: _visionPayload,
              visionResult: _vision,
            );

        final proposalId = outcome.review!.additionalCourses.single.id;
        expect(outcome.review!.prerequisites.single.courseId, proposalId);
        expect(
          outcome.review!.certifications.single.courseIds,
          containsAll(['course-1', proposalId]),
        );
        expect(
          outcome.review!.pendingReview,
          contains('invalid_prerequisite_relation'),
        );
      },
    );

    test(
      'adjunta la revisión sin reemplazar datos correctos de Vision',
      () async {
        final originalCourses = _vision.ramos;
        final outcome =
            await _service(
              _FakeModelClient(
                _response(
                  courseReviews: [
                    _courseReview(
                      'course-1',
                      proposedName: 'Nombre propuesto',
                      proposedCredits: 99,
                    ),
                  ],
                ),
              ),
            ).review(
              uid: 'user-1',
              file: _file,
              visionPayload: _visionPayload,
              visionResult: _vision,
            );
        final combined = _vision.withMultimodalReview(outcome.review);

        expect(identical(combined.ramos, originalCourses), isTrue);
        expect(combined.ramos.first.nombre, 'Álgebra');
        expect(combined.ramos.first.creditos, 4);
        expect(combined.multimodalReview, isNotNull);
      },
    );

    test(
      'neutraliza afirmaciones sin evidencia y referencias inventadas',
      () async {
        final response = _response(
          periodType: 'bimester',
          periodCount: 99,
          periodEvidence: const [],
          courseReviews: [
            _courseReview(
              'course-1',
              proposedName: 'Nombre sin respaldo',
              proposedPeriod: 20,
              evidence: const [],
            ),
            _courseReview('invented-course'),
            _courseReview('course-1'),
          ],
          certifications: [
            _certification('cert_sin_evidencia', 'Certificación inventada', [
              'course-1',
            ], evidence: const []),
          ],
          visualAudit: _visualAuditFor(const [], const []),
        );
        final outcome = await _service(_FakeModelClient(response)).review(
          uid: 'user-1',
          file: _file,
          visionPayload: _visionPayload,
          visionResult: _vision,
        );
        final review = outcome.review!;

        expect(review.periodType, 'unknown');
        expect(review.periodCount, 0);
        expect(review.courseReviews, hasLength(1));
        expect(review.courseReviews.single.proposedName, isNull);
        expect(review.courseReviews.single.proposedPeriod, isNull);
        expect(review.certifications, isEmpty);
        expect(review.pendingReview, contains('unknown_course_reference'));
        expect(
          review.pendingReview,
          contains('course_claim_without_evidence:course-1'),
        );
      },
    );

    test(
      'devuelve fallback de cuota sin descartar el resultado Vision',
      () async {
        final client = _FakeModelClient(
          () => StateError('RESOURCE_EXHAUSTED: quota exceeded'),
        );
        final outcome = await _service(client).review(
          uid: 'user-1',
          file: _file,
          visionPayload: _visionPayload,
          visionResult: _vision,
        );
        final combined = _vision.withMultimodalReview(outcome.review);

        expect(outcome.failure, MallaMultimodalFailureKind.quota);
        expect(outcome.diagnostics.fallbackToVision, isTrue);
        expect(outcome.diagnostics.errorCategory, 'quota');
        expect(outcome.review, isNull);
        expect(combined.ramos, same(_vision.ramos));
        expect(combined.multimodalReview, isNull);
      },
    );

    test('rechaza una respuesta que no cumple el contrato JSON', () async {
      final outcome =
          await _service(_FakeModelClient({'courseReviews': <Object?>[]}))
              .review(
                uid: 'user-1',
                file: _file,
                visionPayload: _visionPayload,
                visionResult: _vision,
              );

      expect(outcome.failure, MallaMultimodalFailureKind.invalidResponse);
      expect(outcome.diagnostics.stage, 'response_validation');
      expect(outcome.diagnostics.errorCategory, 'response_json');
      expect(outcome.review, isNull);
    });

    test(
      'detecta MAX_TOKENS antes del parser y conserva métricas seguras',
      () async {
        const incompleteJson = '{"periodType":"semester';
        final outcome =
            await _service(
              _RawModelClient(
                json: incompleteJson,
                finishReason: 'MAX_TOKENS',
                truncated: true,
              ),
            ).review(
              uid: 'user-1',
              file: _file,
              visionPayload: _visionPayload,
              visionResult: _vision,
            );

        expect(outcome.failure, MallaMultimodalFailureKind.invalidResponse);
        expect(outcome.review, isNull);
        expect(outcome.diagnostics.stage, 'response_truncated');
        expect(outcome.diagnostics.fallbackToVision, isTrue);
        expect(outcome.diagnostics.finishReason, 'MAX_TOKENS');
        expect(outcome.diagnostics.promptTokens, 900);
        expect(outcome.diagnostics.outputTokens, 1800);
        expect(outcome.diagnostics.thinkingTokens, 240);
        expect(outcome.diagnostics.totalTokens, 2940);
        expect(outcome.diagnostics.responseLength, incompleteJson.length);
        expect(outcome.diagnostics.truncated, isTrue);
        expect(outcome.diagnostics.technicalMessage, contains('MAX_TOKENS'));
      },
    );

    test(
      'conserva finishReason y métricas en una respuesta completa',
      () async {
        final json = jsonEncode(_flatResponse());
        final outcome =
            await _service(
              _RawModelClient(
                json: json,
                finishReason: 'STOP',
                truncated: false,
              ),
            ).review(
              uid: 'user-1',
              file: _file,
              visionPayload: _visionPayload,
              visionResult: _vision,
            );

        expect(outcome.failure, isNull);
        expect(outcome.diagnostics.finishReason, 'STOP');
        expect(outcome.diagnostics.thinkingTokens, 240);
        expect(outcome.diagnostics.responseLength, json.length);
        expect(outcome.diagnostics.truncated, isFalse);
      },
    );

    test(
      'mantiene JSON malformado sin MAX_TOKENS como error de parser',
      () async {
        final outcome =
            await _service(
              _RawModelClient(
                json: '{"periodType":',
                finishReason: 'STOP',
                truncated: false,
              ),
            ).review(
              uid: 'user-1',
              file: _file,
              visionPayload: _visionPayload,
              visionResult: _vision,
            );

        expect(outcome.failure, MallaMultimodalFailureKind.invalidResponse);
        expect(outcome.diagnostics.stage, 'response_json_decode');
        expect(outcome.diagnostics.finishReason, 'STOP');
        expect(outcome.diagnostics.truncated, isFalse);
      },
    );

    test('distingue una solicitud rechazada durante generateContent', () async {
      final outcome =
          await _service(
            _FakeModelClient(
              () => ServerException(
                'INVALID_ARGUMENT: invalid value in response_schema; HTTP 400',
              ),
            ),
          ).review(
            uid: 'user-1',
            file: _file,
            visionPayload: _visionPayload,
            visionResult: _vision,
          );

      expect(outcome.failure, MallaMultimodalFailureKind.invalidRequest);
      expect(outcome.diagnostics.provider, 'gemini_developer_api');
      expect(outcome.diagnostics.model, 'gemini-3.5-flash');
      expect(outcome.diagnostics.stage, 'generate_content');
      expect(outcome.diagnostics.httpStatus, 400);
      expect(outcome.diagnostics.backendStatus, 'INVALID_ARGUMENT');
      expect(outcome.diagnostics.retryable, isFalse);
      expect(outcome.diagnostics.technicalMessage, contains('response_schema'));
    });

    test('distingue acceso rechazado y redacta secretos del mensaje', () {
      final details = MallaMultimodalSafeError.inspect(
        ServerException(
          'PERMISSION_DENIED HTTP 403 key '
          'AIza123456789012345678901234567890 and user@example.com',
        ),
      );

      expect(details.category, 'access');
      expect(details.httpStatus, 403);
      expect(details.backendStatus, 'PERMISSION_DENIED');
      expect(details.retryable, isFalse);
      expect(details.technicalMessage, isNot(contains('AIza123')));
      expect(details.technicalMessage, isNot(contains('user@example.com')));
    });

    test(
      'reutiliza caché para el mismo usuario, documento, modelo y versión',
      () async {
        final cache = _MemoryCache();
        final client = _FakeModelClient(
          _response(
            periodType: 'semester',
            periodCount: 2,
            additionalCourses: [
              _additionalCourse(1, name: 'Curso recuperado', period: 2),
            ],
            academicRequirements: [_academicRequirement()],
          ),
        );
        final service = _service(client, cache: cache);

        final first = await service.review(
          uid: 'user-1',
          file: _file,
          visionPayload: _visionPayload,
          visionResult: _vision,
        );
        final second = await service.review(
          uid: 'user-1',
          file: _file,
          visionPayload: _visionPayload,
          visionResult: _vision,
        );

        expect(first.cacheHit, isFalse);
        expect(second.cacheHit, isTrue);
        expect(second.diagnostics.geminiRequestExecuted, isFalse);
        expect(second.diagnostics.cacheHit, isTrue);
        expect(second.diagnostics.totalTokens, isNull);
        expect(second.review!.periodType, 'semester');
        expect(second.review!.additionalCourses, hasLength(1));
        expect(
          second.review!.additionalCourses.single.id,
          first.review!.additionalCourses.single.id,
        );
        expect(second.review!.academicRequirements, hasLength(1));
        expect(
          second.review!.academicRequirements.single.id,
          first.review!.academicRequirements.single.id,
        );
        expect(client.calls, 1);
        expect(cache.values, hasLength(1));
      },
    );
  });
}

MallaMultimodalReviewService _service(
  MallaMultimodalModelClient client, {
  MallaMultimodalCache? cache,
}) => MallaMultimodalReviewService(
  client: client,
  cache: cache ?? _MemoryCache(),
  logger: (_, _) {},
);

final _file = OcrPickedFile(
  name: 'malla.pdf',
  bytes: Uint8List.fromList([37, 80, 68, 70]),
  mimeType: 'application/pdf',
  sizeBytes: 4,
);

final _visionPayload = <String, dynamic>{
  'ok': true,
  'courses': [
    {'id': 'course-1', 'name': 'Álgebra', 'semesterColumnX': 10},
  ],
  'sourceBlocks': [
    {'text': 'Álgebra', 'x': 10, 'y': 20},
  ],
};

final _vision = MallaCurricular(
  id: 'preview',
  archivoNombre: 'malla.pdf',
  ramos: [
    RamoMalla(
      id: 'course-1',
      nombre: 'Álgebra',
      codigo: 'MAT101',
      creditos: 4,
      semestre: 1,
    ),
    RamoMalla(
      id: 'course-2',
      nombre: 'Cálculo',
      codigo: 'MAT102',
      creditos: 5,
      semestre: 2,
    ),
    RamoMalla(
      id: 'course-3',
      nombre: 'Taller',
      codigo: 'TAL101',
      creditos: 2,
      semestre: 2,
    ),
  ],
);

Map<String, Object?> _response({
  String periodType = 'semester',
  int periodCount = 2,
  List<String> periodEvidence = const ['Encabezados visibles'],
  List<Map<String, Object?>> courseReviews = const [],
  List<Map<String, Object?>> additionalCourses = const [],
  List<Map<String, Object?>> prerequisites = const [],
  List<Map<String, Object?>> certifications = const [],
  List<Map<String, Object?>> academicRequirements = const [],
  Map<String, Object?>? visualAudit,
}) => {
  'periodOrganization': {
    'type': periodType,
    'count': periodCount,
    'evidence': periodEvidence,
  },
  'courseReviews': courseReviews,
  'additionalCourses': additionalCourses,
  'prerequisites': prerequisites,
  'certifications': certifications,
  'academicRequirements': academicRequirements,
  'visualAudit': visualAudit ?? _visualAuditFor(prerequisites, certifications),
  'pendingReview': <String>[],
};

Map<String, Object?> _flatResponse({
  String periodType = 'semester',
  int periodCount = 2,
  List<String> periodEvidence = const ['Encabezados visibles'],
  List<Map<String, Object?>> courseReviews = const [],
  List<Map<String, Object?>> additionalCourses = const [],
  List<Map<String, Object?>> prerequisites = const [],
  List<Map<String, Object?>> certifications = const [],
  List<Map<String, Object?>> academicRequirements = const [],
  Map<String, Object?>? visualAudit,
}) => {
  'periodType': periodType,
  'periodCount': periodCount,
  'periodEvidence': periodEvidence,
  'courseReviews': courseReviews,
  'additionalCourses': additionalCourses,
  'prerequisites': prerequisites,
  'certifications': certifications,
  'academicRequirements': academicRequirements,
  'visualAudit': visualAudit ?? _visualAuditFor(prerequisites, certifications),
  'pendingReview': <String>[],
};

Map<String, Object?> _visualAuditFor(
  List<Map<String, Object?>> prerequisites,
  List<Map<String, Object?>> certifications,
) => {
  'certificationContainersInspected': true,
  'certificationContainerCount': certifications.length,
  'certificationTitles': [
    for (final certification in certifications) certification['name'],
  ],
  'courseArrowsInspected': true,
  'coursePrerequisiteConnectionCount': prerequisites.length,
  'unresolvedVisualSignals': <String>[],
};

Map<String, Object?> _courseReview(
  String courseId, {
  String? proposedName,
  int? proposedCredits,
  int? proposedPeriod,
  String category = 'unknown',
  String categoryLabel = '',
  String prerequisiteStatus = 'unknown',
  List<String> prerequisiteStatusEvidence = const [],
  List<String> evidence = const ['Texto visible en la celda'],
}) => {
  'courseId': courseId,
  'proposedName': proposedName,
  'proposedCode': null,
  'proposedCredits': proposedCredits,
  'proposedPeriod': proposedPeriod,
  'category': category,
  'categoryLabel': categoryLabel,
  'prerequisiteStatus': prerequisiteStatus,
  'prerequisiteStatusEvidence': prerequisiteStatusEvidence,
  'evidence': evidence,
  'pendingReasons': <String>[],
};

Map<String, Object?> _flatCourseReview(
  String courseId, {
  String proposedName = '',
  String proposedCode = '',
  int proposedCredits = -1,
  int proposedPeriod = -1,
  String category = 'unknown',
  String categoryLabel = '',
  String prerequisiteStatus = 'unknown',
  List<String> prerequisiteStatusEvidence = const [],
  List<String> evidence = const ['Texto visible en la celda'],
}) => {
  'courseId': courseId,
  'proposedName': proposedName,
  'proposedCode': proposedCode,
  'proposedCredits': proposedCredits,
  'proposedPeriod': proposedPeriod,
  'category': category,
  'categoryLabel': categoryLabel,
  'prerequisiteStatus': prerequisiteStatus,
  'prerequisiteStatusEvidence': prerequisiteStatusEvidence,
  'evidence': evidence,
  'pendingReasons': <String>[],
};

Map<String, Object?> _additionalCourse(
  int index, {
  String? name,
  String? code,
  int period = 1,
  int credits = -1,
  String category = 'unknown',
  String categoryLabel = '',
  List<String> evidence = const ['Asignatura visible en la malla'],
  List<String> pendingReasons = const [],
}) => {
  'proposalKey': 'new_$index',
  'proposedName': name ?? 'Asignatura adicional $index',
  'proposedCode': code ?? 'ADD$index',
  'proposedCredits': credits,
  'proposedPeriod': period,
  'category': category,
  'categoryLabel': categoryLabel,
  'evidence': evidence,
  'pendingReasons': pendingReasons,
};

Map<String, Object?> _prerequisite(
  String courseId,
  String requiresCourseId, {
  String certainty = 'confirmed',
  List<String>? evidence,
  List<String> pendingReasons = const [],
}) => {
  'courseId': courseId,
  'requiresCourseId': requiresCourseId,
  'certainty': certainty,
  'sourceAnchor':
      'La línea nace en el borde derecho de $requiresCourseId como origen',
  'targetArrowhead':
      'La punta de flecha termina en el borde izquierdo de $courseId',
  'pathContinuity':
      'Recorrido continuo y directo desde $requiresCourseId hasta $courseId',
  'ambiguous': certainty == 'uncertain',
  'evidence':
      evidence ??
      ['Flecha desde $requiresCourseId hacia $courseId, conectada en ambos extremos'],
  'pendingReasons': pendingReasons,
};

Map<String, Object?> _certification(
  String id,
  String name,
  List<String> courseIds, {
  String basis = 'container',
  List<String> evidence = const ['Contenedor y rótulo visibles'],
  List<String>? membershipEvidence,
  List<String> excludedNearbyCourseIds = const [],
}) => {
  'id': id,
  'name': name,
  'memberships': [
    for (final courseId in courseIds)
      {
        'courseId': courseId,
        'basis': basis,
        'boundaryStatus': 'inside',
        'boundaryEvidence':
            '$courseId está completamente dentro de los cuatro bordes del contenedor $name',
        'evidence':
            membershipEvidence ??
            [
              '$courseId está completamente dentro de los cuatro bordes del contenedor $name',
            ],
        'pendingReasons': <String>[],
      },
  ],
  'evidence': evidence,
  'excludedNearbyCourseIds': excludedNearbyCourseIds,
};

Map<String, Object?> _academicRequirement({
  String key = 'req_1',
  String type = 'approved_level',
  String targetCourseId = '',
  String targetLabel = 'Práctica profesional',
  String description = 'Tener aprobados los niveles 1 al 4',
  int minimumLevel = 4,
  List<String> evidence = const ['Nota explícita bajo la práctica'],
  List<String> pendingReasons = const [],
}) => {
  'requirementKey': key,
  'type': type,
  'targetCourseId': targetCourseId,
  'targetLabel': targetLabel,
  'description': description,
  'minimumLevel': minimumLevel,
  'evidence': evidence,
  'pendingReasons': pendingReasons,
};
