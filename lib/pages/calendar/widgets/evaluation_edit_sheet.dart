import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/asignatura.dart';
import '../../../models/evaluacion.dart';
import '../../../services/time_format_service.dart';

class EvaluationEditResult {
  const EvaluationEditResult({
    required this.title,
    required this.subjectId,
    required this.type,
    required this.date,
    this.description,
    this.time,
    this.weight,
  });

  final String title;
  final String subjectId;
  final TipoEvaluacion type;
  final DateTime date;

  /// Siempre HH:mm internamente.
  final String? time;

  final String? description;

  /// Porcentaje entre 0 y 100.
  final double? weight;
}

Future<EvaluationEditResult?> showEvaluationEditSheet({
  required BuildContext context,
  required List<Asignatura> subjects,
  required bool spanish,
  required DateTime initialDate,
  Evaluacion? evaluation,
}) {
  return showModalBottomSheet<EvaluationEditResult>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    builder: (_) {
      return _EvaluationEditSheet(
        subjects: subjects,
        spanish: spanish,
        initialDate: initialDate,
        evaluation: evaluation,
      );
    },
  );
}

class _EvaluationEditSheet extends StatefulWidget {
  const _EvaluationEditSheet({
    required this.subjects,
    required this.spanish,
    required this.initialDate,
    this.evaluation,
  });

  final List<Asignatura> subjects;
  final bool spanish;
  final DateTime initialDate;
  final Evaluacion? evaluation;

  @override
  State<_EvaluationEditSheet> createState() => _EvaluationEditSheetState();
}

class _EvaluationEditSheetState extends State<_EvaluationEditSheet> {
  static const Color _evaluationColor = Color(0xFF8B5CF6);

  final TimeFormatService _timeFormatService = TimeFormatService.instance;

  bool get _editing => widget.evaluation != null;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();

  String? _subjectId;
  TipoEvaluacion _type = TipoEvaluacion.prueba;

  late DateTime _date;
  TimeOfDay? _time;

  bool _showErrors = false;

  @override
  void initState() {
    super.initState();

    final Evaluacion? evaluation = widget.evaluation;
    final DateTime baseDate = evaluation?.fecha ?? widget.initialDate;

    _date = DateTime(baseDate.year, baseDate.month, baseDate.day);

    _titleController.text = evaluation?.titulo ?? '';
    _descriptionController.text = evaluation?.descripcion ?? '';
    _subjectId = evaluation?.asignaturaId;
    _type = evaluation?.tipo ?? TipoEvaluacion.prueba;
    _time = _parseStoredTime(evaluation?.hora);

    final double? weight = evaluation?.ponderacion;

    if (weight != null) {
      _weightController.text = weight % 1 == 0
          ? weight.toStringAsFixed(0)
          : weight.toStringAsFixed(1);
    }
  }

  TimeOfDay? _parseStoredTime(String? value) {
    final String clean = value?.trim() ?? '';

    if (clean.isEmpty) {
      return null;
    }

    final List<String> parts = clean.split(':');

    if (parts.length != 2) {
      return null;
    }

    final int? hour = int.tryParse(parts[0]);
    final int? minute = int.tryParse(parts[1]);

    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }

    return TimeOfDay(hour: hour, minute: minute);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _weightController.dispose();

    super.dispose();
  }

  String _typeName(TipoEvaluacion type) {
    if (widget.spanish) {
      switch (type) {
        case TipoEvaluacion.prueba:
          return 'Prueba';
        case TipoEvaluacion.examen:
          return 'Examen';
        case TipoEvaluacion.control:
          return 'Control';
        case TipoEvaluacion.quiz:
          return 'Quiz';
        case TipoEvaluacion.presentacion:
          return 'Presentación';
        case TipoEvaluacion.otro:
          return 'Otro';
      }
    }

    switch (type) {
      case TipoEvaluacion.prueba:
        return 'Test';
      case TipoEvaluacion.examen:
        return 'Exam';
      case TipoEvaluacion.control:
        return 'Assessment';
      case TipoEvaluacion.quiz:
        return 'Quiz';
      case TipoEvaluacion.presentacion:
        return 'Presentation';
      case TipoEvaluacion.otro:
        return 'Other';
    }
  }

  String _subjectName() {
    final String? id = _subjectId;

    if (id == null) {
      return widget.spanish ? 'Seleccionar asignatura' : 'Select subject';
    }

    for (final Asignatura subject in widget.subjects) {
      if (subject.id == id) {
        return subject.nombre;
      }
    }

    return widget.spanish ? 'Seleccionar asignatura' : 'Select subject';
  }

  String _displayDate(DateTime date) {
    if (widget.spanish) {
      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year}';
    }

    return '${date.month.toString().padLeft(2, '0')}/'
        '${date.day.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _displayTime(TimeOfDay time) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      time,
      alwaysUse24HourFormat: _timeFormatService.use24HourFormat(context),
    );
  }

  String _storedTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _chooseSubject() async {
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
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF18181D) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: dark ? const Color(0xFF303038) : const Color(0xFFE7EAF0),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xFF4B4B53)
                      : const Color(0xFFD5D9E0),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.spanish ? 'Asignatura' : 'Subject',
                      style: TextStyle(
                        color: dark
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF111827),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.subjects.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final Asignatura subject = widget.subjects[index];
                    final bool selected = subject.id == _subjectId;

                    return InkWell(
                      borderRadius: BorderRadius.circular(15),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.of(sheetContext).pop(subject.id);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: selected
                              ? (dark
                                    ? const Color(0xFF292936)
                                    : const Color(0xFFF3EEFF))
                              : (dark
                                    ? const Color(0xFF222229)
                                    : const Color(0xFFFAFBFC)),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: selected
                                ? _evaluationColor
                                : (dark
                                      ? const Color(0xFF34343C)
                                      : const Color(0xFFE7EAF0)),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.menu_book_outlined,
                              color: _evaluationColor,
                              size: 21,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                subject.nombre,
                                style: TextStyle(
                                  color: dark
                                      ? const Color(0xFFF8FAFC)
                                      : const Color(0xFF1F2937),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (selected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: _evaluationColor,
                                size: 21,
                              ),
                          ],
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

    if (!mounted || selected == null) {
      return;
    }

    setState(() {
      _subjectId = selected;
    });
  }

  Future<void> _chooseDate() async {
    HapticFeedback.selectionClick();

    final DateTime? result = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 10),
      helpText: widget.spanish ? 'Fecha de evaluación' : 'Evaluation date',
      cancelText: widget.spanish ? 'Cancelar' : 'Cancel',
      confirmText: widget.spanish ? 'Aceptar' : 'OK',
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _date = DateTime(result.year, result.month, result.day);
    });
  }

  Future<void> _chooseTime() async {
    HapticFeedback.selectionClick();

    final bool use24Hours = _timeFormatService.use24HourFormat(context);

    final TimeOfDay? result = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 9, minute: 0),
      helpText: widget.spanish ? 'Hora de evaluación' : 'Evaluation time',
      cancelText: widget.spanish ? 'Cancelar' : 'Cancel',
      confirmText: widget.spanish ? 'Aceptar' : 'OK',
      builder: (pickerContext, child) {
        return MediaQuery(
          data: MediaQuery.of(pickerContext)
              .copyWith(alwaysUse24HourFormat: use24Hours),
          child: child!,
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _time = result;
    });
  }

  double? _parseWeight() {
    final String raw = _weightController.text.trim().replaceAll(',', '.');

    if (raw.isEmpty) {
      return null;
    }

    return double.tryParse(raw);
  }

  void _save() {
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _showErrors = true;
    });

    final String title = _titleController.text.trim();
    final String? subjectId = _subjectId;
    final double? weight = _parseWeight();

    final bool invalidWeight =
        _weightController.text.trim().isNotEmpty &&
        (weight == null || weight < 0 || weight > 100);

    if (title.isEmpty || subjectId == null || invalidWeight) {
      HapticFeedback.mediumImpact();
      return;
    }

    final String description = _descriptionController.text.trim();

    Navigator.of(context).pop(
      EvaluationEditResult(
        title: title,
        subjectId: subjectId,
        type: _type,
        date: _date,
        description: description.isEmpty ? null : description,
        time: _time == null ? null : _storedTime(_time!),
        weight: weight,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    final double? parsedWeight = _parseWeight();
    final bool weightInvalid =
        _showErrors &&
        _weightController.text.trim().isNotEmpty &&
        (parsedWeight == null || parsedWeight < 0 || parsedWeight > 100);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.94,
        ),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF18181D) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(
              color: dark ? const Color(0xFF303038) : const Color(0xFFE7EAF0),
            ),
          ),
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: dark
                        ? const Color(0xFF4B4B53)
                        : const Color(0xFFD5D9E0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'EVALUACIONES',
                          style: TextStyle(
                            color: _evaluationColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _editing
                              ? (widget.spanish
                                    ? 'Editar evaluación'
                                    : 'Edit evaluation')
                              : (widget.spanish
                                    ? 'Nueva evaluación'
                                    : 'New evaluation'),
                          style: TextStyle(
                            color: dark
                                ? const Color(0xFFF8FAFC)
                                : const Color(0xFF111827),
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _editing
                              ? (widget.spanish
                                    ? 'Actualiza la información de esta evaluación.'
                                    : 'Update this evaluation.')
                              : (widget.spanish
                                    ? 'Registra una prueba, examen u otra evaluación académica.'
                                    : 'Add a test, exam or other academic evaluation.'),
                          style: TextStyle(
                            color: dark
                                ? const Color(0xFFA9B1BF)
                                : const Color(0xFF6B7280),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      backgroundColor: dark
                          ? const Color(0xFF24242A)
                          : const Color(0xFFF3F4F7),
                    ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              TextField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                onChanged: (_) {
                  if (_showErrors) {
                    setState(() {});
                  }
                },
                onTapOutside: (_) {
                  FocusManager.instance.primaryFocus?.unfocus();
                },
                decoration: InputDecoration(
                  labelText: widget.spanish ? 'Título *' : 'Title *',
                  hintText: widget.spanish
                      ? 'Ej. Prueba de ecuaciones'
                      : 'E.g. Algebra test',
                  prefixIcon: const Icon(
                    Icons.school_outlined,
                    color: _evaluationColor,
                  ),
                  errorText: _showErrors && _titleController.text.trim().isEmpty
                      ? (widget.spanish
                            ? 'El título es obligatorio.'
                            : 'Title is required.')
                      : null,
                ),
              ),
              const SizedBox(height: 14),
              _selectorField(
                dark: dark,
                label: widget.spanish ? 'Asignatura *' : 'Subject *',
                value: _subjectName(),
                icon: Icons.menu_book_outlined,
                onTap: _chooseSubject,
                error: _showErrors && _subjectId == null,
              ),
              if (_showErrors && _subjectId == null) ...[
                const SizedBox(height: 6),
                Text(
                  widget.spanish
                      ? 'Selecciona una asignatura.'
                      : 'Select a subject.',
                  style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Text(
                widget.spanish ? 'Tipo de evaluación' : 'Evaluation type',
                style: TextStyle(
                  color: dark
                      ? const Color(0xFFC4CAD4)
                      : const Color(0xFF4B5563),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 9),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final TipoEvaluacion type in TipoEvaluacion.values)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _type = type;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: _type == type
                              ? _evaluationColor.withValues(
                                  alpha: dark ? 0.20 : 0.11,
                                )
                              : (dark
                                    ? const Color(0xFF222229)
                                    : const Color(0xFFFAFBFC)),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _type == type
                                ? _evaluationColor
                                : (dark
                                      ? const Color(0xFF34343C)
                                      : const Color(0xFFE2E6ED)),
                          ),
                        ),
                        child: Text(
                          _typeName(type),
                          style: TextStyle(
                            color: _type == type
                                ? _evaluationColor
                                : (dark
                                      ? const Color(0xFFF1F4F8)
                                      : const Color(0xFF374151)),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _descriptionController,
                minLines: 3,
                maxLines: 5,
                onTapOutside: (_) {
                  FocusManager.instance.primaryFocus?.unfocus();
                },
                decoration: InputDecoration(
                  labelText: widget.spanish ? 'Descripción' : 'Description',
                  hintText: widget.spanish ? 'Opcional' : 'Optional',
                  alignLabelWithHint: true,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 55),
                    child: Icon(Icons.notes_rounded, color: _evaluationColor),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _selectorField(
                dark: dark,
                label: widget.spanish ? 'Fecha' : 'Date',
                value: _displayDate(_date),
                icon: Icons.calendar_today_outlined,
                onTap: _chooseDate,
              ),
              const SizedBox(height: 14),
              _selectorField(
                dark: dark,
                label: widget.spanish ? 'Hora' : 'Time',
                value: _time == null
                    ? (widget.spanish ? 'Sin hora' : 'No time')
                    : _displayTime(_time!),
                icon: Icons.schedule_rounded,
                onTap: _chooseTime,
                onClear: _time == null
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _time = null;
                        });
                      },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _weightController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                onChanged: (_) {
                  if (_showErrors) {
                    setState(() {});
                  }
                },
                onTapOutside: (_) {
                  FocusManager.instance.primaryFocus?.unfocus();
                },
                decoration: InputDecoration(
                  labelText: widget.spanish ? 'Ponderación (%)' : 'Weight (%)',
                  hintText: widget.spanish ? 'Opcional' : 'Optional',
                  prefixIcon: const Icon(
                    Icons.percent_rounded,
                    color: _evaluationColor,
                  ),
                  errorText: weightInvalid
                      ? (widget.spanish
                            ? 'Ingresa un porcentaje entre 0 y 100.'
                            : 'Enter a percentage between 0 and 100.')
                      : null,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 49,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(widget.spanish ? 'Cancelar' : 'Cancel'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 49,
                      child: FilledButton(
                        onPressed: _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: _evaluationColor,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          _editing
                              ? (widget.spanish
                                    ? 'Guardar cambios'
                                    : 'Save changes')
                              : (widget.spanish
                                    ? 'Crear evaluación'
                                    : 'Create evaluation'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectorField({
    required bool dark,
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
    VoidCallback? onClear,
    bool error = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF222229) : const Color(0xFFFAFBFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: error
                ? const Color(0xFFEF4444)
                : (dark ? const Color(0xFF34343C) : const Color(0xFFE2E6ED)),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: _evaluationColor, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: dark
                          ? const Color(0xFF8993A2)
                          : const Color(0xFF6B7280),
                      fontSize: 10.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: dark
                          ? const Color(0xFFF8FAFC)
                          : const Color(0xFF1F2937),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (onClear != null)
              IconButton(
                onPressed: onClear,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 18),
              )
            else
              const Icon(
                Icons.chevron_right_rounded,
                color: _evaluationColor,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
