import 'dart:async';
import 'dart:convert';

import 'package:eduflow_ai/models/malla_curricular.dart';
import 'package:eduflow_ai/models/malla_import_review.dart';
import 'package:eduflow_ai/models/malla_multimodal_review.dart';
import 'package:eduflow_ai/models/malla_review.dart';
import 'package:eduflow_ai/services/malla_multimodal_persistence_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _RpcCall {
  const _RpcCall(this.function, this.params);

  final String function;
  final Map<String, dynamic> params;
}

class _FakeRpc implements MallaMultimodalRpcClient {
  _FakeRpc(this.handler);

  final Future<dynamic> Function(String function, Map<String, dynamic> params)
  handler;
  final List<_RpcCall> calls = [];

  @override
  Future<dynamic> invoke(String function, Map<String, dynamic> params) async {
    calls.add(_RpcCall(function, params));
    return handler(function, params);
  }
}

void main() {
  const codec = MallaMultimodalPersistenceCodec();

  test('serializa bimestres, decisiones y pendientes sin confirmarlos', () {
    final payload = codec.encode(
      _review(periodType: 'bimester', periodCount: 8),
    );

    expect(payload['period_type'], 'bimester');
    expect(payload['period_count'], 8);
    expect((payload['courses'] as List), hasLength(3));
    expect(
      (payload['prerequisites'] as List).map(
        (item) => (item as Map)['decision'],
      ),
      ['suggested', 'rejected'],
    );
    expect(
      ((payload['prerequisites'] as List).first as Map)['certainty'],
      'unknown',
    );
    final certification = (payload['certifications'] as List).single as Map;
    expect(certification['decision'], 'accepted');
    expect(
      (certification['memberships'] as List).map(
        (item) => (item as Map)['decision'],
      ),
      ['accepted', 'rejected'],
    );
    expect(
      ((payload['academic_requirements'] as List).single as Map)['decision'],
      'pending',
    );
    expect(
      (payload['pending_items'] as List).every(
        (item) => (item as Map)['status'] == 'pending',
      ),
      isTrue,
    );
  });

  test(
    'serializa corrección de requisito conservando contrato y evidencia',
    () {
      final review = _review();
      final proposal = review.academicRequirements.single;
      proposal.updateDetails(
        description: 'Niveles I a VI aprobados',
        minimumLevel: 6,
      );

      final payload = codec.encode(review);
      final requirement =
          (payload['academic_requirements'] as List).single as Map;

      expect(requirement['id'], 'req_1');
      expect(requirement['type'], 'unknown');
      expect(requirement['target_course_id'], 'gemini_1');
      expect(requirement['target_label'], 'Curso adicional');
      expect(requirement['description'], 'Niveles I a VI aprobados');
      expect(requirement['minimum_level'], 6);
      expect(requirement['source'], 'gemini');
      expect(requirement['evidence'], ['Nota al pie']);
      expect(requirement['decision'], 'pending');
      expect(
        requirement['pending_reasons'],
        contains('manual_confirmation_required'),
      );
    },
  );

  test(
    'serializa exactamente confirmaciones agrupadas y sugerencias excluidas',
    () {
      final review = _review();
      final prerequisite = review.prerequisites.first;
      review.acceptSuggestedPrerequisites([prerequisite]);
      final certification = review.certifications.single;
      final selectedMembership = MallaCertificationMembershipProposal(
        courseId: 'vision_2',
        basis: 'container',
        evidence: const ['Dentro del contenedor'],
      );
      final excludedMembership = certification.memberships.last
        ..decision = MallaProposalDecision.suggested;
      certification.memberships.add(selectedMembership);
      review.acceptCertificationSelection(certification, [selectedMembership]);

      final payload = codec.encode(review);
      final prerequisites = payload['prerequisites'] as List;
      final serializedCertification =
          (payload['certifications'] as List).single as Map;
      final memberships = serializedCertification['memberships'] as List;

      expect((prerequisites.first as Map)['decision'], 'accepted');
      expect((prerequisites.last as Map)['decision'], 'rejected');
      expect(serializedCertification['decision'], 'accepted');
      expect(
        (memberships.singleWhere(
          (item) => (item as Map)['course_id'] == 'vision_2',
        ) as Map)['decision'],
        'accepted',
      );
      expect(
        (memberships.singleWhere(
          (item) => (item as Map)['course_id'] == excludedMembership.courseId,
        ) as Map)['decision'],
        'suggested',
      );
      expect(review.suggestionCount, 1);
    },
  );

  test('recupera contrato completo y conserva decisiones', () {
    final original = _review(periodType: 'semester', periodCount: 8);
    final recovered = codec.decode(_response(codec.encode(original)));

    expect(recovered.periodType, 'semester');
    expect(recovered.periodCount, 8);
    expect(recovered.malla.ramos, hasLength(3));
    expect(recovered.prerequisites.map((item) => item.decision), [
      MallaProposalDecision.suggested,
      MallaProposalDecision.rejected,
    ]);
    expect(
      recovered.certifications.single.memberships.map((item) => item.decision),
      [MallaProposalDecision.accepted, MallaProposalDecision.rejected],
    );
    expect(
      recovered.academicRequirements.single.decision,
      MallaProposalDecision.pending,
    );
    expect(recovered.pendingCount, greaterThan(0));
  });

  test('rechaza una respuesta de recuperación incompleta', () {
    expect(
      () => codec.decode({'id': 'malla-1', 'courses': const []}),
      throwsFormatException,
    );
  });

  test('entorno no autorizado no realiza llamadas RPC', () async {
    final rpc = _FakeRpc((_, _) async => fail('No debe invocar Supabase'));
    final repository = _repository(
      rpc,
      firebaseProject: 'educflow-ai',
      supabaseProject: 'production-ref',
      config: const MallaMultimodalPersistenceConfig(
        requested: true,
        expectedFirebaseProjectId: 'eduflow-ai-testing',
        expectedSupabaseProjectRef: 'testing-ref',
      ),
    );

    expect(repository.enabled, isFalse);
    await expectLater(repository.load(), throwsStateError);
    await expectLater(
      repository.decidePrerequisite(
        mallaId: 'saved-id',
        courseId: 'vision_2',
        requiresCourseId: 'vision_1',
        decision: MallaProposalDecision.accepted,
      ),
      throwsStateError,
    );
    await expectLater(
      repository.decideMembership(
        mallaId: 'saved-id',
        certificationId: 'cert_1',
        courseId: 'gemini_1',
        decision: MallaProposalDecision.accepted,
      ),
      throwsStateError,
    );
    await expectLater(
      repository.decideAcademicRequirement(
        mallaId: 'saved-id',
        requirementId: 'req_1',
        type: 'capstone_eligibility',
        decision: MallaProposalDecision.accepted,
      ),
      throwsStateError,
    );
    await expectLater(repository.deleteConfirmed('saved-id'), throwsStateError);
    expect(rpc.calls, isEmpty);
  });

  test('confirmación usa un RPC y recupera el resultado completo', () async {
    final review = _review(periodType: 'bimester', periodCount: 18);
    final response = _response(codec.encode(review), id: 'saved-id');
    final rpc = _FakeRpc((function, _) async {
      if (function == 'confirmar_malla_multimodal') return 'saved-id';
      if (function == 'obtener_malla_multimodal') return response;
      fail('RPC inesperado: $function');
    });
    final repository = _repository(rpc);

    final saved = await repository.confirm(review);

    expect(saved.malla.id, 'saved-id');
    expect(saved.periodType, 'bimester');
    expect(saved.periodCount, 18);
    expect(rpc.calls.map((call) => call.function), [
      'confirmar_malla_multimodal',
      'obtener_malla_multimodal',
    ]);
    expect(rpc.calls.first.params['p_malla'], isA<Map<String, dynamic>>());
  });

  test('normaliza el nombre de archivo igual que Supabase', () async {
    final review = _review(fileName: '  malla.pdf  ');
    final response = _response(
      codec.encode(review),
      id: 'saved-id',
      fileName: 'malla.pdf',
    );
    final rpc = _FakeRpc((function, params) async {
      if (function == 'confirmar_malla_multimodal') {
        expect(params['p_archivo_nombre'], 'malla.pdf');
        return 'saved-id';
      }
      return response;
    });

    final saved = await _repository(rpc).confirm(review);

    expect(saved.malla.archivoNombre, 'malla.pdf');
  });

  test('round-trip conserva estado manual con procedencia merged', () async {
    final review = _review();
    review.markCourseEdited('vision_1');
    final expected = codec.encode(review);
    final response = _response(expected, id: 'saved-id');
    final repository = _repository(
      _FakeRpc((function, _) async {
        if (function == 'confirmar_malla_multimodal') return 'saved-id';
        return response;
      }),
    );

    final saved = await repository.confirm(review);
    final actual = codec.encode(saved);

    expect(saved.wasManuallyEdited('vision_1'), isTrue);
    expect(codec.differencePaths(expected, actual), isEmpty);
  });

  test('serializa y recupera un ramo confirmado legítimamente sin código', () {
    final review = _review();
    final course = review.courseById('gemini_1')!;
    final remaining = MallaReviewRules.remainingReasons(
      course,
      code: null,
      credits: course.creditos,
      verifyOther: false,
      verifyMissingCode: true,
    );
    course.motivosRevision
      ..clear()
      ..addAll(remaining);
    course.requiereRevision = remaining.isNotEmpty;
    review.markCourseEdited(course.id);

    final payload = codec.encode(review);
    final encodedCourse = (payload['courses'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((item) => item['id'] == course.id);
    final recovered = codec.decode(_response(payload));

    expect(encodedCourse['code'], isNull);
    expect(encodedCourse['review_state'], 'manual');
    expect(encodedCourse['review_reasons'], isEmpty);
    expect(
      (payload['pending_items'] as List).where(
        (item) =>
            (item as Map)['entity_type'] == 'course' &&
            item['entity_key'] == course.id,
      ),
      isEmpty,
    );
    expect(recovered.courseById(course.id)!.codigo, isNull);
    expect(recovered.courseById(course.id)!.motivosRevision, isEmpty);
    expect(codec.equivalentPayloads(payload, codec.encode(recovered)), isTrue);
  });

  test('rechaza una recuperación que pierde información académica', () async {
    final review = _review();
    final response = _response(codec.encode(review), id: 'saved-id');
    final courses = response['courses'] as List;
    courses[0] = {
      ...Map<String, dynamic>.from(courses[0] as Map),
      'category': 'unknown',
    };
    final repository = _repository(
      _FakeRpc((function, _) async {
        if (function == 'confirmar_malla_multimodal') return 'saved-id';
        return response;
      }),
    );

    await expectLater(
      repository.confirm(review),
      throwsA(
        isA<MallaMultimodalIntegrityException>()
            .having(
              (error) => error.fileNameMismatch,
              'fileNameMismatch',
              isFalse,
            )
            .having(
              (error) => error.differencePaths,
              'differencePaths',
              contains(contains('category')),
            ),
      ),
    );
  });

  test('diagnóstico de integridad informa rutas sin exponer valores', () {
    final review = _review();
    final expected = codec.encode(review);
    final actual = Map<String, dynamic>.from(expected);
    actual['courses'] = [
      for (final value in expected['courses'] as List)
        if ((value as Map)['id'] == 'vision_1')
          {
            ...Map<String, dynamic>.from(value),
            'category': 'valor-sensible-no-registrable',
          }
        else
          value,
    ];

    final paths = codec.differencePaths(expected, actual);

    expect(paths, contains(contains('category')));
    expect(paths.join(','), isNot(contains('valor-sensible-no-registrable')));
  });

  test('bloquea escrituras simultáneas y propaga fallos de red', () async {
    final gate = Completer<void>();
    final review = _review();
    final response = _response(codec.encode(review));
    final rpc = _FakeRpc((function, _) async {
      if (function == 'confirmar_malla_multimodal') {
        await gate.future;
        return 'saved-id';
      }
      return response;
    });
    final repository = _repository(rpc);

    final first = repository.confirm(review);
    await Future<void>.delayed(Duration.zero);
    await expectLater(repository.confirm(review), throwsStateError);
    gate.complete();
    await first;
    expect(
      rpc.calls.where((call) => call.function == 'confirmar_malla_multimodal'),
      hasLength(1),
    );

    final failing = _repository(
      _FakeRpc((_, _) async => throw TimeoutException('sin conexión')),
    );
    await expectLater(failing.load(), throwsA(isA<TimeoutException>()));

    final unauthorized = _repository(
      _FakeRpc(
        (_, _) async => throw const PostgrestException(
          message: 'usuario_firebase_no_valido',
          code: '42501',
        ),
      ),
    );
    await expectLater(
      unauthorized.load(),
      throwsA(
        isA<PostgrestException>().having(
          (error) => error.code,
          'code',
          '42501',
        ),
      ),
    );
  });

  test('descarta la recuperación si cambia la cuenta durante la RPC', () async {
    final response = _response(codec.encode(_review()));
    var uid = 'firebase-user-a';
    final repository = _repository(
      _FakeRpc((_, _) async {
        uid = 'firebase-user-b';
        return response;
      }),
      uidProvider: () => uid,
    );

    await expectLater(
      repository.load(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'mensaje',
          contains('sesión cambió'),
        ),
      ),
    );
  });

  test('confirma un grupo completo con una RPC y una recarga', () async {
    final review = _review(mallaId: 'saved-id');
    final second = review.prerequisites.last
      ..decision = MallaProposalDecision.suggested;
    final selected = [review.prerequisites.first, second];
    final response = _response(codec.encode(review));
    for (final value in response['prerequisites'] as List) {
      final item = value as Map;
      item['decision'] = 'accepted';
      item['pending_reasons'] = <String>[];
    }
    final rpc = _FakeRpc((function, _) async {
      if (function == 'gestionar_revision_malla_multimodal') {
        return {'malla_id': 'saved-id'};
      }
      if (function == 'obtener_malla_multimodal') return response;
      fail('RPC inesperado: $function');
    });

    final saved = await _repository(rpc)
        .confirmRelationshipBatch(review: review, prerequisites: selected);

    expect(
      saved.prerequisites.map((item) => item.decision),
      everyElement(MallaProposalDecision.accepted),
    );
    expect(rpc.calls.map((call) => call.function), [
      'gestionar_revision_malla_multimodal',
      'obtener_malla_multimodal',
    ]);
    final changes = rpc.calls.first.params['p_cambios'] as Map;
    expect(changes['prerequisites'], hasLength(2));
    expect(changes['certifications'], isEmpty);
    expect(changes['memberships'], isEmpty);
  });

  test(
    'confirmación parcial no envía exclusiones ni estados protegidos',
    () async {
      final review = _review(mallaId: 'saved-id');
      final selected = review.prerequisites.first;
      final response = _response(codec.encode(review));
      final relation = (response['prerequisites'] as List).first as Map;
      relation['decision'] = 'accepted';
      relation['pending_reasons'] = <String>[];
      final rpc = _FakeRpc((function, _) async {
        if (function == 'gestionar_revision_malla_multimodal') {
          return {'malla_id': 'saved-id'};
        }
        return response;
      });
      final repository = _repository(rpc);

      await repository.confirmRelationshipBatch(
        review: review,
        prerequisites: [selected],
      );

      final sent =
          ((rpc.calls.first.params['p_cambios'] as Map)['prerequisites']
              as List);
      expect(sent, hasLength(1));
      expect((sent.single as Map)['course_id'], selected.courseId);
      await expectLater(
        repository.confirmRelationshipBatch(
          review: review,
          prerequisites: [review.prerequisites.last],
        ),
        throwsArgumentError,
      );
      expect(
        rpc.calls.where(
          (call) => call.function == 'gestionar_revision_malla_multimodal',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'confirma certificación padre y membresías seleccionadas juntas',
    () async {
      final review = _review(mallaId: 'saved-id');
      final certification = review.certifications.single;
      final selected = certification.memberships.last
        ..decision = MallaProposalDecision.suggested;
      final response = _response(codec.encode(review));
      final storedCertification =
          (response['certifications'] as List).single as Map;
      storedCertification['decision'] = 'accepted';
      final storedMembership =
          (storedCertification['memberships'] as List).last as Map;
      storedMembership['decision'] = 'accepted';
      storedMembership['pending_reasons'] = <String>[];
      final rpc = _FakeRpc((function, _) async {
        if (function == 'gestionar_revision_malla_multimodal') {
          return {'malla_id': 'saved-id'};
        }
        return response;
      });

      final saved = await _repository(rpc).confirmRelationshipBatch(
        review: review,
        certifications: [
          MallaCertificationBatchSelection(
            certification: certification,
            memberships: [selected],
          ),
        ],
      );

      expect(
        saved.certifications.single.decision,
        MallaProposalDecision.accepted,
      );
      expect(
        saved.certifications.single.memberships.last.decision,
        MallaProposalDecision.accepted,
      );
      final changes = rpc.calls.first.params['p_cambios'] as Map;
      expect(changes['certifications'], [
        {'id': 'cert_1', 'decision': 'accepted'},
      ]);
      expect(changes['memberships'], [
        {
          'certification_id': 'cert_1',
          'course_id': 'gemini_1',
          'decision': 'accepted',
        },
      ]);
    },
  );

  test('fallo batch no recarga ni altera decisiones locales', () async {
    final review = _review(mallaId: 'saved-id');
    final selected = review.prerequisites.first;
    final rpc = _FakeRpc((function, _) async {
      if (function == 'gestionar_revision_malla_multimodal') {
        throw const PostgrestException(message: 'denied', code: '42501');
      }
      fail('No debe recargar después del error.');
    });

    await expectLater(
      _repository(rpc)
          .confirmRelationshipBatch(review: review, prerequisites: [selected]),
      throwsA(isA<PostgrestException>()),
    );

    expect(selected.decision, MallaProposalDecision.suggested);
    expect(rpc.calls, hasLength(1));
  });

  for (final decision in const [
    MallaProposalDecision.accepted,
    MallaProposalDecision.rejected,
  ]) {
    test('gestiona y recupera prerrequisito ${decision.name}', () async {
      final response = _response(codec.encode(_review()));
      final relation = (response['prerequisites'] as List).first as Map;
      relation['decision'] = decision.name;
      relation['pending_reasons'] = <String>[];
      final rpc = _FakeRpc((function, params) async {
        if (function == 'gestionar_revision_malla_multimodal') {
          return {
            'malla_id': 'saved-id',
            'review_state': 'pending',
            'pending_count': 1,
          };
        }
        if (function == 'obtener_malla_multimodal') return response;
        fail('RPC inesperado: $function');
      });
      final repository = _repository(rpc);

      final saved = await repository.decidePrerequisite(
        mallaId: 'saved-id',
        courseId: 'vision_2',
        requiresCourseId: 'vision_1',
        decision: decision,
      );

      expect(saved.prerequisites.first.decision, decision);
      expect(rpc.calls.map((call) => call.function), [
        'gestionar_revision_malla_multimodal',
        'obtener_malla_multimodal',
      ]);
      final changes = rpc.calls.first.params['p_cambios'] as Map;
      final sent = (changes['prerequisites'] as List).single as Map;
      expect(sent, {
        'course_id': 'vision_2',
        'requires_course_id': 'vision_1',
        'result_course_id': 'vision_2',
        'result_requires_course_id': 'vision_1',
        'decision': decision.name,
      });
      expect(changes['memberships'], isEmpty);
      expect(changes['certifications'], isEmpty);
      expect(changes['academic_requirements'], isEmpty);
      expect(changes['pending_items'], isEmpty);
    });
  }

  test('bloquea decisiones de prerrequisito simultáneas', () async {
    final gate = Completer<void>();
    final response = _response(codec.encode(_review()));
    final relation = (response['prerequisites'] as List).first as Map;
    relation['decision'] = 'accepted';
    relation['pending_reasons'] = <String>[];
    final rpc = _FakeRpc((function, _) async {
      if (function == 'gestionar_revision_malla_multimodal') {
        await gate.future;
        return {'malla_id': 'saved-id'};
      }
      return response;
    });
    final repository = _repository(rpc);

    final first = repository.decidePrerequisite(
      mallaId: 'saved-id',
      courseId: 'vision_2',
      requiresCourseId: 'vision_1',
      decision: MallaProposalDecision.accepted,
    );
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      repository.decidePrerequisite(
        mallaId: 'saved-id',
        courseId: 'vision_2',
        requiresCourseId: 'vision_1',
        decision: MallaProposalDecision.rejected,
      ),
      throwsStateError,
    );
    gate.complete();
    await first;
    expect(
      rpc.calls.where(
        (call) => call.function == 'gestionar_revision_malla_multimodal',
      ),
      hasLength(1),
    );
  });

  test('no recarga ni aplica la decisión si cambia la cuenta', () async {
    var uid = 'firebase-user-a';
    final rpc = _FakeRpc((function, _) async {
      if (function == 'gestionar_revision_malla_multimodal') {
        uid = 'firebase-user-b';
        return {'malla_id': 'saved-id'};
      }
      fail('No debe recuperar datos con otra sesión.');
    });
    final repository = _repository(rpc, uidProvider: () => uid);

    await expectLater(
      repository.decidePrerequisite(
        mallaId: 'saved-id',
        courseId: 'vision_2',
        requiresCourseId: 'vision_1',
        decision: MallaProposalDecision.accepted,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'mensaje',
          contains('sesión cambió'),
        ),
      ),
    );
    expect(rpc.calls, hasLength(1));
  });

  for (final decision in const [
    MallaProposalDecision.accepted,
    MallaProposalDecision.rejected,
  ]) {
    test('gestiona y recupera membresía ${decision.name}', () async {
      final response = _response(codec.encode(_review()));
      final certification = (response['certifications'] as List).single as Map;
      final membership = (certification['memberships'] as List).last as Map;
      membership['decision'] = decision.name;
      membership['pending_reasons'] = <String>[];
      final rpc = _FakeRpc((function, _) async {
        if (function == 'gestionar_revision_malla_multimodal') {
          return {'malla_id': 'saved-id'};
        }
        if (function == 'obtener_malla_multimodal') return response;
        fail('RPC inesperado: $function');
      });
      final repository = _repository(rpc);

      final saved = await repository.decideMembership(
        mallaId: 'saved-id',
        certificationId: 'cert_1',
        courseId: 'gemini_1',
        decision: decision,
      );

      expect(saved.certifications.single.memberships.last.decision, decision);
      expect(rpc.calls.map((call) => call.function), [
        'gestionar_revision_malla_multimodal',
        'obtener_malla_multimodal',
      ]);
      final changes = rpc.calls.first.params['p_cambios'] as Map;
      expect((changes['memberships'] as List).single, {
        'certification_id': 'cert_1',
        'course_id': 'gemini_1',
        'decision': decision.name,
      });
      expect(changes['prerequisites'], isEmpty);
      expect(changes['certifications'], isEmpty);
      expect(changes['academic_requirements'], isEmpty);
      expect(changes['pending_items'], isEmpty);
    });
  }

  test('bloquea membresías simultáneas y otras revisiones', () async {
    final gate = Completer<void>();
    final response = _response(codec.encode(_review()));
    final certification = (response['certifications'] as List).single as Map;
    final membership = (certification['memberships'] as List).last as Map;
    membership['decision'] = 'accepted';
    membership['pending_reasons'] = <String>[];
    final rpc = _FakeRpc((function, _) async {
      if (function == 'gestionar_revision_malla_multimodal') {
        await gate.future;
        return {'malla_id': 'saved-id'};
      }
      return response;
    });
    final repository = _repository(rpc);

    final first = repository.decideMembership(
      mallaId: 'saved-id',
      certificationId: 'cert_1',
      courseId: 'gemini_1',
      decision: MallaProposalDecision.accepted,
    );
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      repository.decideMembership(
        mallaId: 'saved-id',
        certificationId: 'cert_1',
        courseId: 'gemini_1',
        decision: MallaProposalDecision.rejected,
      ),
      throwsStateError,
    );
    await expectLater(
      repository.decidePrerequisite(
        mallaId: 'saved-id',
        courseId: 'vision_2',
        requiresCourseId: 'vision_1',
        decision: MallaProposalDecision.accepted,
      ),
      throwsStateError,
    );
    gate.complete();
    await first;
    expect(
      rpc.calls.where(
        (call) => call.function == 'gestionar_revision_malla_multimodal',
      ),
      hasLength(1),
    );
  });

  test('no aplica membresía si cambia la cuenta', () async {
    var uid = 'firebase-user-a';
    final rpc = _FakeRpc((function, _) async {
      if (function == 'gestionar_revision_malla_multimodal') {
        uid = 'firebase-user-b';
        return {'malla_id': 'saved-id'};
      }
      fail('No debe recuperar datos con otra sesión.');
    });
    final repository = _repository(rpc, uidProvider: () => uid);

    await expectLater(
      repository.decideMembership(
        mallaId: 'saved-id',
        certificationId: 'cert_1',
        courseId: 'gemini_1',
        decision: MallaProposalDecision.accepted,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'mensaje',
          contains('sesión cambió'),
        ),
      ),
    );
    expect(rpc.calls, hasLength(1));
  });

  for (final decision in const [
    MallaProposalDecision.accepted,
    MallaProposalDecision.rejected,
  ]) {
    test('gestiona y recupera requisito ${decision.name}', () async {
      final response = _response(codec.encode(_review()));
      final requirement =
          (response['academic_requirements'] as List).single as Map;
      requirement['type'] = 'capstone_eligibility';
      requirement['decision'] = decision.name;
      requirement['pending_reasons'] = <String>[];
      final rpc = _FakeRpc((function, _) async {
        if (function == 'gestionar_revision_malla_multimodal') {
          return {'malla_id': 'saved-id'};
        }
        if (function == 'obtener_malla_multimodal') return response;
        fail('RPC inesperado: $function');
      });
      final repository = _repository(rpc);

      final saved = await repository.decideAcademicRequirement(
        mallaId: 'saved-id',
        requirementId: 'req_1',
        type: 'capstone_eligibility',
        decision: decision,
      );

      expect(saved.academicRequirements.single.decision, decision);
      expect(
        saved.academicRequirements.single.requirement.type,
        'capstone_eligibility',
      );
      expect(rpc.calls.map((call) => call.function), [
        'gestionar_revision_malla_multimodal',
        'obtener_malla_multimodal',
      ]);
      final changes = rpc.calls.first.params['p_cambios'] as Map;
      expect((changes['academic_requirements'] as List).single, {
        'id': 'req_1',
        'type': 'capstone_eligibility',
        'decision': decision.name,
      });
      expect(changes['prerequisites'], isEmpty);
      expect(changes['certifications'], isEmpty);
      expect(changes['memberships'], isEmpty);
      expect(changes['pending_items'], isEmpty);
    });
  }

  test('no confirma requisitos de tipo unknown', () async {
    final rpc = _FakeRpc((_, _) async => fail('No debe invocar Supabase'));
    final repository = _repository(rpc);

    await expectLater(
      repository.decideAcademicRequirement(
        mallaId: 'saved-id',
        requirementId: 'req_1',
        type: ' UnKnOwN ',
        decision: MallaProposalDecision.accepted,
      ),
      throwsA(isA<MallaMultimodalValidationException>()),
    );
    expect(rpc.calls, isEmpty);
  });

  test('bloquea requisitos simultáneos y otras revisiones', () async {
    final gate = Completer<void>();
    final response = _response(codec.encode(_review()));
    final requirement =
        (response['academic_requirements'] as List).single as Map;
    requirement['type'] = 'capstone_eligibility';
    requirement['decision'] = 'accepted';
    requirement['pending_reasons'] = <String>[];
    final rpc = _FakeRpc((function, _) async {
      if (function == 'gestionar_revision_malla_multimodal') {
        await gate.future;
        return {'malla_id': 'saved-id'};
      }
      return response;
    });
    final repository = _repository(rpc);

    final first = repository.decideAcademicRequirement(
      mallaId: 'saved-id',
      requirementId: 'req_1',
      type: 'capstone_eligibility',
      decision: MallaProposalDecision.accepted,
    );
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      repository.decideAcademicRequirement(
        mallaId: 'saved-id',
        requirementId: 'req_1',
        type: 'capstone_eligibility',
        decision: MallaProposalDecision.rejected,
      ),
      throwsStateError,
    );
    await expectLater(
      repository.decideMembership(
        mallaId: 'saved-id',
        certificationId: 'cert_1',
        courseId: 'gemini_1',
        decision: MallaProposalDecision.rejected,
      ),
      throwsStateError,
    );
    gate.complete();
    await first;
    expect(
      rpc.calls.where(
        (call) => call.function == 'gestionar_revision_malla_multimodal',
      ),
      hasLength(1),
    );
  });

  test('no aplica requisito si cambia la cuenta', () async {
    var uid = 'firebase-user-a';
    final rpc = _FakeRpc((function, _) async {
      if (function == 'gestionar_revision_malla_multimodal') {
        uid = 'firebase-user-b';
        return {'malla_id': 'saved-id'};
      }
      fail('No debe recuperar datos con otra sesión.');
    });
    final repository = _repository(rpc, uidProvider: () => uid);

    await expectLater(
      repository.decideAcademicRequirement(
        mallaId: 'saved-id',
        requirementId: 'req_1',
        type: 'capstone_eligibility',
        decision: MallaProposalDecision.accepted,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'mensaje',
          contains('sesión cambió'),
        ),
      ),
    );
    expect(rpc.calls, hasLength(1));
  });

  test('elimina la malla y verifica que ya no pueda recuperarse', () async {
    final rpc = _FakeRpc((function, params) async {
      if (function == 'eliminar_malla_curricular_confirmada') {
        expect(params['p_expected_uid'], 'firebase-user');
        expect(params['p_malla_id'], 'saved-id');
        return 'saved-id';
      }
      if (function == 'obtener_malla_multimodal') {
        throw const PostgrestException(
          message: 'malla_no_encontrada',
          code: 'P0002',
        );
      }
      fail('RPC inesperado: $function');
    });
    final repository = _repository(rpc);

    await repository.deleteConfirmed('saved-id');

    expect(rpc.calls.map((call) => call.function), [
      'eliminar_malla_curricular_confirmada',
      'obtener_malla_multimodal',
    ]);
  });

  for (final error in const [
    PostgrestException(message: 'uid_firebase_no_valido', code: '42501'),
    PostgrestException(message: 'malla_no_encontrada', code: 'P0002'),
  ]) {
    test('propaga rechazo de eliminación ${error.code}', () async {
      final rpc = _FakeRpc((function, _) async {
        expect(function, 'eliminar_malla_curricular_confirmada');
        throw error;
      });
      final repository = _repository(rpc);

      await expectLater(
        repository.deleteConfirmed('saved-id'),
        throwsA(
          isA<PostgrestException>().having(
            (failure) => failure.code,
            'code',
            error.code,
          ),
        ),
      );
      expect(rpc.calls, hasLength(1));
    });
  }

  test('bloquea eliminaciones duplicadas y otras escrituras', () async {
    final gate = Completer<void>();
    final rpc = _FakeRpc((function, _) async {
      if (function == 'eliminar_malla_curricular_confirmada') {
        await gate.future;
        return 'saved-id';
      }
      throw const PostgrestException(
        message: 'malla_no_encontrada',
        code: 'P0002',
      );
    });
    final repository = _repository(rpc);

    final first = repository.deleteConfirmed('saved-id');
    await Future<void>.delayed(Duration.zero);
    await expectLater(repository.deleteConfirmed('saved-id'), throwsStateError);
    await expectLater(
      repository.decidePrerequisite(
        mallaId: 'saved-id',
        courseId: 'vision_2',
        requiresCourseId: 'vision_1',
        decision: MallaProposalDecision.accepted,
      ),
      throwsStateError,
    );
    gate.complete();
    await first;
    expect(
      rpc.calls.where(
        (call) => call.function == 'eliminar_malla_curricular_confirmada',
      ),
      hasLength(1),
    );
  });

  test('no acepta eliminación si cambia la cuenta', () async {
    var uid = 'firebase-user-a';
    final rpc = _FakeRpc((function, _) async {
      expect(function, 'eliminar_malla_curricular_confirmada');
      uid = 'firebase-user-b';
      return 'saved-id';
    });
    final repository = _repository(rpc, uidProvider: () => uid);

    await expectLater(
      repository.deleteConfirmed('saved-id'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'mensaje',
          contains('sesión cambió'),
        ),
      ),
    );
    expect(rpc.calls, hasLength(1));
  });

  test('rechaza eliminación si la malla continúa recuperándose', () async {
    final response = _response(codec.encode(_review()));
    final rpc = _FakeRpc((function, _) async {
      if (function == 'eliminar_malla_curricular_confirmada') {
        return 'saved-id';
      }
      return response;
    });
    final repository = _repository(rpc);

    await expectLater(
      repository.deleteConfirmed('saved-id'),
      throwsFormatException,
    );
  });

  test('confirma ausencia de código y recupera los demás pendientes', () async {
    final review = _review(mallaId: 'saved-id');
    final response = _response(codec.encode(review));
    final course = (response['courses'] as List).singleWhere(
      (item) => (item as Map)['id'] == 'gemini_1',
    ) as Map;
    course['review_reasons'] = ['low_ocr_confidence'];
    course['review_state'] = 'pending';
    final rpc = _FakeRpc((function, params) async {
      if (function == 'confirmar_ramo_sin_codigo_malla') {
        expect(params['p_expected_uid'], 'firebase-user');
        expect(params['p_malla_id'], 'saved-id');
        expect(params['p_ramo_id'], 'gemini_1');
        return {'malla_id': 'saved-id', 'ramo_id': 'gemini_1'};
      }
      if (function == 'obtener_malla_multimodal') return response;
      fail('RPC inesperado: $function');
    });

    final saved = await _repository(rpc)
        .confirmCourseWithoutCode(mallaId: 'saved-id', courseId: 'gemini_1');

    expect(saved.courseById('gemini_1')!.codigo, isNull);
    expect(saved.courseById('gemini_1')!.motivosRevision, [
      'low_ocr_confidence',
    ]);
    expect(rpc.calls.map((call) => call.function), [
      'confirmar_ramo_sin_codigo_malla',
      'obtener_malla_multimodal',
    ]);
  });

  test('rechaza falso éxito si code_missing continúa recuperado', () async {
    final review = _review(mallaId: 'saved-id');
    final response = _response(codec.encode(review));
    final rpc = _FakeRpc((function, _) async {
      if (function == 'confirmar_ramo_sin_codigo_malla') {
        return {'malla_id': 'saved-id', 'ramo_id': 'gemini_1'};
      }
      return response;
    });

    await expectLater(
      _repository(rpc)
          .confirmCourseWithoutCode(mallaId: 'saved-id', courseId: 'gemini_1'),
      throwsFormatException,
    );
  });

  test(
    'edita requisito y conserva identidad, origen, destino y evidencia',
    () async {
      final review = _review(mallaId: 'saved-id');
      final proposal = review.academicRequirements.single;
      final base = proposal.requirement;
      proposal.requirement = MallaAcademicRequirement(
        id: base.id,
        type: base.type,
        targetCourseId: base.targetCourseId,
        targetLabel: base.targetLabel,
        description: base.description,
        minimumLevel: base.minimumLevel,
        evidence: base.evidence,
        pendingReasons: base.pendingReasons,
        source: 'manual',
      );
      final original = proposal.requirement;
      final payload = codec.encode(review);
      final requirement =
          (payload['academic_requirements'] as List).single as Map;
      requirement['description'] = 'Niveles I a VI aprobados';
      requirement['minimum_level'] = 6;
      requirement['decision'] = 'pending';
      requirement['pending_reasons'] = ['manual_confirmation_required'];
      final response = _response(payload);
      final rpc = _FakeRpc((function, params) async {
        if (function == 'editar_requisito_academico_malla') {
          expect(params['p_expected_uid'], 'firebase-user');
          expect(params['p_requisito_id'], 'req_1');
          expect(params['p_descripcion'], 'Niveles I a VI aprobados');
          expect(params['p_nivel_minimo'], 6);
          return {'malla_id': 'saved-id', 'requisito_id': 'req_1'};
        }
        if (function == 'obtener_malla_multimodal') return response;
        fail('RPC inesperado: $function');
      });

      final saved = await _repository(rpc).updateAcademicRequirement(
        mallaId: 'saved-id',
        requirement: original,
        description: '  Niveles I a VI aprobados  ',
        minimumLevel: 6,
      );

      final updated = saved.academicRequirements.single;
      expect(updated.requirement.id, original.id);
      expect(updated.requirement.type, original.type);
      expect(updated.requirement.targetCourseId, original.targetCourseId);
      expect(updated.requirement.source, original.source);
      expect(updated.requirement.evidence, original.evidence);
      expect(updated.requirement.description, 'Niveles I a VI aprobados');
      expect(updated.requirement.minimumLevel, 6);
      expect(updated.decision, MallaProposalDecision.pending);
    },
  );

  test(
    'actualiza solo el requisito seleccionado y lo conserva al recargar',
    () async {
      final review = _review(mallaId: 'saved-id');
      final laboral = MallaAcademicRequirementProposal(
        requirement: const MallaAcademicRequirement(
          id: 'gemini_requirement_ac4e4ff0c503672615aa',
          type: 'practice_eligibility',
          targetCourseId: 'vision_1',
          targetLabel: 'Práctica Laboral',
          description: 'Requiere I a IV nivel aprobado',
          minimumLevel: 4,
          evidence: ['Rótulo conectado a PLY4614'],
          pendingReasons: ['requirement_confirmation_pending'],
        ),
      );
      final profesional = MallaAcademicRequirementProposal(
        requirement: const MallaAcademicRequirement(
          id: 'gemini_requirement_6e93db9c4251ce6fb50b',
          type: 'practice_eligibility',
          targetCourseId: 'vision_2',
          targetLabel: 'Práctica Profesional',
          description: 'Requiere I a IV nivel aprobado',
          minimumLevel: 6,
          evidence: ['Rótulo conectado a PPY4614'],
          pendingReasons: ['requirement_confirmation_pending'],
        ),
      );
      review.academicRequirements
        ..clear()
        ..addAll([laboral, profesional]);
      final storedPayload = codec.encode(review);
      final rpc = _FakeRpc((function, params) async {
        if (function == 'editar_requisito_academico_malla') {
          expect(
            params['p_requisito_id'],
            'gemini_requirement_ac4e4ff0c503672615aa',
          );
          expect(
            params['p_descripcion'],
            'Debe tener aprobados los niveles I a IV',
          );
          expect(params['p_nivel_minimo'], 4);
          final requirements = storedPayload['academic_requirements'] as List;
          final storedLaboral = requirements.singleWhere(
            (item) => (item as Map)['id'] == params['p_requisito_id'],
          ) as Map;
          storedLaboral['description'] = params['p_descripcion'];
          storedLaboral['minimum_level'] = params['p_nivel_minimo'];
          storedLaboral['decision'] = 'pending';
          storedLaboral['pending_reasons'] = ['manual_confirmation_required'];
          return {
            'malla_id': 'saved-id',
            'requisito_id': 'gemini_requirement_ac4e4ff0c503672615aa',
          };
        }
        if (function == 'obtener_malla_multimodal') {
          final freshPayload = Map<String, dynamic>.from(
            jsonDecode(jsonEncode(storedPayload)) as Map,
          );
          return _response(freshPayload);
        }
        fail('RPC inesperado: $function');
      });

      final saved = await _repository(rpc).updateAcademicRequirement(
        mallaId: 'saved-id',
        requirement: laboral.requirement,
        description: 'Debe tener aprobados los niveles I a IV',
        minimumLevel: 4,
      );

      final savedLaboral = saved.academicRequirements.singleWhere(
        (item) =>
            item.requirement.id == 'gemini_requirement_ac4e4ff0c503672615aa',
      );
      final savedProfesional = saved.academicRequirements.singleWhere(
        (item) =>
            item.requirement.id == 'gemini_requirement_6e93db9c4251ce6fb50b',
      );
      expect(
        savedLaboral.requirement.description,
        'Debe tener aprobados los niveles I a IV',
      );
      expect(savedLaboral.requirement.minimumLevel, 4);
      expect(savedLaboral.requirement.evidence, laboral.requirement.evidence);
      expect(savedLaboral.requirement.source, laboral.requirement.source);
      expect(savedLaboral.decision, MallaProposalDecision.pending);
      expect(
        savedProfesional.requirement.description,
        'Requiere I a IV nivel aprobado',
      );
      expect(savedProfesional.requirement.minimumLevel, 6);

      final reloaded = await _repository(rpc).load();
      final reloadedLaboral = reloaded!.academicRequirements.singleWhere(
        (item) =>
            item.requirement.id == 'gemini_requirement_ac4e4ff0c503672615aa',
      );
      expect(
        reloadedLaboral.requirement.description,
        'Debe tener aprobados los niveles I a IV',
      );
      expect(reloadedLaboral.requirement.minimumLevel, 4);
      expect(
        reloadedLaboral.requirement.evidence,
        laboral.requirement.evidence,
      );
      expect(reloadedLaboral.requirement.source, laboral.requirement.source);
      expect(reloadedLaboral.decision, MallaProposalDecision.pending);
    },
  );

  test(
    'rechaza éxito si Supabase conserva la descripción anterior del ID real',
    () async {
      final review = _review(mallaId: 'saved-id');
      final laboral = MallaAcademicRequirementProposal(
        requirement: const MallaAcademicRequirement(
          id: 'gemini_requirement_ac4e4ff0c503672615aa',
          type: 'practice_eligibility',
          targetCourseId: 'vision_1',
          targetLabel: 'Práctica Laboral',
          description: 'Requiere I a IV nivel aprobado',
          minimumLevel: 4,
          evidence: ['Rótulo conectado a PLY4614'],
          pendingReasons: ['manual_confirmation_required'],
        ),
      );
      review.academicRequirements
        ..clear()
        ..add(laboral);
      final unchangedResponse = _response(codec.encode(review));
      final rpc = _FakeRpc((function, params) async {
        if (function == 'editar_requisito_academico_malla') {
          expect(
            params['p_requisito_id'],
            'gemini_requirement_ac4e4ff0c503672615aa',
          );
          expect(
            params['p_descripcion'],
            'Debe tener aprobados los niveles I a IV',
          );
          return {
            'malla_id': 'saved-id',
            'requisito_id': 'gemini_requirement_ac4e4ff0c503672615aa',
          };
        }
        if (function == 'obtener_malla_multimodal') {
          return unchangedResponse;
        }
        fail('RPC inesperado: $function');
      });

      await expectLater(
        _repository(rpc).updateAcademicRequirement(
          mallaId: 'saved-id',
          requirement: laboral.requirement,
          description: 'Debe tener aprobados los niveles I a IV',
          minimumLevel: 4,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(rpc.calls, hasLength(2));
    },
  );

  test('rechaza nivel contradictorio antes de invocar Supabase', () async {
    final rpc = _FakeRpc((_, _) async => fail('No debe invocar Supabase'));
    final requirement = _review().academicRequirements.single.requirement;

    await expectLater(
      _repository(rpc).updateAcademicRequirement(
        mallaId: 'saved-id',
        requirement: requirement,
        description: 'Niveles aprobados',
        minimumLevel: 31,
      ),
      throwsArgumentError,
    );
    expect(rpc.calls, isEmpty);
  });

  test('detecta pérdida de evidencia al recuperar requisito editado', () async {
    final review = _review(mallaId: 'saved-id');
    final original = review.academicRequirements.single.requirement;
    final payload = codec.encode(review);
    final requirement =
        (payload['academic_requirements'] as List).single as Map;
    requirement['description'] = 'Niveles aprobados';
    requirement['minimum_level'] = 6;
    requirement['decision'] = 'pending';
    requirement['pending_reasons'] = ['manual_confirmation_required'];
    requirement['evidence'] = ['Evidencia alterada'];
    final response = _response(payload);
    final rpc = _FakeRpc((function, _) async {
      if (function == 'editar_requisito_academico_malla') {
        return {'malla_id': 'saved-id', 'requisito_id': 'req_1'};
      }
      return response;
    });

    await expectLater(
      _repository(rpc).updateAcademicRequirement(
        mallaId: 'saved-id',
        requirement: original,
        description: 'Niveles aprobados',
        minimumLevel: 6,
      ),
      throwsFormatException,
    );
  });

  test('propaga rechazo de permisos sin intentar recuperación', () async {
    final rpc = _FakeRpc((function, _) async {
      expect(function, 'editar_requisito_academico_malla');
      throw const PostgrestException(message: 'denegado', code: '42501');
    });

    await expectLater(
      _repository(rpc).updateAcademicRequirement(
        mallaId: 'saved-id',
        requirement: _review().academicRequirements.single.requirement,
        description: 'Niveles aprobados',
        minimumLevel: 6,
      ),
      throwsA(isA<PostgrestException>()),
    );
    expect(rpc.calls, hasLength(1));
  });
}

MallaMultimodalPersistenceRepository _repository(
  _FakeRpc rpc, {
  String firebaseProject = 'eduflow-ai-testing',
  String supabaseProject = 'testing-ref',
  MallaMultimodalPersistenceConfig config =
      const MallaMultimodalPersistenceConfig(
        requested: true,
        expectedFirebaseProjectId: 'eduflow-ai-testing',
        expectedSupabaseProjectRef: 'testing-ref',
      ),
  String? Function()? uidProvider,
}) => MallaMultimodalPersistenceRepository(
  rpc: rpc,
  uidProvider: uidProvider ?? () => 'firebase-user',
  firebaseProjectIdProvider: () => firebaseProject,
  supabaseProjectRef: supabaseProject,
  config: config,
);

Map<String, dynamic> _response(
  Map<String, dynamic> payload, {
  String id = 'saved-id',
  String fileName = 'malla.pdf',
}) => {
  'id': id,
  'file_name': fileName,
  'period_type': payload['period_type'],
  'period_count': payload['period_count'],
  'import_source': 'multimodal',
  'review_state': 'pending',
  'confirmed_at': '2026-11-11T00:00:00Z',
  'courses': [
    for (final value in payload['courses'] as List)
      {
        ...Map<String, dynamic>.from(value as Map),
        'duplicate_code_verified': false,
      },
  ],
  'prerequisites': payload['prerequisites'],
  'certifications': payload['certifications'],
  'academic_requirements': payload['academic_requirements'],
  'pending_items': payload['pending_items'],
};

MallaImportReview _review({
  String periodType = 'semester',
  int periodCount = 8,
  String fileName = 'malla.pdf',
  String mallaId = '',
}) {
  final courses = [
    RamoMalla(
      id: 'vision_1',
      nombre: 'Fundamentos',
      semestre: 1,
      codigo: 'INF1001',
      creditos: 6,
    ),
    RamoMalla(
      id: 'vision_2',
      nombre: 'Programación',
      semestre: 2,
      codigo: 'INF2001',
      creditos: 8,
    ),
    RamoMalla(
      id: 'gemini_1',
      nombre: 'Curso adicional',
      semestre: 3,
      creditos: 4,
      requiereRevision: true,
      motivosRevision: ['code_missing'],
    ),
  ];
  final changes = [
    for (final course in courses)
      MallaCourseChangeProposal(
        review: MallaCourseReview(
          courseId: course.id,
          proposedName: course.nombre,
          proposedCode: course.codigo,
          proposedCredits: course.creditos,
          proposedPeriod: course.semestre,
          category: course.id == 'gemini_1' ? 'institutional' : 'specialty',
          categoryLabel: course.id == 'gemini_1'
              ? 'Formación institucional'
              : 'Especialidad',
          prerequisiteStatus: 'unknown',
          evidence: ['Bloque visible'],
          pendingReasons: course.motivosRevision,
        ),
        originalName: course.nombre,
        originalCode: course.codigo,
        originalCredits: course.creditos,
        originalPeriod: course.semestre,
        automaticallyAppliedFields: const {},
        attentionReasons: course.motivosRevision,
      ),
  ];
  final prerequisiteSuggested = MallaPrerequisiteProposal(
    courseId: 'vision_2',
    requiresCourseId: 'vision_1',
    evidence: ['Flecha inequívoca'],
    pendingReasons: const [],
  );
  final prerequisiteRejected = MallaPrerequisiteProposal(
    courseId: 'gemini_1',
    requiresCourseId: 'vision_1',
    evidence: ['Línea cercana'],
    pendingReasons: const ['arrow_endpoint_uncertain'],
  )..decision = MallaProposalDecision.rejected;
  final membershipAccepted = MallaCertificationMembershipProposal(
    courseId: 'vision_1',
    basis: 'container',
    evidence: const ['Dentro del contenedor'],
  )..decision = MallaProposalDecision.accepted;
  final membershipRejected = MallaCertificationMembershipProposal(
    courseId: 'gemini_1',
    basis: 'outside_container',
    evidence: const ['Fuera del contenedor'],
  )..decision = MallaProposalDecision.rejected;

  return MallaImportReview(
    malla: MallaCurricular(
      id: mallaId,
      archivoNombre: fileName,
      ramos: courses,
    ),
    periodType: periodType,
    periodCount: periodCount,
    periodEvidence: const ['Columnas visibles'],
    geminiCourseIds: {'gemini_1'},
    courseChanges: changes,
    prerequisites: [prerequisiteSuggested, prerequisiteRejected],
    certifications: [
      MallaCertificationProposal(
        id: 'cert_1',
        name: 'Certificado de Desarrollo',
        evidence: const ['Contenedor visible'],
        memberships: [membershipAccepted, membershipRejected],
      ),
    ],
    academicRequirements: [
      MallaAcademicRequirementProposal(
        requirement: const MallaAcademicRequirement(
          id: 'req_1',
          type: 'unknown',
          targetCourseId: 'gemini_1',
          targetLabel: 'Curso adicional',
          description: 'Niveles previos aprobados',
          minimumLevel: 4,
          evidence: ['Nota al pie'],
          pendingReasons: ['requirement_type_uncertain'],
        ),
      ),
    ],
    globalPending: const [],
    deduplicatedAdditionalCourses: const [],
  );
}
