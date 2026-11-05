import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OcrUploadResult {
  const OcrUploadResult({
    required this.bucket,
    required this.path,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String bucket;
  final String path;
  final String mimeType;
  final int sizeBytes;
}

class OcrUploadService {
  OcrUploadService({
    FirebaseAuth? firebaseAuth,
    SupabaseClient? supabase,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _supabase = supabase ?? Supabase.instance.client;

  static const String bucketName = 'ocr-temp';

  static const int maxFileSizeBytes = 10 * 1024 * 1024;

  static const Set<String> allowedMimeTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/pdf',
  };

  final FirebaseAuth _firebaseAuth;
  final SupabaseClient _supabase;

  Future<OcrUploadResult> upload({
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final user = _firebaseAuth.currentUser;

    if (user == null) {
      throw StateError(
        'No hay un usuario autenticado para subir el archivo OCR.',
      );
    }

    if (bytes.isEmpty) {
      throw ArgumentError(
        'El archivo OCR está vacío.',
      );
    }

    if (!allowedMimeTypes.contains(mimeType)) {
      throw ArgumentError(
        'Tipo de archivo no permitido para OCR: $mimeType',
      );
    }

    if (bytes.length > maxFileSizeBytes) {
      throw ArgumentError(
        'El archivo supera el límite máximo de 10 MB.',
      );
    }

    final extension = _extensionForMimeType(mimeType);

    final timestamp =
        DateTime.now().toUtc().microsecondsSinceEpoch;

    final path = '${user.uid}/$timestamp.$extension';

    await _supabase.storage.from(bucketName).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: mimeType,
            upsert: false,
          ),
        );

    return OcrUploadResult(
      bucket: bucketName,
      path: path,
      mimeType: mimeType,
      sizeBytes: bytes.length,
    );
  }

  Future<void> delete(String path) async {
    final user = _firebaseAuth.currentUser;

    if (user == null) {
      throw StateError(
        'No hay un usuario autenticado.',
      );
    }

    final expectedPrefix = '${user.uid}/';

    if (!path.startsWith(expectedPrefix)) {
      throw StateError(
        'El archivo OCR no pertenece al usuario actual.',
      );
    }

    await _supabase.storage.from(bucketName).remove([
      path,
    ]);
  }

  String _extensionForMimeType(String mimeType) {
    switch (mimeType) {
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'application/pdf':
        return 'pdf';
      default:
        throw ArgumentError(
          'No existe una extensión válida para $mimeType.',
        );
    }
  }
}