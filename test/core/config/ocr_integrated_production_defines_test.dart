import 'package:eduflow_ai/core/config/app_environment_config.dart';
import 'package:eduflow_ai/core/config/backend_config.dart';
import 'package:eduflow_ai/services/horario_importacion_service.dart';
import 'package:eduflow_ai/services/malla_multimodal_persistence_service.dart';
import 'package:eduflow_ai/services/malla_multimodal_testing_fixture.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el perfil integrado habilita ambos OCR sin laboratorios', () {
    if (!MallaMultimodalPersistenceConfig.environment.requested ||
        !HorarioImportacionConfig.writesEnabled) {
      markTestSkipped(
        'Ejecutar con config/ocr_integrated_production.json.',
      );
      return;
    }
    expect(AppEnvironmentConfig.environment, EducFlowEnvironment.production);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final firebase = AppEnvironmentConfig.firebaseOptions;
    AppEnvironmentConfig.validateFirebase(firebase);
    AppEnvironmentConfig.validateSupabaseProjectRef(
      BackendConfig.supabaseProjectRef,
    );

    expect(
      MallaMultimodalPersistenceConfig.environment.allows(
        firebaseProjectId: firebase.projectId,
        supabaseProjectRef: BackendConfig.supabaseProjectRef,
      ),
      isTrue,
    );
    expect(HorarioImportacionConfig.writesEnabled, isTrue);
    expect(HorarioImportacionConfig.documentStorageEnabled, isTrue);
    expect(MallaMultimodalTestingConfig.environment.requested, isFalse);
  });
}
