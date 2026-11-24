import 'dart:convert';

import 'package:eduflow_ai/core/config/app_environment_config.dart';
import 'package:eduflow_ai/services/malla_multimodal_persistence_service.dart';
import 'package:eduflow_ai/services/malla_multimodal_testing_fixture.dart';
import 'package:eduflow_ai/services/malla_multimodal_write_diagnostic_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _uidA = 'firebase-user-a';
const _mallaA = '11111111-1111-4111-8111-111111111111';
const _mallaB = '22222222-2222-4222-8222-222222222222';
const _firebaseProject = 'eduflow-ai-testing';
const _supabaseProject = 'oxrvksaljxcwdhkeapej';

class _FakeClient implements MallaWriteDiagnosticClient {
  final calls = <(String, Map<String, dynamic>)>[];
  bool mutateAfterWrite = false;
  bool unsafeCandidate = false;
  var wroteOwnMalla = false;

  Map<String, dynamic> get snapshot => {
    'id': _mallaA,
    'review_state': 'pending',
    'courses': const [],
    'prerequisites': const [
      {
        'course_id': 'testing_proyecto',
        'requires_course_id': 'testing_programacion',
        'source': 'gemini',
        'decision': 'accepted',
        'certainty': 'confirmed',
        'evidence': ['Flecha directa'],
        'pending_reasons': [],
      },
    ],
    'certifications': const [],
    'academic_requirements': const [],
    'pending_items': const [
      {
        'id': 'pending_1',
        'entity_type': 'course',
        'entity_key': 'testing_etica',
        'reasons': ['manual_verification'],
        'evidence': [],
        'status': 'pending',
        'resolution': null,
      },
    ],
    if (mutateAfterWrite && wroteOwnMalla) 'file_name': 'cambio-inesperado',
  };

  @override
  Future<List<Map<String, dynamic>>> ownMallas() async => const [
    {'usuario_uid': _uidA, 'id': _mallaA},
  ];

  @override
  Future<List<Map<String, dynamic>>> acceptedPrerequisites(
    String mallaId,
  ) async => [
    {
      'usuario_uid': _uidA,
      'malla_id': _mallaA,
      'ramo_id': 'testing_proyecto',
      'requisito_ramo_id': 'testing_programacion',
      'procedencia': 'gemini',
      'decision': 'accepted',
      'certeza': 'confirmed',
      'evidencias': const ['Flecha directa'],
      'motivos_pendientes': unsafeCandidate
          ? const ['ambiguous_arrow']
          : const [],
      'corregida_manualmente': false,
    },
  ];

  @override
  Future<dynamic> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    if (function == 'obtener_malla_multimodal') {
      return jsonDecode(jsonEncode(snapshot));
    }
    if (params['p_expected_uid'] != _uidA) {
      throw const PostgrestException(
        message: 'uid_firebase_no_valido',
        code: '42501',
      );
    }
    if (params['p_malla_id'] == _mallaB) {
      throw const PostgrestException(
        message: 'malla_no_encontrada',
        code: 'P0002',
      );
    }
    wroteOwnMalla = true;
    return {'malla_id': _mallaA, 'review_state': 'pending', 'pending_count': 1};
  }
}

MallaMultimodalWriteDiagnosticService _service(
  _FakeClient client, {
  bool requested = true,
  bool debugMode = true,
  bool android = true,
  EducFlowEnvironment environment = EducFlowEnvironment.testing,
  String firebaseProject = _firebaseProject,
  String supabaseProject = _supabaseProject,
  bool persistenceRequested = true,
  bool sampleRequested = true,
  String? Function()? currentUidProvider,
}) => MallaMultimodalWriteDiagnosticService(
  client: client,
  identityProvider: () async => const MallaWriteFirebaseIdentity(
    uid: _uidA,
    hasIdToken: true,
    authenticatedRole: true,
  ),
  currentUidProvider: currentUidProvider ?? () => _uidA,
  firebaseProjectIdProvider: () => firebaseProject,
  supabaseProjectRef: supabaseProject,
  diagnosticConfig: MallaWriteDiagnosticConfig(requested: requested),
  testingConfig: MallaMultimodalTestingConfig(requested: sampleRequested),
  persistenceConfig: MallaMultimodalPersistenceConfig(
    requested: persistenceRequested,
    expectedFirebaseProjectId: _firebaseProject,
    expectedSupabaseProjectRef: _supabaseProject,
  ),
  debugMode: debugMode,
  android: android,
  appEnvironment: environment,
);

void main() {
  test(
    'valida escritura idempotente y ambos rechazos sin alterar datos',
    () async {
      final client = _FakeClient();

      final result = await _service(client).run(_mallaB);

      expect(result.ownMallaId, _mallaA);
      expect(result.foreignMallaId, _mallaB);
      expect(result.prerequisiteKey, 'testing_proyecto>testing_programacion');
      expect(result.pendingCount, 1);
      expect(result.reviewState, 'pending');
      expect(client.wroteOwnMalla, isTrue);
      final writes = client.calls
          .where((call) => call.$1 == 'gestionar_revision_malla_multimodal')
          .toList();
      expect(writes, hasLength(3));
      expect(writes[0].$2['p_expected_uid'], 'diagnostic_uid_incorrecto');
      expect(writes[1].$2['p_malla_id'], _mallaB);
      expect(writes[2].$2['p_malla_id'], _mallaA);
      expect(
        result.safeReport(spanish: true),
        allOf(contains('Datos antes/después: idénticos'), contains('APROBADO')),
      );
    },
  );

  test('se detiene si no puede demostrar una operación idempotente', () async {
    final client = _FakeClient()..unsafeCandidate = true;

    await expectLater(
      _service(client).run(_mallaB),
      throwsA(
        isA<MallaWriteDiagnosticException>().having(
          (error) => error.safeMessage,
          'mensaje',
          contains('sin cambios'),
        ),
      ),
    );
    expect(
      client.calls.where(
        (call) => call.$1 == 'gestionar_revision_malla_multimodal',
      ),
      isEmpty,
    );
  });

  test('falla si la escritura idempotente altera la recuperación', () async {
    final client = _FakeClient()..mutateAfterWrite = true;

    await expectLater(
      _service(client).run(_mallaB),
      throwsA(
        isA<MallaWriteDiagnosticException>().having(
          (error) => error.safeMessage,
          'mensaje',
          contains('alteró datos'),
        ),
      ),
    );
  });

  test('interrumpe si cambia la sesión durante las operaciones', () async {
    var checks = 0;
    await expectLater(
      _service(
        _FakeClient(),
        currentUidProvider: () => checks++ < 2 ? _uidA : 'firebase-user-b',
      ).run(_mallaB),
      throwsA(
        isA<MallaWriteDiagnosticException>().having(
          (error) => error.safeMessage,
          'mensaje',
          contains('sesión cambió'),
        ),
      ),
    );
  });

  test('permanece oculto si falta cualquier protección de Testing', () {
    expect(_service(_FakeClient()).enabled, isTrue);
    expect(_service(_FakeClient(), requested: false).enabled, isFalse);
    expect(_service(_FakeClient(), debugMode: false).enabled, isFalse);
    expect(_service(_FakeClient(), android: false).enabled, isFalse);
    expect(
      _service(
        _FakeClient(),
        environment: EducFlowEnvironment.production,
      ).enabled,
      isFalse,
    );
    expect(
      _service(_FakeClient(), firebaseProject: 'educflow-ai').enabled,
      isFalse,
    );
    expect(
      _service(_FakeClient(), supabaseProject: 'production-ref').enabled,
      isFalse,
    );
    expect(
      _service(_FakeClient(), persistenceRequested: false).enabled,
      isFalse,
    );
    expect(_service(_FakeClient(), sampleRequested: false).enabled, isFalse);
  });
}
