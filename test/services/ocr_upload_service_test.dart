import 'package:eduflow_ai/services/ocr_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('propiedad de rutas OCR temporales', () {
    test('acepta únicamente el archivo directo del UID autenticado', () {
      expect(
        OcrUploadService.pathBelongsToUser(
          path: 'firebase-user/123456.pdf',
          uid: 'firebase-user',
        ),
        isTrue,
      );
    });

    test('rechaza una ruta perteneciente a otra sesión', () {
      expect(
        OcrUploadService.pathBelongsToUser(
          path: 'uid-anterior/123456.pdf',
          uid: 'uid-actual',
        ),
        isFalse,
      );
    });

    test('rechaza rutas vacías, anidadas o con segmentos de navegación', () {
      for (final path in <String>[
        '',
        'firebase-user/',
        'firebase-user/carpeta/archivo.pdf',
        'firebase-user/..',
        'firebase-user/.',
      ]) {
        expect(
          OcrUploadService.pathBelongsToUser(path: path, uid: 'firebase-user'),
          isFalse,
          reason: path,
        );
      }
    });
  });
}
