import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/asignatura.dart';
import '../../../models/tarea.dart';
import '../../../services/time_format_service.dart';

class TaskEditResult {
  const TaskEditResult({
    required this.title,
    required this.priority,
    this.description,
    this.subjectId,
    this.dueDate,
    this.dueTime,
  });

  final String title;
  final String? description;
  final String? subjectId;
  final PrioridadTarea priority;
  final DateTime? dueDate;

  /// Siempre HH:mm internamente.
  final String? dueTime;
}

Future<TaskEditResult?> showTaskEditSheet({
  required BuildContext context,
  required List<Asignatura> subjects,
  required bool spanish,
  Tarea? task,
  DateTime? initialDueDate,
}) {
  return showModalBottomSheet<TaskEditResult>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    builder: (_) {
      return _TaskEditSheet(
        subjects: subjects,
        spanish: spanish,
        task: task,
        initialDueDate: initialDueDate,
      );
    },
  );
}

class _TaskEditSheet extends StatefulWidget {
  const _TaskEditSheet({
    required this.subjects,
    required this.spanish,
    this.task,
    this.initialDueDate,
  });

  final List<Asignatura> subjects;
  final bool spanish;
  final Tarea? task;
  final DateTime? initialDueDate;

  @override
  State<_TaskEditSheet> createState() => _TaskEditSheetState();
}

class _TaskEditSheetState extends State<_TaskEditSheet> {
  static const Color _primaryColor = Color(0xFF5B5FEF);

  static const String _generalSubject = '__general__';

  final TimeFormatService _timeFormatService = TimeFormatService.instance;

  late final TextEditingController _titleController;

  late final TextEditingController _descriptionController;

  late PrioridadTarea _priority;

  String? _subjectId;

  DateTime? _dueDate;
  TimeOfDay? _dueTime;

  bool _showErrors = false;

  bool get _editing => widget.task != null;

  @override
  void initState() {
    super.initState();

    final Tarea? task = widget.task;

    _titleController = TextEditingController(text: task?.titulo ?? '');

    _descriptionController = TextEditingController(
      text: task?.descripcion ?? '',
    );

    _priority = task?.prioridad ?? PrioridadTarea.media;

    _subjectId = task?.asignaturaId;

    final DateTime? initialDate = task?.fechaEntrega ?? widget.initialDueDate;

    _dueDate = initialDate == null
        ? null
        : DateTime(initialDate.year, initialDate.month, initialDate.day);

    _dueTime = _parseStoredTime(task?.horaEntrega);
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

    super.dispose();
  }

  // =========================================================
  // HELPERS
  // =========================================================

  String _cleanNullable(String value) {
    return value.trim();
  }

  String _formatStoredTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  String _displayTime(TimeOfDay time) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      time,
      alwaysUse24HourFormat: _timeFormatService.use24HourFormat(context),
    );
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

  String _priorityName(PrioridadTarea priority) {
    switch (priority) {
      case PrioridadTarea.baja:
        return widget.spanish ? 'Baja' : 'Low';

      case PrioridadTarea.media:
        return widget.spanish ? 'Media' : 'Medium';

      case PrioridadTarea.alta:
        return widget.spanish ? 'Alta' : 'High';
    }
  }

  Color _priorityColor(PrioridadTarea priority) {
    switch (priority) {
      case PrioridadTarea.baja:
        return const Color(0xFF059669);

      case PrioridadTarea.media:
        return const Color(0xFFF59E0B);

      case PrioridadTarea.alta:
        return const Color(0xFFEF4444);
    }
  }

  String _subjectName() {
    final String? id = _subjectId;

    if (id == null) {
      return widget.spanish ? 'Tarea general' : 'General task';
    }

    for (final Asignatura subject in widget.subjects) {
      if (subject.id == id) {
        return subject.nombre;
      }
    }

    return widget.spanish ? 'Tarea general' : 'General task';
  }

  // =========================================================
  // ASIGNATURA
  // =========================================================

  Future<void> _chooseSubject() async {
    HapticFeedback.selectionClick();

    final String? result = await showModalBottomSheet<String>(
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
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    _buildSubjectOption(
                      context: sheetContext,
                      dark: dark,
                      id: _generalSubject,
                      name: widget.spanish ? 'Tarea general' : 'General task',
                      selected: _subjectId == null,
                      icon: Icons.layers_outlined,
                    ),

                    for (final Asignatura subject in widget.subjects) ...[
                      const SizedBox(height: 8),

                      _buildSubjectOption(
                        context: sheetContext,
                        dark: dark,
                        id: subject.id,
                        name: subject.nombre,
                        selected: _subjectId == subject.id,
                        icon: Icons.menu_book_outlined,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _subjectId = result == _generalSubject ? null : result;
    });
  }

  Widget _buildSubjectOption({
    required BuildContext context,
    required bool dark,
    required String id,
    required String name,
    required bool selected,
    required IconData icon,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: () {
        HapticFeedback.selectionClick();

        Navigator.of(context).pop(id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? (dark ? const Color(0xFF292936) : const Color(0xFFEEF0FF))
              : (dark ? const Color(0xFF222229) : const Color(0xFFFAFBFC)),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected
                ? _primaryColor
                : (dark ? const Color(0xFF34343C) : const Color(0xFFE7EAF0)),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: _primaryColor, size: 21),

            const SizedBox(width: 12),

            Expanded(
              child: Text(
                name,
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
                color: _primaryColor,
                size: 21,
              ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // FECHA
  // =========================================================

  Future<void> _chooseDate() async {
    HapticFeedback.selectionClick();

    final DateTime now = DateTime.now();

    final DateTime? result = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
      helpText: widget.spanish ? 'Fecha de entrega' : 'Due date',
      cancelText: widget.spanish ? 'Cancelar' : 'Cancel',
      confirmText: widget.spanish ? 'Aceptar' : 'OK',
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _dueDate = DateTime(result.year, result.month, result.day);
    });
  }

  void _clearDate() {
    HapticFeedback.selectionClick();

    setState(() {
      _dueDate = null;
      _dueTime = null;
    });
  }

  // =========================================================
  // HORA
  // =========================================================

  Future<void> _chooseTime() async {
    if (_dueDate == null) {
      return;
    }

    HapticFeedback.selectionClick();

    final bool use24Hours = _timeFormatService.use24HourFormat(context);

    final TimeOfDay? result = await showTimePicker(
      context: context,
      initialTime: _dueTime ?? const TimeOfDay(hour: 18, minute: 0),
      helpText: widget.spanish ? 'Hora límite' : 'Due time',
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
      _dueTime = result;
    });
  }

  void _clearTime() {
    HapticFeedback.selectionClick();

    setState(() {
      _dueTime = null;
    });
  }

  // =========================================================
  // GUARDAR
  // =========================================================

  void _save() {
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _showErrors = true;
    });

    final String title = _titleController.text.trim();

    if (title.isEmpty) {
      HapticFeedback.mediumImpact();
      return;
    }

    final String description = _cleanNullable(_descriptionController.text);

    HapticFeedback.selectionClick();

    Navigator.of(context).pop(
      TaskEditResult(
        title: title,
        description: description.isEmpty ? null : description,
        subjectId: _subjectId,
        priority: _priority,
        dueDate: _dueDate,
        dueTime: _dueTime == null ? null : _formatStoredTime(_dueTime!),
      ),
    );
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
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
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.spanish ? 'TAREAS' : 'TASKS',
                          style: const TextStyle(
                            color: _primaryColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),

                        const SizedBox(height: 5),

                        Text(
                          _editing
                              ? (widget.spanish ? 'Editar tarea' : 'Edit task')
                              : (widget.spanish ? 'Nueva tarea' : 'New task'),
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
                                    ? 'Actualiza la información de esta tarea.'
                                    : 'Update this task\'s information.')
                              : (widget.spanish
                                    ? 'Organiza una entrega o pendiente académico.'
                                    : 'Organize an academic assignment or pending task.'),
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
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
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
                autofocus: false,
                textInputAction: TextInputAction.next,
                onTapOutside: (_) {
                  FocusManager.instance.primaryFocus?.unfocus();
                },
                onChanged: (_) {
                  if (_showErrors) {
                    setState(() {});
                  }
                },
                decoration: InputDecoration(
                  labelText: widget.spanish ? 'Título *' : 'Title *',
                  hintText: widget.spanish
                      ? 'Ej. Hacer guía de Historia'
                      : 'E.g. Complete History worksheet',
                  prefixIcon: const Icon(
                    Icons.task_alt_outlined,
                    color: _primaryColor,
                  ),
                  errorText: _showErrors && _titleController.text.trim().isEmpty
                      ? (widget.spanish
                            ? 'El título es obligatorio.'
                            : 'Title is required.')
                      : null,
                ),
              ),

              const SizedBox(height: 14),

              _buildSelectorField(
                dark: dark,
                label: widget.spanish ? 'Asignatura' : 'Subject',
                value: _subjectName(),
                icon: Icons.menu_book_outlined,
                onTap: _chooseSubject,
              ),

              const SizedBox(height: 14),

              TextField(
                controller: _descriptionController,
                minLines: 3,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                onTapOutside: (_) {
                  FocusManager.instance.primaryFocus?.unfocus();
                },
                decoration: InputDecoration(
                  labelText: widget.spanish ? 'Descripción' : 'Description',
                  hintText: widget.spanish ? 'Opcional' : 'Optional',
                  alignLabelWithHint: true,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 55),
                    child: Icon(Icons.notes_rounded, color: _primaryColor),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              Text(
                widget.spanish ? 'Prioridad' : 'Priority',
                style: TextStyle(
                  color: dark
                      ? const Color(0xFFC4CAD4)
                      : const Color(0xFF4B5563),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 9),

              Row(
                children: [
                  for (final PrioridadTarea priority
                      in PrioridadTarea.values) ...[
                    Expanded(
                      child: _buildPriorityButton(
                        dark: dark,
                        priority: priority,
                      ),
                    ),

                    if (priority != PrioridadTarea.values.last)
                      const SizedBox(width: 8),
                  ],
                ],
              ),

              const SizedBox(height: 20),

              _buildSelectorField(
                dark: dark,
                label: widget.spanish ? 'Fecha de entrega' : 'Due date',
                value: _dueDate == null
                    ? (widget.spanish ? 'Sin fecha' : 'No date')
                    : _displayDate(_dueDate!),
                icon: Icons.calendar_today_outlined,
                onTap: _chooseDate,
                onClear: _dueDate == null ? null : _clearDate,
              ),

              const SizedBox(height: 14),

              _buildSelectorField(
                dark: dark,
                label: widget.spanish ? 'Hora límite' : 'Due time',
                value: _dueDate == null
                    ? (widget.spanish
                          ? 'Agrega una fecha primero'
                          : 'Add a date first')
                    : _dueTime == null
                    ? (widget.spanish ? 'Sin hora' : 'No time')
                    : _displayTime(_dueTime!),
                icon: Icons.schedule_rounded,
                enabled: _dueDate != null,
                onTap: _chooseTime,
                onClear: _dueTime == null ? null : _clearTime,
              ),

              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 49,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
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
                          backgroundColor: _primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          _editing
                              ? (widget.spanish
                                    ? 'Guardar cambios'
                                    : 'Save changes')
                              : (widget.spanish
                                    ? 'Crear tarea'
                                    : 'Create task'),
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

  Widget _buildPriorityButton({
    required bool dark,
    required PrioridadTarea priority,
  }) {
    final bool selected = _priority == priority;

    final Color accent = _priorityColor(priority);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();

        setState(() {
          _priority = priority;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        height: 45,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: dark ? 0.20 : 0.11)
              : (dark ? const Color(0xFF222229) : const Color(0xFFFAFBFC)),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected
                ? accent
                : (dark ? const Color(0xFF34343C) : const Color(0xFFE2E6ED)),
          ),
        ),
        child: Text(
          _priorityName(priority),
          style: TextStyle(
            color: selected
                ? accent
                : (dark ? const Color(0xFFF1F4F8) : const Color(0xFF374151)),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectorField({
    required bool dark,
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
    VoidCallback? onClear,
    bool enabled = true,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF222229) : const Color(0xFFFAFBFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: dark ? const Color(0xFF34343C) : const Color(0xFFE2E6ED),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: enabled ? _primaryColor : const Color(0xFF7F899A),
              size: 21,
            ),

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
                      color: enabled
                          ? (dark
                                ? const Color(0xFFF8FAFC)
                                : const Color(0xFF1F2937))
                          : const Color(0xFF7F899A),
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
                color: _primaryColor,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
