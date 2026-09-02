import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/evaluacion.dart';
import '../../../services/time_format_service.dart';

enum EvaluationDetailAction { edit, delete }

Future<EvaluationDetailAction?> showEvaluationDetailSheet({
  required BuildContext context,
  required Evaluacion evaluation,
  required String subjectName,
  required String typeName,
  required bool spanish,
}) {
  return showModalBottomSheet<EvaluationDetailAction>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    builder: (_) {
      return _EvaluationDetailSheet(
        evaluation: evaluation,
        subjectName: subjectName,
        typeName: typeName,
        spanish: spanish,
      );
    },
  );
}

class _EvaluationDetailSheet extends StatelessWidget {
  const _EvaluationDetailSheet({
    required this.evaluation,
    required this.subjectName,
    required this.typeName,
    required this.spanish,
  });

  final Evaluacion evaluation;
  final String subjectName;
  final String typeName;
  final bool spanish;

  static const Color _evaluationColor = Color(0xFF8B5CF6);

  String _dateText() {
    final DateTime date = evaluation.fecha;

    if (spanish) {
      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year}';
    }

    return '${date.month.toString().padLeft(2, '0')}/'
        '${date.day.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _weightText() {
    final double? value = evaluation.ponderacion;

    if (value == null) {
      return spanish ? 'Sin ponderación' : 'No weight';
    }

    final String formatted = value % 1 == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);

    return '$formatted%';
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    final TimeFormatService timeService = TimeFormatService.instance;

    final String time = evaluation.hora?.trim().isNotEmpty == true
        ? timeService.formatStoredTime(context, evaluation.hora!)
        : (spanish ? 'Sin hora' : 'No time');

    final String description = evaluation.descripcion?.trim() ?? '';

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
                    color: _evaluationColor.withValues(
                      alpha: dark ? 0.18 : 0.10,
                    ),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.school_outlined,
                    color: _evaluationColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${spanish ? 'EVALUACIÓN' : 'EVALUATION'} · '
                        '${typeName.toUpperCase()}',
                        style: const TextStyle(
                          color: _evaluationColor,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        evaluation.titulo,
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
                PopupMenuButton<EvaluationDetailAction>(
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
                  onOpened: HapticFeedback.selectionClick,
                  onSelected: (action) {
                    Navigator.of(context).pop(action);
                  },
                  itemBuilder: (_) {
                    return [
                      PopupMenuItem(
                        value: EvaluationDetailAction.edit,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.edit_outlined,
                              color: _evaluationColor,
                              size: 20,
                            ),
                            const SizedBox(width: 11),
                            Text(
                              spanish ? 'Editar evaluación' : 'Edit evaluation',
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: EvaluationDetailAction.delete,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.delete_outline_rounded,
                              color: Color(0xFFDC2626),
                              size: 20,
                            ),
                            const SizedBox(width: 11),
                            Text(
                              spanish
                                  ? 'Eliminar evaluación'
                                  : 'Delete evaluation',
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
                      color: _evaluationColor,
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
                  _infoRow(
                    dark: dark,
                    icon: Icons.menu_book_outlined,
                    label: spanish ? 'Asignatura' : 'Subject',
                    value: subjectName,
                  ),
                  const SizedBox(height: 14),
                  _infoRow(
                    dark: dark,
                    icon: Icons.category_outlined,
                    label: spanish ? 'Tipo' : 'Type',
                    value: typeName,
                  ),
                  const SizedBox(height: 14),
                  _infoRow(
                    dark: dark,
                    icon: Icons.calendar_today_outlined,
                    label: spanish ? 'Fecha' : 'Date',
                    value: _dateText(),
                  ),
                  const SizedBox(height: 14),
                  _infoRow(
                    dark: dark,
                    icon: Icons.schedule_rounded,
                    label: spanish ? 'Hora' : 'Time',
                    value: time,
                  ),
                  const SizedBox(height: 14),
                  _infoRow(
                    dark: dark,
                    icon: Icons.percent_rounded,
                    label: spanish ? 'Ponderación' : 'Weight',
                    value: _weightText(),
                    valueColor: evaluation.ponderacion == null
                        ? null
                        : _evaluationColor,
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
                        color: _evaluationColor,
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

  Widget _infoRow({
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
            color: _evaluationColor.withValues(alpha: dark ? 0.16 : 0.09),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _evaluationColor, size: 19),
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
