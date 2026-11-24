import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';

import '../../core/navigation/main_navigation.dart';
import '../../models/horario_ocr_result.dart';
import '../../models/horario_importacion.dart';
import '../../services/horario_importacion_service.dart';
import '../../services/horario_ocr_document_service.dart';
import '../../services/horario_ocr_extraction_service.dart';
import '../../services/ocr_file_picker_service.dart';
import '../../widgets/app_transparent_app_bar.dart';
import '../../widgets/app_scroll_header.dart';
import '../../widgets/app_pressable.dart';
import '../ocr/widgets/ocr_pdf_preview.dart';
import 'horario_ocr_review_page.dart';

class HorarioOcrDiagnosticPage extends StatefulWidget {
  const HorarioOcrDiagnosticPage({
    super.key,
    required this.spanish,
    this.gateway,
    this.importacionGateway,
    this.writesEnabled = HorarioImportacionConfig.writesEnabled,
    this.showDeveloperDiagnostics = false,
  });

  final bool spanish;
  final HorarioOcrDocumentGateway? gateway;
  final HorarioImportacionGateway? importacionGateway;
  final bool writesEnabled;
  final bool showDeveloperDiagnostics;

  @override
  State<HorarioOcrDiagnosticPage> createState() =>
      _HorarioOcrDiagnosticPageState();
}

class _HorarioOcrDiagnosticPageState extends State<HorarioOcrDiagnosticPage> {
  late final HorarioOcrDocumentGateway _gateway;
  late final HorarioImportacionGateway? _importacionGateway;
  OcrPickedFile? _file;
  HorarioOcrRunOutcome? _outcome;
  bool _selecting = false;
  bool _processing = false;
  bool _deleting = false;
  String? _error;
  final ScrollController _scrollController = ScrollController();
  double _headerProgress = 0;

  String _t(String es, String en) => widget.spanish ? es : en;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? HorarioOcrDocumentService();
    _importacionGateway =
        widget.importacionGateway ??
        (widget.writesEnabled ? HorarioImportacionService() : null);
    _scrollController.addListener(_updateHeader);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _updateHeader() {
    final progress = _scrollController.offset >= 24 ? 1.0 : 0.0;
    if (progress != _headerProgress && mounted) {
      setState(() => _headerProgress = progress);
    }
  }

  Future<void> _pick() async {
    if (_selecting || _processing) return;
    setState(() {
      _selecting = true;
      _error = null;
    });
    try {
      final file = await _gateway.pickDocument();
      if (!mounted || file == null) return;
      setState(() {
        _file = file;
        _outcome = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _safeError(error));
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  Future<void> _process() async {
    final file = _file;
    if (file == null || _processing) return;
    setState(() {
      _processing = true;
      _error = null;
      _outcome = null;
    });
    try {
      final outcome = await _gateway.extractWithDiagnostics(file);
      if (!mounted) return;
      setState(() => _outcome = outcome);
      if (!widget.showDeveloperDiagnostics &&
          outcome.result.subjects.isNotEmpty) {
        await _openReview(outcome.result);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _safeError(error));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  String _safeError(Object error) {
    final value = error.toString().replaceFirst(
      RegExp(r'^\w+Exception:\s*'),
      '',
    );
    return value.isEmpty
        ? _t(
            'No fue posible analizar el documento.',
            'Document analysis failed.',
          )
        : value;
  }

  Future<void> _openReview(HorarioOcrResult result) async {
    final file = _file;
    if (file == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => HorarioOcrReviewPage(
          result: result,
          spanish: widget.spanish,
          documentHash: result.documentHash,
          sourceName: file.name,
          originalFile: file,
          importacionGateway: _importacionGateway,
          writesEnabled: widget.writesEnabled,
        ),
      ),
    );
    if (saved == true && mounted) {
      if (!widget.showDeveloperDiagnostics) {
        final navigator = Navigator.of(context);
        MainNavigation.goTo(context, SeccionPrincipal.horario);
        if (navigator.canPop()) navigator.pop(true);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'Horario importado correctamente.',
              'Schedule imported successfully.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _deleteImport() async {
    if (!widget.writesEnabled || _deleting) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      final imports = await _importacionGateway!.listar();
      if (!mounted) return;
      if (imports.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                'No hay horarios importados.',
                'There are no imported schedules.',
              ),
            ),
          ),
        );
        return;
      }
      final selected = await showModalBottomSheet<HorarioImportacionRegistro>(
        context: context,
        useSafeArea: true,
        builder: (context) => ListView(
          key: const Key('horario-import-delete-list'),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            ListTile(
              title: Text(
                _t('Eliminar horario importado', 'Delete imported schedule'),
              ),
              subtitle: Text(
                _t(
                  'Selecciona exactamente la importación de prueba.',
                  'Select the exact test import.',
                ),
              ),
            ),
            for (final item in imports)
              ListTile(
                title: Text(item.nombreDocumento),
                subtitle: Text(
                  '${item.numeroPeriodo}° ${item.anio} · '
                  '${item.asignaturas} ${_t('asignaturas', 'subjects')} · '
                  '${item.bloques} ${_t('bloques', 'blocks')} · '
                  '${item.sesiones} ${_t('sesiones', 'sessions')}',
                ),
                onTap: () => Navigator.pop(context, item),
              ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_t('Confirmar eliminación', 'Confirm deletion')),
          content: Text(
            _t(
              'Se eliminarán únicamente ${selected.asignaturas} asignaturas, ${selected.bloques} bloques y ${selected.sesiones} sesiones creadas por ${selected.nombreDocumento}. La operación se cancelará si existen datos académicos posteriores asociados.',
              'Only ${selected.asignaturas} subjects, ${selected.bloques} blocks, and ${selected.sesiones} sessions created by ${selected.nombreDocumento} will be deleted. The operation will be canceled if later academic data is linked.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_t('Cancelar', 'Cancel')),
            ),
            FilledButton(
              key: const Key('horario-import-confirm-delete'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(_t('Eliminar importación', 'Delete import')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final result = await _importacionGateway.eliminar(selected.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              '${result.asignaturasEliminadas} asignaturas importadas fueron eliminadas.',
              '${result.asignaturasEliminadas} imported subjects were deleted.',
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _safeError(error));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showDeveloperDiagnostics) return _buildOfficialImport();
    return _buildDeveloperView();
  }

  Widget _buildOfficialImport() {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final horizontal = constraints.maxWidth <= 600 ? 10.0 : 24.0;
                return ListView(
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 48),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _officialHeader(theme),
                            const SizedBox(height: 28),
                            Text(
                              _t('SELECCIONAR ARCHIVO', 'SELECT FILE'),
                              style: const TextStyle(
                                color: Color(0xFF5B5FEF),
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _officialFilePicker(theme),
                            const SizedBox(height: 9),
                            Text(
                              _t(
                                'PDF, JPEG, PNG o WebP · Máximo 10 MB',
                                'PDF, JPEG, PNG or WebP · Up to 10 MB',
                              ),
                              style: theme.textTheme.bodySmall,
                            ),
                            if (_file case final file?) ...[
                              const SizedBox(height: 16),
                              _officialSelectedFile(theme, file),
                              const SizedBox(height: 14),
                              _preview(file),
                              const SizedBox(height: 14),
                              FilledButton.icon(
                                key: const Key('horario-ocr-process-document'),
                                onPressed: _processing ? null : _process,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                icon: _processing
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.document_scanner_outlined,
                                      ),
                                label: Text(
                                  _processing
                                      ? _t('Analizando…', 'Analyzing…')
                                      : _t(
                                          'Analizar horario',
                                          'Analyze schedule',
                                        ),
                                ),
                              ),
                            ],
                            if (_error case final error?) ...[
                              const SizedBox(height: 16),
                              _errorCard(error),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AppScrollHeader(
                progress: _headerProgress,
                opaqueBackground: true,
                title: _t('Importar horario', 'Import schedule'),
                leading: _compactBackButton(dark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _officialHeader(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: dark ? const Color(0xFF191F29) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            key: const Key('horario-import-back-button'),
            borderRadius: BorderRadius.circular(15),
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: dark
                      ? const Color(0xFF2B323E)
                      : const Color(0xFFE2E6ED),
                ),
              ),
              child: Icon(
                Ionicons.chevronBackOutline,
                color: dark ? const Color(0xFFE5E9F0) : const Color(0xFF374151),
                size: 21,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'EDUCFLOW AI',
                style: TextStyle(
                  color: Color(0xFF5B5FEF),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 5),
              Opacity(
                opacity: _headerProgress == 0 ? 1 : 0,
                child: Text(
                  _t('Importar horario', 'Import schedule'),
                  style: TextStyle(
                    color: dark
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF111827),
                    fontSize: 32,
                    height: 1.08,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _t(
                  'Selecciona tu horario para detectar clases y revisar toda la información antes de guardar.',
                  'Choose your schedule to detect classes and review all information before saving.',
                ),
                style: TextStyle(
                  color: dark
                      ? const Color(0xFFA9B1BF)
                      : const Color(0xFF6B7280),
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  BoxDecoration _panelDecoration(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    return BoxDecoration(
      color: dark ? const Color(0xFF191F29) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: dark ? const Color(0xFF2B323E) : const Color(0xFFE7EAF0),
      ),
    );
  }

  Widget _officialFilePicker(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    return Material(
      color: dark ? const Color(0xFF191F29) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: const Key('horario-ocr-select-document'),
        onTap: _selecting || _processing ? null : _pick,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: _panelDecoration(theme),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xFF292F47)
                      : const Color(0xFFEEF0FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _selecting
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Ionicons.documentTextOutline,
                        color: dark
                            ? const Color(0xFFB8BBFF)
                            : const Color(0xFF5B5FEF),
                        size: 23,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _file == null
                      ? _t('Elegir PDF o imagen', 'Choose PDF or image')
                      : _t('Cambiar archivo', 'Change file'),
                  style: TextStyle(
                    color: dark
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF1F2937),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: dark ? const Color(0xFF7F899A) : const Color(0xFF9CA3AF),
                size: 21,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _officialSelectedFile(
    ThemeData theme,
    OcrPickedFile file,
  ) => Container(
    padding: const EdgeInsets.all(14),
    decoration: _panelDecoration(theme),
    child: Row(
      children: [
        Icon(
          file.mimeType == 'application/pdf'
              ? Icons.picture_as_pdf_outlined
              : Icons.image_outlined,
          color: const Color(0xFF5B5FEF),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                '${file.mimeType} · ${(file.sizeBytes / 1024).toStringAsFixed(1)} KiB',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _compactBackButton(bool dark) => AppPressable(
    scale: 0.86,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).maybePop(),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF202631) : const Color(0xFFF4F5F8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: dark ? const Color(0xFF343C48) : const Color(0xFFE2E6ED),
          ),
        ),
        child: Icon(
          Ionicons.chevronBackOutline,
          color: dark ? const Color(0xFFE5E9F0) : const Color(0xFF374151),
          size: 19,
        ),
      ),
    ),
  );

  Widget _buildDeveloperView() {
    return Scaffold(
      appBar: AppTransparentAppBar(
        title: widget.showDeveloperDiagnostics
            ? _t('Diagnóstico OCR de horario', 'Schedule OCR diagnostic')
            : _t('Importar horario', 'Import schedule'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _notice(),
            if (widget.showDeveloperDiagnostics) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('horario-import-delete'),
                onPressed: widget.writesEnabled && !_deleting
                    ? _deleteImport
                    : null,
                icon: _deleting
                    ? const Icon(Icons.hourglass_top_rounded)
                    : const Icon(Icons.delete_sweep_outlined),
                label: Text(
                  widget.writesEnabled
                      ? _t(
                          'Eliminar horario importado',
                          'Delete imported schedule',
                        )
                      : _t(
                          'Eliminación pendiente de autorización',
                          'Deletion pending authorization',
                        ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('horario-ocr-select-document'),
              onPressed: _selecting || _processing ? null : _pick,
              icon: _selecting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_rounded),
              label: Text(
                _t('Seleccionar PDF o imagen', 'Select PDF or image'),
              ),
            ),
            if (_file case final file?) ...[
              const SizedBox(height: 16),
              _fileCard(file),
              const SizedBox(height: 12),
              _preview(file),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                key: const Key('horario-ocr-process-document'),
                onPressed: _processing ? null : _process,
                icon: _processing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.document_scanner_outlined),
                label: Text(
                  _processing
                      ? _t('Analizando…', 'Analyzing…')
                      : widget.showDeveloperDiagnostics
                      ? _t('Ejecutar diagnóstico', 'Run diagnostic')
                      : _t('Analizar horario', 'Analyze schedule'),
                ),
              ),
            ],
            if (_error case final error?) ...[
              const SizedBox(height: 16),
              _errorCard(error),
            ],
            if (_outcome case final outcome?) ...[
              const SizedBox(height: 24),
              _validatedResult(outcome),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('horario-ocr-open-review'),
                onPressed: outcome.result.subjects.isEmpty
                    ? null
                    : () => _openReview(outcome.result),
                icon: const Icon(Icons.edit_calendar_outlined),
                label: Text(_t('Revisar horario', 'Review schedule')),
              ),
              if (widget.showDeveloperDiagnostics) ...[
                const SizedBox(height: 16),
                _rawStage(
                  key: const Key('horario-ocr-vision-result'),
                  title: 'Google Cloud Vision',
                  subtitle: _t(
                    'Texto y geometría compacta entregados a Gemini.',
                    'Compact text and geometry passed to Gemini.',
                  ),
                  value: _prettyJson(outcome.visionContext),
                ),
                const SizedBox(height: 12),
                _rawStage(
                  key: const Key('horario-ocr-gemini-result'),
                  title: 'Gemini',
                  subtitle: _t(
                    'JSON original antes de las validaciones locales.',
                    'Original JSON before local validation.',
                  ),
                  value: _prettyGemini(outcome.geminiJson),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _notice() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.science_outlined, color: Color(0xFF5B5FEF)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.showDeveloperDiagnostics
                  ? _t(
                      'Herramienta temporal de desarrollo. Procesa un documento a la vez y muestra las respuestas técnicas de Vision y Gemini.',
                      'Temporary development tool. It processes one document at a time and shows the technical Vision and Gemini responses.',
                    )
                  : _t(
                      'Selecciona un PDF o una imagen. Podrás revisar y corregir toda la información antes de guardar el horario.',
                      'Select a PDF or image. You can review and correct all information before saving the schedule.',
                    ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _fileCard(OcrPickedFile file) => Card(
    child: ListTile(
      leading: Icon(
        file.mimeType == 'application/pdf'
            ? Icons.picture_as_pdf_outlined
            : Icons.image_outlined,
      ),
      title: Text(file.name),
      subtitle: Text(
        '${file.mimeType} · ${(file.sizeBytes / 1024).toStringAsFixed(1)} KiB',
      ),
    ),
  );

  Widget _preview(OcrPickedFile file) {
    if (file.mimeType == 'application/pdf') {
      return OcrPdfPreview(
        bytes: file.bytes,
        sourceName: file.name,
        spanish: widget.spanish,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(
        file.bytes,
        height: 320,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const SizedBox(
          height: 160,
          child: Center(child: Icon(Icons.broken_image_outlined, size: 40)),
        ),
      ),
    );
  }

  Widget _errorCard(String error) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(error, key: const Key('horario-ocr-error')),
    ),
  );

  Widget _validatedResult(HorarioOcrRunOutcome outcome) {
    final result = outcome.result;
    final diagnostics = outcome.diagnostics;
    final period = result.period;
    final semester = period.semester == null ? '?' : '${period.semester}';
    final year = period.year == null ? '?' : '${period.year}';
    return Card(
      key: const Key('horario-ocr-validated-result'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _t('Resultado validado', 'Validated result'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              _t(
                'Período detectado: semestre $semester de $year',
                'Detected period: semester $semester of $year',
              ),
            ),
            Text(
              _t(
                '${diagnostics.pageCount} páginas · ${result.subjects.length} asignaturas · revisión humana obligatoria',
                '${diagnostics.pageCount} pages · ${result.subjects.length} subjects · human review required',
              ),
            ),
            if (period.startDate != null || period.endDate != null)
              Text('${_date(period.startDate)} — ${_date(period.endDate)}'),
            const Divider(height: 28),
            for (final subject in result.subjects) ...[
              _subject(subject),
              const Divider(height: 28),
            ],
            _reviewList(result),
            const SizedBox(height: 8),
            Text(
              _t(
                'Diagnóstico solamente: no existe una acción de guardado.',
                'Diagnostic only: no save action is available.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _subject(HorarioOcrSubject subject) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        subject.name ?? _t('Nombre pendiente', 'Name pending'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      Text(
        [
          if (subject.code?.isNotEmpty == true) subject.code!,
          if (subject.section?.isNotEmpty == true)
            _t('Sección ${subject.section}', 'Section ${subject.section}'),
        ].join(' · '),
      ),
      if (subject.professor?.isNotEmpty == true)
        Text(
          _t(
            'Profesor: ${subject.professor}',
            'Professor: ${subject.professor}',
          ),
        ),
      if (subject.professorEmail?.isNotEmpty == true)
        Text(subject.professorEmail!),
      if (subject.weeklyBlocks.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(_t('Clases semanales', 'Weekly classes')),
        for (final block in subject.weeklyBlocks)
          Text(
            '• ${_day(block.day)} ${block.startTime ?? '?'}–${block.endTime ?? '?'}${_room(block.room)}',
          ),
      ],
      if (subject.datedSessions.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(_t('Sesiones con fecha específica', 'Dated sessions')),
        for (final session in subject.datedSessions)
          Text(
            '• ${_date(session.date)} ${session.startTime ?? '?'}–${session.endTime ?? '?'}${_room(session.room)}',
          ),
      ],
      for (final pending in subject.pendingReasons)
        Text('⚠ $pending', style: Theme.of(context).textTheme.bodySmall),
    ],
  );

  Widget _reviewList(HorarioOcrResult result) {
    final messages = <String>{
      ...result.pendingReview,
      ...result.period.pendingReasons,
      ...result.issues.map((issue) => issue.message),
    };
    if (messages.isEmpty) {
      return Text(
        _t('Sin advertencias adicionales.', 'No additional warnings.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t('Advertencias y pendientes', 'Warnings and pending data'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        for (final message in messages) Text('• $message'),
      ],
    );
  }

  Widget _rawStage({
    required Key key,
    required String title,
    required String subtitle,
    required String value,
  }) => ExpansionTile(
    key: key,
    initiallyExpanded: title == 'Google Cloud Vision',
    tilePadding: const EdgeInsets.symmetric(horizontal: 16),
    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    title: Text(title),
    subtitle: Text(subtitle),
    children: [
      SelectableText(
        value.isEmpty ? _t('Sin datos.', 'No data.') : value,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    ],
  );

  String _prettyJson(Object value) =>
      const JsonEncoder.withIndent('  ').convert(value);

  String _prettyGemini(String value) {
    if (value.trim().isEmpty) return '';
    try {
      return _prettyJson(jsonDecode(value));
    } catch (_) {
      return value;
    }
  }

  String _date(DateTime? value) {
    if (value == null) return '?';
    return '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/${value.year}';
  }

  String _room(String? room) =>
      room?.isNotEmpty == true ? _t(' · sala $room', ' · room $room') : '';

  String _day(HorarioOcrDay? day) => switch (day) {
    HorarioOcrDay.lunes => _t('Lunes', 'Monday'),
    HorarioOcrDay.martes => _t('Martes', 'Tuesday'),
    HorarioOcrDay.miercoles => _t('Miércoles', 'Wednesday'),
    HorarioOcrDay.jueves => _t('Jueves', 'Thursday'),
    HorarioOcrDay.viernes => _t('Viernes', 'Friday'),
    HorarioOcrDay.sabado => _t('Sábado', 'Saturday'),
    HorarioOcrDay.domingo => _t('Domingo', 'Sunday'),
    null => '?',
  };
}
