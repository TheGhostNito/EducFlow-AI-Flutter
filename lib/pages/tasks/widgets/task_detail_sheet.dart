import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/tarea.dart';

enum TaskDetailAction { edit, delete }

Future<TaskDetailAction?> showTaskDetailSheet({
  required BuildContext context,
  required Tarea task,
  required String subjectName,
  required String dueText,
  required String priorityText,
  required bool spanish,
}) {
  return showModalBottomSheet<TaskDetailAction>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    builder: (_) {
      return _TaskDetailSheet(
        task: task,
        subjectName: subjectName,
        dueText: dueText,
        priorityText: priorityText,
        spanish: spanish,
      );
    },
  );
}

class _TaskDetailSheet extends StatelessWidget {
  const _TaskDetailSheet({
    required this.task,
    required this.subjectName,
    required this.dueText,
    required this.priorityText,
    required this.spanish,
  });

  final Tarea task;
  final String subjectName;
  final String dueText;
  final String priorityText;
  final bool spanish;

  static const Color _primaryColor = Color(0xFF5B5FEF);

  Color get _priorityColor {
    switch (task.prioridad) {
      case PrioridadTarea.baja:
        return const Color(0xFF059669);

      case PrioridadTarea.media:
        return const Color(0xFFF59E0B);

      case PrioridadTarea.alta:
        return const Color(0xFFEF4444);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    final String description = task.descripcion?.trim() ?? '';

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
      child: SingleChildScrollView(
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
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: dark
                        ? const Color(0xFF292936)
                        : const Color(0xFFEEF0FF),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.task_alt_rounded,
                    color: _primaryColor,
                    size: 24,
                  ),
                ),

                const SizedBox(width: 13),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        spanish ? 'TAREA' : 'TASK',
                        style: const TextStyle(
                          color: _primaryColor,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),

                      const SizedBox(height: 5),

                      Text(
                        task.titulo,
                        style: TextStyle(
                          color: dark
                              ? const Color(0xFFF8FAFC)
                              : const Color(0xFF111827),
                          fontSize: 21,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                PopupMenuButton<TaskDetailAction>(
                  tooltip: '',
                  color: dark ? const Color(0xFF222229) : Colors.white,
                  surfaceTintColor: Colors.transparent,
                  elevation: 10,
                  position: PopupMenuPosition.under,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(
                      color: dark
                          ? const Color(0xFF34343C)
                          : const Color(0xFFE7EAF0),
                    ),
                  ),
                  onOpened: () {
                    HapticFeedback.selectionClick();
                  },
                  onSelected: (action) {
                    Navigator.of(context).pop(action);
                  },
                  itemBuilder: (_) {
                    return [
                      PopupMenuItem(
                        value: TaskDetailAction.edit,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.edit_outlined,
                              color: _primaryColor,
                              size: 20,
                            ),
                            const SizedBox(width: 11),
                            Text(spanish ? 'Editar tarea' : 'Edit task'),
                          ],
                        ),
                      ),

                      PopupMenuItem(
                        value: TaskDetailAction.delete,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.delete_outline_rounded,
                              color: Color(0xFFDC2626),
                              size: 20,
                            ),
                            const SizedBox(width: 11),
                            Text(
                              spanish ? 'Eliminar tarea' : 'Delete task',
                              style: const TextStyle(
                                color: Color(0xFFDC2626),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ];
                  },
                  child: Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: dark
                          ? const Color(0xFF24242A)
                          : const Color(0xFFF3F4F7),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.more_horiz_rounded,
                      color: _primaryColor,
                    ),
                  ),
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
                  color: dark
                      ? const Color(0xFF34343C)
                      : const Color(0xFFE7EAF0),
                ),
              ),
              child: Column(
                children: [
                  _buildInfoRow(
                    dark: dark,
                    icon: Icons.menu_book_outlined,
                    label: spanish ? 'Asignatura' : 'Subject',
                    value: subjectName,
                  ),

                  const SizedBox(height: 14),

                  _buildInfoRow(
                    dark: dark,
                    icon: Icons.calendar_today_outlined,
                    label: spanish ? 'Entrega' : 'Due',
                    value: dueText,
                  ),

                  const SizedBox(height: 14),

                  _buildInfoRow(
                    dark: dark,
                    icon: Icons.flag_outlined,
                    label: spanish ? 'Prioridad' : 'Priority',
                    value: priorityText,
                    valueColor: _priorityColor,
                  ),

                  const SizedBox(height: 14),

                  _buildInfoRow(
                    dark: dark,
                    icon: task.completada
                        ? Icons.check_circle_outline
                        : Icons.pending_actions_outlined,
                    label: spanish ? 'Estado' : 'Status',
                    value: task.completada
                        ? (spanish ? 'Completada' : 'Completed')
                        : (spanish ? 'Pendiente' : 'Pending'),
                    valueColor: task.completada
                        ? const Color(0xFF059669)
                        : _primaryColor,
                  ),
                ],
              ),
            ),

            if (description.isNotEmpty) ...[
              const SizedBox(height: 16),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xFF222229)
                      : const Color(0xFFFAFBFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: dark
                        ? const Color(0xFF34343C)
                        : const Color(0xFFE7EAF0),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spanish ? 'DESCRIPCIÓN' : 'DESCRIPTION',
                      style: const TextStyle(
                        color: _primaryColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      description,
                      style: TextStyle(
                        color: dark
                            ? const Color(0xFFE7EAF0)
                            : const Color(0xFF374151),
                        fontSize: 13.5,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required bool dark,
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF292936) : const Color(0xFFEEF0FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _primaryColor, size: 19),
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
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                value,
                style: TextStyle(
                  color:
                      valueColor ??
                      (dark
                          ? const Color(0xFFF8FAFC)
                          : const Color(0xFF1F2937)),
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
