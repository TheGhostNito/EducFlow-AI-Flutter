import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Intercepta los canales del SDK fijado en pubspec.lock. Ninguna prueba
/// realiza peticiones, crea usuarios ni escribe perfiles en Firebase.
class FirebaseAuthTestHost {
  final _messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  static const _codec = _FirebaseTestCodec();
  static const _authPrefix =
      'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi';

  final List<List<Object?>> registros = [];
  final List<List<Object?>> iniciosDeSesion = [];
  Future<void>? respuestaPendiente;

  Future<void> initialize({String? initialUid}) async {
    _messenger.setMockMessageHandler(
      'dev.flutter.pigeon.firebase_core_platform_interface.FirebaseCoreHostApi.initializeCore',
      (_) async => _codec.encodeMessage([
        [
          _PigeonValue(130, [
            '[DEFAULT]',
            _PigeonValue(129, [
              'fake-api-key',
              'fake-app-id',
              'fake-sender',
              'demo-educflow-test',
              ...List<Object?>.filled(10, null),
            ]),
            false,
            <String, Object?>{
              if (initialUid != null)
                'plugins.flutter.io/firebase_auth': {
                  'APP_CURRENT_USER': [
                    [
                      initialUid,
                      'estudiante@example.test',
                      'Martín',
                      null,
                      null,
                      false,
                      true,
                      null,
                      null,
                      null,
                      null,
                      null,
                    ],
                    <Object?>[],
                  ],
                },
            },
          ]),
        ],
      ]),
    );
    await Firebase.initializeApp();
    _mockAuth('createUserWithEmailAndPassword', registros);
    _mockAuth('signInWithEmailAndPassword', iniciosDeSesion);
  }

  void _mockAuth(String method, List<List<Object?>> requests) {
    _messenger.setMockMessageHandler('$_authPrefix.$method', (message) async {
      requests.add((_codec.decodeMessage(message)! as List).cast<Object?>());
      await respuestaPendiente;
      // Detenemos el flujo antes de la navegación y de cualquier escritura.
      return _codec.encodeMessage([
        'network-request-failed',
        'Prueba local',
        null,
      ]);
    });
  }

  void reset() {
    respuestaPendiente = null;
    registros.clear();
    iniciosDeSesion.clear();
  }
}

class _PigeonValue {
  const _PigeonValue(this.type, this.fields);
  final int type;
  final List<Object?> fields;
}

class _FirebaseTestCodec extends StandardMessageCodec {
  const _FirebaseTestCodec();

  @override
  void writeValue(WriteBuffer buffer, Object? value) {
    if (value is _PigeonValue) {
      buffer.putUint8(value.type);
      writeValue(buffer, value.fields);
    } else {
      super.writeValue(buffer, value);
    }
  }

  @override
  Object? readValueOfType(int type, ReadBuffer buffer) {
    return type >= 128
        ? readValue(buffer)
        : super.readValueOfType(type, buffer);
  }
}
