import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/developer_tools_config.dart';
import '../../models/malla_curricular.dart';
import '../../models/malla_import_review.dart';
import '../../models/malla_review.dart';
import '../../services/malla_curricular_service.dart';
import '../../services/malla_multimodal_isolation_service.dart';
import '../../services/malla_multimodal_persistence_service.dart';
import '../../services/malla_multimodal_rls_diagnostic_service.dart';
import '../../services/malla_multimodal_testing_fixture.dart';
import '../../services/malla_multimodal_write_diagnostic_service.dart';
import '../../services/ocr_document_service.dart';
import '../../services/ocr_file_picker_service.dart';
import '../../services/translation_service.dart';
import '../../widgets/app_status_snackbar.dart';
import '../../widgets/app_full_screen_loading.dart';
import '../profile/widgets/profile_option_sheet.dart';
import '../../widgets/app_scroll_header.dart';
import '../../widgets/app_pressable.dart';
import 'malla_ui_failure.dart';
import 'widgets/ocr_file_picker_overlay.dart';
import 'widgets/malla_multimodal_review_panel.dart';
import 'widgets/malla_persisted_academic_details.dart';
import 'widgets/malla_write_diagnostic_dialog.dart';
import 'widgets/ocr_pdf_preview.dart';

class MallaCurricularPage extends StatefulWidget {
  const MallaCurricularPage({
    super.key,
    this.service,
    this.documents,
    this.rlsDiagnostic,
    this.writeDiagnostic,
  });

  final MallaCurricularGateway? service;
  final OcrDocumentGateway? documents;
  final MallaRlsDiagnosticGateway? rlsDiagnostic;
  final MallaWriteDiagnosticGateway? writeDiagnostic;

  @override
  State<MallaCurricularPage> createState() => _MallaCurricularPageState();
}

class _MallaRlsDiagnosticDialog extends StatefulWidget {
  const _MallaRlsDiagnosticDialog({
    required this.ownMallaId,
    required this.diagnostic,
    required this.spanish,
  });

  final String ownMallaId;
  final MallaRlsDiagnosticGateway diagnostic;
  final bool spanish;

  @override
  State<_MallaRlsDiagnosticDialog> createState() =>
      _MallaRlsDiagnosticDialogState();
}

class _MallaRlsDiagnosticDialogState extends State<_MallaRlsDiagnosticDialog> {
  final TextEditingController _foreignMallaController = TextEditingController();
  bool _running = false;
  String? _error;
  MallaRlsDiagnosticResult? _result;

  String _t(String es, String en) => widget.spanish ? es : en;

  @override
  void dispose() {
    _foreignMallaController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
      _result = null;
    });
    try {
      final value = await widget.diagnostic.run(_foreignMallaController.text);
      if (!mounted) return;
      setState(() => _result = value);
    } on MallaRlsDiagnosticException catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.safeMessage);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = _t(
          'No fue posible completar la comprobación RLS.',
          'The RLS check could not be completed.',
        ),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return AlertDialog(
      title: Text(_t('Validar RLS Firebase', 'Validate Firebase RLS')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _t(
                'Solo lectura. Usa la sesión Firebase activa y el cliente Supabase normal.',
                'Read-only. Uses the active Firebase session and the regular Supabase client.',
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              _t(
                'UUID propia: ${widget.ownMallaId}',
                'Own UUID: ${widget.ownMallaId}',
              ),
              key: const Key('malla-rls-own-id'),
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: widget.ownMallaId));
              },
              icon: const Icon(Icons.copy_outlined),
              label: Text(_t('Copiar UUID propia', 'Copy own UUID')),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('malla-rls-foreign-id'),
              controller: _foreignMallaController,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: _t(
                  'UUID de la malla de la otra cuenta',
                  'Other account curriculum UUID',
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('malla-rls-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                result.safeReport(spanish: widget.spanish),
                key: const Key('malla-rls-result'),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text: result.safeReport(spanish: widget.spanish),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_all_outlined),
                label: Text(_t('Copiar resultado', 'Copy result')),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('malla-close-rls-diagnostic'),
          onPressed: _running ? null : () => Navigator.of(context).pop(),
          child: Text(_t('Cerrar', 'Close')),
        ),
        FilledButton.icon(
          key: const Key('malla-run-rls-diagnostic'),
          onPressed: _running ? null : _run,
          icon: _running
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.verified_user_outlined),
          label: Text(_t('Comprobar', 'Check')),
        ),
      ],
    );
  }
}

class _MallaCurricularPageState extends State<MallaCurricularPage> {
  static const _minimumDeletionIndicatorDuration = Duration(milliseconds: 800);

  late final MallaCurricularGateway _service =
      widget.service ?? MallaCurricularService();
  late final OcrDocumentGateway _documents =
      widget.documents ?? OcrDocumentService();
  late final MallaRlsDiagnosticGateway _rlsDiagnostic =
      widget.rlsDiagnostic ?? MallaMultimodalRlsDiagnosticService();
  late final MallaWriteDiagnosticGateway _writeDiagnostic =
      widget.writeDiagnostic ?? MallaMultimodalWriteDiagnosticService();
  final _translation = TranslationService.instance;
  MallaCurricular? _saved;
  MallaImportReview? _savedMultimodalReview;
  MallaCurricular? _preview;
  MallaImportReview? _integratedReview;
  OcrPickedFile? _file;
  bool _busy = true;
  bool _savingCurriculum = false;
  bool _deletingCurriculum = false;
  bool _isolationBusy = false;
  MallaUiFailure? _loadFailure;
  MallaUiFailure? _actionFailure;
  bool _loadVerified = false;
  bool _reviewOnly = false;
  int? _selectedSemester;
  String _status = '';
  int _newId = 0;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _reviewSectionKey = GlobalKey();
  final GlobalKey _coursesSectionKey = GlobalKey();
  bool _reviewIntroShownForCurrentImport = false;
  double _headerProgress = 0;

  bool get _es => _translation.isSpanish;
  String _t(String es, String en) => _es ? es : en;
  bool get _backendReady => _loadVerified && _loadFailure == null;
  bool get _curriculumOperationInProgress =>
      _savingCurriculum || _deletingCurriculum;
  bool get _testingSampleEnabled =>
      DeveloperToolsConfig.enabled && _service.multimodalTestingSampleEnabled;
  bool get _rlsDiagnosticEnabled =>
      _testingSampleEnabled && _rlsDiagnostic.enabled;
  bool get _writeDiagnosticEnabled =>
      _testingSampleEnabled && _writeDiagnostic.enabled;

  String _periodSingular({bool lowercase = false}) {
    final value =
        switch ((_integratedReview ?? _savedMultimodalReview)?.periodType) {
          'bimester' => _t('Bimestre', 'Bimester'),
          'trimester' => _t('Trimestre', 'Trimester'),
          'quarter' => _t('Trimestre', 'Quarter'),
          'annual' => _t('Período anual', 'Annual period'),
          _ => _t('Semestre', 'Semester'),
        };
    return lowercase ? value.toLowerCase() : value;
  }

  String _periodPlural() =>
      switch ((_integratedReview ?? _savedMultimodalReview)?.periodType) {
        'bimester' => _t('Bimestres', 'Bimesters'),
        'trimester' => _t('Trimestres', 'Trimesters'),
        'quarter' => _t('Trimestres', 'Quarters'),
        'annual' => _t('Períodos anuales', 'Annual periods'),
        _ => _t('Semestres', 'Semesters'),
      };

  Future<void> _selectSemester(List<int> semesters, int? selected) async {
    final value = await showProfileOptionSheet<int>(
      context: context,
      title: _periodSingular(),
      options: [
        for (final semester in semesters)
          ProfileOption(
            value: semester,
            label: '${_periodSingular()} $semester',
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

  void _resetScrollAfterSuccessfulImport() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.minScrollExtent);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _saved == null || !_scrollController.hasClients) return;
      final minimum = _scrollController.position.minScrollExtent;
      if (_scrollController.offset != minimum) {
        _scrollController.jumpTo(minimum);
      }
    });
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
      final savedReview = _service.multimodalPersistenceEnabled
          ? await _service.cargarRevisionMultimodal()
          : null;
      final saved =
          savedReview?.malla ??
          (_service.multimodalPersistenceEnabled
              ? null
              : await _service.cargar());
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _savedMultimodalReview = savedReview;
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
      _applyPickedFile(file);
    } catch (error, stack) {
      _handlePickError(error, stack);
    }
  }

  void _applyPickedFile(OcrPickedFile file) {
    if (file.sizeBytes > 10 * 1024 * 1024) {
      throw ArgumentError(
        _t('El archivo supera 10 MB.', 'The file exceeds 10 MB.'),
      );
    }
    setState(() {
      _file = file;
      _preview = null;
      _integratedReview = null;
      _reviewIntroShownForCurrentImport = false;
      _actionFailure = null;
    });
  }

  void _handlePickError(Object error, StackTrace stack) {
    _logFailure('pick', error, stack);
    if (mounted) {
      setState(() => _actionFailure = MallaUiFailure.fromTransfer(error));
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
    var showReviewIntro = false;
    try {
      uploaded = await _documents.upload(file);
      if (!mounted) return;
      setState(
        () => _status = _t(
          'EducFlow AI está analizando tu malla…',
          'EducFlow AI is analyzing your curriculum…',
        ),
      );
      final parsed = await _service.procesar(
        uploaded,
        fileName: file.name,
        originalFile: file,
      );
      if (!mounted) return;
      final integrated = MallaImportReviewBuilder.integrate(parsed);
      final preview = integrated?.malla ?? parsed;
      setState(() {
        _integratedReview = integrated;
        _preview = preview;
        _selectedSemester = preview.semestres.firstOrNull;
        _reviewOnly = false;
        _status = _hasMultimodalFallback(preview)
            ? _t(
                'La revisión de IA no se completó. Revisa cuidadosamente la información detectada antes de guardarla.',
                'The AI review could not be completed. Carefully review the detected information before saving it.',
              )
            : _t(
                'Revisa el resultado antes de guardarlo.',
                'Review the result before saving.',
              );
      });
      showReviewIntro =
          integrated != null && _service.multimodalPersistenceEnabled;
    } catch (error, stack) {
      _logFailure('process', error, stack);
      if (mounted) {
        setState(() => _actionFailure = MallaUiFailure.fromTransfer(error));
      }
    } finally {
      if (uploaded != null) {
        try {
          await _documents.deleteUploadedFile(uploaded.path);
        } catch (error, stack) {
          // La limpieza es secundaria: el backend puede haber eliminado ya el
          // objeto y un fallo aquí no debe ocultar un OCR completado.
          _logFailure('temporary_cleanup', error, stack);
        }
      }
      if (mounted) setState(() => _busy = false);
    }
    if (showReviewIntro && mounted) {
      await _showInitialReviewNotice();
    }
  }

  Future<void> _showInitialReviewNotice() async {
    if (!mounted ||
        _integratedReview == null ||
        _reviewIntroShownForCurrentImport) {
      return;
    }
    _reviewIntroShownForCurrentImport = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(
            _t(
              'Tu malla está lista para revisar',
              'Your curriculum is ready to review',
            ),
          ),
          content: Text(
            _t(
              'Revisa cuidadosamente los datos y las sugerencias de IA para que las herramientas académicas funcionen con información correcta. Esta revisión inicial se realiza al importar una malla nueva; después podrás consultarla sin repetir el proceso.',
              'Carefully review the data and AI suggestions so the academic tools use correct information. This initial review happens when importing a new curriculum; afterwards you can consult it without repeating the process.',
            ),
          ),
          actions: [
            FilledButton(
              key: const Key('malla-review-intro-start'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                _t('Entendido, comenzar revisión', 'Got it, start review'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _loadTestingExample() {
    if (!_testingSampleEnabled || !_backendReady || _busy || _saved != null) {
      return;
    }
    try {
      final review = MallaMultimodalTestingFixture.create();
      setState(() {
        _file = null;
        _preview = review.malla;
        _integratedReview = review;
        _selectedSemester = review.malla.semestres.firstOrNull;
        _reviewOnly = false;
        _actionFailure = null;
        _status = _t(
          'Malla simulada lista para revisar y guardar.',
          'Sample curriculum ready to review and save.',
        );
      });
    } catch (error, stack) {
      _logFailure('testing_fixture', error, stack);
      setState(() => _actionFailure = MallaUiFailure.from(error));
    }
  }

  bool _isTestingExample(MallaCurricular malla) =>
      _testingSampleEnabled && MallaMultimodalTestingFixture.isExample(malla);

  Future<void> _showRlsDiagnostic(MallaCurricular malla) async {
    if (!_rlsDiagnosticEnabled || malla.id.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _MallaRlsDiagnosticDialog(
        ownMallaId: malla.id,
        diagnostic: _rlsDiagnostic,
        spanish: _es,
      ),
    );
  }

  Future<void> _showWriteDiagnostic(MallaCurricular malla) async {
    if (!_writeDiagnosticEnabled || malla.id.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (_) => MallaWriteDiagnosticDialog(
        ownMallaId: malla.id,
        diagnostic: _writeDiagnostic,
        spanish: _es,
      ),
    );
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

  String _multimodalDiagnosticText(MallaCurricular malla) {
    final diagnostics = malla.multimodalDiagnostics;
    final review = malla.multimodalReview;
    final unavailableReason = diagnostics == null
        ? 'El flujo no entregó metadatos de ejecución multimodal.'
        : diagnostics.successful && review == null
        ? 'La ejecución figura como exitosa, pero no existe una revisión estructurada.'
        : !diagnostics.successful
        ? 'Gemini no entregó una revisión válida; se conservó el resultado de Vision.'
        : null;
    return const JsonEncoder.withIndent('  ').convert({
      'diagnostics':
          diagnostics?.toJson() ??
          {
            'status': 'not_available',
            'geminiRequestExecuted': false,
            'successful': false,
            'cacheHit': false,
            'fallbackToVision': true,
          },
      'unavailableReason': unavailableReason,
      'review': review?.toJson(),
    });
  }

  bool _hasMultimodalFallback(MallaCurricular malla) {
    final diagnostics = malla.multimodalDiagnostics;
    return diagnostics?.fallbackToVision == true ||
        (diagnostics != null &&
            !diagnostics.successful &&
            malla.multimodalReview == null);
  }

  Future<void> _showMultimodalDiagnostics(MallaCurricular malla) async {
    final text = _multimodalDiagnosticText(malla);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Diagnóstico Gemini', 'Gemini diagnostics')),
        content: SizedBox(
          width: 720,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: SingleChildScrollView(
              child: SelectableText(
                text,
                key: const Key('malla-multimodal-diagnostic-text'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            key: const Key('malla-copy-multimodal-diagnostic'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _t('Diagnóstico copiado.', 'Diagnostics copied.'),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.copy_all_outlined),
            label: Text(_t('Copiar', 'Copy')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(_t('Cerrar', 'Close')),
          ),
        ],
      ),
    );
  }

  Future<void> _runMultimodalIsolation() async {
    final file = _file;
    if (!DeveloperToolsConfig.enabled || file == null || _isolationBusy) {
      return;
    }
    setState(() => _isolationBusy = true);
    try {
      final outcome = await MallaMultimodalAcademicIsolationService().run(file);
      if (!mounted) return;
      final text = const JsonEncoder.withIndent('  ').convert(outcome.toJson());
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Aislamiento Gemini D/E'),
          content: SizedBox(
            width: 720,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: SingleChildScrollView(
                child: SelectableText(
                  text,
                  key: const Key('malla-multimodal-isolation-text'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              key: const Key('malla-copy-multimodal-isolation'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Diagnóstico D/E copiado.')),
                );
              },
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('Copiar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (error, stack) {
      _logFailure('multimodal_isolation', error, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo iniciar el aislamiento Gemini D/E.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isolationBusy = false);
    }
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
        canVerifyMissingCode: true,
        periodType: _integratedReview?.periodType ?? 'semester',
        sourceEvidence: ramo == null
            ? const []
            : _integratedReview?.evidenceFor(ramo.id) ?? const [],
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
        _integratedReview?.markManualCourse(edited.id);
      } else {
        preview.ramos[index] = edited;
        _integratedReview?.markCourseEdited(edited.id);
      }
      _selectedSemester = edited.semestre;
    });
  }

  Future<void> _editAcademicRequirement(
    MallaAcademicRequirementProposal proposal,
  ) async {
    final review = _integratedReview;
    if (review == null || !review.academicRequirements.contains(proposal)) {
      return;
    }
    final result = await showDialog<_AcademicRequirementEditResult>(
      context: context,
      builder: (_) => _AcademicRequirementEditDialog(
        proposal: proposal,
        spanish: _es,
        typeLabel: _academicRequirementTypeLabel(proposal.requirement.type),
        targetLabel: proposal.requirement.targetCourseId == null
            ? proposal.requirement.targetLabel
            : review.courseName(proposal.requirement.targetCourseId!),
      ),
    );
    if (result == null || !mounted || _integratedReview != review) return;
    setState(() {
      proposal.updateDetails(
        description: result.description,
        minimumLevel: result.minimumLevel,
      );
    });
  }

  String _academicRequirementTypeLabel(String type) => switch (type) {
    'approved_level' => _t('Niveles aprobados', 'Approved levels'),
    'completed_periods' => _t('Períodos completados', 'Completed periods'),
    'practice_eligibility' => _t('Acceso a práctica', 'Practice eligibility'),
    'capstone_eligibility' => _t('Acceso a Capstone', 'Capstone eligibility'),
    'other' => _t('Otro requisito', 'Other requirement'),
    _ => _t('Tipo por comprobar', 'Type to verify'),
  };

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
        canVerifyMissingCode: _savedMultimodalReview != null,
        periodType: 'semester',
        sourceEvidence: const [],
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
        confirmarSinCodigo: result.confirmarSinCodigo,
      );
      final updatedReview = result.confirmarSinCodigo
          ? await _service.cargarRevisionMultimodal()
          : null;
      if (!mounted) return;
      setState(() {
        _savedMultimodalReview = updatedReview ?? _savedMultimodalReview;
        _saved = updatedReview?.malla ?? updated;
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
    if (preview == null ||
        preview.ramos.isEmpty ||
        !_backendReady ||
        _busy ||
        _integratedReview != null && !_service.multimodalPersistenceEnabled) {
      return;
    }
    final integrated = _integratedReview;
    final ambiguous =
        integrated?.pendingCount ?? MallaReviewRules.pendingCount(preview);
    final periodCount = integrated?.periodCount ?? preview.semestres.length;
    final periodLabel = integrated == null
        ? _t('semestres', 'semesters')
        : _periodPlural().toLowerCase();
    final simulated = _isTestingExample(preview);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF18181D)
            : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(
          simulated
              ? _t('Confirmar malla de ejemplo', 'Confirm sample curriculum')
              : _t('Confirmar malla', 'Confirm curriculum'),
        ),
        content: Text(
          _t(
            '${simulated ? 'Estos son datos simulados de Testing. ' : ''}Guardarás ${preview.ramos.length} asignaturas en $periodCount $periodLabel. $ambiguous elementos siguen marcados para revisión. Las sugerencias no se convertirán automáticamente en relaciones vigentes. Esta importación no reemplazará una malla existente.',
            '${simulated ? 'These are simulated Testing data. ' : ''}You will save ${preview.ramos.length} courses in $periodCount $periodLabel. $ambiguous items remain marked for review. Suggestions will not automatically become active relationships. This import will not replace an existing curriculum.',
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
      _savingCurriculum = true;
      _actionFailure = null;
      _status = _t('Guardando malla curricular…', 'Saving curriculum…');
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_savingCurriculum) return;
      final savedReview = integrated == null
          ? null
          : await _service.confirmarMultimodal(integrated);
      final saved = savedReview?.malla ?? await _service.confirmar(preview);
      if (!mounted) return;
      _resetScrollAfterSuccessfulImport();
      setState(() {
        _saved = saved;
        _savedMultimodalReview = savedReview;
        _preview = null;
        _integratedReview = null;
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
      if (mounted) {
        setState(() {
          _busy = false;
          _savingCurriculum = false;
        });
      }
    }
  }

  Future<void> _details(RamoMalla ramo) async {
    final persistedReview = _savedMultimodalReview;
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
        child: SingleChildScrollView(
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
                '${_periodSingular()} ${ramo.semestre}',
                key: const Key('malla-course-period'),
              ),
              if (ramo.codigo != null)
                Text(_t('Código: ${ramo.codigo}', 'Code: ${ramo.codigo}')),
              if (ramo.creditos != null)
                Text(
                  _t('Créditos: ${ramo.creditos}', 'Credits: ${ramo.creditos}'),
                ),
              if (persistedReview != null)
                MallaCourseAcademicDetails(
                  review: persistedReview,
                  course: ramo,
                  spanish: _es,
                  onDecidePrerequisite: (prerequisite, decision) async {
                    final updated = await _decidePersistedPrerequisite(
                      prerequisite,
                      decision,
                    );
                    if (updated && sheetContext.mounted) {
                      Navigator.pop(sheetContext);
                    }
                    return updated;
                  },
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
                    barrierColor: Colors.transparent,
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

  Future<bool> _decidePersistedPrerequisite(
    MallaPrerequisiteProposal prerequisite,
    MallaProposalDecision decision,
  ) async {
    final review = _savedMultimodalReview;
    if (review == null ||
        (decision != MallaProposalDecision.accepted &&
            decision != MallaProposalDecision.rejected)) {
      return false;
    }
    try {
      final updated = await _service.decidirPrerrequisito(
        mallaId: review.malla.id,
        courseId: prerequisite.courseId,
        requiresCourseId: prerequisite.requiresCourseId,
        decision: decision,
      );
      if (!mounted) return false;
      setState(() {
        _savedMultimodalReview = updated;
        _saved = updated.malla;
        _actionFailure = null;
      });
      showAppStatusSnackBar(
        context,
        message: decision == MallaProposalDecision.accepted
            ? _t('Prerrequisito confirmado.', 'Prerequisite confirmed.')
            : _t('Prerrequisito rechazado.', 'Prerequisite rejected.'),
      );
      return true;
    } catch (error, stack) {
      _logFailure('prerequisite_decision', error, stack);
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(MallaUiFailure.from(error).description(_es))),
      );
      return false;
    }
  }

  Future<bool> _confirmPersistedPrerequisiteGroup(
    List<MallaPrerequisiteProposal> prerequisites,
  ) async {
    final review = _savedMultimodalReview;
    if (review == null || prerequisites.isEmpty) return false;
    try {
      final updated = await _service.confirmarRelacionesAgrupadas(
        review: review,
        prerequisites: prerequisites,
      );
      if (!mounted) return false;
      setState(() {
        _savedMultimodalReview = updated;
        _saved = updated.malla;
        _actionFailure = null;
      });
      showAppStatusSnackBar(
        context,
        message: _t(
          '${prerequisites.length} prerrequisitos confirmados.',
          '${prerequisites.length} prerequisites confirmed.',
        ),
      );
      return true;
    } catch (error, stack) {
      _logFailure('prerequisite_group_decision', error, stack);
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(MallaUiFailure.from(error).description(_es))),
      );
      return false;
    }
  }

  Future<bool> _confirmPersistedCertificationGroup(
    MallaCertificationProposal certification,
    List<MallaCertificationMembershipProposal> memberships,
  ) async {
    final review = _savedMultimodalReview;
    if (review == null ||
        certification.decision == MallaProposalDecision.pending ||
        certification.decision == MallaProposalDecision.rejected) {
      return false;
    }
    try {
      final updated = await _service.confirmarRelacionesAgrupadas(
        review: review,
        certifications: [
          MallaCertificationBatchSelection(
            certification: certification,
            memberships: memberships,
          ),
        ],
      );
      if (!mounted) return false;
      setState(() {
        _savedMultimodalReview = updated;
        _saved = updated.malla;
        _actionFailure = null;
      });
      showAppStatusSnackBar(
        context,
        message: memberships.isEmpty
            ? _t('Certificación confirmada.', 'Certification confirmed.')
            : _t(
                '${memberships.length} asignaturas confirmadas en la certificación.',
                '${memberships.length} courses confirmed in the certification.',
              ),
      );
      return true;
    } catch (error, stack) {
      _logFailure('certification_group_decision', error, stack);
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(MallaUiFailure.from(error).description(_es))),
      );
      return false;
    }
  }

  Future<bool> _decidePersistedMembership(
    MallaCertificationProposal certification,
    MallaCertificationMembershipProposal membership,
    MallaProposalDecision decision,
  ) async {
    final review = _savedMultimodalReview;
    if (review == null ||
        (decision != MallaProposalDecision.accepted &&
            decision != MallaProposalDecision.rejected)) {
      return false;
    }
    try {
      final updated = await _service.decidirMembresiaCertificacion(
        mallaId: review.malla.id,
        certificationId: certification.id,
        courseId: membership.courseId,
        decision: decision,
      );
      if (!mounted) return false;
      setState(() {
        _savedMultimodalReview = updated;
        _saved = updated.malla;
        _actionFailure = null;
      });
      showAppStatusSnackBar(
        context,
        message: decision == MallaProposalDecision.accepted
            ? _t(
                'Asignatura incorporada a la certificación.',
                'Course added to the certification.',
              )
            : _t(
                'Membresía de certificación rechazada.',
                'Certification membership rejected.',
              ),
      );
      return true;
    } catch (error, stack) {
      _logFailure('membership_decision', error, stack);
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(MallaUiFailure.from(error).description(_es))),
      );
      return false;
    }
  }

  Future<bool> _decidePersistedAcademicRequirement(
    MallaAcademicRequirementProposal proposal,
    MallaProposalDecision decision,
  ) async {
    final review = _savedMultimodalReview;
    if (review == null ||
        (decision != MallaProposalDecision.accepted &&
            decision != MallaProposalDecision.rejected)) {
      return false;
    }
    final requirement = proposal.requirement;
    try {
      final updated = await _service.decidirRequisitoAcademico(
        mallaId: review.malla.id,
        requirementId: requirement.id,
        type: requirement.type,
        decision: decision,
      );
      if (!mounted) return false;
      setState(() {
        _savedMultimodalReview = updated;
        _saved = updated.malla;
        _actionFailure = null;
      });
      showAppStatusSnackBar(
        context,
        message: decision == MallaProposalDecision.accepted
            ? _t(
                'Requisito académico confirmado.',
                'Academic requirement confirmed.',
              )
            : _t(
                'Requisito académico rechazado.',
                'Academic requirement rejected.',
              ),
      );
      return true;
    } catch (error, stack) {
      _logFailure('academic_requirement_decision', error, stack);
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(MallaUiFailure.from(error).description(_es))),
      );
      return false;
    }
  }

  Future<void> _editPersistedAcademicRequirement(
    MallaAcademicRequirementProposal proposal,
  ) async {
    final review = _savedMultimodalReview;
    if (review == null ||
        _busy ||
        !review.academicRequirements.contains(proposal)) {
      return;
    }
    final requirement = proposal.requirement;
    final result = await showDialog<_AcademicRequirementEditResult>(
      context: context,
      builder: (_) => _AcademicRequirementEditDialog(
        proposal: proposal,
        spanish: _es,
        typeLabel: _academicRequirementTypeLabel(requirement.type),
        targetLabel: requirement.targetCourseId == null
            ? requirement.targetLabel
            : review.courseName(requirement.targetCourseId!),
      ),
    );
    if (result == null || !mounted || _savedMultimodalReview != review) return;
    setState(() => _busy = true);
    try {
      final updated = await _service.editarRequisitoAcademico(
        mallaId: review.malla.id,
        requirement: requirement,
        description: result.description,
        minimumLevel: result.minimumLevel,
      );
      if (!mounted) return;
      setState(() {
        _savedMultimodalReview = updated;
        _saved = updated.malla;
        _actionFailure = null;
      });
      showAppStatusSnackBar(
        context,
        message: _t(
          'Requisito actualizado y pendiente de confirmación.',
          'Requirement updated and awaiting confirmation.',
        ),
      );
    } catch (error, stack) {
      _logFailure('academic_requirement_edit', error, stack);
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

  Future<void> _deleteSavedCurriculum() async {
    final saved = _saved;
    if (saved == null ||
        saved.id.isEmpty ||
        _busy ||
        !_service.multimodalPersistenceEnabled) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Eliminar malla curricular', 'Delete curriculum')),
        content: Text(
          _t(
            'Esta acción es permanente. Se eliminarán la malla importada, sus asignaturas, prerrequisitos, certificaciones, membresías, requisitos académicos y pendientes asociados. No se eliminarán tus asignaturas académicas independientes, notas, tareas ni evaluaciones. Después podrás importar una malla nueva.',
            'This action is permanent. The imported curriculum, its courses, prerequisites, certifications, memberships, academic requirements, and related pending items will be deleted. Your independent academic courses, grades, tasks, and assessments will not be deleted. You can import a new curriculum afterwards.',
          ),
        ),
        actions: [
          TextButton(
            key: const Key('malla-delete-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t('Cancelar', 'Cancel')),
          ),
          FilledButton(
            key: const Key('malla-delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t('Eliminar permanentemente', 'Delete permanently')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _saved?.id != saved.id) return;
    setState(() {
      _busy = true;
      _deletingCurriculum = true;
      _actionFailure = null;
      _status = _t('Eliminando malla curricular…', 'Deleting curriculum…');
    });
    Future<void>? minimumVisibility;
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_deletingCurriculum || _saved?.id != saved.id) return;
      minimumVisibility = Future<void>.delayed(
        _minimumDeletionIndicatorDuration,
      );
      await _service.eliminarMallaConfirmada(saved.id);
      await minimumVisibility;
      if (!mounted || _saved?.id != saved.id) return;
      setState(() {
        _saved = null;
        _savedMultimodalReview = null;
        _preview = null;
        _integratedReview = null;
        _file = null;
        _selectedSemester = null;
        _reviewOnly = false;
        _loadFailure = null;
        _actionFailure = null;
        _loadVerified = true;
        _newId = 0;
        _status = _t(
          'Puedes importar una nueva malla.',
          'You can import a new curriculum.',
        );
      });
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      showAppStatusSnackBar(
        context,
        message: _t(
          'Malla eliminada. Ya puedes importar una nueva.',
          'Curriculum deleted. You can now import a new one.',
        ),
      );
    } catch (error, stack) {
      await minimumVisibility;
      _logFailure('delete_curriculum', error, stack);
      if (!mounted) return;
      showAppStatusSnackBar(
        context,
        message: MallaUiFailure.from(error).description(_es),
        type: AppStatusType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _deletingCurriculum = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final malla = _saved ?? _preview;
    return PopScope(
      canPop: !_curriculumOperationInProgress,
      child: Scaffold(
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
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      24,
                      horizontal,
                      48,
                    ),
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
                              if (_busy &&
                                  _loadVerified &&
                                  !_curriculumOperationInProgress) ...[
                                _progress(theme),
                                const SizedBox(height: 16),
                              ],
                              if (malla == null && _loadVerified)
                                _fileSection(theme),
                              if (_loadFailure != null) ...[
                                const SizedBox(height: 14),
                                _failurePanel(
                                  theme,
                                  _loadFailure!,
                                  retry: _load,
                                ),
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
                  opaqueBackground: true,
                  title: _t('Malla curricular', 'Curriculum'),
                  leading: _compactBackButton(
                    theme.brightness == Brightness.dark,
                  ),
                ),
              ),
              if (_curriculumOperationInProgress)
                Positioned.fill(
                  key: Key(
                    _deletingCurriculum
                        ? 'malla-delete-progress-overlay'
                        : 'malla-save-progress-overlay',
                  ),
                  child: AbsorbPointer(
                    child: Semantics(
                      container: true,
                      liveRegion: true,
                      label: _status,
                      child: AppFullScreenLoading(
                        title: _status,
                        description: _deletingCurriculum
                            ? _t(
                                'Estamos eliminando la malla y sus datos asociados.',
                                'We are deleting the curriculum and its associated data.',
                              )
                            : _t(
                                'Estamos guardando tus asignaturas y relaciones académicas.',
                                'We are saving your courses and academic relationships.',
                              ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
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

  Widget _progress(ThemeData theme, {String? secondary}) => Container(
    key: const Key('malla-progress'),
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
          if (secondary != null) ...[
            const SizedBox(height: 6),
            Text(secondary, style: theme.textTheme.bodyMedium),
          ],
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
        Stack(
          children: [
            IgnorePointer(
              ignoring: kIsWeb,
              child: Material(
                color: dark ? const Color(0xFF191F29) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  key: const Key('malla-file-picker'),
                  borderRadius: BorderRadius.circular(18),
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: Colors.transparent,
                  onTap: _busy ? null : _pick,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 76),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
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
                                ? _t(
                                    'Elegir PDF o imagen',
                                    'Choose PDF or image',
                                  )
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
            ),
            if (kIsWeb)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: OcrFilePickerOverlay(
                    enabled: !_busy,
                    spanish: _es,
                    onPicked: _applyPickedFile,
                    onError: (error) =>
                        _handlePickError(error, StackTrace.current),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          _t(
            'PDF, JPEG, PNG o WebP · Máximo 10 MB',
            'PDF, JPEG, PNG or WebP · Up to 10 MB',
          ),
          style: theme.textTheme.bodySmall,
        ),
        if (_testingSampleEnabled && file == null) ...[
          const SizedBox(height: 16),
          Container(
            key: const Key('malla-testing-sample-access'),
            padding: const EdgeInsets.all(16),
            decoration: _panelDecoration(theme),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.science_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _t(
                          'Prueba aislada de persistencia',
                          'Isolated persistence test',
                        ),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _t(
                    'Carga datos académicos simulados. No ejecuta Vision, OCR ni Gemini.',
                    'Loads simulated academic data. It does not run Vision, OCR, or Gemini.',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('malla-load-testing-sample'),
                  onPressed: _busy || !_backendReady
                      ? null
                      : _loadTestingExample,
                  icon: const Icon(Icons.dataset_outlined),
                  label: Text(
                    _t(
                      'Cargar malla de ejemplo (Testing)',
                      'Load sample curriculum (Testing)',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
                    const SizedBox(height: 12),
                    OcrPdfPreview(
                      key: ValueKey(identityHashCode(file.bytes)),
                      bytes: file.bytes,
                      sourceName:
                          '${file.name}-${identityHashCode(file.bytes)}',
                      spanish: _es,
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
              child: Text(_t('Analizar malla', 'Analyze curriculum')),
            ),
          ),
          if (DeveloperToolsConfig.enabled) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('malla-multimodal-isolation-button'),
              onPressed: _busy || _isolationBusy
                  ? null
                  : _runMultimodalIsolation,
              icon: _isolationBusy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.science_outlined),
              label: const Text('Aislar Gemini D/E (desarrollo)'),
            ),
          ],
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

  void _focusOpenReview(MallaCurricular malla, MallaImportReview? review) {
    final courseAttention = review?.courseAttentionItems ?? const [];
    String? courseId;
    var onlyCourseAttention = false;
    if (courseAttention.isNotEmpty) {
      courseId = courseAttention.first.courseId;
      onlyCourseAttention = true;
    } else if (review != null) {
      for (final proposal in review.prerequisites) {
        if (proposal.decision == MallaProposalDecision.pending ||
            proposal.decision == MallaProposalDecision.suggested) {
          courseId = proposal.courseId;
          break;
        }
      }
    }
    final course = courseId == null
        ? null
        : malla.ramos.where((item) => item.id == courseId).firstOrNull;
    setState(() {
      _reviewOnly = onlyCourseAttention;
      if (course != null) _selectedSemester = course.semestre;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = course == null
          ? _reviewSectionKey.currentContext
          : _coursesSectionKey.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _mallaSection(ThemeData theme, MallaCurricular malla) {
    final integrated = _integratedReview;
    final persisted = _savedMultimodalReview;
    final review = integrated ?? persisted;
    final attentionCount =
        integrated?.pendingCount ??
        persisted?.pendingCount ??
        MallaReviewRules.pendingCount(malla);
    final suggestionCount = review?.suggestionCount ?? 0;
    final hasOpenReview = attentionCount > 0 || suggestionCount > 0;
    final reviewOnly = _reviewOnly;
    final semesters = malla.semestres;
    final courseCount = malla.ramos.length;
    final periodCount =
        integrated?.periodCount ?? persisted?.periodCount ?? semesters.length;
    final certificationCount =
        (integrated ?? persisted)?.certifications.length ?? 0;
    final selected = semesters.contains(_selectedSemester)
        ? _selectedSemester
        : semesters.firstOrNull;
    final visible = malla.ramos
        .where(
          (ramo) =>
              ramo.semestre == selected &&
              (!reviewOnly || _courseNeedsReview(malla, ramo)),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isTestingExample(malla)) ...[
          Container(
            key: const Key('malla-testing-sample-banner'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer.withValues(
                alpha: 0.55,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.tertiary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.science_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _t(
                      'Malla de ejemplo · Datos simulados para validar únicamente el guardado y la recuperación.',
                      'Sample curriculum · Simulated data to validate storage and recovery only.',
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (_saved != null) ...[
          Container(
            key: const Key('malla-review-summary'),
            padding: const EdgeInsets.all(16),
            decoration: _panelDecoration(theme),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attentionCount > 0
                      ? _t(
                          '$attentionCount ${attentionCount == 1 ? 'elemento necesita' : 'elementos necesitan'} atención.${suggestionCount > 0 ? ' Además, hay $suggestionCount ${suggestionCount == 1 ? 'relación sugerida' : 'relaciones sugeridas'} por revisar.' : ''}',
                          '$attentionCount ${attentionCount == 1 ? 'item needs' : 'items need'} attention.${suggestionCount > 0 ? ' There are also $suggestionCount suggested ${suggestionCount == 1 ? 'relationship' : 'relationships'} to review.' : ''}',
                        )
                      : suggestionCount > 0
                      ? _t(
                          'No hay datos obligatorios pendientes. Tienes $suggestionCount ${suggestionCount == 1 ? 'relación sugerida' : 'relaciones sugeridas'} por revisar.',
                          'There are no required data issues. You have $suggestionCount suggested ${suggestionCount == 1 ? 'relationship' : 'relationships'} to review.',
                        )
                      : _t(
                          'Tu malla está completamente revisada.',
                          'Your curriculum has been fully reviewed.',
                        ),
                ),
                if (hasOpenReview)
                  TextButton.icon(
                    onPressed: () => _focusOpenReview(malla, review),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(_t('Ver pendientes', 'View items to review')),
                  ),
                if (_rlsDiagnosticEnabled) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('malla-rls-diagnostic-access'),
                    onPressed: () => _showRlsDiagnostic(malla),
                    icon: const Icon(Icons.verified_user_outlined),
                    label: Text(
                      _t(
                        'Validar RLS Firebase (Testing)',
                        'Validate Firebase RLS (Testing)',
                      ),
                    ),
                  ),
                ],
                if (_writeDiagnosticEnabled) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('malla-write-diagnostic-access'),
                    onPressed: () => _showWriteDiagnostic(malla),
                    icon: const Icon(Icons.rule_outlined),
                    label: Text(
                      _t(
                        'Validar escritura Firebase (Testing)',
                        'Validate Firebase write (Testing)',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (_preview != null && _hasMultimodalFallback(malla)) ...[
          Container(
            key: const Key('malla-multimodal-fallback-warning'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.error.withValues(alpha: 0.28),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t(
                          'Revisión avanzada no completada',
                          'Advanced review not completed',
                        ),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _t(
                          'Se conservó la información detectada. Los prerrequisitos, certificaciones y requisitos académicos no pudieron validarse con IA; revísalos antes de guardar.',
                          'The detected information was preserved. Prerequisites, certifications and academic requirements could not be validated with AI; review them before saving.',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 17),
        ],
        Container(
          key: const Key('malla-count-summary'),
          padding: const EdgeInsets.all(17),
          decoration: _panelDecoration(theme),
          child: Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _count(
                theme,
                '$courseCount',
                courseCount == 1
                    ? _t('Asignatura', 'Course')
                    : _t('Asignaturas', 'Courses'),
                Icons.menu_book_outlined,
                key: const Key('malla-course-count'),
              ),
              _count(
                theme,
                '$periodCount',
                periodCount == 1 ? _periodSingular() : _periodPlural(),
                Icons.view_week_outlined,
                key: const Key('malla-period-count'),
              ),
              if (certificationCount > 0)
                _count(
                  theme,
                  '$certificationCount',
                  certificationCount == 1
                      ? _t('Certificación', 'Certification')
                      : _t('Certificaciones', 'Certifications'),
                  Icons.workspace_premium_outlined,
                  key: const Key('malla-certification-count'),
                ),
              _count(
                theme,
                '$attentionCount',
                _t('Atención', 'Attention'),
                Icons.fact_check_outlined,
                key: const Key('malla-review-count'),
              ),
              if (suggestionCount > 0)
                _count(
                  theme,
                  '$suggestionCount',
                  _t('Sugerencias', 'Suggestions'),
                  Icons.auto_awesome_outlined,
                  key: const Key('malla-suggestion-count'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 17),
        if (integrated != null) ...[
          KeyedSubtree(
            key: _reviewSectionKey,
            child: MallaMultimodalReviewPanel(
              review: integrated,
              spanish: _es,
              onCourseDecision: (proposal, decision) => setState(
                () => integrated.decideCourseChange(proposal, decision),
              ),
              onPrerequisiteDecision: (proposal, decision) =>
                  setState(() => proposal.decision = decision),
              onConfirmPrerequisiteGroup: (proposals) => setState(
                () => integrated.acceptSuggestedPrerequisites(proposals),
              ),
              onMembershipDecision: (proposal, decision) =>
                  setState(() => proposal.decision = decision),
              onCertificationDecision: (proposal, decision) =>
                  setState(() => proposal.decision = decision),
              onConfirmCertificationGroup: (certification, memberships) =>
                  setState(
                    () => integrated.acceptCertificationSelection(
                      certification,
                      memberships,
                    ),
                  ),
              onRequirementDecision: (proposal, decision) =>
                  setState(() => proposal.decision = decision),
              onEditRequirement: _editAcademicRequirement,
              onResolveGlobal: (item) =>
                  setState(() => integrated.resolveGlobalPending(item)),
              onEditCourse: (courseId) {
                final course = integrated.courseById(courseId);
                if (course != null) _edit(course);
              },
            ),
          ),
          const SizedBox(height: 17),
        ],
        if (persisted != null) ...[
          KeyedSubtree(
            key: _reviewSectionKey,
            child: Column(
              children: [
                _academicExpansion(
                  theme: theme,
                  key: const Key('malla-prerequisites-section'),
                  title: _t(
                    'Prerrequisitos y relaciones',
                    'Prerequisites and relationships',
                  ),
                  icon: Icons.account_tree_outlined,
                  child: MallaPersistedRelationshipGroups(
                    review: persisted,
                    spanish: _es,
                    includeCertifications: false,
                    showHeader: false,
                    onConfirmPrerequisites: _confirmPersistedPrerequisiteGroup,
                    onDecidePrerequisite: _decidePersistedPrerequisite,
                    onConfirmCertification: _confirmPersistedCertificationGroup,
                    onDecideMembership: _decidePersistedMembership,
                  ),
                ),
                const SizedBox(height: 10),
                _academicExpansion(
                  theme: theme,
                  key: const Key('malla-certifications-group-section'),
                  title: _t('Certificaciones', 'Certifications'),
                  icon: Icons.workspace_premium_outlined,
                  child: MallaPersistedRelationshipGroups(
                    review: persisted,
                    spanish: _es,
                    includePrerequisites: false,
                    showHeader: false,
                    onConfirmPrerequisites: _confirmPersistedPrerequisiteGroup,
                    onDecidePrerequisite: _decidePersistedPrerequisite,
                    onConfirmCertification: _confirmPersistedCertificationGroup,
                    onDecideMembership: _decidePersistedMembership,
                  ),
                ),
                const SizedBox(height: 10),
                _academicExpansion(
                  theme: theme,
                  key: const Key('malla-requirements-group-section'),
                  title: _t('Requisitos académicos', 'Academic requirements'),
                  icon: Icons.rule_outlined,
                  child: MallaAcademicRequirementsSection(
                    review: persisted,
                    spanish: _es,
                    onDecideRequirement: _decidePersistedAcademicRequirement,
                    onEditRequirement: _editPersistedAcademicRequirement,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 17),
        ],
        if (_preview != null &&
            !_isTestingExample(malla) &&
            DeveloperToolsConfig.enabled) ...[
          OutlinedButton.icon(
            key: const Key('malla-multimodal-diagnostic-button'),
            onPressed: () => _showMultimodalDiagnostics(malla),
            icon: const Icon(Icons.bug_report_outlined),
            label: Text(
              _hasMultimodalFallback(malla)
                  ? _t('Ver diagnóstico de Gemini', 'View Gemini diagnostics')
                  : _t(
                      'Diagnóstico Gemini (desarrollo)',
                      'Gemini diagnostics (development)',
                    ),
            ),
          ),
          const SizedBox(height: 17),
        ],
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
        Material(
          key: const Key('malla-courses-group-section'),
          color: theme.brightness == Brightness.dark
              ? const Color(0xFF191F29)
              : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF2B323E)
                  : const Color(0xFFE7EAF0),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(
              _t('Asignaturas', 'Courses'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KeyedSubtree(
                    key: _coursesSectionKey,
                    child: Text(
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
                  ),
                  const SizedBox(height: 13),
                  if (semesters.isNotEmpty) ...[
                    _selectionField(
                      theme,
                      key: const Key('malla-semester-selector'),
                      label: _periodSingular(),
                      value: '${_periodSingular()} $selected',
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
                      onSelected: (value) =>
                          setState(() => _reviewOnly = value),
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
                ],
              ),
            ],
          ),
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
            key: const Key('malla-confirm-import'),
            onPressed:
                _busy ||
                    malla.ramos.isEmpty ||
                    !_backendReady ||
                    integrated != null && !_service.multimodalPersistenceEnabled
                ? null
                : _confirm,
            icon: Icon(
              integrated == null || _service.multimodalPersistenceEnabled
                  ? Icons.check_circle_outline_rounded
                  : Icons.lock_outline_rounded,
            ),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                integrated == null || _service.multimodalPersistenceEnabled
                    ? _t(
                        'Revisar y confirmar importación',
                        'Review and confirm import',
                      )
                    : _t(
                        'Guardado disponible en la siguiente etapa',
                        'Saving available in the next stage',
                      ),
              ),
            ),
          ),
          if (integrated != null) ...[
            const SizedBox(height: 7),
            Text(
              _t(
                _service.multimodalPersistenceEnabled
                    ? 'Se guardarán las decisiones actuales. Las sugerencias y pendientes permanecerán separadas de las relaciones vigentes.'
                    : 'Esta revisión es local. El guardado multimodal permanece deshabilitado hasta que el backend autorizado esté disponible.',
                _service.multimodalPersistenceEnabled
                    ? 'Current decisions will be saved. Suggestions and pending items will remain separate from active relationships.'
                    : 'This review is local. Multimodal saving remains disabled until the authorized backend is available.',
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
        if (_saved != null && _service.multimodalPersistenceEnabled) ...[
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.center,
            child: OutlinedButton.icon(
              key: const Key('malla-delete-saved'),
              onPressed: _busy ? null : _deleteSavedCurriculum,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(
                  color: theme.colorScheme.error.withValues(alpha: 0.55),
                ),
              ),
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(
                _t('Eliminar malla guardada', 'Delete saved curriculum'),
              ),
            ),
          ),
        ],
      ],
    );
  }

  bool _courseNeedsReview(MallaCurricular malla, RamoMalla course) {
    if (MallaReviewRules.issuesFor(malla, course).isNotEmpty) return true;
    return _integratedReview?.courseChangeFor(course.id)?.decision ==
        MallaProposalDecision.pending;
  }

  Widget _count(
    ThemeData theme,
    String value,
    String label,
    IconData icon, {
    Key? key,
  }) => Row(
    key: key,
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

  Widget _academicExpansion({
    required ThemeData theme,
    required Key key,
    required String title,
    required IconData icon,
    required Widget child,
  }) => Material(
    key: key,
    color: theme.brightness == Brightness.dark
        ? const Color(0xFF191F29)
        : Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF2B323E)
            : const Color(0xFFE7EAF0),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      children: [child],
    ),
  );

  Widget _courseCard(ThemeData theme, MallaCurricular malla, RamoMalla ramo) {
    final dark = theme.brightness == Brightness.dark;
    final saved = _saved != null;
    final issues = MallaReviewRules.issuesFor(malla, ramo);
    final source = _integratedReview?.sourceFor(ramo.id);
    final courseProposal = _integratedReview?.courseChangeFor(ramo.id);
    final category = _categoryLabel(
      _integratedReview?.categoryLabelFor(ramo.id),
    );
    return Material(
      key: ValueKey('malla-course-${ramo.id}'),
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
                          setState(() {
                            _preview!.ramos.remove(ramo);
                            _integratedReview?.removeCourse(ramo.id);
                          });
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
                  if (!saved &&
                      source != null &&
                      source != MallaCourseSource.vision)
                    _metadata(
                      theme,
                      switch (source) {
                        MallaCourseSource.vision =>
                          Icons.document_scanner_outlined,
                        MallaCourseSource.gemini => Icons.auto_awesome_outlined,
                        MallaCourseSource.merged => Icons.merge_outlined,
                        MallaCourseSource.manual => Icons.person_add_outlined,
                      },
                      switch (source) {
                        MallaCourseSource.vision => _t(
                          'Extracción',
                          'Extraction',
                        ),
                        MallaCourseSource.gemini => _t(
                          'Revisión de IA',
                          'AI review',
                        ),
                        MallaCourseSource.merged => _t(
                          'Extracción + revisión',
                          'Extraction + review',
                        ),
                        MallaCourseSource.manual => _t(
                          'Agregada manualmente',
                          'Added manually',
                        ),
                      },
                    ),
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
                  if (!saved && category != null)
                    _metadata(theme, Icons.category_outlined, category),
                  if (!saved &&
                      courseProposal != null &&
                      courseProposal.automaticallyAppliedFields.isNotEmpty &&
                      courseProposal.decision == MallaProposalDecision.accepted)
                    _metadata(
                      theme,
                      Icons.auto_awesome_outlined,
                      _t('Datos completados con IA', 'Data completed with AI'),
                    ),
                  if (!saved &&
                      courseProposal?.decision == MallaProposalDecision.pending)
                    _metadata(
                      theme,
                      Icons.auto_fix_high_outlined,
                      _t('La IA propone cambios', 'AI proposes changes'),
                    ),
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

  String? _categoryLabel(String? value) => switch (value) {
    null => null,
    'specialty' => _t('Especialidad', 'Specialty'),
    'institutional' => _t('Formación institucional', 'Institutional'),
    'mandatory' => _t('Obligatoria', 'Mandatory'),
    'elective' => _t('Electiva', 'Elective'),
    'general' => _t('Formación general', 'General education'),
    'other' || 'unknown' => null,
    _ => value,
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

class _AcademicRequirementEditResult {
  const _AcademicRequirementEditResult({
    required this.description,
    required this.minimumLevel,
  });

  final String description;
  final int? minimumLevel;
}

class _AcademicRequirementEditDialog extends StatefulWidget {
  const _AcademicRequirementEditDialog({
    required this.proposal,
    required this.spanish,
    required this.typeLabel,
    required this.targetLabel,
  });

  final MallaAcademicRequirementProposal proposal;
  final bool spanish;
  final String typeLabel;
  final String? targetLabel;

  @override
  State<_AcademicRequirementEditDialog> createState() =>
      _AcademicRequirementEditDialogState();
}

class _AcademicRequirementEditDialogState
    extends State<_AcademicRequirementEditDialog> {
  late final TextEditingController _description;
  late final TextEditingController _minimumLevel;
  String? _validation;

  String _t(String es, String en) => widget.spanish ? es : en;

  @override
  void initState() {
    super.initState();
    final requirement = widget.proposal.requirement;
    _description = TextEditingController(text: requirement.description);
    _minimumLevel = TextEditingController(
      text: requirement.minimumLevel?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _description.dispose();
    _minimumLevel.dispose();
    super.dispose();
  }

  void _save() {
    final description = _description.text.trim();
    final levelText = _minimumLevel.text.trim();
    final minimumLevel = levelText.isEmpty ? null : int.tryParse(levelText);
    if (description.isEmpty ||
        description.length > 1000 ||
        levelText.isNotEmpty &&
            (minimumLevel == null || minimumLevel < 1 || minimumLevel > 30)) {
      setState(() {
        _validation = _t(
          'Ingresa una descripción (máximo 1000 caracteres) y un nivel entre 1 y 30, o déjalo vacío si no corresponde.',
          'Enter a description (up to 1000 characters) and a level from 1 to 30, or leave it empty when it does not apply.',
        );
      });
      return;
    }
    Navigator.of(context).pop(
      _AcademicRequirementEditResult(
        description: description,
        minimumLevel: minimumLevel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _t('Corregir requisito académico', 'Correct academic requirement'),
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.targetLabel ??
                _t('Requisito general', 'General requirement'),
          ),
          const SizedBox(height: 4),
          Text(widget.typeLabel, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            key: const Key('academic-requirement-description'),
            controller: _description,
            maxLength: 1000,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: _t('Descripción', 'Description'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('academic-requirement-minimum-level'),
            controller: _minimumLevel,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: _t('Nivel mínimo aprobado', 'Minimum approved level'),
              hintText: _t('Opcional', 'Optional'),
              border: const OutlineInputBorder(),
            ),
          ),
          if (_validation != null) ...[
            const SizedBox(height: 10),
            Text(
              _validation!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            _t(
              'Se conservarán el tipo, el destino y la evidencia original. La corrección seguirá pendiente de confirmación.',
              'The original type, target, and evidence will be preserved. The correction will still require confirmation.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(_t('Cancelar', 'Cancel')),
      ),
      FilledButton(
        key: const Key('academic-requirement-save'),
        onPressed: _save,
        child: Text(_t('Guardar corrección', 'Save correction')),
      ),
    ],
  );
}

class _RamoEditResult {
  const _RamoEditResult(
    this.ramo,
    this.confirmarRevision,
    this.codigoDuplicadoVerificado,
    this.confirmarSinCodigo,
  );

  final RamoMalla ramo;
  final bool confirmarRevision;
  final bool codigoDuplicadoVerificado;
  final bool confirmarSinCodigo;
}

class _RamoEditDialog extends StatefulWidget {
  const _RamoEditDialog({
    required this.malla,
    required this.ramo,
    required this.newRamoId,
    required this.spanish,
    required this.saved,
    required this.canVerifyMissingCode,
    required this.periodType,
    required this.sourceEvidence,
  });

  final MallaCurricular malla;
  final RamoMalla? ramo;
  final String newRamoId;
  final bool spanish;
  final bool saved;
  final bool canVerifyMissingCode;
  final String periodType;
  final List<String> sourceEvidence;

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
  bool _verifyMissingCode = false;
  bool _verifyDuplicate = false;

  bool get _sameNormalizedCode =>
      MallaReviewRules.normalizedCode(widget.ramo?.codigo) ==
      MallaReviewRules.normalizedCode(_code.text);

  String _t(String es, String en) => widget.spanish ? es : en;

  String get _periodLabel => switch (widget.periodType) {
    'bimester' => _t('Bimestre', 'Bimester'),
    'trimester' => _t('Trimestre', 'Trimester'),
    'quarter' => _t('Trimestre', 'Quarter'),
    'annual' => _t('Período anual', 'Annual period'),
    _ => _t('Semestre', 'Semester'),
  };

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
          'Revisa el nombre (máximo 300 caracteres), código (máximo 64), ${_periodLabel.toLowerCase()} (1 a 30) y créditos (0 a 999 o vacíos).',
          'Check the name (up to 300 characters), code (up to 64), period (1 to 30), and credits (0 to 999 or empty).',
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
              verifyMissingCode: _verifyMissingCode,
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
        _verifyMissingCode,
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
                  if (MallaReviewRules.normalizedCode(_code.text) != null) {
                    _verifyMissingCode = false;
                  }
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
                label: '$_periodLabel *',
                icon: Ionicons.layersOutline,
              ),
              if (widget.sourceEvidence.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5B5FEF).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('Referencia de la malla', 'Curriculum reference'),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.sourceEvidence.first,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (widget.canVerifyMissingCode &&
                  widget.ramo != null &&
                  widget.ramo!.motivosRevision.contains('code_missing') &&
                  MallaReviewRules.normalizedCode(_code.text) == null)
                CheckboxListTile(
                  key: const Key('malla-verify-missing-code'),
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
                      'Confirmo que esta asignatura no tiene código en mi malla original',
                      'I confirm this course has no code in my original curriculum',
                    ),
                  ),
                  subtitle: Text(
                    _t(
                      'No se inventará ni asignará un código.',
                      'No code will be invented or assigned.',
                    ),
                  ),
                  value: _verifyMissingCode,
                  onChanged: (value) =>
                      setState(() => _verifyMissingCode = value ?? false),
                ),
              if (widget.canVerifyMissingCode &&
                  widget.ramo != null &&
                  widget.ramo!.motivosRevision.contains('code_missing') &&
                  MallaReviewRules.normalizedCode(_code.text) == null)
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
