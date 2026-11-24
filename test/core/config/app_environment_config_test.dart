import 'package:eduflow_ai/core/config/app_environment_config.dart';
import 'package:eduflow_ai/core/config/backend_config.dart';
import 'package:eduflow_ai/firebase_options_testing.dart';
import 'package:eduflow_ai/services/malla_multimodal_persistence_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppEnvironmentConfig', () {
    test('el entorno predeterminado continúa siendo producción', () {
      expect(AppEnvironmentConfig.environment, EducFlowEnvironment.production);
      expect(
        AppEnvironmentConfig.expectedFirebaseProjectId,
        AppEnvironmentConfig.productionFirebaseProjectId,
      );
      expect(
        BackendConfig.supabaseProjectRef,
        AppEnvironmentConfig.productionSupabaseProjectRef,
      );
    });

    test('producción mantiene desactivada la persistencia multimodal', () {
      expect(MallaMultimodalPersistenceConfig.environment.requested, isFalse);
      expect(
        MallaMultimodalPersistenceConfig.environment.allows(
          firebaseProjectId: AppEnvironmentConfig.productionFirebaseProjectId,
          supabaseProjectRef: AppEnvironmentConfig.productionSupabaseProjectRef,
        ),
        isFalse,
      );
    });

    test('la configuración Android Testing conserva IDs aislados', () {
      expect(
        TestingFirebaseOptions.android.projectId,
        AppEnvironmentConfig.testingFirebaseProjectId,
      );
      expect(
        TestingFirebaseOptions.android.appId,
        AppEnvironmentConfig.testingFirebaseAndroidAppId,
      );
    });

    test('rechaza una app Firebase de otro flavor', () {
      expect(
        () => AppEnvironmentConfig.validateAndroidFirebaseAppId(
          actualAppId: AppEnvironmentConfig.productionFirebaseAndroidAppId,
          expectedAppId: AppEnvironmentConfig.testingFirebaseAndroidAppId,
        ),
        throwsStateError,
      );
    });

    test('rechaza un package Android de otro entorno', () {
      expect(
        () => AppEnvironmentConfig.validateAndroidPackage(
          actualPackage: AppEnvironmentConfig.productionAndroidPackage,
          expectedPackage: AppEnvironmentConfig.testingAndroidPackage,
        ),
        throwsStateError,
      );
    });
  });
}
