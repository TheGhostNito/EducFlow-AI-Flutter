import 'package:flutter/material.dart';

import '../../../models/evaluacion.dart';

Future<bool> showEvaluationGradeDetails({
  required BuildContext context,
  required Evaluacion evaluacion,
  required String grade,
  required String weight,
  required bool spanish,
  required bool isFinalExam,
}) async {
  return await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => _EvaluationGradeDetail(
          evaluacion: evaluacion,
          grade: grade,
          weight: weight,
          spanish: spanish,
          isFinalExam: isFinalExam,
        ),
      ) ??
      false;
}

class _EvaluationGradeDetail extends StatelessWidget {
  const _EvaluationGradeDetail({
    required this.evaluacion,
    required this.grade,
    required this.weight,
    required this.spanish,
    required this.isFinalExam,
  });

  final Evaluacion evaluacion;
  final String grade;
  final String weight;
  final bool spanish;
  final bool isFinalExam;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    evaluacion.titulo,
                    key: const ValueKey('evaluation-grade-detail-title'),
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (isFinalExam)
                  Chip(label: Text(spanish ? 'Examen final' : 'Final exam')),
              ],
            ),
            if ((evaluacion.descripcion ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                evaluacion.descripcion!,
                style: TextStyle(
                  color: dark
                      ? const Color(0xFFA9B1BF)
                      : const Color(0xFF6B7280),
                ),
              ),
            ],
            const SizedBox(height: 22),
            Text(
              grade,
              key: const ValueKey('evaluation-grade-detail-grade'),
              style: const TextStyle(
                color: Color(0xFF5B5FEF),
                fontSize: 42,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(spanish ? 'Nota obtenida' : 'Grade earned'),
            const SizedBox(height: 20),
            _Metric(label: spanish ? 'Ponderación' : 'Weight', value: weight),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const ValueKey('edit-evaluation-grade'),
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.edit_outlined),
              label: Text(spanish ? 'Editar' : 'Edit'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
