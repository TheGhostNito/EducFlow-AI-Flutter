import 'package:flutter/foundation.dart';

abstract final class DeveloperToolsConfig {
  static const requested = bool.fromEnvironment(
    'EDUFLOW_DEVELOPER_TOOLS_ENABLED',
  );

  @visibleForTesting
  static bool? debugOverride;

  static bool get enabled => kDebugMode && (debugOverride ?? requested);
}
