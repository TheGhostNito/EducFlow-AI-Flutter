import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../firebase_options.dart';
import '../../firebase_options_testing.dart';

enum EducFlowEnvironment { production, testing }

class AppEnvironmentConfig {
  const AppEnvironmentConfig._();

  static const _androidEnvironmentChannel = MethodChannel(
    'educflow/environment',
  );

  static const _environmentName = String.fromEnvironment(
    'EDUFLOW_APP_ENVIRONMENT',
    defaultValue: 'production',
  );

  static const productionFirebaseProjectId = 'educflow-ai';
  static const testingFirebaseProjectId = 'eduflow-ai-testing';
  static const productionFirebaseAndroidAppId =
      '1:621346416674:android:ebdfb4dcdf7d41c8dd027b';
  static const testingFirebaseAndroidAppId =
      '1:495312343955:android:3ca51a17095d2702f9ce66';
  static const productionAndroidPackage = 'com.martinrozas.eduflowai';
  static const testingAndroidPackage = 'com.martinrozas.eduflowai.testing';
  static const productionSupabaseProjectRef = 'ubjmdfwkjgblnjgmufpc';
  static const testingSupabaseProjectRef = 'oxrvksaljxcwdhkeapej';

  static EducFlowEnvironment get environment => switch (_environmentName) {
    'production' => EducFlowEnvironment.production,
    'testing' => EducFlowEnvironment.testing,
    _ => throw StateError(
      'EDUFLOW_APP_ENVIRONMENT debe ser production o testing.',
    ),
  };

  static FirebaseOptions get firebaseOptions {
    if (environment == EducFlowEnvironment.production) {
      return DefaultFirebaseOptions.currentPlatform;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError(
        'El entorno testing de Fase 2B.2 está habilitado solo para Android.',
      );
    }
    return TestingFirebaseOptions.android;
  }

  static String get expectedFirebaseProjectId =>
      environment == EducFlowEnvironment.testing
      ? testingFirebaseProjectId
      : productionFirebaseProjectId;

  static String get expectedFirebaseAppId =>
      environment == EducFlowEnvironment.testing
      ? testingFirebaseAndroidAppId
      : productionFirebaseAndroidAppId;

  static String get expectedSupabaseProjectRef =>
      environment == EducFlowEnvironment.testing
      ? testingSupabaseProjectRef
      : productionSupabaseProjectRef;

  static String get expectedAndroidPackage =>
      environment == EducFlowEnvironment.testing
      ? testingAndroidPackage
      : productionAndroidPackage;

  static Future<void> validateNativeEnvironment() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final applicationId = await _androidEnvironmentChannel.invokeMethod<String>(
      'getApplicationId',
    );
    if (applicationId == null || applicationId.isEmpty) {
      throw StateError('Android no informó el identificador de la aplicación.');
    }
    validateAndroidPackage(
      actualPackage: applicationId,
      expectedPackage: expectedAndroidPackage,
    );
  }

  static void validateFirebase(FirebaseOptions actual) {
    if (actual.projectId != expectedFirebaseProjectId) {
      throw StateError(
        'Firebase no coincide con el entorno ${environment.name}.',
      );
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      validateAndroidFirebaseAppId(
        actualAppId: actual.appId,
        expectedAppId: expectedFirebaseAppId,
      );
    }
  }

  static void validateSupabaseProjectRef(String actualProjectRef) {
    if (actualProjectRef != expectedSupabaseProjectRef) {
      throw StateError(
        'Supabase no coincide con el entorno ${environment.name}.',
      );
    }
  }

  @visibleForTesting
  static void validateAndroidFirebaseAppId({
    required String actualAppId,
    required String expectedAppId,
  }) {
    if (actualAppId != expectedAppId) {
      throw StateError(
        'La aplicación Firebase Android no coincide con el flavor activo.',
      );
    }
  }

  @visibleForTesting
  static void validateAndroidPackage({
    required String actualPackage,
    required String expectedPackage,
  }) {
    if (actualPackage != expectedPackage) {
      throw StateError(
        'El paquete Android no coincide con el entorno seleccionado.',
      );
    }
  }
}
