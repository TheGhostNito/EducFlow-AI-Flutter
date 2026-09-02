import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import '../../../models/asignatura.dart';
import '../../../services/time_format_service.dart';

enum CalendarClassDetailAction { edit, viewSubject }

Future<CalendarClassDetailAction?> showCalendarClassDetailSheet({
  required BuildContext context,
  required Asignatura subject,
  required BloqueHorario block,
  required bool spanish,
}) {
  return showModalBottomSheet<CalendarClassDetailAction>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    builder: (_) {
      return _CalendarClassDetailSheet(
        subject: subject,
        block: block,
        spanish: spanish,
      );
    },
  );
}

class _CalendarClassDetailSheet extends StatelessWidget {
  const _CalendarClassDetailSheet({
    required this.subject,
    required this.block,
    required this.spanish,
  });

  final Asignatura subject;
  final BloqueHorario block;
  final bool spanish;

  static const Color _primaryColor = Color(0xFF5B5FEF);
  static const Color _classColor = Color(0xFF3B82F6);

  String _room() {
    final String blockRoom = block.sala?.trim() ?? '';

    if (blockRoom.isNotEmpty) {
      return blockRoom;
    }

    final String subjectRoom = subject.sala?.trim() ?? '';

    if (subjectRoom.isNotEmpty) {
      return subjectRoom;
    }

    return spanish ? 'Sin sala' : 'No room';
  }

  String _teacher() {
    final String teacher = subject.profesor?.trim() ?? '';

    if (teacher.isNotEmpty) {
      return teacher;
    }

    return spanish ? 'Sin profesor' : 'No teacher';
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final TimeFormatService timeService = TimeFormatService.instance;

    final String start = timeService.formatStoredTime(
      context,
      block.horaInicio,
    );

    final String end = timeService.formatStoredTime(context, block.horaFin);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF4B4B53) : const Color(0xFFD5D9E0),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _classColor.withValues(alpha: dark ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Ionicons.bookOutline,
                  color: _classColor,
                  size: 23,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spanish ? 'CLASE' : 'CLASS',
                      style: const TextStyle(
                        color: _classColor,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subject.nombre,
                      style: TextStyle(
                        color: dark
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF111827),
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
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
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF222229) : const Color(0xFFFAFBFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: dark ? const Color(0xFF34343C) : const Color(0xFFE7EAF0),
              ),
            ),
            child: Column(
              children: [
                _infoRow(
                  dark: dark,
                  icon: Icons.schedule_rounded,
                  label: spanish ? 'Horario' : 'Schedule',
                  value: '$start – $end',
                ),
                const SizedBox(height: 14),
                _infoRow(
                  dark: dark,
                  icon: Icons.person_outline_rounded,
                  label: spanish ? 'Profesor' : 'Teacher',
                  value: _teacher(),
                ),
                const SizedBox(height: 14),
                _infoRow(
                  dark: dark,
                  icon: Icons.location_on_outlined,
                  label: spanish ? 'Sala' : 'Room',
                  value: _room(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 49,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      HapticFeedback.selectionClick();

                      Navigator.of(context).pop(CalendarClassDetailAction.edit);
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(
                      spanish ? 'Editar clase' : 'Edit class',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 49,
                  child: FilledButton.icon(
                    onPressed: () {
                      HapticFeedback.selectionClick();

                      Navigator.of(context)
                          .pop(CalendarClassDetailAction.viewSubject);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(
                      spanish ? 'Ver asignatura' : 'View subject',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow({
    required bool dark,
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _classColor.withValues(alpha: dark ? 0.16 : 0.09),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _classColor, size: 19),
        ),
        const SizedBox(width: 11),
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
              const SizedBox(height: 3),
              Text(
                value,
                style: TextStyle(
                  color: dark
                      ? const Color(0xFFF8FAFC)
                      : const Color(0xFF1F2937),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
