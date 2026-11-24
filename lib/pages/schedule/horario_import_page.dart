import 'package:flutter/material.dart';

import '../../services/horario_importacion_service.dart';
import '../../services/horario_ocr_document_service.dart';
import 'horario_ocr_diagnostic_page.dart';

/// Entrada oficial del OCR de horarios. La vista técnica continúa disponible
/// por separado en modo debug.
class HorarioImportPage extends StatelessWidget {
  const HorarioImportPage({
    super.key,
    required this.spanish,
    this.gateway,
    this.importacionGateway,
    this.writesEnabled = HorarioImportacionConfig.writesEnabled,
  });

  final bool spanish;
  final HorarioOcrDocumentGateway? gateway;
  final HorarioImportacionGateway? importacionGateway;
  final bool writesEnabled;

  @override
  Widget build(BuildContext context) {
    return HorarioOcrDiagnosticPage(
      spanish: spanish,
      gateway: gateway,
      importacionGateway: importacionGateway,
      writesEnabled: writesEnabled,
      showDeveloperDiagnostics: false,
    );
  }
}
