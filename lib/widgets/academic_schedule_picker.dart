import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/asignatura.dart';
import '../services/time_format_service.dart';

int academicWeekday(DiaSemana day) => switch (day) {
  DiaSemana.lunes => DateTime.monday,
  DiaSemana.martes => DateTime.tuesday,
  DiaSemana.miercoles => DateTime.wednesday,
  DiaSemana.jueves => DateTime.thursday,
  DiaSemana.viernes => DateTime.friday,
  DiaSemana.sabado => DateTime.saturday,
};

DateTime academicDateOnly(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

DateTime suggestAcademicDateForDay(
  DateTime selectedDate,
  DiaSemana day, {
  DateTime? notBefore,
}) {
  DateTime base = academicDateOnly(selectedDate);
  if (notBefore != null) {
    final DateTime minimum = academicDateOnly(notBefore);
    if (base.isBefore(minimum)) base = minimum;
  }
  final int daysToAdd = (academicWeekday(day) - base.weekday + 7) % 7;
  return base.add(Duration(days: daysToAdd));
}

bool academicDateMatchesBlock(DateTime date, BloqueHorario block) {
  return date.weekday == academicWeekday(block.dia);
}

bool academicDateIsSelectable(
  DateTime date,
  BloqueHorario block, {
  required DateTime notBefore,
}) {
  return !academicDateOnly(date).isBefore(academicDateOnly(notBefore)) &&
      academicDateMatchesBlock(date, block);
}

TimeOfDay? parseAcademicStoredTime(String? value) {
  final String clean = value?.trim() ?? '';
  final List<String> parts = clean.split(':');
  if (parts.length != 2) return null;
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

List<BloqueHorario> validAcademicBlocks(Asignatura? subject) {
  if (subject == null) return const [];
  return subject.horario
      .where((block) => parseAcademicStoredTime(block.horaInicio) != null)
      .toList(growable: false);
}

String academicDayName(DiaSemana day, {required bool spanish}) {
  return switch (day) {
    DiaSemana.lunes => spanish ? 'Lunes' : 'Monday',
    DiaSemana.martes => spanish ? 'Martes' : 'Tuesday',
    DiaSemana.miercoles => spanish ? 'Miércoles' : 'Wednesday',
    DiaSemana.jueves => spanish ? 'Jueves' : 'Thursday',
    DiaSemana.viernes => spanish ? 'Viernes' : 'Friday',
    DiaSemana.sabado => spanish ? 'Sábado' : 'Saturday',
  };
}

String academicBlockDescription(
  BuildContext context,
  BloqueHorario block, {
  Asignatura? subject,
}) {
  final TimeFormatService timeFormatService = TimeFormatService.instance;
  final String start = timeFormatService.formatStoredTime(
    context,
    block.horaInicio,
  );
  final String end = timeFormatService.formatStoredTime(context, block.horaFin);
  final String room = block.sala?.trim().isNotEmpty == true
      ? block.sala!.trim()
      : (subject?.sala?.trim() ?? '');
  return room.isEmpty ? '$start – $end' : '$start – $end · $room';
}

Future<BloqueHorario?> showAcademicBlockPicker({
  required BuildContext context,
  required Asignatura subject,
  required List<BloqueHorario> blocks,
  required BloqueHorario? selectedBlock,
  required bool spanish,
  required Color accentColor,
  required String keyPrefix,
}) {
  return showModalBottomSheet<BloqueHorario>(
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
                color: dark ? const Color(0xFF4B4B53) : const Color(0xFFD5D9E0),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        spanish
                            ? 'Horario de la asignatura'
                            : 'Subject schedule',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subject.nombre,
                        style: TextStyle(
                          color: accentColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: blocks.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, index) {
                  final BloqueHorario block = blocks[index];
                  final bool active = identical(block, selectedBlock);
                  return InkWell(
                    key: ValueKey('$keyPrefix-class-block-$index'),
                    borderRadius: BorderRadius.circular(15),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(sheetContext).pop(block);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: active
                            ? (dark
                                  ? const Color(0xFF292936)
                                  : accentColor.withValues(alpha: 0.1))
                            : (dark
                                  ? const Color(0xFF222229)
                                  : const Color(0xFFFAFBFC)),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: active
                              ? accentColor
                              : (dark
                                    ? const Color(0xFF34343C)
                                    : const Color(0xFFE7EAF0)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            color: accentColor,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  academicDayName(block.dia, spanish: spanish),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  academicBlockDescription(
                                    sheetContext,
                                    block,
                                    subject: subject,
                                  ),
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
                          if (active)
                            Icon(
                              Icons.check_circle_rounded,
                              color: accentColor,
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
}

class AcademicScheduleModePanel extends StatelessWidget {
  const AcademicScheduleModePanel({
    required this.keyPrefix,
    required this.spanish,
    required this.accentColor,
    required this.subject,
    required this.blocks,
    required this.usingSchedule,
    required this.selectedBlock,
    required this.onManualSelected,
    required this.onScheduleSelected,
    required this.onChangeBlock,
    super.key,
  });

  final String keyPrefix;
  final bool spanish;
  final Color accentColor;
  final Asignatura? subject;
  final List<BloqueHorario> blocks;
  final bool usingSchedule;
  final BloqueHorario? selectedBlock;
  final VoidCallback onManualSelected;
  final VoidCallback onScheduleSelected;
  final VoidCallback onChangeBlock;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final bool hasSubject = subject != null;
    final bool hasBlocks = blocks.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _modeOption(
                key: ValueKey('$keyPrefix-schedule-manual'),
                dark: dark,
                active: !usingSchedule,
                enabled: true,
                icon: Icons.edit_calendar_outlined,
                label: 'Manual',
                onTap: onManualSelected,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _modeOption(
                key: ValueKey('$keyPrefix-schedule-class'),
                dark: dark,
                active: usingSchedule,
                enabled: hasBlocks,
                icon: Icons.schedule_rounded,
                label: spanish ? 'Usar horario' : 'Use schedule',
                onTap: onScheduleSelected,
              ),
            ),
          ],
        ),
        if (!hasSubject) ...[
          const SizedBox(height: 8),
          Text(
            spanish
                ? 'Selecciona una asignatura para consultar sus bloques de clase.'
                : 'Select a subject to view its class blocks.',
            style: TextStyle(
              color: dark ? const Color(0xFF8993A2) : const Color(0xFF6B7280),
              fontSize: 11.5,
            ),
          ),
        ] else if (!hasBlocks) ...[
          const SizedBox(height: 8),
          Text(
            spanish
                ? 'Esta asignatura no tiene horarios registrados. Puedes ingresar la fecha y hora manualmente.'
                : 'This subject has no registered schedule. Enter the date and time manually.',
            style: TextStyle(
              color: dark ? const Color(0xFF8993A2) : const Color(0xFF6B7280),
              fontSize: 11.5,
            ),
          ),
        ] else if (usingSchedule && selectedBlock != null) ...[
          const SizedBox(height: 9),
          Container(
            key: ValueKey('$keyPrefix-selected-class-block'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: dark ? 0.16 : 0.08),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: accentColor.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  color: accentColor,
                  size: 20,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '${academicDayName(selectedBlock!.dia, spanish: spanish)} · '
                    '${academicBlockDescription(context, selectedBlock!, subject: subject)}',
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onChangeBlock,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(spanish ? 'Cambiar' : 'Change'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _modeOption({
    required Key key,
    required bool dark,
    required bool active,
    required bool enabled,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(13),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: active
              ? accentColor.withValues(alpha: dark ? 0.18 : 0.1)
              : (dark ? const Color(0xFF222229) : const Color(0xFFFAFBFC)),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: active
                ? accentColor
                : (dark ? const Color(0xFF34343C) : const Color(0xFFE2E6ED)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 19,
              color: enabled
                  ? (active
                        ? accentColor
                        : (dark
                              ? const Color(0xFFC4CAD4)
                              : const Color(0xFF6B7280)))
                  : (dark ? const Color(0xFF616976) : const Color(0xFFB3B8C2)),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled
                      ? (active
                            ? accentColor
                            : (dark
                                  ? const Color(0xFFF1F4F8)
                                  : const Color(0xFF374151)))
                      : (dark
                            ? const Color(0xFF616976)
                            : const Color(0xFFB3B8C2)),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
