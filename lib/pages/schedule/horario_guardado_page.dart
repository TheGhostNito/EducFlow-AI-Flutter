import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/horario_importacion.dart';
import '../../services/horario_documento_original_service.dart';
import '../../services/horario_importacion_service.dart';
import '../../services/ocr_file_picker_service.dart';
import '../../widgets/app_full_screen_loading.dart';
import '../../widgets/app_pressable.dart';
import '../../widgets/app_scroll_header.dart';
import '../../widgets/app_status_snackbar.dart';
import '../ocr/widgets/ocr_pdf_preview.dart';
import 'horario_import_page.dart';

typedef HorarioDocumentPicker = Future<OcrPickedFile?> Function();

class HorarioGuardadoPage extends StatefulWidget {
  const HorarioGuardadoPage({
    super.key,
    required this.spanish,
    this.importacionGateway,
    this.documentoGateway,
    this.documentPicker,
    this.writesEnabled = HorarioImportacionConfig.writesEnabled,
    this.documentStorageEnabled =
        HorarioImportacionConfig.documentStorageEnabled,
  });

  final bool spanish;
  final HorarioImportacionGateway? importacionGateway;
  final HorarioDocumentoOriginalGateway? documentoGateway;
  final HorarioDocumentPicker? documentPicker;
  final bool writesEnabled;
  final bool documentStorageEnabled;

  @override
  State<HorarioGuardadoPage> createState() => _HorarioGuardadoPageState();
}

class _HorarioGuardadoPageState extends State<HorarioGuardadoPage> {
  late final HorarioImportacionGateway _imports;
  late final HorarioDocumentoOriginalGateway _documents;
  late final HorarioDocumentPicker _pickDocument;
  List<HorarioImportacionRegistro> _records = const [];
  HorarioImportacionRegistro? _selected;
  Uint8List? _bytes;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  final ScrollController _scrollController = ScrollController();
  double _headerProgress = 0;

  String _t(String es, String en) => widget.spanish ? es : en;

  @override
  void initState() {
    super.initState();
    _imports = widget.importacionGateway ?? HorarioImportacionService();
    _documents = widget.documentoGateway ?? HorarioDocumentoOriginalService();
    _pickDocument =
        widget.documentPicker ?? OcrFilePickerService().pickDocument;
    _scrollController.addListener(_listenScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_listenScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _listenScroll() {
    if (!_scrollController.hasClients) return;
    final progress = ((_scrollController.offset - 45) / 100).clamp(0.0, 1.0);
    if ((progress - _headerProgress).abs() < .01) return;
    setState(() => _headerProgress = progress);
  }

  Future<void> _load({String? selectedId}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = await _imports.listar();
      HorarioImportacionRegistro? selected;
      if (records.isNotEmpty) {
        selected = records.first;
        for (final record in records) {
          if (record.id == selectedId) selected = record;
        }
      }
      Uint8List? bytes;
      final document = selected?.documentoOriginal;
      if (document != null) bytes = await _documents.descargar(document);
      if (!mounted) return;
      setState(() {
        _records = records;
        _selected = selected;
        _bytes = bytes;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _safeError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openImport() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => HorarioImportPage(
          spanish: widget.spanish,
          importacionGateway: _imports,
          writesEnabled: widget.writesEnabled,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _attachLegacyDocument() async {
    final record = _selected;
    if (record == null || _busy || !widget.documentStorageEnabled) return;
    final file = await _pickDocument();
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    HorarioDocumentoOriginal? uploaded;
    try {
      uploaded = await _documents.subir(file: file, importacionId: record.id);
      await _documents.asociar(importacionId: record.id, documento: uploaded);
      if (!mounted) return;
      showAppStatusSnackBar(
        context,
        message: _t(
          'Documento original asociado sin duplicar asignaturas.',
          'Original document linked without duplicating subjects.',
        ),
      );
      await _load(selectedId: record.id);
    } catch (error) {
      if (uploaded != null) await _cleanup(uploaded.path);
      if (mounted) {
        showAppStatusSnackBar(
          context,
          message: _safeError(error),
          type: AppStatusType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    final document = _selected?.documentoOriginal;
    final bytes = _bytes;
    if (document == null || bytes == null || _busy) return;
    setState(() => _busy = true);
    try {
      final dot = document.nombre.lastIndexOf('.');
      final extension = dot < 0 ? 'pdf' : document.nombre.substring(dot + 1);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: _t('Guardar documento original', 'Save original document'),
        fileName: document.nombre,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: [extension.toLowerCase()],
      );
      if (path != null && mounted) {
        showAppStatusSnackBar(
          context,
          message: _t('Documento descargado.', 'Document downloaded.'),
        );
      }
    } catch (error) {
      if (mounted) {
        showAppStatusSnackBar(
          context,
          message: _safeError(error),
          type: AppStatusType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final record = _selected;
    if (record == null || _busy || !widget.writesEnabled) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _DeleteConfirmation(spanish: widget.spanish, record: record),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await _imports.eliminar(record.id);
      final path = result.documentoPath ?? record.documentoOriginal?.path;
      if (!mounted) return;
      showAppStatusSnackBar(
        context,
        message: path != null && widget.documentStorageEnabled
            ? _t(
                'Horario eliminado. El archivo privado quedó pendiente de limpieza del servidor.',
                'Schedule deleted. The private file is pending server cleanup.',
              )
            : _t(
                'Horario eliminado. Las asignaturas manuales se conservaron.',
                'Schedule deleted. Manual subjects were preserved.',
              ),
      );
      await _load();
    } catch (error) {
      if (mounted) {
        showAppStatusSnackBar(
          context,
          message: _safeError(error),
          type: AppStatusType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cleanup(String path) async {
    try {
      await _documents.registrarLimpieza(path);
    } catch (_) {
      // La cola conserva el archivo privado para que el servidor lo limpie.
    }
  }

  String _safeError(Object error) =>
      error.toString().replaceFirst(RegExp(r'^\w+Exception:\s*'), '').trim();

  @override
  Widget build(BuildContext context) {
    if (_loading && _selected == null) {
      return AppFullScreenLoading(
        title: _t('Cargando tu horario', 'Loading your schedule'),
        description: _t(
          'Recuperando el documento original.',
          'Retrieving the original document.',
        ),
      );
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final compactProgress = _selected == null ? 1.0 : _headerProgress;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: SafeArea(bottom: false, child: _body())),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AppScrollHeader(
              progress: compactProgress,
              title: _t('Ver horario', 'View schedule'),
              leading: _compactBackButton(dark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error case final error?) {
      return _StateMessage(
        icon: Icons.cloud_off_outlined,
        title: _t('No pudimos cargar el horario', 'Could not load schedule'),
        description: error,
        buttonLabel: _t('Reintentar', 'Try again'),
        onPressed: _load,
      );
    }
    final record = _selected;
    if (record == null) {
      return _StateMessage(
        key: const Key('horario-guardado-empty'),
        icon: Icons.calendar_month_outlined,
        title: _t('Aún no tienes un horario', 'You do not have a schedule yet'),
        description: _t(
          'Importa un PDF o imagen y revisa sus datos antes de guardarlo.',
          'Import a PDF or image and review its data before saving.',
        ),
        buttonLabel: _t('Importar horario', 'Import schedule'),
        onPressed: widget.writesEnabled ? _openImport : null,
      );
    }
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
      children: [
        _largeHeader(Theme.of(context).brightness == Brightness.dark),
        const SizedBox(height: 24),
        if (_records.length > 1) _selector(record),
        if (record.documentoOriginal case final document?)
          _DocumentPreview(
            document: document,
            bytes: _bytes!,
            spanish: widget.spanish,
          )
        else
          _LegacyImportCard(
            spanish: widget.spanish,
            enabled: widget.documentStorageEnabled && !_busy,
            onAttach: _attachLegacyDocument,
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('horario-guardado-download'),
          onPressed: record.documentoOriginal != null && !_busy
              ? _download
              : null,
          icon: const Icon(Icons.download_outlined),
          label: Text(_t('Descargar original', 'Download original')),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('horario-guardado-delete'),
          onPressed: widget.writesEnabled && !_busy ? _delete : null,
          icon: const Icon(Icons.delete_outline_rounded),
          label: Text(_t('Eliminar horario', 'Delete schedule')),
        ),
      ],
    );
  }

  Widget _largeHeader(bool dark) => Transform.translate(
    offset: Offset(0, -10 * _headerProgress),
    child: Opacity(
      opacity: 1 - _headerProgress,
      child: Row(
        children: [
          AppPressable(scale: .86, child: _backButton(dark, compact: false)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _t('Ver horario', 'View schedule'),
              style: TextStyle(
                color: dark ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _compactBackButton(bool dark) =>
      AppPressable(scale: .86, child: _backButton(dark, compact: true));

  Widget _backButton(bool dark, {required bool compact}) => GestureDetector(
    onTap: () => Navigator.maybePop(context),
    behavior: HitTestBehavior.opaque,
    child: Container(
      width: compact ? 38 : 46,
      height: compact ? 38 : 46,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF222833) : const Color(0xFFF4F5F8),
        borderRadius: BorderRadius.circular(compact ? 12 : 15),
        border: Border.all(
          color: dark ? const Color(0xFF303744) : const Color(0xFFE2E6ED),
        ),
      ),
      child: Icon(
        Icons.chevron_left_rounded,
        color: dark ? const Color(0xFFE7EAF0) : const Color(0xFF374151),
      ),
    ),
  );

  Widget _selector(HorarioImportacionRegistro selected) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final item in _records) ...[
            ChoiceChip(
              label: Text('${item.numeroPeriodo}° ${item.anio}'),
              selected: item.id == selected.id,
              onSelected: item.id == selected.id
                  ? null
                  : (_) => _load(selectedId: item.id),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    ),
  );
}

class _DocumentPreview extends StatelessWidget {
  const _DocumentPreview({
    required this.document,
    required this.bytes,
    required this.spanish,
  });
  final HorarioDocumentoOriginal document;
  final Uint8List bytes;
  final bool spanish;

  @override
  Widget build(BuildContext context) {
    if (document.mimeType == 'application/pdf') {
      return OcrPdfPreview(
        bytes: bytes,
        sourceName: document.nombre,
        spanish: spanish,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF11151C)
            : const Color(0xFFF3F4F8),
        height: 470,
        child: InteractiveViewer(
          minScale: .8,
          maxScale: 6,
          child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
        ),
      ),
    );
  }
}

class _LegacyImportCard extends StatelessWidget {
  const _LegacyImportCard({
    required this.spanish,
    required this.enabled,
    required this.onAttach,
  });
  final bool spanish;
  final bool enabled;
  final VoidCallback onAttach;
  String _t(String es, String en) => spanish ? es : en;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('horario-guardado-legacy-document'),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF191F29)
          : Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Column(
      children: [
        const Icon(Icons.file_present_outlined, size: 38),
        const SizedBox(height: 12),
        Text(
          _t(
            'Documento original no disponible',
            'Original document unavailable',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          _t(
            'Esta importación se creó antes de conservar archivos. Puedes asociar el original sin volver a crear asignaturas.',
            'This import was created before files were retained. You can link the original without recreating subjects.',
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const Key('horario-guardado-attach-document'),
          onPressed: enabled ? onAttach : null,
          icon: const Icon(Icons.attach_file_rounded),
          label: Text(
            _t('Asociar documento original', 'Link original document'),
          ),
        ),
      ],
    ),
  );
}

class _DeleteConfirmation extends StatelessWidget {
  const _DeleteConfirmation({required this.spanish, required this.record});
  final bool spanish;
  final HorarioImportacionRegistro record;
  String _t(String es, String en) => spanish ? es : en;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
    decoration: BoxDecoration(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF191F29)
          : Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.delete_outline_rounded,
          color: Color(0xFFEF4444),
          size: 36,
        ),
        const SizedBox(height: 12),
        Text(
          _t('¿Eliminar este horario?', 'Delete this schedule?'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          _t(
            'Se eliminarán ${record.asignaturas} asignaturas y su documento original. Las asignaturas manuales y otros horarios no se modificarán.',
            '${record.asignaturas} subjects and the original document will be deleted. Manual subjects and other schedules will not be changed.',
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('horario-guardado-confirm-delete'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444),
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(_t('Eliminar horario', 'Delete schedule')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(_t('Cancelar', 'Cancel')),
        ),
      ],
    ),
  );
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
  });
  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF5B5FEF), size: 42),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(description, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
        ],
      ),
    ),
  );
}
