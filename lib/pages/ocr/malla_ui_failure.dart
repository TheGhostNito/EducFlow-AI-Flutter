import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

enum MallaFailureKind {
  setup,
  connection,
  permission,
  duplicate,
  quota,
  file,
  empty,
  other,
}

class MallaUiFailure {
  const MallaUiFailure(this.kind);

  final MallaFailureKind kind;

  bool get blocksProcessing =>
      kind == MallaFailureKind.setup ||
      kind == MallaFailureKind.connection ||
      kind == MallaFailureKind.permission ||
      kind == MallaFailureKind.other;

  /// `maybeSingle()` puede sustituir el código de PostgREST por el HTTP 404.
  /// Solo aceptamos como configuración pendiente un PGRST205 de las tablas
  /// propias de este módulo; un 404 ajeno sigue siendo un fallo inesperado.
  static bool _isMissingMallaTable(PostgrestException error) {
    if (error.code == 'PGRST205') return true;
    if (error.code != '404') return false;
    try {
      final body = jsonDecode(error.message);
      if (body is! Map<String, dynamic> || body['code'] != 'PGRST205') {
        return false;
      }
      final message = body['message'];
      return message is String &&
          (message.contains('public.mallas_curriculares') ||
              message.contains('public.ramos_malla'));
    } on FormatException {
      return false;
    }
  }

  static String? diagnosticCode(Object error) {
    if (error is! PostgrestException) return null;
    return _isMissingMallaTable(error) ? 'PGRST205' : error.code;
  }

  static MallaUiFailure from(Object error) {
    if (error is PostgrestException) {
      if (_isMissingMallaTable(error)) {
        return const MallaUiFailure(MallaFailureKind.setup);
      }
      switch (error.code) {
        case '42501':
        case 'PGRST301':
        case 'PGRST302':
          return const MallaUiFailure(MallaFailureKind.permission);
        case 'PGRST000':
        case 'PGRST001':
        case 'PGRST002':
        case 'PGRST003':
          return const MallaUiFailure(MallaFailureKind.connection);
        case '23505':
          return const MallaUiFailure(MallaFailureKind.duplicate);
      }
      return const MallaUiFailure(MallaFailureKind.other);
    }
    if (error is StorageException) {
      if (error.statusCode == '401' || error.statusCode == '403') {
        return const MallaUiFailure(MallaFailureKind.permission);
      }
      if (error.statusCode == '413') {
        return const MallaUiFailure(MallaFailureKind.file);
      }
      if (error.statusCode == '429') {
        return const MallaUiFailure(MallaFailureKind.quota);
      }
      return const MallaUiFailure(MallaFailureKind.other);
    }
    if (error is FunctionException) {
      if (error.status == 0) {
        return const MallaUiFailure(MallaFailureKind.connection);
      }
      if (error.status == 401 || error.status == 403) {
        return const MallaUiFailure(MallaFailureKind.permission);
      }
      if (error.status == 429) {
        return const MallaUiFailure(MallaFailureKind.quota);
      }
      if (error.status == 413) {
        return const MallaUiFailure(MallaFailureKind.file);
      }
      return const MallaUiFailure(MallaFailureKind.other);
    }
    if (error is TimeoutException) {
      return const MallaUiFailure(MallaFailureKind.connection);
    }
    if (error is FormatException) {
      return const MallaUiFailure(MallaFailureKind.empty);
    }
    if (error is ArgumentError) {
      return const MallaUiFailure(MallaFailureKind.file);
    }
    if (error is StateError) {
      return const MallaUiFailure(MallaFailureKind.permission);
    }
    return const MallaUiFailure(MallaFailureKind.other);
  }

  /// En la lectura inicial, las excepciones de transporte del cliente HTTP
  /// pueden llegar sin un tipo exportado por Supabase.
  static MallaUiFailure fromLoad(Object error) {
    final failure = from(error);
    if (failure.kind == MallaFailureKind.other &&
        error is Exception &&
        error is! PostgrestException &&
        error is! FunctionException &&
        error is! StorageException) {
      return const MallaUiFailure(MallaFailureKind.connection);
    }
    return failure;
  }

  static MallaUiFailure fromTransfer(Object error) {
    final failure = from(error);
    if (failure.kind == MallaFailureKind.other &&
        error is Exception &&
        error is! PostgrestException &&
        error is! FunctionException &&
        error is! StorageException) {
      return const MallaUiFailure(MallaFailureKind.connection);
    }
    return failure;
  }

  String title(bool spanish) => switch (kind) {
    MallaFailureKind.setup =>
      spanish
          ? 'Importación pendiente de habilitación'
          : 'Import is not enabled yet',
    MallaFailureKind.connection =>
      spanish ? 'Sin conexión con la malla' : 'Cannot connect to curriculum',
    MallaFailureKind.permission =>
      spanish
          ? 'No pudimos verificar tu acceso'
          : 'Could not verify your access',
    MallaFailureKind.duplicate =>
      spanish
          ? 'Ya tienes una malla guardada'
          : 'You already have a saved curriculum',
    MallaFailureKind.quota =>
      spanish
          ? 'Límite de procesamiento alcanzado'
          : 'Processing limit reached',
    MallaFailureKind.file =>
      spanish ? 'Archivo no compatible' : 'Unsupported file',
    MallaFailureKind.empty =>
      spanish ? 'No encontramos asignaturas' : 'No courses found',
    MallaFailureKind.other =>
      spanish
          ? 'No pudimos completar la operación'
          : 'Could not complete the operation',
  };

  String description(bool spanish) => switch (kind) {
    MallaFailureKind.setup =>
      spanish
          ? 'El guardado de mallas aún no está habilitado. Puedes elegir un archivo y revisarlo localmente; el OCR se activará cuando el módulo esté listo.'
          : 'Curriculum storage is not enabled yet. You can choose and inspect a file locally; OCR will be available when the module is ready.',
    MallaFailureKind.connection =>
      spanish
          ? 'Comprueba tu conexión y vuelve a intentarlo. No procesaremos el documento hasta poder verificar el guardado.'
          : 'Check your connection and try again. We will not process the document until storage can be checked.',
    MallaFailureKind.permission =>
      spanish
          ? 'Vuelve a iniciar sesión y reintenta. Si continúa, contacta al equipo de soporte.'
          : 'Sign in again and retry. If the problem persists, contact support.',
    MallaFailureKind.duplicate =>
      spanish
          ? 'La malla existente no se reemplazó. Vuelve a cargarla para consultarla.'
          : 'Your existing curriculum was not replaced. Reload it to view it.',
    MallaFailureKind.quota =>
      spanish
          ? 'Espera antes de volver a procesar el archivo.'
          : 'Wait before processing the file again.',
    MallaFailureKind.file =>
      spanish
          ? 'Selecciona un PDF, JPEG, PNG o WebP de hasta 10 MB.'
          : 'Choose a PDF, JPEG, PNG, or WebP file up to 10 MB.',
    MallaFailureKind.empty =>
      spanish
          ? 'Prueba con un documento más nítido o selecciona otra malla.'
          : 'Try a clearer document or choose another curriculum.',
    MallaFailureKind.other =>
      spanish
          ? 'Vuelve a intentarlo. Si el problema continúa, contacta al equipo de soporte.'
          : 'Try again. If the problem persists, contact support.',
  };
}
