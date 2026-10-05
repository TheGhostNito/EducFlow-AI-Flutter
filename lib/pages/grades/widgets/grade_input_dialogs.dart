import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/nota.dart';
import '../../../services/grade_input_interpreter.dart';

typedef GuardarObjetivoNota = Future<void> Function(double value);
typedef GuardarEdicionEvaluacion = Future<void> Function(
  GradeEvaluationEdit value,
);
typedef GuardarConfiguracionNotas = Future<void> Function(
  ConfiguracionNotas value,
);

class GradeEvaluationEdit {
  const GradeEvaluationEdit({required this.nota, required this.ponderacion});

  final double? nota;
  final double? ponderacion;
}

Future<double?> showTargetGradeDialog({
  required BuildContext context,
  required double initialValue,
  required ConfiguracionNotas configuration,
  required bool spanish,
  required GuardarObjetivoNota onSave,
}) {
  return showDialog<double>(
    context: context,
    builder: (_) => _TargetGradeDialog(
      initialValue: initialValue,
      configuration: configuration,
      spanish: spanish,
      onSave: onSave,
    ),
  );
}

Future<GradeEvaluationEdit?> showEvaluationGradeDialog({
  required BuildContext context,
  required String title,
  required double? initialGrade,
  required double? initialWeight,
  required double otherWeight,
  required ConfiguracionNotas configuration,
  required bool spanish,
  bool editWeight = true,
  required GuardarEdicionEvaluacion onSave,
}) {
  return showDialog<GradeEvaluationEdit>(
    context: context,
    builder: (_) => _EvaluationGradeDialog(
      title: title,
      initialGrade: initialGrade,
      initialWeight: initialWeight,
      otherWeight: otherWeight,
      configuration: configuration,
      spanish: spanish,
      editWeight: editWeight,
      onSave: onSave,
    ),
  );
}

Future<ConfiguracionNotas?> showGradeSettingsDialog({
  required BuildContext context,
  required ConfiguracionNotas initial,
  required bool spanish,
  required GuardarConfiguracionNotas onSave,
}) {
  return showDialog<ConfiguracionNotas>(
    context: context,
    builder: (_) => _GradeSettingsDialog(
      initial: initial,
      spanish: spanish,
      onSave: onSave,
    ),
  );
}

class _TargetGradeDialog extends StatefulWidget {
  const _TargetGradeDialog({
    required this.initialValue,
    required this.configuration,
    required this.spanish,
    required this.onSave,
  });

  final double initialValue;
  final ConfiguracionNotas configuration;
  final bool spanish;
  final GuardarObjetivoNota onSave;

  @override
  State<_TargetGradeDialog> createState() => _TargetGradeDialogState();
}

class _TargetGradeDialogState extends State<_TargetGradeDialog> {
  static const _interpreter = GradeInputInterpreter();
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _editableNullableNumber(widget.initialValue, widget.spanish),
    );
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _cancel() {
    if (_saving) return;
    _unfocus();
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    if (_saving) return;
    final interpretation = _interpreter.interpretar(
      _controller.text,
      widget.configuration,
    );
    final value = interpretation.valor;
    if (!interpretation.esValida || value == null) {
      setState(() {
        _error = interpretation.estado == EstadoInterpretacionNota.ambigua
            ? (widget.spanish
                  ? 'La entrada es ambigua. Usa coma o punto decimal.'
                  : 'The entry is ambiguous. Add a decimal separator.')
            : (widget.spanish
                  ? 'Ingresa una nota válida dentro de la escala.'
                  : 'Enter a valid grade within the scale.');
      });
      return;
    }

    _unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(value);
      if (mounted) Navigator.of(context).pop(value);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = widget.spanish
            ? 'No pudimos guardar el objetivo.'
            : 'We could not save the goal.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _unfocus,
        child: AlertDialog(
          title: Text(widget.spanish ? 'Nota objetivo' : 'Target grade'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.spanish
                      ? 'Elige la nota final que quieres alcanzar.'
                      : 'Choose the final grade you want to reach.',
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('grade-goal-input'),
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: !_saving,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  inputFormatters: const [DecimalTextInputFormatter(3)],
                  onTapOutside: (_) => _unfocus(),
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    labelText: widget.spanish ? 'Objetivo' : 'Goal',
                    errorText: _error,
                    helperText:
                        '${_editableNumber(widget.configuration.notaMinima)} – ${_editableNumber(widget.configuration.notaMaxima)}',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : _cancel,
              child: Text(widget.spanish ? 'Cancelar' : 'Cancel'),
            ),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(widget.spanish ? 'Guardar' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EvaluationGradeDialog extends StatefulWidget {
  const _EvaluationGradeDialog({
    required this.title,
    required this.initialGrade,
    required this.initialWeight,
    required this.otherWeight,
    required this.configuration,
    required this.spanish,
    required this.editWeight,
    required this.onSave,
  });

  final String title;
  final double? initialGrade;
  final double? initialWeight;
  final double otherWeight;
  final ConfiguracionNotas configuration;
  final bool spanish;
  final bool editWeight;
  final GuardarEdicionEvaluacion onSave;

  @override
  State<_EvaluationGradeDialog> createState() => _EvaluationGradeDialogState();
}

class _EvaluationGradeDialogState extends State<_EvaluationGradeDialog> {
  static const _interpreter = GradeInputInterpreter();
  late final TextEditingController _gradeController;
  late final TextEditingController _weightController;
  late final FocusNode _gradeFocusNode;
  late final FocusNode _weightFocusNode;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _gradeController = TextEditingController(
      text: _editableNullableNumber(widget.initialGrade, widget.spanish),
    );
    _weightController = TextEditingController(
      text: _editableNullableNumber(widget.initialWeight, false),
    );
    _gradeFocusNode = FocusNode();
    _weightFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _gradeController.dispose();
    _weightController.dispose();
    _gradeFocusNode.dispose();
    _weightFocusNode.dispose();
    super.dispose();
  }

  void _cancel() {
    if (_saving) return;
    _unfocus();
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    if (_saving) return;
    final gradeText = _gradeController.text.trim();
    final weightText = _weightController.text.trim();
    final gradeInterpretation = _interpreter.interpretar(
      gradeText,
      widget.configuration,
    );
    final grade = gradeInterpretation.valor;
    final weight = widget.editWeight
        ? (weightText.isEmpty ? null : _parseDecimal(weightText))
        : widget.initialWeight;

    if (gradeText.isNotEmpty && !gradeInterpretation.esValida) {
      setState(() {
        _error = gradeInterpretation.estado == EstadoInterpretacionNota.ambigua
            ? (widget.spanish
                  ? 'La nota es ambigua. Usa coma o punto decimal.'
                  : 'The grade is ambiguous. Add a decimal separator.')
            : (widget.spanish
                  ? 'La nota debe estar dentro de la escala configurada.'
                  : 'The grade must be within the configured scale.');
      });
      return;
    }
    if (widget.editWeight &&
        weightText.isNotEmpty &&
        (weight == null || !weight.isFinite || weight < 0 || weight > 100)) {
      setState(() {
        _error = widget.spanish
            ? 'La ponderación debe estar entre 0 y 100.'
            : 'The weight must be between 0 and 100.';
      });
      return;
    }
    if (widget.editWeight &&
        weight != null &&
        widget.otherWeight + weight > 100.000001) {
      setState(() {
        _error = widget.spanish
            ? 'La suma de ponderaciones de la asignatura no puede superar 100 %.'
            : 'The subject weight total cannot exceed 100%.';
      });
      return;
    }

    final result = GradeEvaluationEdit(nota: grade, ponderacion: weight);
    _unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(result);
      if (mounted) Navigator.of(context).pop(result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = widget.spanish
            ? 'No pudimos guardar los cambios. Inténtalo nuevamente.'
            : 'We could not save the changes. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _unfocus,
        child: AlertDialog(
          title: Text(widget.title),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const ValueKey('grade-earned-input'),
                    controller: _gradeController,
                    focusNode: _gradeFocusNode,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.next,
                    inputFormatters: const [DecimalTextInputFormatter(3)],
                    onTapOutside: (_) => _unfocus(),
                    onSubmitted: (_) => _weightFocusNode.requestFocus(),
                    decoration: InputDecoration(
                      labelText: widget.spanish
                          ? 'Nota obtenida'
                          : 'Grade earned',
                      hintText: widget.spanish ? 'Pendiente' : 'Pending',
                      helperText: widget.spanish
                          ? 'Déjalo vacío si aún no tienes nota.'
                          : 'Leave empty if it is still pending.',
                    ),
                  ),
                  if (widget.editWeight) ...[
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('grade-weight-input'),
                      controller: _weightController,
                      focusNode: _weightFocusNode,
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.done,
                      inputFormatters: const [DecimalTextInputFormatter(2)],
                      onTapOutside: (_) => _unfocus(),
                      onSubmitted: (_) => _save(),
                      decoration: InputDecoration(
                        labelText: widget.spanish
                            ? 'Ponderación (%)'
                            : 'Weight (%)',
                        helperText: widget.spanish
                            ? 'La suma de la asignatura no puede superar 100 %.'
                            : 'The subject total cannot exceed 100%.',
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : _cancel,
              child: Text(widget.spanish ? 'Cancelar' : 'Cancel'),
            ),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(widget.spanish ? 'Guardar' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradeSettingsDialog extends StatefulWidget {
  const _GradeSettingsDialog({
    required this.initial,
    required this.spanish,
    required this.onSave,
  });

  final ConfiguracionNotas initial;
  final bool spanish;
  final GuardarConfiguracionNotas onSave;

  @override
  State<_GradeSettingsDialog> createState() => _GradeSettingsDialogState();
}

class _GradeSettingsDialogState extends State<_GradeSettingsDialog> {
  late final TextEditingController _minController;
  late final TextEditingController _maxController;
  late final TextEditingController _passController;
  late final FocusNode _minFocusNode;
  late final FocusNode _maxFocusNode;
  late final FocusNode _passFocusNode;
  late int _decimals;
  late PoliticaRedondeoNotas _rounding;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _minController = TextEditingController(
      text: _editableNumber(widget.initial.notaMinima),
    );
    _maxController = TextEditingController(
      text: _editableNumber(widget.initial.notaMaxima),
    );
    _passController = TextEditingController(
      text: _editableNumber(widget.initial.notaAprobacion),
    );
    _minFocusNode = FocusNode();
    _maxFocusNode = FocusNode();
    _passFocusNode = FocusNode();
    _decimals = widget.initial.decimales;
    _rounding = widget.initial.politicaRedondeo;
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    _passController.dispose();
    _minFocusNode.dispose();
    _maxFocusNode.dispose();
    _passFocusNode.dispose();
    super.dispose();
  }

  void _cancel() {
    if (_saving) return;
    _unfocus();
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    if (_saving) return;
    final configuration = ConfiguracionNotas(
      notaMinima: _parseDecimal(_minController.text) ?? double.nan,
      notaMaxima: _parseDecimal(_maxController.text) ?? double.nan,
      notaAprobacion: _parseDecimal(_passController.text) ?? double.nan,
      decimales: _decimals,
      politicaRedondeo: _rounding,
    );
    if (!configuration.esValida) {
      setState(() {
        _error = widget.spanish
            ? 'Revisa la escala y la nota de aprobación.'
            : 'Check the scale and passing grade.';
      });
      return;
    }

    _unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(configuration);
      if (mounted) Navigator.of(context).pop(configuration);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = widget.spanish
            ? 'No pudimos guardar la configuración.'
            : 'We could not save the settings.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _unfocus,
        child: AlertDialog(
          title: Text(widget.spanish ? 'Configurar escala' : 'Configure scale'),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('grade-settings-min-input'),
                          controller: _minController,
                          focusNode: _minFocusNode,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textInputAction: TextInputAction.next,
                          inputFormatters: const [DecimalTextInputFormatter(3)],
                          onTapOutside: (_) => _unfocus(),
                          onSubmitted: (_) => _maxFocusNode.requestFocus(),
                          decoration: InputDecoration(
                            labelText: widget.spanish
                                ? 'Nota mínima'
                                : 'Minimum grade',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('grade-settings-max-input'),
                          controller: _maxController,
                          focusNode: _maxFocusNode,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textInputAction: TextInputAction.next,
                          inputFormatters: const [DecimalTextInputFormatter(3)],
                          onTapOutside: (_) => _unfocus(),
                          onSubmitted: (_) => _passFocusNode.requestFocus(),
                          decoration: InputDecoration(
                            labelText: widget.spanish
                                ? 'Nota máxima'
                                : 'Maximum grade',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('grade-settings-pass-input'),
                    controller: _passController,
                    focusNode: _passFocusNode,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.done,
                    inputFormatters: const [DecimalTextInputFormatter(3)],
                    onTapOutside: (_) => _unfocus(),
                    onSubmitted: (_) => _unfocus(),
                    decoration: InputDecoration(
                      labelText: widget.spanish
                          ? 'Nota de aprobación'
                          : 'Passing grade',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _decimals,
                    decoration: InputDecoration(
                      labelText: widget.spanish
                          ? 'Decimales'
                          : 'Decimal places',
                    ),
                    items: [0, 1, 2, 3]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text('$value'),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _decimals = value ?? 1),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<PoliticaRedondeoNotas>(
                    initialValue: _rounding,
                    decoration: InputDecoration(
                      labelText: widget.spanish ? 'Redondeo' : 'Rounding',
                    ),
                    items: PoliticaRedondeoNotas.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(
                              value == PoliticaRedondeoNotas.masCercano
                                  ? (widget.spanish
                                        ? 'Al más cercano'
                                        : 'Nearest')
                                  : (widget.spanish ? 'Truncar' : 'Truncate'),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) => setState(
                            () => _rounding =
                                value ?? PoliticaRedondeoNotas.masCercano,
                          ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : _cancel,
              child: Text(widget.spanish ? 'Cancelar' : 'Cancel'),
            ),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(widget.spanish ? 'Guardar' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class DecimalTextInputFormatter extends TextInputFormatter {
  const DecimalTextInputFormatter(this.maxDecimalPlaces);

  final int maxDecimalPlaces;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final pattern = RegExp('^\\d*(?:[.,]\\d{0,$maxDecimalPlaces})?\$');
    return pattern.hasMatch(newValue.text) ? newValue : oldValue;
  }
}

void _unfocus() {
  FocusManager.instance.primaryFocus?.unfocus();
}

double? _parseDecimal(String value) {
  return double.tryParse(value.trim().replaceAll(',', '.'));
}

String _editableNullableNumber(double? value, bool spanish) {
  if (value == null) return '';
  final formatted = _editableNumber(value);
  return spanish ? formatted.replaceAll('.', ',') : formatted;
}

String _editableNumber(double value) {
  if (value % 1 == 0) return value.toStringAsFixed(0);
  return value.toString();
}
