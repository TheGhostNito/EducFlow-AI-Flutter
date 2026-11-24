import 'package:eduflow_ai/core/config/app_check_provider_config.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Debug usa exclusivamente el proveedor Debug de Android', () {
    final provider = AppCheckProviderConfig.android(debugBuild: true);

    expect(provider, isA<AndroidDebugProvider>());
    expect(provider, isNot(isA<AndroidPlayIntegrityProvider>()));
  });

  test('Release usa Play Integrity y nunca el proveedor Debug', () {
    final provider = AppCheckProviderConfig.android(debugBuild: false);

    expect(provider, isA<AndroidPlayIntegrityProvider>());
    expect(provider, isNot(isA<AndroidDebugProvider>()));
  });

  test('Debug verifica atestación sin conservar ni exponer el token', () async {
    bool? forceRefresh;

    final ready = await AppCheckProviderConfig.verifyDebugAttestation(
      debugBuild: true,
      getToken: (value) async {
        forceRefresh = value;
        return DateTime.now().microsecondsSinceEpoch.toString();
      },
    );

    expect(ready, isTrue);
    expect(forceRefresh, isTrue);
  });

  test('Release nunca ejecuta la verificación del proveedor Debug', () async {
    var calls = 0;

    final ready = await AppCheckProviderConfig.verifyDebugAttestation(
      debugBuild: false,
      getToken: (_) async {
        calls++;
        throw StateError(
          'La verificación Debug no debe ejecutarse en Release.',
        );
      },
    );

    expect(ready, isNull);
    expect(calls, 0);
  });
}
