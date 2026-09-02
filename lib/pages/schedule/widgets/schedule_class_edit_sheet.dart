import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/asignatura.dart';
import '../../../services/time_format_service.dart';

Future<BloqueHorario?> showScheduleClassEditSheet({
  required BuildContext context,
  required BloqueHorario block,
  required bool spanish,
  required bool school,
}) {
  return showModalBottomSheet<BloqueHorario>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    builder: (_) {
      return _ScheduleClassEditSheet(
        block: block,
        spanish: spanish,
        school: school,
      );
    },
  );
}

class _ScheduleClassEditSheet extends StatefulWidget {
  const _ScheduleClassEditSheet({
    required this.block,
    required this.spanish,
    required this.school,
  });

  final BloqueHorario block;
  final bool spanish;
  final bool school;

  @override
  State<_ScheduleClassEditSheet> createState() =>
      _ScheduleClassEditSheetState();
}

class _ScheduleClassEditSheetState extends State<_ScheduleClassEditSheet> {
  static const Color _primaryColor = Color(0xFF5B5FEF);

  final TimeFormatService _timeFormatService = TimeFormatService.instance;

  late DiaSemana _day;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;

  late final TextEditingController _roomController;

  bool _showTimeError = false;

  List<DiaSemana> get _allowedDays {
    final List<DiaSemana> days = [
      DiaSemana.lunes,
      DiaSemana.martes,
      DiaSemana.miercoles,
      DiaSemana.jueves,
      DiaSemana.viernes,
    ];

    if (!widget.school) {
      days.add(DiaSemana.sabado);
    }

    return days;
  }

  @override
  void initState() {
    super.initState();

    _day = widget.block.dia;
    _startTime = _parseTime(widget.block.horaInicio);
    _endTime = _parseTime(widget.block.horaFin);

    _roomController = TextEditingController(text: widget.block.sala ?? '');

    if (!_allowedDays.contains(_day)) {
      _day = DiaSemana.lunes;
    }
  }

  @override
  void dispose() {
    _roomController.dispose();
    super.dispose();
  }

  // =========================================================
  // HORAS
  // =========================================================

  TimeOfDay _parseTime(String value) {
    final List<String> parts = value.split(':');

    if (parts.length != 2) {
      return const TimeOfDay(hour: 8, minute: 0);
    }

    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 8,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  /// Formato utilizado únicamente para mostrar la hora.
  ///
  /// Respeta la preferencia:
  /// - Dispositivo
  /// - 24 horas
  /// - 12 horas
  String _displayTime(TimeOfDay value) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      value,
      alwaysUse24HourFormat: _timeFormatService.use24HourFormat(context),
    );
  }

  /// Formato interno.
  ///
  /// Este NO cambia según las preferencias del usuario.
  /// Firestore continúa recibiendo siempre HH:mm.
  String _formatTime(TimeOfDay value) {
    return '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  int _minutes(TimeOfDay value) {
    return (value.hour * 60) + value.minute;
  }

  bool get _validTime {
    return _minutes(_endTime) > _minutes(_startTime);
  }

  String _dayName(DiaSemana day) {
    if (widget.spanish) {
      switch (day) {
        case DiaSemana.lunes:
          return 'Lun';

        case DiaSemana.martes:
          return 'Mar';

        case DiaSemana.miercoles:
          return 'Mié';

        case DiaSemana.jueves:
          return 'Jue';

        case DiaSemana.viernes:
          return 'Vie';

        case DiaSemana.sabado:
          return 'Sáb';
      }
    }

    switch (day) {
      case DiaSemana.lunes:
        return 'Mon';

      case DiaSemana.martes:
        return 'Tue';

      case DiaSemana.miercoles:
        return 'Wed';

      case DiaSemana.jueves:
        return 'Thu';

      case DiaSemana.viernes:
        return 'Fri';

      case DiaSemana.sabado:
        return 'Sat';
    }
  }

  // =========================================================
  // SELECTORES DE HORA
  // =========================================================

  Future<void> _chooseStartTime() async {
    HapticFeedback.selectionClick();

    final bool usar24Horas = _timeFormatService.use24HourFormat(context);

    final TimeOfDay? result = await showTimePicker(
      context: context,
      initialTime: _startTime,
      helpText: widget.spanish ? 'Hora de inicio' : 'Start time',
      cancelText: widget.spanish ? 'Cancelar' : 'Cancel',
      confirmText: widget.spanish ? 'Aceptar' : 'OK',
      builder: (pickerContext, child) {
        final MediaQueryData mediaQuery = MediaQuery.of(pickerContext);

        return MediaQuery(
          data: mediaQuery.copyWith(alwaysUse24HourFormat: usar24Horas),
          child: child!,
        );
      },
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _startTime = result;
      _showTimeError = false;
    });
  }

  Future<void> _chooseEndTime() async {
    HapticFeedback.selectionClick();

    final bool usar24Horas = _timeFormatService.use24HourFormat(context);

    final TimeOfDay? result = await showTimePicker(
      context: context,
      initialTime: _endTime,
      helpText: widget.spanish ? 'Hora de término' : 'End time',
      cancelText: widget.spanish ? 'Cancelar' : 'Cancel',
      confirmText: widget.spanish ? 'Aceptar' : 'OK',
      builder: (pickerContext, child) {
        final MediaQueryData mediaQuery = MediaQuery.of(pickerContext);

        return MediaQuery(
          data: mediaQuery.copyWith(alwaysUse24HourFormat: usar24Horas),
          child: child!,
        );
      },
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _endTime = result;
      _showTimeError = false;
    });
  }

  // =========================================================
  // GUARDAR
  // =========================================================

  void _save() {
    FocusManager.instance.primaryFocus?.unfocus();

    if (!_validTime) {
      HapticFeedback.mediumImpact();

      setState(() {
        _showTimeError = true;
      });

      return;
    }

    HapticFeedback.selectionClick();

    Navigator.of(context).pop(
      BloqueHorario(
        dia: _day,

        // IMPORTANTE:
        // Siempre se guarda internamente en 24 horas.
        horaInicio: _formatTime(_startTime),
        horaFin: _formatTime(_endTime),

        sala: _roomController.text.trim().isEmpty
            ? null
            : _roomController.text.trim(),
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
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
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
                          widget.spanish ? 'HORARIO' : 'SCHEDULE',
                          style: const TextStyle(
                            color: _primaryColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),

                        const SizedBox(height: 5),

                        Text(
                          widget.spanish ? 'Editar clase' : 'Edit class',
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
                          widget.spanish
                              ? 'Modifica solo este bloque de horario.'
                              : 'Edit only this schedule block.',
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

              Text(
                widget.spanish ? 'Día de la semana' : 'Day of the week',
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
                  for (int index = 0; index < _allowedDays.length; index++) ...[
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();

                          setState(() {
                            _day = _allowedDays[index];
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 170),
                          height: 45,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _day == _allowedDays[index]
                                ? _primaryColor
                                : (dark
                                      ? const Color(0xFF222229)
                                      : const Color(0xFFF7F8FA)),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _day == _allowedDays[index]
                                  ? _primaryColor
                                  : (dark
                                        ? const Color(0xFF34343C)
                                        : const Color(0xFFE2E6ED)),
                            ),
                          ),
                          child: Text(
                            _dayName(_allowedDays[index]),
                            style: TextStyle(
                              color: _day == _allowedDays[index]
                                  ? Colors.white
                                  : (dark
                                        ? const Color(0xFFF1F4F8)
                                        : const Color(0xFF374151)),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),

                    if (index != _allowedDays.length - 1)
                      const SizedBox(width: 6),
                  ],
                ],
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: _TimeField(
                      label: widget.spanish ? 'Hora de inicio' : 'Start time',

                      // Aquí mostramos el formato
                      // elegido por el usuario.
                      value: _displayTime(_startTime),

                      dark: dark,
                      onTap: _chooseStartTime,
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: _TimeField(
                      label: widget.spanish ? 'Hora de término' : 'End time',

                      // Aquí también.
                      value: _displayTime(_endTime),

                      dark: dark,
                      onTap: _chooseEndTime,
                    ),
                  ),
                ],
              ),

              if (_showTimeError) ...[
                const SizedBox(height: 8),

                Text(
                  widget.spanish
                      ? 'La hora de término debe ser posterior a la hora de inicio.'
                      : 'The end time must be later than the start time.',
                  style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],

              const SizedBox(height: 20),

              Text(
                widget.spanish ? 'Sala de este bloque' : 'Room for this block',
                style: TextStyle(
                  color: dark
                      ? const Color(0xFFC4CAD4)
                      : const Color(0xFF4B5563),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 8),

              TextField(
                controller: _roomController,
                textInputAction: TextInputAction.done,
                onTapOutside: (_) {
                  FocusManager.instance.primaryFocus?.unfocus();
                },
                decoration: InputDecoration(
                  hintText: widget.spanish ? 'Opcional' : 'Optional',
                  prefixIcon: const Icon(
                    Icons.meeting_room_outlined,
                    color: _primaryColor,
                  ),
                ),
              ),

              const SizedBox(height: 23),

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
                          widget.spanish ? 'Guardar' : 'Save',
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
}

// ===========================================================
// CAMPO DE HORA
// ===========================================================

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.dark,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool dark;
  final VoidCallback onTap;

  static const Color _primaryColor = Color(0xFF5B5FEF);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF222229) : const Color(0xFFFAFBFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: dark ? const Color(0xFF34343C) : const Color(0xFFE2E6ED),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: dark ? const Color(0xFF8993A2) : const Color(0xFF6B7280),
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 6),

            Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  color: _primaryColor,
                  size: 19,
                ),

                const SizedBox(width: 7),

                Text(
                  value,
                  style: TextStyle(
                    color: dark
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF1F2937),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
