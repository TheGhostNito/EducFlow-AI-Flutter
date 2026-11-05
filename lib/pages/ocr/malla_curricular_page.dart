import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/malla_curricular.dart';
import '../../models/malla_review.dart';
import '../../services/malla_curricular_service.dart';
import '../../services/ocr_document_service.dart';
import '../../services/ocr_file_picker_service.dart';
import '../../services/translation_service.dart';
import '../../widgets/app_status_snackbar.dart';
import '../profile/widgets/profile_option_sheet.dart';
import '../../widgets/app_scroll_header.dart';
import '../../widgets/app_pressable.dart';
import 'malla_ui_failure.dart';

class MallaCurricularPage extends StatefulWidget {
  const MallaCurricularPage({super.key, this.service, this.documents});

  final MallaCurricularGateway? service;
  final OcrDocumentGateway? documents;

  @override
  State<MallaCurricularPage> createState() => _MallaCurricularPageState();
}

class _MallaCurricularPageState extends State<MallaCurricularPage> {
  late final MallaCurricularGateway _service =
      widget.service ?? MallaCurricularService();
  late final OcrDocumentGateway _documents =
      widget.documents ?? OcrDocumentService();
  final _translation = TranslationService.instance;
  MallaCurricular? _saved;
  MallaCurricular? _preview;
  OcrPickedFile? _file;
  bool _busy = true;
  MallaUiFailure? _loadFailure;
  MallaUiFailure? _actionFailure;
  bool _loadVerified = false;
  bool _reviewOnly = false;
  int? _selectedSemester;
  String _status = '';
  int _newId = 0;
  final ScrollController _scrollController = ScrollController();
  double _headerProgress = 0;

  bool get _es => _translation.isSpanish;
  String _t(String es, String en) => _es ? es : en;
  bool get _backendReady => _loadVerified && _loadFailure == null;

  Future<void> _selectSemester(List<int> semesters, int? selected) async {
    final value = await showProfileOptionSheet<int>(
      context: context,
      title: _t('Semestre', 'Semester'),
      options: [
        for (final semester in semesters)
          ProfileOption(
            value: semester,
            label: _t('Semestre $semester', 'Semester $semester'),
          ),
      ],
      selectedValue: selected,
    );
    if (mounted && value != null) setState(() => _selectedSemester = value);
  }

  @override
  void initState() {
    super.initState();
    _translation.addListener(_languageChanged);
    _scrollController.addListener(_updateHeader);
    _load();
  }

  @override
  void dispose() {
    _translation.removeListener(_languageChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateHeader() {
    // El título grande aún queda bajo el encabezado durante su fundido.
    // Cambiamos de uno a otro con una superficie completamente opaca.
    final progress = _scrollController.offset >= 24 ? 1.0 : 0.0;
    if (progress != _headerProgress) {
      setState(() => _headerProgress = progress);
    }
  }

  void _languageChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _loadFailure = null;
      _actionFailure = null;
      _loadVerified = false;
      _status = _t('Cargando tu malla…', 'Loading your curriculum…');
    });
    try {
      final saved = await _service.cargar();
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _loadVerified = true;
        _selectedSemester = saved?.semestres.firstOrNull;
      });
    } catch (error, stack) {
      _logFailure('load', error, stack);
      if (!mounted) return;
      setState(() => _loadFailure = MallaUiFailure.fromLoad(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    try {
      final file = await _documents.pickDocument();
      if (!mounted || file == null) return;
      if (file.sizeBytes > 10 * 1024 * 1024) {
        throw ArgumentError(
          _t('El archivo supera 10 MB.', 'The file exceeds 10 MB.'),
        );
      }
      setState(() {
        _file = file;
        _preview = null;
        _actionFailure = null;
      });
    } catch (error, stack) {
      _logFailure('pick', error, stack);
      if (mounted) {
        setState(() => _actionFailure = MallaUiFailure.fromTransfer(error));
      }
    }
  }

  Future<void> _process() async {
    final file = _file;
    if (file == null || !_backendReady) return;
    setState(() {
      _busy = true;
      _actionFailure = null;
      _status = _t('Subiendo el documento…', 'Uploading document…');
    });
    OcrDocumentResult? uploaded;
    try {
      uploaded = await _documents.upload(file);
      if (!mounted) return;
      setState(
        () => _status = _t(
          'Analizando la malla con OCR…',
          'Analyzing curriculum with OCR…',
        ),
      );
      final parsed = await _service.procesar(uploaded, fileName: file.name);
      if (!mounted) return;
      setState(() {
        _preview = parsed;
        _selectedSemester = parsed.semestres.firstOrNull;
        _reviewOnly = false;
        _status = _t(
          'Revisa el resultado antes de guardarlo.',
          'Review the result before saving.',
        );
      });
      try {
        await _documents.deleteUploadedFile(uploaded.path);
      } catch (_) {
        // La limpieza del temporal no invalida la revisión del OCR.
      }
    } catch (error, stack) {
      _logFailure('process', error, stack);
      if (uploaded != null) {
        try {
          await _documents.deleteUploadedFile(uploaded.path);
        } catch (_) {
          // El OCR o la limpieza del backend pueden haber quitado el temporal.
        }
      }
      if (mounted) {
        setState(() => _actionFailure = MallaUiFailure.fromTransfer(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _logFailure(String step, Object error, StackTrace stack) {
    if (!kDebugMode) return;
    final code = MallaUiFailure.diagnosticCode(error);
    final httpCode = error is PostgrestException ? error.code : null;
    final status = error is FunctionException ? error.status : null;
    debugPrint(
      'Malla $step: ${error.runtimeType}; code=$code; '
      'httpCode=$httpCode; status=$status',
    );
    debugPrint(stack.toString().split('\n').take(4).join(' | '));
  }

  Future<void> _edit(RamoMalla? ramo) async {
    final preview = _preview;
    if (preview == null) return;
    final result = await showDialog<_RamoEditResult>(
      context: context,
      builder: (_) => _RamoEditDialog(
        malla: preview,
        ramo: ramo,
        newRamoId: 'manual_${_newId + 1}',
        spanish: _es,
        saved: false,
      ),
    );
    if (result == null || !mounted || _preview != preview) return;
    final edited = result.ramo;
    final index = ramo == null
        ? -1
        : preview.ramos.indexWhere((item) => item.id == ramo.id);
    if (ramo != null && index < 0) return;
    setState(() {
      if (ramo == null) {
        _newId++;
        preview.ramos.add(edited);
      } else {
        preview.ramos[index] = edited;
      }
      _selectedSemester = edited.semestre;
    });
  }

  Future<void> _editSaved(RamoMalla ramo) async {
    final saved = _saved;
    if (saved == null || _busy) return;
    final result = await showDialog<_RamoEditResult>(
      context: context,
      builder: (_) => _RamoEditDialog(
        malla: saved,
        ramo: ramo,
        newRamoId: ramo.id,
        spanish: _es,
        saved: true,
      ),
    );
    if (result == null || !mounted || _saved != saved) return;
    setState(() => _busy = true);
    try {
      final updated = await _service.editarRamo(
        saved,
        result.ramo,
        confirmarRevision: result.confirmarRevision,
        codigoDuplicadoVerificado: result.codigoDuplicadoVerificado,
      );
      if (!mounted) return;
      setState(() {
        _saved = updated;
        _selectedSemester = result.ramo.semestre;
      });
      showAppStatusSnackBar(
        context,
        message: _t('Asignatura actualizada.', 'Course updated.'),
      );
    } catch (error, stack) {
      _logFailure('edit', error, stack);
      if (mounted) {
        showAppStatusSnackBar(
          context,
          message: MallaUiFailure.from(error).description(_es),
          type: AppStatusType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final preview = _preview;
    if (preview == null || preview.ramos.isEmpty || !_backendReady || _busy) {
      return;
    }
    final ambiguous = MallaReviewRules.pendingCount(preview);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF18181D)
            : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(_t('Confirmar malla', 'Confirm curriculum')),
        content: Text(
          _t(
            'Guardarás ${preview.ramos.length} asignaturas en ${preview.semestres.length} semestres. $ambiguous elementos siguen marcados para revisión. Esta importación no reemplazará una malla existente.',
            'You will save ${preview.ramos.length} courses in ${preview.semestres.length} semesters. $ambiguous items remain marked for review. This import will not replace an existing curriculum.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('Volver a revisar', 'Review again')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('Confirmar y guardar', 'Confirm and save')),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      _busy = true;
      _actionFailure = null;
      _status = _t('Guardando la malla…', 'Saving curriculum…');
    });
    try {
      final saved = await _service.confirmar(preview);
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _preview = null;
        _file = null;
        _selectedSemester = saved.semestres.firstOrNull;
      });
      showAppStatusSnackBar(
        context,
        message: _t('Malla guardada correctamente.', 'Curriculum saved.'),
      );
    } catch (error, stack) {
      _logFailure('confirm', error, stack);
      if (mounted) {
        final failure = MallaUiFailure.from(error);
        setState(() {
          if (failure.blocksProcessing) {
            _loadFailure = failure;
            _loadVerified = false;
          } else {
            _actionFailure = failure;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _details(RamoMalla ramo) async {
    final edit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF191F29)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(sheetContext).brightness == Brightness.dark
                        ? const Color(0xFF48505E)
                        : const Color(0xFFD5D9E0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ramo.nombre,
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: _t('Cerrar', 'Close'),
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _t('Semestre ${ramo.semestre}', 'Semester ${ramo.semestre}'),
              ),
              if (ramo.codigo != null)
                Text(_t('Código: ${ramo.codigo}', 'Code: ${ramo.codigo}')),
              if (ramo.creditos != null)
                Text(
                  _t('Créditos: ${ramo.creditos}', 'Credits: ${ramo.creditos}'),
                ),
              for (final issue in MallaReviewRules.issuesFor(_saved!, ramo))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(issue.label(_es)),
                ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(sheetContext, true),
                icon: const Icon(Icons.edit_outlined),
                label: Text(_t('Corregir datos', 'Edit details')),
              ),
              const SizedBox(height: 12),
              _selectionField(
                Theme.of(sheetContext),
                key: const Key('malla-state-selector'),
                label: _t('Estado académico', 'Academic status'),
                value: _statusLabel(ramo.estado),
                icon: Ionicons.checkmarkCircleOutline,
                onTap: () async {
                  final value = await showProfileOptionSheet<String>(
                    context: sheetContext,
                    title: _t('Estado académico', 'Academic status'),
                    options: [
                      ProfileOption(
                        value: 'pendiente',
                        label: _t('Pendiente', 'Pending'),
                      ),
                      ProfileOption(
                        value: 'en_curso',
                        label: _t('En curso', 'In progress'),
                      ),
                      ProfileOption(
                        value: 'aprobada',
                        label: _t('Aprobada', 'Passed'),
                      ),
                    ],
                    selectedValue: ramo.estado,
                  );
                  if (!sheetContext.mounted ||
                      value == null ||
                      value == ramo.estado) {
                    return;
                  }
                  try {
                    await _service.cambiarEstado(ramo, value);
                    if (!mounted) return;
                    setState(() {});
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  } catch (error, stack) {
                    _logFailure('state', error, stack);
                    if (sheetContext.mounted) {
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        SnackBar(
                          content: Text(
                            MallaUiFailure.from(error).description(_es),
                          ),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (edit == true && mounted) await _editSaved(ramo);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final malla = _saved ?? _preview;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final horizontal = constraints.maxWidth <= 600
                    ? 10.0
                    : constraints.maxWidth <= 900
                    ? 24.0
                    : 40.0;
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
                            _header(theme),
                            const SizedBox(height: 28),
                            if (!_loadVerified &&
                                _loadFailure == null &&
                                malla == null)
                              const SizedBox(
                                height: 360,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                  ),
                                ),
                              ),
                            if (_busy && _loadVerified) ...[
                              _progress(theme),
                              const SizedBox(height: 16),
                            ],
                            if (malla == null && _loadVerified)
                              _fileSection(theme),
                            if (_loadFailure != null) ...[
                              const SizedBox(height: 14),
                              _failurePanel(theme, _loadFailure!, retry: _load),
                            ],
                            if (_actionFailure != null) ...[
                              const SizedBox(height: 14),
                              _failurePanel(theme, _actionFailure!),
                            ],
                            if (malla != null) _mallaSection(theme, malla),
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
                title: _t('Malla curricular', 'Curriculum'),
                opaqueBackground: true,
                leading: _compactBackButton(
                  theme.brightness == Brightness.dark,
                ),
              ),
            ),
          ],
        ),
      ),
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

  Widget _compactBackButton(bool dark) => AppPressable(
    scale: 0.86,
    child: Semantics(
      button: true,
      label: _t('Volver', 'Back'),
      child: GestureDetector(
        key: const Key('malla-compact-back-button'),
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
    ),
  );

  Widget _selectionField(
    ThemeData theme, {
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
    Key? key,
  }) {
    final dark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 7),
        Material(
          color: dark ? const Color(0xFF202631) : const Color(0xFFFAFBFC),
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            key: key,
            onTap: onTap,
            borderRadius: BorderRadius.circular(13),
            child: Container(
              constraints: const BoxConstraints(minHeight: 50),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: dark
                      ? const Color(0xFF343C48)
                      : const Color(0xFFDFE3EA),
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, color: const Color(0xFF5B5FEF), size: 20),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 21),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    final description = _saved != null
        ? _t(
            'Consulta tus ramos y actualiza su estado académico.',
            'View your courses and update their academic status.',
          )
        : _preview != null
        ? _t(
            'Revisa las asignaturas detectadas antes de guardar.',
            'Review the detected courses before saving.',
          )
        : _t(
            'Selecciona tu malla para detectar asignaturas y revisarlas antes de guardar.',
            'Choose your curriculum to detect and review courses before saving.',
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: dark ? const Color(0xFF191F29) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            key: const Key('malla-back-button'),
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
                key: const Key('malla-large-title-visibility'),
                opacity: _headerProgress == 0 ? 1 : 0,
                child: Text(
                  _t('Malla curricular', 'Curriculum'),
                  key: const Key('malla-large-title'),
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
                description,
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

  Widget _progress(ThemeData theme) => Container(
    decoration: _panelDecoration(theme),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.hourglass_top_rounded,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(_status, style: theme.textTheme.titleSmall)),
            ],
          ),
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
      ),
    ),
  );

  Widget _failurePanel(
    ThemeData theme,
    MallaUiFailure failure, {
    VoidCallback? retry,
  }) {
    final setup = failure.kind == MallaFailureKind.setup;
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: setup
            ? (dark ? const Color(0xFF191F29) : Colors.white)
            : colors.errorContainer.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: setup
              ? (dark ? const Color(0xFF2B323E) : const Color(0xFFE7EAF0))
              : colors.error.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            setup ? Icons.info_outline_rounded : Icons.error_outline_rounded,
            color: setup ? const Color(0xFF5B5FEF) : colors.onErrorContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  failure.title(_es),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(failure.description(_es)),
                if (retry != null && !setup) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _busy ? null : retry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(_t('Comprobar nuevamente', 'Check again')),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileSection(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    final file = _file;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        Material(
          color: dark ? const Color(0xFF191F29) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            key: const Key('malla-file-picker'),
            borderRadius: BorderRadius.circular(18),
            onTap: _busy ? null : _pick,
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
                    child: Icon(
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
                      file == null
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
                    color: dark
                        ? const Color(0xFF7F899A)
                        : const Color(0xFF9CA3AF),
                    size: 21,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 9),
        Text(
          _t(
            'PDF, JPEG, PNG o WebP · Máximo 10 MB',
            'PDF, JPEG, PNG or WebP · Up to 10 MB',
          ),
          style: theme.textTheme.bodySmall,
        ),
        if (file != null) ...[
          const SizedBox(height: 14),
          Container(
            decoration: _panelDecoration(theme),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        file.mimeType == 'application/pdf'
                            ? Icons.picture_as_pdf_outlined
                            : Icons.image_outlined,
                        color: const Color(0xFF5B5FEF),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          file.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${(file.sizeBytes / 1024).toStringAsFixed(0)} KB · ${file.mimeType}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (file.mimeType.startsWith('image/')) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 250),
                        child: Image.memory(file.bytes, fit: BoxFit.contain),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    Text(
                      _t(
                        'PDF seleccionado. La vista de páginas aún no está disponible.',
                        'PDF selected. Page preview is not available yet.',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('malla-process-button'),
            onPressed: !_busy && _backendReady ? _process : null,
            icon: const Icon(Icons.document_scanner_outlined),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_t('Analizar con OCR', 'Analyze with OCR')),
            ),
          ),
          if (!_backendReady) ...[
            const SizedBox(height: 7),
            Text(
              _t(
                'Primero debemos verificar que tu malla pueda guardarse.',
                'We must first verify that your curriculum can be saved.',
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ],
    );
  }

  Widget _mallaSection(ThemeData theme, MallaCurricular malla) {
    final reviewCount = MallaReviewRules.pendingCount(malla);
    final reviewOnly = _reviewOnly;
    final semesters = malla.semestres;
    final selected = semesters.contains(_selectedSemester)
        ? _selectedSemester
        : semesters.firstOrNull;
    final visible = malla.ramos
        .where(
          (ramo) =>
              ramo.semestre == selected &&
              (!reviewOnly ||
                  MallaReviewRules.issuesFor(malla, ramo).isNotEmpty),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_saved != null) ...[
          Container(
            key: const Key('malla-review-summary'),
            padding: const EdgeInsets.all(16),
            decoration: _panelDecoration(theme),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reviewCount > 0
                      ? _t(
                          'Tu malla tiene $reviewCount ${reviewCount == 1 ? 'asignatura' : 'asignaturas'} que ${reviewCount == 1 ? 'necesita' : 'necesitan'} revisión. Comprueba sus datos para mantener tu plan actualizado.',
                          '$reviewCount ${reviewCount == 1 ? 'course needs' : 'courses need'} review. Check the details to keep your curriculum up to date.',
                        )
                      : _t(
                          'Tu malla está completamente revisada.',
                          'Your curriculum has been fully reviewed.',
                        ),
                ),
                if (reviewCount > 0)
                  TextButton.icon(
                    onPressed: () {
                      final first = malla.ramos.firstWhere(
                        (ramo) =>
                            MallaReviewRules.issuesFor(malla, ramo).isNotEmpty,
                      );
                      setState(() {
                        _reviewOnly = true;
                        _selectedSemester = first.semestre;
                      });
                    },
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(_t('Ver pendientes', 'View items to review')),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        Container(
          padding: const EdgeInsets.all(17),
          decoration: _panelDecoration(theme),
          child: Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _count(
                theme,
                '${malla.ramos.length}',
                _t('Asignaturas', 'Courses'),
                Icons.menu_book_outlined,
              ),
              _count(
                theme,
                '${semesters.length}',
                _t('Semestres', 'Semesters'),
                Icons.view_week_outlined,
              ),
              _count(
                theme,
                '$reviewCount',
                _t('Por revisar', 'To review'),
                Icons.fact_check_outlined,
              ),
            ],
          ),
        ),
        const SizedBox(height: 17),
        if (_preview != null && malla.especiales.isNotEmpty) ...[
          Text(
            _t('Otros elementos detectados', 'Other detected elements'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _t(
              'Agrégalos solo si corresponden a ramos de tu malla.',
              'Add these only if they are courses in your curriculum.',
            ),
          ),
          const SizedBox(height: 9),
          for (final special in malla.especiales)
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(special.nombre),
                subtitle: Text(
                  [
                    special.tipo,
                    if (special.semestre != null)
                      _t(
                        'Semestre ${special.semestre}',
                        'Semester ${special.semestre}',
                      ),
                    if (special.creditos != null)
                      _t(
                        '${special.creditos} créditos',
                        '${special.creditos} credits',
                      ),
                    ...special.motivosRevision.map(_reasonLabel),
                  ].join(' · '),
                ),
                trailing: IconButton(
                  tooltip: _t('Añadir a la malla', 'Add to curriculum'),
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => setState(() {
                    malla.ramos.add(
                      RamoMalla(
                        id: 'special_${++_newId}',
                        nombre: special.nombre,
                        semestre: special.semestre ?? 1,
                        codigo: special.codigo,
                        creditos: special.creditos,
                        requiereRevision: true,
                        motivosRevision: special.motivosRevision,
                      ),
                    );
                    malla.especiales.remove(special);
                  }),
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
        Text(
          _saved != null
              ? _t('Explora por semestre', 'Explore by semester')
              : _t('Revisa por semestre', 'Review by semester'),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          _saved != null
              ? _t(
                  'Selecciona un ramo para ver sus detalles y estado.',
                  'Select a course to see its details and status.',
                )
              : _t(
                  'Toca un ramo para corregirlo. Los espacios repetidos se conservan.',
                  'Tap a course to edit it. Repeated slots are preserved.',
                ),
        ),
        const SizedBox(height: 13),
        if (semesters.isNotEmpty) ...[
          _selectionField(
            theme,
            key: const Key('malla-semester-selector'),
            label: _t('Semestre', 'Semester'),
            value: _t('Semestre $selected', 'Semester $selected'),
            icon: Ionicons.layersOutline,
            onTap: () => _selectSemester(semesters, selected),
          ),
        ],
        if (semesters.isNotEmpty) ...[
          const SizedBox(height: 9),
          FilterChip(
            key: const Key('malla-review-filter'),
            label: Text(_t('Solo por revisar', 'Needs review only')),
            selected: reviewOnly,
            showCheckmark: false,
            onSelected: (value) => setState(() => _reviewOnly = value),
            avatar: const Icon(Icons.fact_check_outlined, size: 18),
          ),
        ],
        const SizedBox(height: 12),
        if (visible.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                semesters.isEmpty
                    ? _t(
                        'Añade una asignatura para continuar.',
                        'Add a course to continue.',
                      )
                    : reviewOnly
                    ? _t(
                        'No hay ramos pendientes de revisión en este semestre.',
                        'No courses need review in this semester.',
                      )
                    : _t(
                        'No hay ramos con este filtro en el semestre.',
                        'No courses match this filter in this semester.',
                      ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 720
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final ramo in visible)
                  SizedBox(
                    width: width,
                    child: _courseCard(theme, malla, ramo),
                  ),
              ],
            );
          },
        ),
        if (_preview != null) ...[
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _edit(null),
            icon: const Icon(Icons.add_rounded),
            label: Text(_t('Añadir asignatura omitida', 'Add missing course')),
          ),
          const SizedBox(height: 9),
          FilledButton.icon(
            onPressed: _busy || malla.ramos.isEmpty || !_backendReady
                ? null
                : _confirm,
            icon: const Icon(Icons.check_circle_outline_rounded),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _t(
                  'Revisar y confirmar importación',
                  'Review and confirm import',
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _count(ThemeData theme, String value, String label, IconData icon) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 7),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Text(label),
        ],
      );

  Widget _courseCard(ThemeData theme, MallaCurricular malla, RamoMalla ramo) {
    final dark = theme.brightness == Brightness.dark;
    final saved = _saved != null;
    final issues = MallaReviewRules.issuesFor(malla, ramo);
    return Material(
      color: dark ? const Color(0xFF191F29) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: saved ? () => _details(ramo) : () => _edit(ramo),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: issues.isNotEmpty
                  ? const Color(0xFF5B5FEF)
                  : dark
                  ? const Color(0xFF2B323E)
                  : const Color(0xFFE7EAF0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ramo.nombre,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (!saved)
                    PopupMenuButton<String>(
                      tooltip: _t('Opciones de asignatura', 'Course options'),
                      onSelected: (action) {
                        if (action == 'edit') _edit(ramo);
                        if (action == 'delete') {
                          setState(() => _preview!.ramos.remove(ramo));
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text(_t('Editar', 'Edit')),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(_t('Eliminar', 'Delete')),
                        ),
                      ],
                    )
                  else
                    const Icon(Icons.chevron_right_rounded, size: 21),
                ],
              ),
              const SizedBox(height: 9),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (ramo.codigo != null)
                    _metadata(theme, Icons.tag_rounded, ramo.codigo!),
                  if (ramo.creditos != null)
                    _metadata(
                      theme,
                      Icons.stars_outlined,
                      _t(
                        '${ramo.creditos} créditos',
                        '${ramo.creditos} credits',
                      ),
                    ),
                  if (saved) _statePill(theme, ramo.estado),
                  for (final issue in issues)
                    _metadata(
                      theme,
                      issue.priority == MallaReviewPriority.high
                          ? Icons.priority_high_rounded
                          : Icons.fact_check_outlined,
                      '${_priorityLabel(issue.priority)} · ${issue.label(_es)}',
                    ),
                ],
              ),
              if (!saved) ...[
                const SizedBox(height: 8),
                Text(
                  _t('Toca para corregir', 'Tap to edit'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _metadata(ThemeData theme, IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15),
        const SizedBox(width: 5),
        Flexible(child: Text(label, style: theme.textTheme.bodySmall)),
      ],
    ),
  );

  Widget _statePill(ThemeData theme, String state) {
    final icon = switch (state) {
      'aprobada' => Icons.check_circle_outline_rounded,
      'en_curso' => Icons.play_circle_outline_rounded,
      _ => Icons.schedule_rounded,
    };
    return _metadata(theme, icon, _statusLabel(state));
  }

  String _statusLabel(String status) => switch (status) {
    'aprobada' => _t('Aprobada', 'Passed'),
    'en_curso' => _t('En curso', 'In progress'),
    _ => _t('Pendiente', 'Pending'),
  };

  String _priorityLabel(MallaReviewPriority priority) => switch (priority) {
    MallaReviewPriority.high => _t('Alta', 'High'),
    MallaReviewPriority.medium => _t('Media', 'Medium'),
    MallaReviewPriority.verification => _t('Verificar', 'Verify'),
  };

  String _reasonLabel(String reason) => switch (reason) {
    'credits_missing' => _t('Créditos sin detectar', 'Credits not detected'),
    'code_missing' => _t('Código sin detectar', 'Code not detected'),
    'low_ocr_confidence' => _t('Lectura OCR incierta', 'Uncertain OCR reading'),
    'name_association_uncertain' => _t('Nombre incierto', 'Uncertain name'),
    'elective_slot' => _t('Electivo por definir', 'Elective to be defined'),
    _ => reason.replaceAll('_', ' '),
  };
}

class _RamoEditResult {
  const _RamoEditResult(
    this.ramo,
    this.confirmarRevision,
    this.codigoDuplicadoVerificado,
  );

  final RamoMalla ramo;
  final bool confirmarRevision;
  final bool codigoDuplicadoVerificado;
}

class _RamoEditDialog extends StatefulWidget {
  const _RamoEditDialog({
    required this.malla,
    required this.ramo,
    required this.newRamoId,
    required this.spanish,
    required this.saved,
  });

  final MallaCurricular malla;
  final RamoMalla? ramo;
  final String newRamoId;
  final bool spanish;
  final bool saved;

  @override
  State<_RamoEditDialog> createState() => _RamoEditDialogState();
}

class _RamoEditDialogState extends State<_RamoEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _credits;
  late final TextEditingController _semester;
  String? _validation;
  bool _verifyOther = false;
  bool _verifyDuplicate = false;

  bool get _sameNormalizedCode =>
      MallaReviewRules.normalizedCode(widget.ramo?.codigo) ==
      MallaReviewRules.normalizedCode(_code.text);

  String _t(String es, String en) => widget.spanish ? es : en;

  @override
  void initState() {
    super.initState();
    final ramo = widget.ramo;
    _name = TextEditingController(text: ramo?.nombre);
    _code = TextEditingController(text: ramo?.codigo);
    _credits = TextEditingController(text: ramo?.creditos?.toString());
    _semester = TextEditingController(text: ramo?.semestre.toString() ?? '1');
    _verifyDuplicate = ramo?.codigoDuplicadoVerificado ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _credits.dispose();
    _semester.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final code = _code.text.trim();
    final parsedSemester = int.tryParse(_semester.text.trim());
    final parsedCredits = _credits.text.trim().isEmpty
        ? null
        : int.tryParse(_credits.text.trim());
    if (name.isEmpty ||
        name.length > 300 ||
        code.length > 64 ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(name) ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(code) ||
        parsedSemester == null ||
        parsedSemester < 1 ||
        parsedSemester > 30 ||
        _credits.text.trim().isNotEmpty &&
            (parsedCredits == null ||
                parsedCredits < 0 ||
                parsedCredits > 999)) {
      setState(
        () => _validation = _t(
          'Revisa el nombre (máximo 300 caracteres), código (máximo 64), semestre (1 a 30) y créditos (0 a 999 o vacíos).',
          'Check the name (up to 300 characters), code (up to 64), semester (1 to 30), and credits (0 to 999 or empty).',
        ),
      );
      return;
    }
    final edited = RamoMalla(
      id: widget.ramo?.id ?? widget.newRamoId,
      nombre: name,
      semestre: parsedSemester,
      codigo: code.isEmpty ? null : code,
      creditos: parsedCredits,
      motivosRevision: widget.ramo == null
          ? const []
          : MallaReviewRules.remainingReasons(
              widget.ramo!,
              code: _code.text,
              credits: parsedCredits,
              verifyOther: _verifyOther,
              deriveMissing: widget.saved,
            ),
      codigoDuplicadoVerificado: _verifyDuplicate && _sameNormalizedCode,
    );
    edited.requiereRevision = edited.motivosRevision.isNotEmpty;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(
      _RamoEditResult(
        edited,
        _verifyOther,
        _verifyDuplicate && _sameNormalizedCode,
      ),
    );
  }

  Widget _editField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
    bool autofocus = false,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = dark
        ? const Color(0xFF343C48)
        : const Color(0xFFDFE3EA);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          autofocus: autofocus,
          keyboardType: keyboardType,
          onChanged: onChanged,
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          decoration: InputDecoration(
            filled: true,
            fillColor: dark ? const Color(0xFF202631) : const Color(0xFFFAFBFC),
            prefixIcon: Icon(icon, color: const Color(0xFF5B5FEF), size: 20),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(
                color: Color(0xFF5B5FEF),
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: dark ? const Color(0xFF18181D) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      title: Text(
        widget.ramo == null
            ? _t('Añadir asignatura', 'Add course')
            : _t('Corregir asignatura', 'Edit course'),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _editField(
                context,
                controller: _name,
                autofocus: true,
                label: _t('Nombre *', 'Name *'),
                icon: Ionicons.schoolOutline,
              ),
              const SizedBox(height: 14),
              _editField(
                context,
                controller: _code,
                onChanged: (_) => setState(() {
                  if (!_sameNormalizedCode) _verifyDuplicate = false;
                }),
                label: _t('Código opcional', 'Optional code'),
                icon: Ionicons.pricetagOutline,
              ),
              const SizedBox(height: 14),
              _editField(
                context,
                controller: _credits,
                keyboardType: TextInputType.number,
                label: _t('Créditos opcionales', 'Optional credits'),
                icon: Ionicons.calculatorOutline,
              ),
              const SizedBox(height: 14),
              _editField(
                context,
                controller: _semester,
                keyboardType: TextInputType.number,
                label: _t('Semestre *', 'Semester *'),
                icon: Ionicons.layersOutline,
              ),
              const SizedBox(height: 14),
              if (widget.ramo != null &&
                  (widget.ramo!.motivosRevision.any(
                        (reason) =>
                            reason != 'credits_missing' &&
                            reason != 'code_missing',
                      ) ||
                      widget.ramo!.requiereRevision &&
                          widget.ramo!.motivosRevision.isEmpty))
                CheckboxListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  tileColor: dark
                      ? const Color(0xFF202631)
                      : const Color(0xFFFAFBFC),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                    side: BorderSide(
                      color: dark
                          ? const Color(0xFF343C48)
                          : const Color(0xFFDFE3EA),
                    ),
                  ),
                  activeColor: const Color(0xFF5B5FEF),
                  checkColor: Colors.white,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    _t(
                      'He comprobado estos datos con mi malla original',
                      'I checked these details against my original curriculum',
                    ),
                  ),
                  value: _verifyOther,
                  onChanged: (value) =>
                      setState(() => _verifyOther = value ?? false),
                ),
              if (widget.saved &&
                  MallaReviewRules.duplicateNamesForCode(
                    widget.malla,
                    widget.ramo!.id,
                    _code.text,
                  ).isNotEmpty)
                CheckboxListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  tileColor: dark
                      ? const Color(0xFF202631)
                      : const Color(0xFFFAFBFC),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                    side: BorderSide(
                      color: dark
                          ? const Color(0xFF343C48)
                          : const Color(0xFFDFE3EA),
                    ),
                  ),
                  activeColor: const Color(0xFF5B5FEF),
                  checkColor: Colors.white,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    _t(
                      'Confirmo que este código compartido es correcto',
                      'I confirm this shared code is correct',
                    ),
                  ),
                  value: _verifyDuplicate,
                  subtitle: _sameNormalizedCode
                      ? null
                      : Text(
                          _t(
                            'Guarda el nuevo código para verificarlo después.',
                            'Save the new code to verify it afterward.',
                          ),
                        ),
                  onChanged: _sameNormalizedCode
                      ? (value) =>
                            setState(() => _verifyDuplicate = value ?? false)
                      : null,
                ),
              if (_validation != null) ...[
                const SizedBox(height: 8),
                Text(
                  _validation!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () {
            FocusScope.of(context).unfocus();
            Navigator.of(context).pop();
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: dark
                ? const Color(0xFFE5E9F0)
                : const Color(0xFF4B5563),
            side: BorderSide(
              color: dark ? const Color(0xFF343C48) : const Color(0xFFDFE3EA),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
            minimumSize: const Size(0, 49),
          ),
          child: Text(_t('Cancelar', 'Cancel')),
        ),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF5B5FEF),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
            minimumSize: const Size(0, 49),
          ),
          child: Text(_t('Guardar corrección', 'Save edit')),
        ),
      ],
    );
  }
}
