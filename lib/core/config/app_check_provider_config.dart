import 'package:firebase_app_check/firebase_app_check.dart';

abstract final class AppCheckProviderConfig {
  static AndroidAppCheckProvider android({required bool debugBuild}) {
    return debugBuild
        ? const AndroidDebugProvider()
        : const AndroidPlayIntegrityProvider();
  }

  static Future<bool?> verifyDebugAttestation({
    required bool debugBuild,
    required Future<String?> Function(bool forceRefresh) getToken,
  }) async {
    if (!debugBuild) return null;
    final token = await getToken(true);
    return token?.isNotEmpty == true;
  }
}
