import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/horario_importacion.dart';
import 'ocr_file_picker_service.dart';
import 'ocr_upload_service.dart';

abstract interface class HorarioDocumentoOriginalGateway {
  Future<HorarioDocumentoOriginal> subir({
    required OcrPickedFile file,
    required String importacionId,
  });

  Future<Uint8List> descargar(HorarioDocumentoOriginal documento);

  Future<void> asociar({
    required String importacionId,
    required HorarioDocumentoOriginal documento,
  });

  Future<void> registrarLimpieza(String path);
}

class HorarioDocumentoOriginalService
    implements HorarioDocumentoOriginalGateway {
  HorarioDocumentoOriginalService({
    FirebaseAuth? firebaseAuth,
    SupabaseClient? supabase,
  }) : _auth = firebaseAuth ?? FirebaseAuth.instance,
       _supabase = supabase ?? Supabase.instance.client;

  static const bucketName = 'horarios-originales';

  final FirebaseAuth _auth;
  final SupabaseClient _supabase;

  @override
  Future<HorarioDocumentoOriginal> subir({
    required OcrPickedFile file,
    required String importacionId,
  }) async {
    final uid = _uid();
    _validarImportacion(importacionId);
    if (file.bytes.isEmpty || file.sizeBytes != file.bytes.length) {
      throw ArgumentError('El documento original no es válido.');
    }
    if (!OcrUploadService.allowedMimeTypes.contains(file.mimeType)) {
      throw ArgumentError('Tipo de archivo no permitido: ${file.mimeType}');
    }
    if (file.sizeBytes > OcrUploadService.maxFileSizeBytes) {
      throw ArgumentError('El archivo supera el límite máximo de 10 MB.');
    }
    final extension = _extension(file.mimeType);
    final nonce = DateTime.now().toUtc().microsecondsSinceEpoch;
    final path = '$uid/$importacionId/$nonce.$extension';
    await _supabase.storage
        .from(bucketName)
        .uploadBinary(
          path,
          file.bytes,
          fileOptions: FileOptions(contentType: file.mimeType, upsert: false),
        );
    return HorarioDocumentoOriginal(
      path: path,
      nombre: _nombreSeguro(file.name),
      mimeType: file.mimeType,
      sizeBytes: file.sizeBytes,
    );
  }

  @override
  Future<Uint8List> descargar(HorarioDocumentoOriginal documento) async {
    _validarPath(documento.path);
    return _supabase.storage.from(bucketName).download(documento.path);
  }

  @override
  Future<void> asociar({
    required String importacionId,
    required HorarioDocumentoOriginal documento,
  }) async {
    _validarImportacion(importacionId);
    _validarPath(documento.path, importacionId: importacionId);
    await _supabase.rpc(
      'asociar_documento_importacion_horario',
      params: {
        'p_importacion_id': importacionId,
        'p_documento': _payload(documento),
      },
    );
  }

  @override
  Future<void> registrarLimpieza(String path) async {
    _validarPath(path);
    await _supabase.rpc(
      'registrar_limpieza_documento_horario',
      params: {'p_documento_path': path},
    );
  }

  Map<String, dynamic> _payload(HorarioDocumentoOriginal value) => {
    'path': value.path,
    'nombre': value.nombre,
    'mime': value.mimeType,
    'size': value.sizeBytes,
  };

  void _validarPath(String path, {String? importacionId}) {
    final parts = path.split('/');
    if (parts.length != 3 ||
        parts[0] != _uid() ||
        (importacionId != null && parts[1] != importacionId) ||
        parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw StateError('El documento no pertenece al usuario actual.');
    }
  }

  void _validarImportacion(String value) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(value)) {
      throw const FormatException('Identificador de importación no válido.');
    }
  }

  String _nombreSeguro(String value) {
    final clean = value.trim().replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '');
    if (clean.isEmpty) return 'horario';
    return clean.length <= 255 ? clean : clean.substring(clean.length - 255);
  }

  String _uid() {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Inicia sesión para gestionar el documento.');
    }
    return uid;
  }

  String _extension(String mime) => switch (mime) {
    'application/pdf' => 'pdf',
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
    _ => throw ArgumentError('Tipo de archivo no permitido.'),
  };
}
