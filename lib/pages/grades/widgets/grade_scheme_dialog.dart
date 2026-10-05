import 'package:flutter/material.dart';

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
  return showDialog<ConfiguracionCalculoAsignatura>(
    context: context,
    builder: (_) => _GradeSchemeDialog(
      initial: initial,
      evaluaciones: evaluaciones,
      spanish: spanish,
      onSave: onSave,
    ),
  );
}

class _GradeSchemeDialog extends StatefulWidget {
  const _GradeSchemeDialog({
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
  State<_GradeSchemeDialog> createState() => _GradeSchemeDialogState();
}

class _GradeSchemeDialogState extends State<_GradeSchemeDialog> {
  late EsquemaCalculoNotas _scheme;
  late String? _examId;
  late final TextEditingController _presentationController;
  late final TextEditingController _examController;
  bool _saving = false;
  String? _error;

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

  void _changeScheme(EsquemaCalculoNotas? value) {
    if (value == null) return;
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

  Future<void> _save() async {
    final presentation = double.tryParse(
      _presentationController.text.replaceAll(',', '.'),
    );
    final exam = double.tryParse(_examController.text.replaceAll(',', '.'));
    final result = ConfiguracionCalculoAsignatura(
      asignaturaId: widget.initial.asignaturaId,
      esquema: _scheme,
      pesoPresentacion: presentation ?? double.nan,
      pesoExamen: exam ?? double.nan,
      evaluacionExamenId: _scheme == EsquemaCalculoNotas.presentacionExamen
          ? _examId
          : null,
    );
    if (!result.esValida) {
      setState(() {
        _error = widget.spanish
            ? 'Los pesos deben sumar 100 % y debes elegir un examen final.'
            : 'Weights must total 100% and a final exam must be selected.';
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
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(
          widget.spanish ? 'Esquema de cálculo' : 'Calculation scheme',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioGroup<EsquemaCalculoNotas>(
                groupValue: _scheme,
                onChanged: (value) {
                  if (!_saving) _changeScheme(value);
                },
                child: Column(
                  children: [
                    RadioListTile<EsquemaCalculoNotas>(
                      value: EsquemaCalculoNotas.directo,
                      title: Text(widget.spanish ? 'Directo' : 'Direct'),
                      subtitle: Text(
                        widget.spanish
                            ? 'Las evaluaciones forman la nota final.'
                            : 'Assessments build the final grade.',
                      ),
                    ),
                    RadioListTile<EsquemaCalculoNotas>(
                      value: EsquemaCalculoNotas.presentacionExamen,
                      title: Text(
                        widget.spanish
                            ? 'Presentación + examen'
                            : 'Coursework + final exam',
                      ),
                    ),
                  ],
                ),
              ),
              if (_scheme == EsquemaCalculoNotas.presentacionExamen) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const ValueKey('grade-scheme-exam'),
                  initialValue: _examId,
                  decoration: InputDecoration(
                    labelText: widget.spanish ? 'Examen final' : 'Final exam',
                  ),
                  items: widget.evaluaciones
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.titulo),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _examId = value),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('grade-scheme-presentation-weight'),
                        controller: _presentationController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: const [DecimalTextInputFormatter(2)],
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        decoration: InputDecoration(
                          labelText: widget.spanish
                              ? 'Presentación %'
                              : 'Coursework %',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('grade-scheme-exam-weight'),
                        controller: _examController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: const [DecimalTextInputFormatter(2)],
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        decoration: InputDecoration(
                          labelText: widget.spanish ? 'Examen %' : 'Exam %',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.of(context).pop();
                  },
            child: Text(widget.spanish ? 'Cancelar' : 'Cancel'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(widget.spanish ? 'Guardar' : 'Save'),
          ),
        ],
      ),
    );
  }
}
