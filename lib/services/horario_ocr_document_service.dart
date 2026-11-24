import '../models/horario_ocr_result.dart';
import 'horario_ocr_extraction_service.dart';
import 'ocr_document_service.dart';
import 'ocr_file_picker_service.dart';

abstract interface class HorarioOcrDocumentGateway {
  Future<OcrPickedFile?> pickDocument();

  Future<HorarioOcrRunOutcome> extractWithDiagnostics(OcrPickedFile file);
}

class HorarioOcrDocumentService implements HorarioOcrDocumentGateway {
  HorarioOcrDocumentService({
    OcrDocumentGateway? documents,
    HorarioOcrExtractor? extraction,
  }) : _documents = documents ?? OcrDocumentService(),
       _extraction = extraction ?? HorarioOcrExtractionService();

  final OcrDocumentGateway _documents;
  final HorarioOcrExtractor _extraction;

  @override
  Future<OcrPickedFile?> pickDocument() => _documents.pickDocument();

  /// Procesa una propuesta local y siempre intenta retirar el archivo
  /// temporal. No confirma ni persiste períodos, asignaturas o sesiones.
  Future<HorarioOcrResult> extract(OcrPickedFile file) async {
    return (await extractWithDiagnostics(file)).result;
  }

  @override
  Future<HorarioOcrRunOutcome> extractWithDiagnostics(
    OcrPickedFile file,
  ) async {
    OcrDocumentResult? upload;
    try {
      upload = await _documents.upload(file);
      return await _extraction.extractWithDiagnostics(
        upload: upload,
        originalFile: file,
      );
    } finally {
      if (upload != null) {
        try {
          await _documents.deleteUploadedFile(upload.path);
        } catch (_) {
          // El endpoint también elimina el objeto. La limpieza secundaria no
          // debe reemplazar un resultado válido ni ocultar el error principal.
        }
      }
    }
  }
}
