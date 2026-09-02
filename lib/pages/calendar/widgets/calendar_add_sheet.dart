import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

enum CalendarAddAction { task, evaluation }

Future<CalendarAddAction?> showCalendarAddSheet({
  required BuildContext context,
  required bool spanish,
  required DateTime selectedDate,
}) {
  return showModalBottomSheet<CalendarAddAction>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    builder: (_) {
      return _CalendarAddSheet(spanish: spanish, selectedDate: selectedDate);
    },
  );
}

class _CalendarAddSheet extends StatelessWidget {
  const _CalendarAddSheet({required this.spanish, required this.selectedDate});

  final bool spanish;
  final DateTime selectedDate;

  static const Color _primaryColor = Color(0xFF5B5FEF);
  static const Color _evaluationColor = Color(0xFF8B5CF6);

  String _dateText() {
    if (spanish) {
      return '${selectedDate.day.toString().padLeft(2, '0')}/'
          '${selectedDate.month.toString().padLeft(2, '0')}/'
          '${selectedDate.year}';
    }

    return '${selectedDate.month.toString().padLeft(2, '0')}/'
        '${selectedDate.day.toString().padLeft(2, '0')}/'
        '${selectedDate.year}';
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CALENDARIO',
                      style: TextStyle(
                        color: _primaryColor,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      spanish
                          ? '¿Qué quieres agregar?'
                          : 'What do you want to add?',
                      style: TextStyle(
                        color: dark
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF111827),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      spanish ? 'Para el ${_dateText()}' : 'For ${_dateText()}',
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
          _buildOption(
            context: context,
            dark: dark,
            color: _primaryColor,
            icon: Icons.checklist_rounded,
            title: spanish ? 'Tarea' : 'Task',
            description: spanish
                ? 'Agrega una entrega o pendiente para este día.'
                : 'Add an assignment or pending task for this day.',
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pop(CalendarAddAction.task);
            },
          ),
          const SizedBox(height: 10),
          _buildOption(
            context: context,
            dark: dark,
            color: _evaluationColor,
            icon: Icons.school_outlined,
            title: spanish ? 'Prueba / Evaluación' : 'Test / Evaluation',
            description: spanish
                ? 'Registra una prueba, examen, control o presentación.'
                : 'Add a test, exam, assessment or presentation.',
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pop(CalendarAddAction.evaluation);
            },
          ),
          const SizedBox(height: 10),
          _buildFutureOption(
            dark: dark,
            icon: Ionicons.calendarOutline,
            title: spanish ? 'Evento' : 'Event',
            description: spanish
                ? 'Eventos personales o académicos.'
                : 'Personal or academic events.',
            comingSoon: spanish ? 'Próximamente' : 'Coming soon',
          ),
        ],
      ),
    );
  }

  Widget _buildOption({
    required BuildContext context,
    required bool dark,
    required Color color,
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF222229) : const Color(0xFFFAFBFC),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: dark ? const Color(0xFF34343C) : const Color(0xFFE7EAF0),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: dark ? 0.17 : 0.09),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: color, size: 23),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: dark
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF1F2937),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: dark
                            ? const Color(0xFFA9B1BF)
                            : const Color(0xFF6B7280),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFutureOption({
    required bool dark,
    required IconData icon,
    required String title,
    required String description,
    required String comingSoon,
  }) {
    return Opacity(
      opacity: 0.55,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF222229) : const Color(0xFFFAFBFC),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: dark ? const Color(0xFF34343C) : const Color(0xFFE7EAF0),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF292936) : const Color(0xFFEEF0FF),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: _primaryColor, size: 22),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: dark
                                ? const Color(0xFFF8FAFC)
                                : const Color(0xFF1F2937),
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _primaryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          comingSoon,
                          style: const TextStyle(
                            color: _primaryColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: dark
                          ? const Color(0xFFA9B1BF)
                          : const Color(0xFF6B7280),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
