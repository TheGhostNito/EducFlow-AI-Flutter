import 'package:flutter/material.dart';

import '../../models/asignatura.dart';
import '../../models/horario_importacion.dart';
import '../../models/horario_ocr_result.dart';
import '../../models/periodo_academico.dart';
import '../../services/horario_importacion_service.dart';
import '../../services/horario_documento_original_service.dart';
import '../../services/ocr_file_picker_service.dart';
import '../../widgets/app_transparent_app_bar.dart';

class HorarioOcrReviewPage extends StatefulWidget {
  const HorarioOcrReviewPage({
    super.key,
    required this.result,
    required this.spanish,
    this.documentHash = '',
    this.sourceName = '',
    this.originalFile,
    this.importacionGateway,
    this.documentoGateway,
    this.writesEnabled = false,
    this.documentStorageEnabled =
        HorarioImportacionConfig.documentStorageEnabled,
  });

  final HorarioOcrResult result;
  final bool spanish;
  final String documentHash;
  final String sourceName;
  final OcrPickedFile? originalFile;
  final HorarioImportacionGateway? importacionGateway;
  final HorarioDocumentoOriginalGateway? documentoGateway;
  final bool writesEnabled;
  final bool documentStorageEnabled;

  @visibleForTesting
  static bool periodoValido(DateTime? inicio, DateTime? fin) {
    return inicio == null || fin == null || !fin.isBefore(inicio);
  }

  @visibleForTesting
  static bool sesionDentroDeLimites(
    DateTime fecha,
    DateTime? inicio,
    DateTime? fin,
  ) {
    return (inicio == null || !fecha.isBefore(inicio)) &&
        (fin == null || !fecha.isAfter(fin));
  }

  @override
  State<HorarioOcrReviewPage> createState() => _HorarioOcrReviewPageState();
}

class _HorarioOcrReviewPageState extends State<HorarioOcrReviewPage> {
  final _scrollController = ScrollController();
  late final TextEditingController _yearController;
  late int? _semester;
  late DateTime? _startDate;
  late DateTime? _endDate;
  late final List<_SubjectDraft> _subjects;
  late final HorarioImportacionGateway? _importacionGateway;
  late final HorarioDocumentoOriginalGateway? _documentoGateway;
  List<String> _errors = const [];
  bool _saving = false;

  String _t(String es, String en) => widget.spanish ? es : en;

  @override
  void initState() {
    super.initState();
    final period = widget.result.period;
    _yearController = TextEditingController(
      text: period.year?.toString() ?? '',
    );
    _semester = period.semester;
    _startDate = period.startDate;
    _endDate = period.endDate;
    _subjects = widget.result.subjects.map(_SubjectDraft.fromResult).toList();
    _importacionGateway =
        widget.importacionGateway ??
        (widget.writesEnabled ? HorarioImportacionService() : null);
    _documentoGateway =
        widget.documentoGateway ??
        (widget.writesEnabled && widget.documentStorageEnabled
            ? HorarioDocumentoOriginalService()
            : null);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _yearController.dispose();
    for (final subject in _subjects) {
      subject.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPeriodDate({required bool start}) async {
    final current = start ? _startDate : _endDate;
    final year = int.tryParse(_yearController.text) ?? DateTime.now().year;
    final selected = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(year, start ? 3 : 7),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        _startDate = selected;
      } else {
        _endDate = selected;
      }
      _errors = const [];
    });
  }

  Future<void> _pickSessionDate(_SessionDraft session) async {
    final year = int.tryParse(_yearController.text) ?? DateTime.now().year;
    final selected = await showDatePicker(
      context: context,
      initialDate: session.date ?? _startDate ?? DateTime(year, 3),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (selected == null || !mounted) return;
    setState(() {
      session.date = selected;
      _errors = const [];
    });
  }

  void _addWeeklyBlock(_SubjectDraft subject) {
    setState(() {
      subject.weeklyBlocks.add(_WeeklyBlockDraft.empty());
      _errors = const [];
    });
  }

  void _addSession(_SubjectDraft subject) {
    setState(() {
      subject.datedSessions.add(_SessionDraft.empty());
      _errors = const [];
    });
  }

  void _removeWeeklyBlock(_SubjectDraft subject, int index) {
    setState(() {
      subject.weeklyBlocks.removeAt(index).dispose();
      _errors = const [];
    });
  }

  void _removeSession(_SubjectDraft subject, int index) {
    setState(() {
      subject.datedSessions.removeAt(index).dispose();
      _errors = const [];
    });
  }

  void _review() {
    FocusScope.of(context).unfocus();
    final errors = _validate();
    setState(() => _errors = errors);
    if (errors.isNotEmpty) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      return;
    }
    _showSummary();
  }

  List<String> _validate() {
    final errors = <String>[];
    final year = int.tryParse(_yearController.text.trim());
    if (year == null || year < 2000 || year > 2100) {
      errors.add(
        _t('Ingresa un año académico válido.', 'Enter a valid academic year.'),
      );
    }
    if (_semester == null || _semester! < 1 || _semester! > 3) {
      errors.add(
        _t('Selecciona un semestre válido.', 'Select a valid semester.'),
      );
    }
    if (!HorarioOcrReviewPage.periodoValido(_startDate, _endDate)) {
      errors.add(
        _t(
          'La fecha de término no puede ser anterior al inicio.',
          'The end date cannot be before the start date.',
        ),
      );
    }

    for (
      var subjectIndex = 0;
      subjectIndex < _subjects.length;
      subjectIndex++
    ) {
      final subject = _subjects[subjectIndex];
      final label = subject.name.text.trim().isEmpty
          ? _t('Asignatura ${subjectIndex + 1}', 'Subject ${subjectIndex + 1}')
          : subject.name.text.trim();
      if (subject.name.text.trim().isEmpty) {
        errors.add(_t('$label necesita un nombre.', '$label needs a name.'));
      }
      final email = subject.professorEmail.text.trim();
      if (email.isNotEmpty &&
          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
        errors.add(
          _t(
            'El correo de $label no es válido.',
            '$label has an invalid email.',
          ),
        );
      }
      if (subject.weeklyBlocks.isEmpty && subject.datedSessions.isEmpty) {
        errors.add(
          _t(
            '$label necesita al menos una clase o sesión.',
            '$label needs at least one class or session.',
          ),
        );
      }

      final weeklyIdentities = <String>{};
      for (var index = 0; index < subject.weeklyBlocks.length; index++) {
        final block = subject.weeklyBlocks[index];
        final blockLabel = _t(
          'bloque ${index + 1} de $label',
          'block ${index + 1} of $label',
        );
        if (block.day == null) {
          errors.add(
            _t(
              'Selecciona el día del $blockLabel.',
              'Select the day for $blockLabel.',
            ),
          );
        } else if (block.day == HorarioOcrDay.domingo) {
          errors.add(
            _t(
              'El domingo no es compatible con los bloques académicos actuales.',
              'Sunday is not supported by the current academic blocks.',
            ),
          );
        }
        if (!_validTimeRange(block.start.text, block.end.text)) {
          errors.add(
            _t(
              'Revisa las horas del $blockLabel.',
              'Review the times for $blockLabel.',
            ),
          );
        }
        final identity =
            '${block.day}|${block.start.text}|${block.end.text}|${block.room.text.trim().toLowerCase()}';
        if (!weeklyIdentities.add(identity)) {
          errors.add(
            _t(
              '$label contiene bloques semanales duplicados.',
              '$label contains duplicate weekly blocks.',
            ),
          );
        }
      }

      final sessionIdentities = <String>{};
      for (var index = 0; index < subject.datedSessions.length; index++) {
        final session = subject.datedSessions[index];
        final sessionLabel = _t(
          'sesión ${index + 1} de $label',
          'session ${index + 1} of $label',
        );
        if (session.date == null) {
          errors.add(
            _t(
              'Selecciona la fecha de la $sessionLabel.',
              'Select the date for $sessionLabel.',
            ),
          );
        } else if (!HorarioOcrReviewPage.sesionDentroDeLimites(
          session.date!,
          _startDate,
          _endDate,
        )) {
          errors.add(
            _t(
              'La $sessionLabel está fuera del período.',
              'The $sessionLabel is outside the period.',
            ),
          );
        }
        if (!_validTimeRange(session.start.text, session.end.text)) {
          errors.add(
            _t(
              'Revisa las horas de la $sessionLabel.',
              'Review the times for $sessionLabel.',
            ),
          );
        }
        final identity =
            '${session.date}|${session.start.text}|${session.end.text}|${session.room.text.trim().toLowerCase()}';
        if (!sessionIdentities.add(identity)) {
          errors.add(
            _t(
              '$label contiene sesiones específicas duplicadas.',
              '$label contains duplicate dated sessions.',
            ),
          );
        }
      }
    }
    return errors.toSet().toList();
  }

  bool _validTimeRange(String start, String end) {
    final startMinutes = _timeMinutes(start.trim());
    final endMinutes = _timeMinutes(end.trim());
    return startMinutes != null &&
        endMinutes != null &&
        endMinutes > startMinutes;
  }

  int? _timeMinutes(String value) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }

  Future<void> _showSummary() async {
    final weeklyCount = _subjects.fold<int>(
      0,
      (sum, item) => sum + item.weeklyBlocks.length,
    );
    final sessionCount = _subjects.fold<int>(
      0,
      (sum, item) => sum + item.datedSessions.length,
    );
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        builder: (context, controller) => ListView(
          key: const Key('horario-review-summary'),
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Icon(
              Icons.check_circle_outline_rounded,
              color: Color(0xFF5B5FEF),
              size: 44,
            ),
            const SizedBox(height: 10),
            Text(
              _t(
                'Horario listo para la siguiente fase',
                'Schedule ready for the next phase',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _t(
                'Validación local completada. No se guardó información.',
                'Local validation completed. No information was saved.',
              ),
              textAlign: TextAlign.center,
            ),
            const Divider(height: 32),
            _summaryRow(
              _t('Período', 'Period'),
              '$_semester° ${_yearController.text.trim()}',
            ),
            _summaryRow(
              _t('Fechas', 'Dates'),
              '${_formatDate(_startDate)} — ${_formatDate(_endDate)}',
            ),
            _summaryRow(_t('Asignaturas', 'Subjects'), '${_subjects.length}'),
            _summaryRow(
              _t('Bloques semanales', 'Weekly blocks'),
              '$weeklyCount',
            ),
            _summaryRow(
              _t('Sesiones específicas', 'Dated sessions'),
              '$sessionCount',
            ),
            const Divider(height: 32),
            for (final subject in _subjects)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(subject.name.text.trim()),
                subtitle: Text(
                  [
                    if (subject.code.text.trim().isNotEmpty)
                      subject.code.text.trim(),
                    if (subject.section.text.trim().isNotEmpty)
                      _t(
                        'Sección ${subject.section.text.trim()}',
                        'Section ${subject.section.text.trim()}',
                      ),
                    _t(
                      '${subject.weeklyBlocks.length} bloques',
                      '${subject.weeklyBlocks.length} blocks',
                    ),
                    _t(
                      '${subject.datedSessions.length} sesiones',
                      '${subject.datedSessions.length} sessions',
                    ),
                  ].join(' · '),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              _t(
                'Advertencias pendientes: ninguna validación bloqueante.',
                'Pending warnings: no blocking validation issues.',
              ),
              key: const Key('horario-review-summary-warnings'),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('horario-review-save-import'),
              onPressed: widget.writesEnabled && !_saving
                  ? () => _confirmSave(context)
                  : null,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: Text(
                widget.writesEnabled
                    ? _t('Guardar horario importado', 'Save imported schedule')
                    : _t(
                        'Guardado remoto pendiente de autorización',
                        'Remote save pending authorization',
                      ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_t('Volver a revisar', 'Back to review')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSave(BuildContext sheetContext) async {
    if (_saving) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: sheetContext,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF191F29) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: dark
                        ? const Color(0xFF48505E)
                        : const Color(0xFFD5D9E0),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Icon(
                Icons.cloud_upload_outlined,
                color: Color(0xFF5B5FEF),
                size: 34,
              ),
              const SizedBox(height: 12),
              Text(
                _t('Guardar horario', 'Save schedule'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _t(
                  'Se crearán el período, las asignaturas, sus bloques y sesiones en una única operación. Tus asignaturas actuales no se modificarán.',
                  'The period, subjects, blocks, and sessions will be created in one operation. Your existing subjects will not be modified.',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('horario-review-confirm-save'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(_t('Guardar horario', 'Save schedule')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(_t('Cancelar', 'Cancel')),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true || !mounted || !sheetContext.mounted) return;
    final importGateway = _importacionGateway;
    if (importGateway == null) {
      throw StateError('El guardado remoto no está habilitado.');
    }
    Navigator.pop(sheetContext);
    setState(() {
      _saving = true;
      _errors = const [];
    });
    try {
      HorarioDocumentoOriginal? document;
      final file = widget.originalFile;
      if (widget.documentStorageEnabled && file != null) {
        document = await _documentoGateway!.subir(
          file: file,
          importacionId: _importacionId(),
        );
      }
      HorarioImportacionResultado result;
      try {
        result = await importGateway.confirmar(
          _buildProposal(documentoOriginal: document),
        );
      } catch (_) {
        if (document != null) await _limpiarDocumentoFallido(document.path);
        rethrow;
      }
      if (result.yaExistia && document != null) {
        // La RPC puede asociarlo a una importación anterior sin volver a
        // crear asignaturas. Si ya existía otro documento, limpia el nuevo.
        final imports = await importGateway.listar();
        HorarioImportacionRegistro? current;
        for (final item in imports) {
          if (item.id == result.importacionId) {
            current = item;
            break;
          }
        }
        if (current?.documentoOriginal?.path != document.path) {
          await _limpiarDocumentoFallido(document.path);
        }
      }
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        enableDrag: false,
        isDismissible: false,
        backgroundColor: Colors.transparent,
        builder: (context) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          return Container(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF191F29) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  color: Color(0xFF22C55E),
                  size: 42,
                ),
                const SizedBox(height: 12),
                Text(
                  result.yaExistia
                      ? _t('Horario ya importado', 'Schedule already imported')
                      : _t('Horario guardado', 'Schedule saved'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _t(
                    '${result.asignaturas} asignaturas, ${result.bloques} bloques y ${result.sesiones} sesiones ya están disponibles en Horario y Calendario.',
                    '${result.asignaturas} subjects, ${result.bloques} blocks, and ${result.sesiones} sessions are now available in Schedule and Calendar.',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(_t('Ver mi horario', 'View my schedule')),
                ),
              ],
            ),
          );
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errors = [_safeError(error)]);
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _limpiarDocumentoFallido(String path) async {
    final gateway = _documentoGateway;
    if (gateway == null) return;
    try {
      await gateway.registrarLimpieza(path);
    } catch (_) {
      // La cola conserva el archivo privado para que el servidor lo limpie.
    }
  }

  String _importacionId() {
    final hash = widget.documentHash.trim().toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('El hash del documento no es válido.');
    }
    return hash.substring(0, 32);
  }

  HorarioImportacionPropuesta _buildProposal({
    HorarioDocumentoOriginal? documentoOriginal,
  }) {
    final year = int.parse(_yearController.text.trim());
    final semester = _semester!;
    final period = PeriodoAcademico(
      id: 'pendiente',
      anio: year,
      tipo: TipoPeriodoAcademico.semestre,
      numero: semester,
      nombre: _t('Semestre $semester de $year', 'Semester $semester of $year'),
      fechaInicio: _startDate,
      fechaFin: _endDate,
      estado: year < DateTime.now().year
          ? EstadoPeriodoAcademico.historico
          : EstadoPeriodoAcademico.activo,
    );
    return HorarioImportacionPropuesta(
      documentHash: widget.documentHash,
      nombreDocumento: widget.sourceName,
      periodo: period,
      asignaturas: [
        for (var index = 0; index < _subjects.length; index++)
          HorarioImportacionAsignatura(
            asignatura: Asignatura(
              id: 'pendiente_${index + 1}',
              nombre: _subjects[index].name.text.trim(),
              profesor: _clean(_subjects[index].professor.text),
              correoProfesor: _clean(_subjects[index].professorEmail.text),
              periodo: '$semester° semestre $year',
              periodoAcademicoId: period.id,
              horario: [
                for (final block in _subjects[index].weeklyBlocks)
                  BloqueHorario(
                    dia: _domainDay(block.day!),
                    horaInicio: block.start.text.trim(),
                    horaFin: block.end.text.trim(),
                    sala: _clean(block.room.text),
                  ),
              ],
              estado: EstadoAsignatura.enCurso,
              origen: OrigenAsignatura.horario,
              sigla: _clean(_subjects[index].code.text),
              seccion: _clean(_subjects[index].section.text),
              anioAcademico: year,
            ),
            sesiones: [
              for (final session in _subjects[index].datedSessions)
                HorarioImportacionSesion(
                  fecha: session.date!,
                  horaInicio: session.start.text.trim(),
                  horaFin: session.end.text.trim(),
                  sala: _clean(session.room.text),
                ),
            ],
          ),
      ],
      documentoOriginal: documentoOriginal,
    );
  }

  DiaSemana _domainDay(HorarioOcrDay value) => switch (value) {
    HorarioOcrDay.lunes => DiaSemana.lunes,
    HorarioOcrDay.martes => DiaSemana.martes,
    HorarioOcrDay.miercoles => DiaSemana.miercoles,
    HorarioOcrDay.jueves => DiaSemana.jueves,
    HorarioOcrDay.viernes => DiaSemana.viernes,
    HorarioOcrDay.sabado => DiaSemana.sabado,
    HorarioOcrDay.domingo => throw const FormatException(
      'El domingo no es compatible con bloques académicos.',
    ),
  };

  String? _clean(String value) {
    final clean = value.trim();
    return clean.isEmpty ? null : clean;
  }

  String _safeError(Object error) {
    return error.toString().replaceFirst(RegExp(r'^\w+Exception:\s*'), '');
  }

  Widget _summaryRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTransparentAppBar(
        title: _t('Revisar horario', 'Review schedule'),
      ),
      body: SafeArea(
        child: ListView(
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _intro(),
            if (_errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              _errorSummary(),
            ],
            const SizedBox(height: 16),
            _periodCard(),
            const SizedBox(height: 18),
            Text(
              _t('Asignaturas detectadas', 'Detected subjects'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < _subjects.length; index++) ...[
              _subjectCard(_subjects[index], index),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('horario-review-confirm'),
              onPressed: _review,
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(
                _t('Validar y revisar resumen', 'Validate and review summary'),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _t(
                'Esta acción solo valida el borrador local. No escribe en Supabase.',
                'This action only validates the local draft. It does not write to Supabase.',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _intro() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.edit_calendar_outlined, color: Color(0xFF5B5FEF)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _t(
                'Corrige los datos detectados. Las clases semanales y las sesiones con fecha específica permanecen separadas.',
                'Correct the detected data. Weekly classes and dated sessions remain separate.',
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _errorSummary() => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        key: const Key('horario-review-errors'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('Revisa estos datos:', 'Review these details:'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          for (final error in _errors) Text('• $error'),
        ],
      ),
    ),
  );

  Widget _periodCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _t('Período académico', 'Academic period'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('horario-review-year'),
                  controller: _yearController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: _t('Año', 'Year')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: const Key('horario-review-semester'),
                  initialValue: _semester,
                  decoration: InputDecoration(
                    labelText: _t('Semestre', 'Semester'),
                  ),
                  items: [
                    for (final value in [1, 2, 3])
                      DropdownMenuItem(value: value, child: Text('$value')),
                  ],
                  onChanged: (value) => setState(() => _semester = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _dateButton(
            key: const Key('horario-review-period-start'),
            label: _t('Inicio del período', 'Period start'),
            value: _startDate,
            onTap: () => _pickPeriodDate(start: true),
            onClear: _startDate == null
                ? null
                : () => setState(() => _startDate = null),
          ),
          const SizedBox(height: 8),
          _dateButton(
            key: const Key('horario-review-period-end'),
            label: _t('Término del período', 'Period end'),
            value: _endDate,
            onTap: () => _pickPeriodDate(start: false),
            onClear: _endDate == null
                ? null
                : () => setState(() => _endDate = null),
          ),
          if (_startDate == null || _endDate == null) ...[
            const SizedBox(height: 10),
            Text(
              _t(
                'Las fechas son opcionales e independientes. Puedes dejarlas por definir y completarlas posteriormente.',
                'Dates are optional and independent. You can leave them undefined and complete them later.',
              ),
              key: const Key('horario-review-period-dates-optional'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _dateButton({
    required Key key,
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    required VoidCallback? onClear,
  }) => Row(
    children: [
      Expanded(
        child: OutlinedButton.icon(
          key: key,
          onPressed: onTap,
          icon: const Icon(Icons.calendar_month_outlined),
          label: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '$label: ${value == null ? _t('Por definir', 'To be defined') : _formatDate(value)}',
            ),
          ),
        ),
      ),
      if (onClear != null)
        IconButton(
          tooltip: _t('Dejar fecha por definir', 'Leave date undefined'),
          onPressed: onClear,
          icon: const Icon(Icons.clear_rounded),
        ),
    ],
  );

  Widget _subjectCard(_SubjectDraft subject, int subjectIndex) => Card(
    child: ExpansionTile(
      key: ValueKey('horario-review-subject-$subjectIndex'),
      initiallyExpanded: subjectIndex == 0,
      title: Text(
        subject.name.text.trim().isEmpty
            ? _t(
                'Asignatura ${subjectIndex + 1}',
                'Subject ${subjectIndex + 1}',
              )
            : subject.name.text.trim(),
      ),
      subtitle: Text(
        _t(
          '${subject.weeklyBlocks.length} bloques · ${subject.datedSessions.length} sesiones',
          '${subject.weeklyBlocks.length} blocks · ${subject.datedSessions.length} sessions',
        ),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        TextField(
          key: ValueKey('horario-review-subject-name-$subjectIndex'),
          controller: subject.name,
          decoration: InputDecoration(labelText: _t('Nombre', 'Name')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: subject.code,
                decoration: InputDecoration(labelText: _t('Código', 'Code')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: subject.section,
                decoration: InputDecoration(
                  labelText: _t('Sección', 'Section'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: subject.professor,
          decoration: InputDecoration(
            labelText: _t('Profesor opcional', 'Optional professor'),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: subject.professorEmail,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: _t('Correo opcional', 'Optional email'),
          ),
        ),
        const SizedBox(height: 18),
        _occurrenceHeader(
          _t('Clases semanales', 'Weekly classes'),
          () => _addWeeklyBlock(subject),
          'horario-review-add-block-$subjectIndex',
        ),
        if (subject.weeklyBlocks.isEmpty)
          _empty(_t('Sin bloques semanales.', 'No weekly blocks.')),
        for (var index = 0; index < subject.weeklyBlocks.length; index++)
          _weeklyBlockEditor(subject, subjectIndex, index),
        const SizedBox(height: 16),
        _occurrenceHeader(
          _t('Sesiones con fecha específica', 'Dated sessions'),
          () => _addSession(subject),
          'horario-review-add-session-$subjectIndex',
        ),
        if (subject.datedSessions.isEmpty)
          _empty(_t('Sin sesiones específicas.', 'No dated sessions.')),
        for (var index = 0; index < subject.datedSessions.length; index++)
          _sessionEditor(subject, subjectIndex, index),
      ],
    ),
  );

  Widget _occurrenceHeader(String title, VoidCallback onAdd, String key) => Row(
    children: [
      Expanded(
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      IconButton(
        key: ValueKey(key),
        tooltip: _t('Agregar', 'Add'),
        onPressed: onAdd,
        icon: const Icon(Icons.add_circle_outline),
      ),
    ],
  );

  Widget _weeklyBlockEditor(
    _SubjectDraft subject,
    int subjectIndex,
    int index,
  ) {
    final block = subject.weeklyBlocks[index];
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<HorarioOcrDay>(
                  key: ValueKey(
                    'horario-review-block-day-$subjectIndex-$index',
                  ),
                  initialValue: block.day,
                  decoration: InputDecoration(labelText: _t('Día', 'Day')),
                  items: [
                    for (final day in HorarioOcrDay.values)
                      DropdownMenuItem(value: day, child: Text(_day(day))),
                  ],
                  onChanged: (value) => setState(() => block.day = value),
                ),
              ),
              IconButton(
                key: ValueKey(
                  'horario-review-remove-block-$subjectIndex-$index',
                ),
                tooltip: _t('Quitar bloque', 'Remove block'),
                onPressed: () => _removeWeeklyBlock(subject, index),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _timeAndRoom(
            block.start,
            block.end,
            block.room,
            'block-$subjectIndex-$index',
          ),
        ],
      ),
    );
  }

  Widget _sessionEditor(_SubjectDraft subject, int subjectIndex, int index) {
    final session = subject.datedSessions[index];
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: ValueKey(
                    'horario-review-session-date-$subjectIndex-$index',
                  ),
                  onPressed: () => _pickSessionDate(session),
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    session.date == null
                        ? _t('Elegir fecha', 'Choose date')
                        : _formatDate(session.date),
                  ),
                ),
              ),
              IconButton(
                key: ValueKey(
                  'horario-review-remove-session-$subjectIndex-$index',
                ),
                tooltip: _t('Quitar sesión', 'Remove session'),
                onPressed: () => _removeSession(subject, index),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _timeAndRoom(
            session.start,
            session.end,
            session.room,
            'session-$subjectIndex-$index',
          ),
        ],
      ),
    );
  }

  Widget _timeAndRoom(
    TextEditingController start,
    TextEditingController end,
    TextEditingController room,
    String keyPrefix,
  ) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: TextField(
              key: ValueKey('horario-review-$keyPrefix-start'),
              controller: start,
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                labelText: _t('Inicio HH:mm', 'Start HH:mm'),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: ValueKey('horario-review-$keyPrefix-end'),
              controller: end,
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                labelText: _t('Término HH:mm', 'End HH:mm'),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      TextField(
        key: ValueKey('horario-review-$keyPrefix-room'),
        controller: room,
        decoration: InputDecoration(
          labelText: _t('Sala opcional', 'Optional room'),
        ),
      ),
    ],
  );

  Widget _empty(String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(value, style: Theme.of(context).textTheme.bodySmall),
    ),
  );

  String _formatDate(DateTime? value) {
    if (value == null) return _t('Por definir', 'To be defined');
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  }

  String _day(HorarioOcrDay day) => switch (day) {
    HorarioOcrDay.lunes => _t('Lunes', 'Monday'),
    HorarioOcrDay.martes => _t('Martes', 'Tuesday'),
    HorarioOcrDay.miercoles => _t('Miércoles', 'Wednesday'),
    HorarioOcrDay.jueves => _t('Jueves', 'Thursday'),
    HorarioOcrDay.viernes => _t('Viernes', 'Friday'),
    HorarioOcrDay.sabado => _t('Sábado', 'Saturday'),
    HorarioOcrDay.domingo => _t('Domingo', 'Sunday'),
  };
}

class _SubjectDraft {
  _SubjectDraft({
    required this.name,
    required this.code,
    required this.section,
    required this.professor,
    required this.professorEmail,
    required this.weeklyBlocks,
    required this.datedSessions,
  });

  factory _SubjectDraft.fromResult(HorarioOcrSubject subject) => _SubjectDraft(
    name: TextEditingController(text: subject.name ?? ''),
    code: TextEditingController(text: subject.code ?? ''),
    section: TextEditingController(text: subject.section ?? ''),
    professor: TextEditingController(text: subject.professor ?? ''),
    professorEmail: TextEditingController(text: subject.professorEmail ?? ''),
    weeklyBlocks: subject.weeklyBlocks
        .map(_WeeklyBlockDraft.fromResult)
        .toList(),
    datedSessions: subject.datedSessions.map(_SessionDraft.fromResult).toList(),
  );

  final TextEditingController name;
  final TextEditingController code;
  final TextEditingController section;
  final TextEditingController professor;
  final TextEditingController professorEmail;
  final List<_WeeklyBlockDraft> weeklyBlocks;
  final List<_SessionDraft> datedSessions;

  void dispose() {
    name.dispose();
    code.dispose();
    section.dispose();
    professor.dispose();
    professorEmail.dispose();
    for (final value in weeklyBlocks) {
      value.dispose();
    }
    for (final value in datedSessions) {
      value.dispose();
    }
  }
}

class _WeeklyBlockDraft {
  _WeeklyBlockDraft({
    required this.day,
    required this.start,
    required this.end,
    required this.room,
  });
  factory _WeeklyBlockDraft.fromResult(HorarioOcrWeeklyBlock value) =>
      _WeeklyBlockDraft(
        day: value.day,
        start: TextEditingController(text: value.startTime ?? ''),
        end: TextEditingController(text: value.endTime ?? ''),
        room: TextEditingController(text: value.room ?? ''),
      );
  factory _WeeklyBlockDraft.empty() => _WeeklyBlockDraft(
    day: null,
    start: TextEditingController(),
    end: TextEditingController(),
    room: TextEditingController(),
  );
  HorarioOcrDay? day;
  final TextEditingController start;
  final TextEditingController end;
  final TextEditingController room;
  void dispose() {
    start.dispose();
    end.dispose();
    room.dispose();
  }
}

class _SessionDraft {
  _SessionDraft({
    required this.date,
    required this.start,
    required this.end,
    required this.room,
  });
  factory _SessionDraft.fromResult(HorarioOcrDatedSession value) =>
      _SessionDraft(
        date: value.date,
        start: TextEditingController(text: value.startTime ?? ''),
        end: TextEditingController(text: value.endTime ?? ''),
        room: TextEditingController(text: value.room ?? ''),
      );
  factory _SessionDraft.empty() => _SessionDraft(
    date: null,
    start: TextEditingController(),
    end: TextEditingController(),
    room: TextEditingController(),
  );
  DateTime? date;
  final TextEditingController start;
  final TextEditingController end;
  final TextEditingController room;
  void dispose() {
    start.dispose();
    end.dispose();
    room.dispose();
  }
}
