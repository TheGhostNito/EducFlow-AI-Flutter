import 'package:eduflow_ai/core/config/app_environment_config.dart';
import 'package:eduflow_ai/core/config/backend_config.dart';
import 'package:eduflow_ai/services/malla_multimodal_persistence_service.dart';
import 'package:eduflow_ai/services/malla_multimodal_testing_fixture.dart';
import 'package:eduflow_ai/services/horario_importacion_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'los dart-define habilitan Android Testing sin laboratorios visibles',
    () {
      if (AppEnvironmentConfig.environment != EducFlowEnvironment.testing) {
        markTestSkipped('Ejecutar con config/android_testing.local.json.');
        return;
      }

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final firebase = AppEnvironmentConfig.firebaseOptions;
      AppEnvironmentConfig.validateFirebase(firebase);
      AppEnvironmentConfig.validateSupabaseProjectRef(
        BackendConfig.supabaseProjectRef,
      );
      AppEnvironmentConfig.validateAndroidPackage(
        actualPackage: 'com.martinrozas.eduflowai.testing',
        expectedPackage: AppEnvironmentConfig.expectedAndroidPackage,
      );

      expect(firebase.projectId, 'eduflow-ai-testing');
      expect(firebase.appId, AppEnvironmentConfig.testingFirebaseAndroidAppId);
      expect(
        MallaMultimodalPersistenceConfig.environment.allows(
          firebaseProjectId: firebase.projectId,
          supabaseProjectRef: BackendConfig.supabaseProjectRef,
        ),
        isTrue,
      );
      expect(
        MallaMultimodalTestingConfig.environment.allows(
          firebaseProjectId: firebase.projectId,
          supabaseProjectRef: BackendConfig.supabaseProjectRef,
          persistenceEnabled: true,
          debugMode: true,
          android: true,
        ),
        isFalse,
      );
      expect(HorarioImportacionConfig.writesEnabled, isTrue);
      expect(HorarioImportacionConfig.documentStorageEnabled, isTrue);
    },
  );
}
