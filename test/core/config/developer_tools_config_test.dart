import 'package:eduflow_ai/core/config/developer_tools_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => DeveloperToolsConfig.debugOverride = null);

  test('las herramientas de desarrollo están deshabilitadas por defecto', () {
    expect(DeveloperToolsConfig.requested, isFalse);
    expect(DeveloperToolsConfig.enabled, isFalse);
  });

  test('la habilitación de pruebas requiere una decisión explícita', () {
    DeveloperToolsConfig.debugOverride = true;
    expect(DeveloperToolsConfig.enabled, isTrue);

    DeveloperToolsConfig.debugOverride = false;
    expect(DeveloperToolsConfig.enabled, isFalse);
  });
}
