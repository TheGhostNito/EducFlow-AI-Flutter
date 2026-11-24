import 'package:eduflow_ai/core/config/app_environment_config.dart';
import 'package:eduflow_ai/services/malla_multimodal_persistence_service.dart';
import 'package:eduflow_ai/services/malla_multimodal_rls_diagnostic_service.dart';
import 'package:eduflow_ai/services/malla_multimodal_testing_fixture.dart';
import 'package:flutter_test/flutter_test.dart';

const _uidA = 'firebase-user-a';
const _mallaA = '11111111-1111-4111-8111-111111111111';
const _mallaB = '22222222-2222-4222-8222-222222222222';
const _firebaseProject = 'eduflow-ai-testing';
const _supabaseProject = 'oxrvksaljxcwdhkeapej';

class _SelectCall {
  const _SelectCall(
    this.table,
    this.columns,
    this.equalsColumn,
    this.equalsValue,
  );

  final String table;
  final String columns;
  final String? equalsColumn;
  final Object? equalsValue;
}

class _FakeReadClient implements MallaRlsReadClient {
  final calls = <_SelectCall>[];
  final Map<String, List<Map<String, dynamic>>> responses = {};

  String key(String table, Object? equalsValue) => '$table|$equalsValue';

  @override
  Future<List<Map<String, dynamic>>> select(
    String table,
    String columns, {
    String? equalsColumn,
    Object? equalsValue,
  }) async {
    calls.add(_SelectCall(table, columns, equalsColumn, equalsValue));
    return responses[key(table, equalsValue)] ?? const [];
  }
}

MallaMultimodalRlsDiagnosticService _service(
  _FakeReadClient reader, {
  MallaRlsFirebaseIdentity? identity = const MallaRlsFirebaseIdentity(
    uid: _uidA,
    hasIdToken: true,
    authenticatedRole: true,
  ),
  bool debugMode = true,
  bool android = true,
  EducFlowEnvironment environment = EducFlowEnvironment.testing,
  String firebaseProject = _firebaseProject,
  String supabaseProject = _supabaseProject,
  bool persistenceRequested = true,
  bool sampleRequested = true,
  String? Function()? currentUidProvider,
}) => MallaMultimodalRlsDiagnosticService(
  reader: reader,
  identityProvider: () async => identity,
  currentUidProvider: currentUidProvider ?? () => identity?.uid,
  firebaseProjectIdProvider: () => firebaseProject,
  supabaseProjectRef: supabaseProject,
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

void _configureOwnRows(_FakeReadClient reader) {
  reader.responses[reader.key('mallas_curriculares', null)] = const [
    {'usuario_uid': _uidA, 'id': _mallaA},
  ];
  for (final table in const [
    'ramos_malla',
    'prerrequisitos_malla',
    'certificaciones_malla',
    'membresias_certificacion_malla',
    'requisitos_academicos_malla',
    'pendientes_revision_malla',
  ]) {
    reader.responses[reader.key(table, _mallaA)] = [
      {'usuario_uid': _uidA, 'malla_id': _mallaA},
    ];
  }
}

void main() {
  test(
    'usa solo lecturas y oculta la malla ajena en todas las tablas',
    () async {
      final reader = _FakeReadClient();
      _configureOwnRows(reader);

      final result = await _service(reader).run(_mallaB);

      expect(result.passed, isTrue);
      expect(result.ownMallaId, _mallaA);
      expect(result.foreignMallaId, _mallaB);
      expect(result.ownRowsByTable.values, everyElement(1));
      expect(result.foreignRowsHidden.values, everyElement(isTrue));
      expect(reader.calls, hasLength(14));
      expect(
        reader.calls.map((call) => call.table).toSet(),
        containsAll(<String>{
          'mallas_curriculares',
          'ramos_malla',
          'prerrequisitos_malla',
          'certificaciones_malla',
          'membresias_certificacion_malla',
          'requisitos_academicos_malla',
          'pendientes_revision_malla',
        }),
      );
      expect(
        result.safeReport(spanish: true),
        allOf(
          contains('JWT Firebase activo: verificado'),
          contains('APROBADO'),
        ),
      );
    },
  );

  test(
    'falla si RLS expone una relación perteneciente a otra cuenta',
    () async {
      final reader = _FakeReadClient();
      _configureOwnRows(reader);
      reader.responses[reader.key('prerrequisitos_malla', _mallaB)] = const [
        {'usuario_uid': 'firebase-user-b', 'malla_id': _mallaB},
      ];

      await expectLater(
        _service(reader).run(_mallaB),
        throwsA(
          isA<MallaRlsDiagnosticException>().having(
            (error) => error.safeMessage,
            'mensaje seguro',
            contains('prerrequisitos_malla'),
          ),
        ),
      );
    },
  );

  test('rechaza la prueba antes de consultar si falta JWT o role', () async {
    for (final identity in [
      const MallaRlsFirebaseIdentity(
        uid: _uidA,
        hasIdToken: false,
        authenticatedRole: true,
      ),
      const MallaRlsFirebaseIdentity(
        uid: _uidA,
        hasIdToken: true,
        authenticatedRole: false,
      ),
    ]) {
      final reader = _FakeReadClient();
      await expectLater(
        _service(reader, identity: identity).run(_mallaB),
        throwsA(isA<MallaRlsDiagnosticException>()),
      );
      expect(reader.calls, isEmpty);
    }
  });

  test(
    'interrumpe de forma segura si la sesión cambia durante la lectura',
    () async {
      final reader = _FakeReadClient();
      _configureOwnRows(reader);
      var checks = 0;

      await expectLater(
        _service(
          reader,
          currentUidProvider: () => checks++ == 0 ? _uidA : 'firebase-user-b',
        ).run(_mallaB),
        throwsA(
          isA<MallaRlsDiagnosticException>().having(
            (error) => error.safeMessage,
            'mensaje seguro',
            contains('sesión cambió'),
          ),
        ),
      );
    },
  );

  test('solo se habilita con todas las protecciones de Android Testing', () {
    expect(_service(_FakeReadClient()).enabled, isTrue);
    expect(_service(_FakeReadClient(), debugMode: false).enabled, isFalse);
    expect(_service(_FakeReadClient(), android: false).enabled, isFalse);
    expect(
      _service(
        _FakeReadClient(),
        environment: EducFlowEnvironment.production,
      ).enabled,
      isFalse,
    );
    expect(
      _service(_FakeReadClient(), firebaseProject: 'educflow-ai').enabled,
      isFalse,
    );
    expect(
      _service(_FakeReadClient(), supabaseProject: 'production-ref').enabled,
      isFalse,
    );
    expect(
      _service(_FakeReadClient(), persistenceRequested: false).enabled,
      isFalse,
    );
    expect(
      _service(_FakeReadClient(), sampleRequested: false).enabled,
      isFalse,
    );
  });
}
