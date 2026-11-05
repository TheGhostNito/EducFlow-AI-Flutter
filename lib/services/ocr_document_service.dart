import 'ocr_file_picker_service.dart';
import 'ocr_upload_service.dart';

abstract interface class OcrDocumentGateway {
  Future<OcrPickedFile?> pickDocument();
  Future<OcrDocumentResult> upload(OcrPickedFile pickedFile);
  Future<void> deleteUploadedFile(String path);
}

class OcrDocumentResult {
  const OcrDocumentResult({
    required this.originalName,
    required this.bucket,
    required this.path,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String originalName;
  final String bucket;
  final String path;
  final String mimeType;
  final int sizeBytes;
}

class OcrDocumentService implements OcrDocumentGateway {
  OcrDocumentService({
    OcrFilePickerService? filePickerService,
    OcrUploadService? uploadService,
  }) : _filePickerService = filePickerService ?? OcrFilePickerService(),
       _uploadService = uploadService ?? OcrUploadService();

  final OcrFilePickerService _filePickerService;
  final OcrUploadService _uploadService;

  @override
  Future<OcrPickedFile?> pickDocument() => _filePickerService.pickDocument();

  @override
  Future<OcrDocumentResult> upload(OcrPickedFile pickedFile) async {
    final uploaded = await _uploadService.upload(
      bytes: pickedFile.bytes,
      mimeType: pickedFile.mimeType,
    );
    return OcrDocumentResult(
      originalName: pickedFile.name,
      bucket: uploaded.bucket,
      path: uploaded.path,
      mimeType: uploaded.mimeType,
      sizeBytes: uploaded.sizeBytes,
    );
  }

  Future<OcrDocumentResult?> pickAndUpload() async {
    final pickedFile = await _filePickerService.pickDocument();

    if (pickedFile == null) {
      return null;
    }

    return upload(pickedFile);
  }

  @override
  Future<void> deleteUploadedFile(String path) {
    return _uploadService.delete(path);
  }
}
