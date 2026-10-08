import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/evaluacion.dart';
import '../../../models/nota.dart';
import 'grade_input_dialogs.dart';

Future<ConfiguracionCalculoAsignatura?> showGradeSchemeDialog({
  required BuildContext context,
  required ConfiguracionCalculoAsignatura initial,
  required List<Evaluacion> evaluaciones,
  required bool spanish,
  required Future<void> Function(ConfiguracionCalculoAsignatura) onSave,
}) {
  return showModalBottomSheet<ConfiguracionCalculoAsignatura>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    builder: (_) => _GradeSchemeSheet(
      initial: initial,
      evaluaciones: evaluaciones,
      spanish: spanish,
      onSave: onSave,
    ),
  );
}

class _GradeSchemeSheet extends StatefulWidget {
  const _GradeSchemeSheet({
    required this.initial,
    required this.evaluaciones,
    required this.spanish,
    required this.onSave,
  });

  final ConfiguracionCalculoAsignatura initial;
  final List<Evaluacion> evaluaciones;
  final bool spanish;
  final Future<void> Function(ConfiguracionCalculoAsignatura) onSave;

  @override
  State<_GradeSchemeSheet> createState() => _GradeSchemeSheetState();
}

class _GradeSchemeSheetState extends State<_GradeSchemeSheet> {
  static const Color _primaryColor = Color(0xFF5B5FEF);
  late EsquemaCalculoNotas _scheme;
  late String? _examId;
  late final TextEditingController _presentationController;
  late final TextEditingController _examController;
  bool _saving = false;
  String? _error;

  bool get _usesExam => _scheme == EsquemaCalculoNotas.presentacionExamen;

  double? get _presentationWeight =>
      double.tryParse(_presentationController.text.trim().replaceAll(',', '.'));

  double? get _examWeight =>
      double.tryParse(_examController.text.trim().replaceAll(',', '.'));

  double? get _totalWeight {
    final double? presentation = _presentationWeight;
    final double? exam = _examWeight;
    if (presentation == null || exam == null) return null;
    return presentation + exam;
  }

  Evaluacion? get _selectedExam {
    for (final Evaluacion evaluation in widget.evaluaciones) {
      if (evaluation.id == _examId) return evaluation;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _scheme = widget.initial.esquema;
    _examId = widget.initial.evaluacionExamenId;
    _presentationController = TextEditingController(
      text: widget.initial.pesoPresentacion.toStringAsFixed(0),
    );
    _examController = TextEditingController(
      text: widget.initial.pesoExamen.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _presentationController.dispose();
    _examController.dispose();
    super.dispose();
  }

  void _changeScheme(EsquemaCalculoNotas value) {
    if (_saving || value == _scheme) return;
    HapticFeedback.selectionClick();
    setState(() {
      _scheme = value;
      _error = null;
      if (value == EsquemaCalculoNotas.directo) {
        _presentationController.text = '100';
        _examController.text = '0';
        _examId = null;
      } else if (_examController.text == '0') {
        _presentationController.text = '60';
        _examController.text = '40';
      }
    });
  }

  Future<void> _chooseExam() async {
    if (_saving || widget.evaluaciones.isEmpty) return;
    HapticFeedback.selectionClick();
    final String? selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (sheetContext) {
        final bool dark = Theme.of(sheetContext).brightness == Brightness.dark;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.68,
          ),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
          decoration: _sheetDecoration(dark),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dragHandle(dark),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 18, 4, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.spanish
                            ? 'Selecciona el examen final'
                            : 'Select the final exam',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.35,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.evaluaciones.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final Evaluacion evaluation = widget.evaluaciones[index];
                    final bool active = evaluation.id == _examId;
                    return InkWell(
                      key: ValueKey('grade-scheme-exam-${evaluation.id}'),
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.of(sheetContext).pop(evaluation.id);
                      },
                      child: _selectionCard(
                        dark: dark,
                        active: active,
                        icon: Icons.school_outlined,
                        child: Text(
                          evaluation.titulo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: active
                                ? (dark
                                      ? const Color(0xFFC7C9FF)
                                      : _primaryColor)
                                : null,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    setState(() {
      _examId = selected;
      _error = null;
    });
  }

  Future<void> _save() async {
    final ConfiguracionCalculoAsignatura result =
        ConfiguracionCalculoAsignatura(
          asignaturaId: widget.initial.asignaturaId,
          esquema: _scheme,
          pesoPresentacion: _presentationWeight ?? double.nan,
          pesoExamen: _examWeight ?? double.nan,
          evaluacionExamenId: _usesExam ? _examId : null,
        );
    if (!result.esValida) {
      setState(() {
        _error = widget.spanish
            ? 'Los porcentajes deben sumar 100 % y debes elegir un examen final.'
            : 'Percentages must total 100% and a final exam must be selected.';
      });
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);
    try {
      await widget.onSave(result);
      if (mounted) Navigator.of(context).pop(result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = widget.spanish
            ? 'No pudimos guardar el esquema académico.'
            : 'We could not save the academic scheme.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: !_saving,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        decoration: _sheetDecoration(dark),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            18,
            10,
            18,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: _dragHandle(dark)),
              const SizedBox(height: 18),
              _header(dark),
              const SizedBox(height: 22),
              _sectionLabel(
                widget.spanish ? 'TIPO DE CÁLCULO' : 'CALCULATION TYPE',
              ),
              const SizedBox(height: 10),
              _schemeOption(
                dark: dark,
                value: EsquemaCalculoNotas.directo,
                icon: Icons.calculate_outlined,
                title: widget.spanish
                    ? 'Cálculo directo'
                    : 'Direct calculation',
                description: widget.spanish
                    ? 'Todas las evaluaciones forman directamente la nota final.'
                    : 'All assessments directly build the final grade.',
              ),
              const SizedBox(height: 9),
              _schemeOption(
                dark: dark,
                value: EsquemaCalculoNotas.presentacionExamen,
                icon: Icons.account_tree_outlined,
                title: widget.spanish
                    ? 'Presentación + examen final'
                    : 'Coursework + final exam',
                description: widget.spanish
                    ? 'Combina la presentación con un examen separado.'
                    : 'Combines coursework with a separate final exam.',
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: !_usesExam
                    ? const SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 22),
                          _sectionLabel(
                            widget.spanish
                                ? 'CONFIGURACIÓN DEL EXAMEN'
                                : 'EXAM SETUP',
                          ),
                          const SizedBox(height: 10),
                          _examSelector(dark),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _weightField(
                                  dark: dark,
                                  fieldKey: const ValueKey(
                                    'grade-scheme-presentation-weight',
                                  ),
                                  controller: _presentationController,
                                  label: widget.spanish
                                      ? 'Presentación'
                                      : 'Coursework',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _weightField(
                                  dark: dark,
                                  fieldKey: const ValueKey(
                                    'grade-scheme-exam-weight',
                                  ),
                                  controller: _examController,
                                  label: widget.spanish ? 'Examen' : 'Exam',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _weightStatus(dark),
                        ],
                      ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                _errorMessage(),
              ],
              const SizedBox(height: 22),
              _actions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(bool dark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _iconBox(Icons.tune_rounded, dark, active: true),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.spanish ? 'Esquema de cálculo' : 'Calculation scheme',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.45,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.spanish
                    ? 'Define cómo se obtiene la nota final de esta asignatura.'
                    : 'Define how the final grade is calculated for this subject.',
                style: TextStyle(
                  color: dark
                      ? const Color(0xFFA9B1BF)
                      : const Color(0xFF6B7280),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }

  Widget _schemeOption({
    required bool dark,
    required EsquemaCalculoNotas value,
    required IconData icon,
    required String title,
    required String description,
  }) {
    final bool active = _scheme == value;
    return InkWell(
      key: ValueKey('grade-scheme-${value.name}'),
      onTap: _saving ? null : () => _changeScheme(value),
      borderRadius: BorderRadius.circular(17),
      child: _selectionCard(
        dark: dark,
        active: active,
        icon: icon,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: active
                    ? (dark ? const Color(0xFFC7C9FF) : _primaryColor)
                    : null,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              description,
              style: TextStyle(
                color: dark ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectionCard({
    required bool dark,
    required bool active,
    required IconData icon,
    required Widget child,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: active
            ? (dark ? const Color(0xFF2B3047) : const Color(0xFFEEF0FF))
            : (dark ? const Color(0xFF202731) : Colors.white),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: active
              ? (dark ? const Color(0xFF5E66A0) : const Color(0xFFC9CCFF))
              : (dark ? const Color(0xFF303844) : const Color(0xFFE7EAF0)),
          width: active ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          _iconBox(icon, dark, active: active),
          const SizedBox(width: 13),
          Expanded(child: child),
          const SizedBox(width: 10),
          Icon(
            active ? Icons.check_circle_rounded : Icons.circle_outlined,
            color: active
                ? _primaryColor
                : (dark ? const Color(0xFF667080) : const Color(0xFFB4BAC4)),
          ),
        ],
      ),
    );
  }

  Widget _examSelector(bool dark) {
    final Evaluacion? exam = _selectedExam;
    final bool empty = widget.evaluaciones.isEmpty;
    return InkWell(
      key: const ValueKey('grade-scheme-exam'),
      onTap: empty || _saving ? null : _chooseExam,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF202731) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: exam == null
                ? (dark ? const Color(0xFF3A4350) : const Color(0xFFDDE1E7))
                : (dark ? const Color(0xFF5E66A0) : const Color(0xFFC9CCFF)),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.school_outlined, color: _primaryColor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.spanish ? 'Examen final' : 'Final exam',
                    style: TextStyle(
                      color: dark
                          ? const Color(0xFFA9B1BF)
                          : const Color(0xFF6B7280),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    empty
                        ? (widget.spanish
                              ? 'No hay evaluaciones disponibles'
                              : 'No assessments available')
                        : exam?.titulo ??
                              (widget.spanish
                                  ? 'Seleccionar evaluación'
                                  : 'Select assessment'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            if (!empty)
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: _primaryColor,
              ),
          ],
        ),
      ),
    );
  }

  Widget _weightField({
    required bool dark,
    required Key fieldKey,
    required TextEditingController controller,
    required String label,
  }) {
    return TextField(
      key: fieldKey,
      controller: controller,
      enabled: !_saving,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: const [DecimalTextInputFormatter(2)],
      onChanged: (_) => setState(() => _error = null),
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: InputDecoration(
        labelText: label,
        suffixText: '%',
        filled: true,
        fillColor: dark ? const Color(0xFF202731) : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(
            color: dark ? const Color(0xFF3A4350) : const Color(0xFFDDE1E7),
          ),
        ),
      ),
    );
  }

  Widget _weightStatus(bool dark) {
    final double? total = _totalWeight;
    final bool complete = total != null && (total - 100).abs() < 0.000001;
    final String value = total == null
        ? '—'
        : total % 1 == 0
        ? total.toStringAsFixed(0)
        : total.toStringAsFixed(1);
    return Row(
      children: [
        Icon(
          complete ? Icons.check_circle_rounded : Icons.info_outline_rounded,
          color: complete
              ? const Color(0xFF16A34A)
              : (dark ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280)),
          size: 18,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            widget.spanish
                ? 'Total configurado: $value % de 100 %'
                : 'Configured total: $value% of 100%',
            style: TextStyle(
              color: complete
                  ? const Color(0xFF16A34A)
                  : (dark ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280)),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorMessage() {
    final Color errorColor = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: errorColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: errorColor, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(color: errorColor, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: Text(widget.spanish ? 'Cancelar' : 'Cancel'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            key: const ValueKey('save-grade-scheme'),
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: _primaryColor,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(widget.spanish ? 'Guardar' : 'Save'),
          ),
        ),
      ],
    );
  }

  Widget _iconBox(IconData icon, bool dark, {required bool active}) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: active
            ? _primaryColor.withValues(alpha: dark ? 0.22 : 0.11)
            : (dark ? const Color(0xFF29313D) : const Color(0xFFF3F4F7)),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(
        icon,
        color: active
            ? _primaryColor
            : (dark ? const Color(0xFF9BA4B1) : const Color(0xFF6B7280)),
        size: 22,
      ),
    );
  }

  Widget _sectionLabel(String value) {
    return Text(
      value,
      style: const TextStyle(
        color: _primaryColor,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1,
      ),
    );
  }

  BoxDecoration _sheetDecoration(bool dark) {
    return BoxDecoration(
      color: dark ? const Color(0xFF191F29) : const Color(0xFFFDFDFE),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      border: Border(
        top: BorderSide(
          color: dark ? const Color(0xFF303844) : const Color(0xFFE7EAF0),
        ),
      ),
    );
  }

  Widget _dragHandle(bool dark) {
    return Container(
      width: 42,
      height: 4,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF48505E) : const Color(0xFFD5D9E0),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
