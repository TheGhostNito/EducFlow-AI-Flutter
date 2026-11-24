import 'package:eduflow_ai/core/config/app_environment_config.dart';
import 'package:eduflow_ai/services/malla_multimodal_persistence_service.dart';
import 'package:eduflow_ai/services/malla_multimodal_testing_fixture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = MallaMultimodalPersistenceCodec();

  test('fixture cumple el contrato académico y SQL multimodal', () {
    final review = MallaMultimodalTestingFixture.create();
    final payload = codec.encode(review);

    expect(review.malla.archivoNombre, 'malla-ejemplo-testing.json');
    expect(review.malla.ramos, hasLength(4));
    expect(review.periodType, 'semester');
    expect(review.periodCount, 3);
    expect(
      (payload['courses'] as List).map((item) => (item as Map)['category']),
      containsAll(['specialty', 'capstone', 'general_education']),
    );
    expect(
      (payload['courses'] as List).where(
        (item) => (item as Map)['review_state'] == 'pending',
      ),
      hasLength(1),
    );

    final prerequisites = payload['prerequisites'] as List;
    expect(prerequisites.map((item) => (item as Map)['decision']).toSet(), {
      'accepted',
      'suggested',
      'rejected',
    });
    final certification = (payload['certifications'] as List).single as Map;
    expect(certification['decision'], 'accepted');
    expect(
      (certification['memberships'] as List)
          .map((item) => (item as Map)['decision'])
          .toSet(),
      {'accepted', 'suggested', 'rejected'},
    );
    expect(
      ((payload['academic_requirements'] as List).single as Map)['decision'],
      'pending',
    );
    expect(payload['pending_items'], isNotEmpty);
    expect({
      ...prerequisites.map((item) => (item as Map)['decision']),
      ...(certification['memberships'] as List).map(
        (item) => (item as Map)['decision'],
      ),
      ((payload['academic_requirements'] as List).single as Map)['decision'],
    }, containsAll(['accepted', 'suggested', 'pending', 'rejected']));
  });

  test('acceso exige debug Android Testing, persistencia y solicitud', () {
    const enabled = MallaMultimodalTestingConfig(requested: true);
    bool allows({
      bool debug = true,
      bool android = true,
      bool persistence = true,
      EducFlowEnvironment environment = EducFlowEnvironment.testing,
      String firebase = AppEnvironmentConfig.testingFirebaseProjectId,
      String supabase = AppEnvironmentConfig.testingSupabaseProjectRef,
    }) => enabled.allows(
      firebaseProjectId: firebase,
      supabaseProjectRef: supabase,
      persistenceEnabled: persistence,
      debugMode: debug,
      android: android,
      appEnvironment: environment,
    );

    expect(allows(), isTrue);
    expect(allows(debug: false), isFalse);
    expect(allows(android: false), isFalse);
    expect(allows(persistence: false), isFalse);
    expect(allows(environment: EducFlowEnvironment.production), isFalse);
    expect(
      allows(firebase: AppEnvironmentConfig.productionFirebaseProjectId),
      isFalse,
    );
    expect(
      allows(supabase: AppEnvironmentConfig.productionSupabaseProjectRef),
      isFalse,
    );
    expect(
      const MallaMultimodalTestingConfig(requested: false).allows(
        firebaseProjectId: AppEnvironmentConfig.testingFirebaseProjectId,
        supabaseProjectRef: AppEnvironmentConfig.testingSupabaseProjectRef,
        persistenceEnabled: true,
        debugMode: true,
        android: true,
        appEnvironment: EducFlowEnvironment.testing,
      ),
      isFalse,
    );
  });

  test('comparación semántica conserva decisiones aunque cambie el orden', () {
    final payload = codec.encode(MallaMultimodalTestingFixture.create());
    final reordered = <String, dynamic>{...payload};
    reordered['courses'] = (payload['courses'] as List).reversed.toList();
    reordered['prerequisites'] = (payload['prerequisites'] as List).reversed
        .toList();

    expect(codec.equivalentPayloads(payload, reordered), isTrue);

    final changed = <String, dynamic>{...payload};
    changed['period_count'] = 4;
    expect(codec.equivalentPayloads(payload, changed), isFalse);
  });
}
