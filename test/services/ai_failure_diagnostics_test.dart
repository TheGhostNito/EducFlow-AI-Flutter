import 'dart:io';

import 'package:eduflow_ai/services/ai_chat_history_service.dart';
import 'package:eduflow_ai/services/ai_failure_diagnostics.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('clasifica cuota como HTTP 429 sin registrar el mensaje remoto', () {
    final diagnostics = AiFailureDiagnostics.from(
      QuotaExceeded('detalle remoto que no debe registrarse'),
    );

    expect(diagnostics.category, AiFailureCategory.quotaExceeded);
    expect(diagnostics.httpStatus, 429);
    expect(diagnostics.backendStatus, 'RESOURCE_EXHAUSTED');
    expect(diagnostics.retryable, isTrue);
    expect(
      diagnostics.toSafeLog().toString(),
      isNot(contains('detalle remoto')),
    );
  });

  test('distingue modelo inexistente, App Check y errores del servidor', () {
    final model = AiFailureDiagnostics.from(
      ServerException(
        'Model was not found or your project does not have access to it.',
      ),
    );
    final appCheck = AiFailureDiagnostics.from(
      ServerException('PERMISSION_DENIED: enforce Firebase App Check.'),
    );
    final server = AiFailureDiagnostics.from(
      FirebaseAIException('Server Error [503]: contenido sensible'),
    );

    expect(model.category, AiFailureCategory.modelUnavailable);
    expect(model.httpStatus, 404);
    expect(appCheck.category, AiFailureCategory.appCheck);
    expect(appCheck.httpStatus, 403);
    expect(server.category, AiFailureCategory.server);
    expect(server.httpStatus, 503);
  });

  test('entrega mensaje específico y seguro para cuota', () {
    final diagnostics = AiFailureDiagnostics.from(
      QuotaExceeded('quota con identificadores internos'),
    );

    expect(diagnostics.userMessage(spanish: true), contains('cuota de Gemini'));
    expect(
      diagnostics.userMessage(spanish: true),
      contains('consultas directas'),
    );
    expect(
      diagnostics.userMessage(spanish: true),
      isNot(contains('identificadores')),
    );
  });

  test('Firestore pendiente o desconectado no se presenta como respuesta', () {
    final pending = AiFailureDiagnostics.from(
      const AiChatUnconfirmedDataException(),
    );
    final offline = AiFailureDiagnostics.from(
      FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'detalle interno',
      ),
    );
    expect(pending.category, AiFailureCategory.chatStorageConnectivity);
    expect(offline.category, AiFailureCategory.chatStorageConnectivity);
    expect(offline.retryable, isTrue);
    expect(offline.userMessage(spanish: true), contains('conexión'));
    expect(
      offline.userMessage(spanish: true),
      isNot(contains('detalle interno')),
    );
  });

  test(
    'fallos SQL de historial distinguen permiso, conexión y error genérico',
    () {
      final permission = AiFailureDiagnostics.from(
        PostgrestException(message: 'dato privado', code: '42501'),
        chatStorage: true,
      );
      final offline = AiFailureDiagnostics.from(
        const SocketException('sin conexión'),
        chatStorage: true,
      );
      final unknown = AiFailureDiagnostics.from(
        StateError('dato privado'),
        chatStorage: true,
      );
      expect(permission.category, AiFailureCategory.chatStoragePermission);
      expect(permission.retryable, isFalse);
      expect(offline.category, AiFailureCategory.chatStorageConnectivity);
      expect(offline.userMessage(spanish: true), isNot(contains('Gemini')));
      expect(unknown.category, AiFailureCategory.chatStorage);
      expect(unknown.toSafeLog().toString(), isNot(contains('dato privado')));
    },
  );
}
