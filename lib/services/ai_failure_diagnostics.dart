import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ai_chat_history_service.dart';
import 'ai_function_calling_flow.dart';

enum AiFailureCategory {
  chatStorage,
  chatStoragePermission,
  chatStorageConnectivity,
  academicData,
  academicDataPermission,
  academicDataConnectivity,
  quotaExceeded,
  invalidApiKey,
  serviceNotEnabled,
  unsupportedLocation,
  appCheck,
  permissionDenied,
  modelUnavailable,
  connectivity,
  timeout,
  server,
  sdk,
  unknown,
}

class AiFailureDiagnostics {
  const AiFailureDiagnostics({
    required this.category,
    required this.errorType,
    required this.retryable,
    this.httpStatus,
    this.backendStatus,
  });

  final AiFailureCategory category;
  final String errorType;
  final bool retryable;
  final int? httpStatus;
  final String? backendStatus;

  factory AiFailureDiagnostics.from(Object error, {bool chatStorage = false}) {
    final String type = error.runtimeType.toString();

    if (error is AiChatUnconfirmedDataException) {
      return AiFailureDiagnostics(
        category: AiFailureCategory.chatStorageConnectivity,
        errorType: type,
        retryable: true,
      );
    }
    if (error is FirebaseException && error.plugin == 'cloud_firestore') {
      final permission =
          error.code == 'permission-denied' || error.code == 'unauthenticated';
      return AiFailureDiagnostics(
        category: permission
            ? AiFailureCategory.chatStoragePermission
            : error.code == 'unavailable' || error.code == 'deadline-exceeded'
            ? AiFailureCategory.chatStorageConnectivity
            : AiFailureCategory.chatStorage,
        errorType: type,
        retryable: !permission,
      );
    }

    if (chatStorage) {
      final permission =
          error is PostgrestException &&
          (error.code == '42501' || error.code == 'PGRST301');
      final connectivity =
          error is AiRequestTimeoutException ||
          _looksLikeConnectivityFailure(
            type,
            _safeMessage(error).toLowerCase(),
          );
      return AiFailureDiagnostics(
        category: permission
            ? AiFailureCategory.chatStoragePermission
            : connectivity
            ? AiFailureCategory.chatStorageConnectivity
            : AiFailureCategory.chatStorage,
        errorType: type,
        retryable: !permission,
      );
    }

    if (error is AiRequestTimeoutException) {
      return AiFailureDiagnostics(
        category: AiFailureCategory.timeout,
        errorType: type,
        retryable: true,
        backendStatus: 'DEADLINE_EXCEEDED',
      );
    }
    if (error is QuotaExceeded) {
      return AiFailureDiagnostics(
        category: AiFailureCategory.quotaExceeded,
        errorType: type,
        retryable: true,
        httpStatus: 429,
        backendStatus: 'RESOURCE_EXHAUSTED',
      );
    }
    if (error is InvalidApiKey) {
      return AiFailureDiagnostics(
        category: AiFailureCategory.invalidApiKey,
        errorType: type,
        retryable: false,
        httpStatus: 400,
        backendStatus: 'INVALID_ARGUMENT',
      );
    }
    if (error is ServiceApiNotEnabled) {
      return AiFailureDiagnostics(
        category: AiFailureCategory.serviceNotEnabled,
        errorType: type,
        retryable: false,
        httpStatus: 403,
        backendStatus: 'PERMISSION_DENIED',
      );
    }
    if (error is UnsupportedUserLocation) {
      return AiFailureDiagnostics(
        category: AiFailureCategory.unsupportedLocation,
        errorType: type,
        retryable: false,
        httpStatus: 400,
        backendStatus: 'FAILED_PRECONDITION',
      );
    }
    if (error is FirebaseAISdkException) {
      return AiFailureDiagnostics(
        category: AiFailureCategory.sdk,
        errorType: type,
        retryable: false,
      );
    }

    final String message = _safeMessage(error).toLowerCase();
    if (_containsAny(message, const ['app check', 'appcheck', 'attestation'])) {
      return AiFailureDiagnostics(
        category: AiFailureCategory.appCheck,
        errorType: type,
        retryable: false,
        httpStatus: 403,
        backendStatus: 'PERMISSION_DENIED',
      );
    }
    if (_containsAny(message, const [
      'model was not found',
      'model is not found',
      'valid model version',
      'does not have access to it',
    ])) {
      return AiFailureDiagnostics(
        category: AiFailureCategory.modelUnavailable,
        errorType: type,
        retryable: false,
        httpStatus: 404,
        backendStatus: 'NOT_FOUND',
      );
    }
    if (_containsAny(message, const [
      'permission_denied',
      'does not have permission',
      'caller does not have permission',
      'requests to this api',
    ])) {
      return AiFailureDiagnostics(
        category: AiFailureCategory.permissionDenied,
        errorType: type,
        retryable: false,
        httpStatus: 403,
        backendStatus: 'PERMISSION_DENIED',
      );
    }
    if (_containsAny(message, const ['quota', 'resource_exhausted'])) {
      return AiFailureDiagnostics(
        category: AiFailureCategory.quotaExceeded,
        errorType: type,
        retryable: true,
        httpStatus: 429,
        backendStatus: 'RESOURCE_EXHAUSTED',
      );
    }
    if (_looksLikeConnectivityFailure(type, message)) {
      return AiFailureDiagnostics(
        category: AiFailureCategory.connectivity,
        errorType: type,
        retryable: true,
      );
    }

    final int? status = _serverStatus(message);
    if (error is ServerException || status != null) {
      return AiFailureDiagnostics(
        category: AiFailureCategory.server,
        errorType: type,
        retryable: status == null || status >= 500 || status == 429,
        httpStatus: status,
      );
    }

    return AiFailureDiagnostics(
      category: AiFailureCategory.unknown,
      errorType: type,
      retryable: false,
    );
  }

  Map<String, Object?> toSafeLog() => <String, Object?>{
    'failureCategory': category.name,
    'errorType': errorType,
    'retryable': retryable,
    if (httpStatus != null) 'httpStatus': httpStatus,
    if (backendStatus != null) 'backendStatus': backendStatus,
  };

  String userMessage({required bool spanish}) {
    if (category == AiFailureCategory.chatStoragePermission) {
      return spanish
          ? 'No tengo permiso para guardar este chat. Vuelve a iniciar sesión o revisa el acceso de tu cuenta.'
          : 'I do not have permission to save this chat. Sign in again or check your account access.';
    }
    if (category == AiFailureCategory.chatStorageConnectivity) {
      return spanish
          ? 'No pude confirmar el chat con el servidor. Revisa tu conexión y reinténtalo.'
          : 'I could not confirm the chat with the server. Check your connection and retry.';
    }
    if (category == AiFailureCategory.chatStorage) {
      return spanish
          ? 'No pude guardar o recuperar el chat. Inténtalo nuevamente.'
          : 'I could not save or restore the chat. Please try again.';
    }
    if (category == AiFailureCategory.academicDataPermission) {
      return spanish
          ? 'No tengo permiso para consultar esos datos académicos. Vuelve a iniciar sesión o revisa el acceso de tu cuenta.'
          : 'I do not have permission to read that academic data. Sign in again or check your account access.';
    }
    if (category == AiFailureCategory.academicDataConnectivity) {
      return spanish
          ? 'No pude conectar con tus datos académicos. Revisa tu conexión e inténtalo nuevamente.'
          : 'I could not connect to your academic data. Check your connection and try again.';
    }
    if (category == AiFailureCategory.academicData) {
      return spanish
          ? 'No pude consultar tus datos académicos en este momento. Inténtalo nuevamente.'
          : 'I could not read your academic data right now. Please try again.';
    }
    if (category == AiFailureCategory.quotaExceeded) {
      return spanish
          ? 'Se alcanzó temporalmente la cuota de Gemini. Las consultas directas sobre tus datos académicos siguen disponibles; intenta nuevamente más tarde para preguntas que requieren IA.'
          : 'The Gemini quota has been temporarily reached. Direct queries about your academic data are still available; try again later for questions that require AI.';
    }
    if (category == AiFailureCategory.connectivity) {
      return spanish
          ? 'No pude conectar con Gemini. Revisa tu conexión e inténtalo nuevamente.'
          : 'I could not connect to Gemini. Check your connection and try again.';
    }
    if (category == AiFailureCategory.appCheck) {
      return spanish
          ? 'Firebase rechazó la verificación de esta instalación. La configuración de App Check debe revisarse.'
          : 'Firebase rejected this app installation verification. The App Check configuration needs to be reviewed.';
    }
    if (category == AiFailureCategory.modelUnavailable) {
      return spanish
          ? 'El modelo de Gemini configurado no está disponible para este proyecto.'
          : 'The configured Gemini model is not available for this project.';
    }
    if (category == AiFailureCategory.invalidApiKey ||
        category == AiFailureCategory.permissionDenied ||
        category == AiFailureCategory.serviceNotEnabled) {
      return spanish
          ? 'Firebase AI Logic rechazó la configuración o los permisos de la aplicación.'
          : 'Firebase AI Logic rejected the app configuration or permissions.';
    }
    return spanish
        ? 'No pude responder en este momento. Inténtalo nuevamente.'
        : 'I could not respond right now. Please try again.';
  }

  static String _safeMessage(Object error) {
    if (error is FirebaseAIException) return error.message;
    if (error is FirebaseAISdkException) return error.message;
    return error.toString();
  }

  static bool _containsAny(String value, Iterable<String> terms) =>
      terms.any(value.contains);

  static bool _looksLikeConnectivityFailure(String type, String message) {
    final String normalizedType = type.toLowerCase();
    return _containsAny(normalizedType, const [
          'clientexception',
          'socketexception',
          'handshakeexception',
        ]) ||
        _containsAny(message, const [
          'failed host lookup',
          'connection reset',
          'connection refused',
          'network is unreachable',
        ]);
  }

  static int? _serverStatus(String message) {
    final Match? match = RegExp(r'server error \[(\d{3})\]')
        .firstMatch(message);
    return match == null ? null : int.tryParse(match.group(1)!);
  }
}
