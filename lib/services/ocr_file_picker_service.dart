import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class OcrPickedFile {
  const OcrPickedFile({
    required this.name,
    required this.bytes,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String name;
  final Uint8List bytes;
  final String mimeType;
  final int sizeBytes;
}

class OcrFilePickerService {
  Future<OcrPickedFile?> pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'pdf',
      ],
      allowMultiple: false,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.single;
    final bytes = file.bytes;

    if (bytes == null || bytes.isEmpty) {
      throw StateError(
        'No se pudieron obtener los datos del archivo seleccionado.',
      );
    }

    final mimeType = _mimeTypeFromExtension(file.extension);

    return OcrPickedFile(
      name: file.name,
      bytes: bytes,
      mimeType: mimeType,
      sizeBytes: bytes.length,
    );
  }

  String _mimeTypeFromExtension(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';

      case 'png':
        return 'image/png';

      case 'webp':
        return 'image/webp';

      case 'pdf':
        return 'application/pdf';

      default:
        throw ArgumentError(
          'Tipo de archivo no compatible con OCR.',
        );
    }
  }
}