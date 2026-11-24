import 'malla_curricular.dart';

enum MallaReviewPriority { high, medium, verification }

class MallaReviewIssue {
  const MallaReviewIssue(this.reason, this.priority, this.relatedNames);

  final String reason;
  final MallaReviewPriority priority;
  final List<String> relatedNames;

  String label(bool spanish) => switch (reason) {
    'credits_missing' => spanish ? 'Completa los créditos' : 'Add credits',
    'code_missing' => spanish ? 'Comprueba el código' : 'Check the code',
    'name_association_uncertain' =>
      spanish
          ? 'Comprueba el nombre de esta asignatura'
          : 'Check this course name',
    'elective_slot' =>
      spanish
          ? 'Comprueba qué electivo corresponde a este espacio'
          : 'Check which elective belongs in this slot',
    'semester_uncertain' =>
      spanish ? 'Comprueba el semestre' : 'Check the semester',
    'gemini_additional_course' =>
      spanish
          ? 'Confirma la asignatura propuesta por la IA'
          : 'Confirm the course proposed by AI',
    'gemini_name_conflict' =>
      spanish
          ? 'La extracción y la revisión de IA proponen nombres distintos'
          : 'Extraction and AI review propose different names',
    'gemini_code_conflict' =>
      spanish
          ? 'La extracción y la revisión de IA proponen códigos distintos'
          : 'Extraction and AI review propose different codes',
    'gemini_name_uncertain' =>
      spanish ? 'Comprueba el nombre propuesto' : 'Check the proposed name',
    'gemini_code_uncertain' =>
      spanish ? 'Comprueba el código propuesto' : 'Check the proposed code',
    'gemini_credits_uncertain' =>
      spanish
          ? 'Comprueba los créditos propuestos'
          : 'Check the proposed credits',
    'gemini_category_uncertain' =>
      spanish
          ? 'Comprueba la categoría propuesta'
          : 'Check the proposed category',
    'gemini_credits_conflict' =>
      spanish
          ? 'La extracción y la revisión de IA proponen créditos distintos'
          : 'Extraction and AI review propose different credits',
    'gemini_period_conflict' || 'gemini_period_invalid' =>
      spanish ? 'Comprueba el período propuesto' : 'Check the proposed period',
    'gemini_period_uncertain' =>
      spanish ? 'Comprueba el período propuesto' : 'Check the proposed period',
    'gemini_change_without_evidence' || 'gemini_change_uncertain' =>
      spanish
          ? 'Comprueba esta propuesta con la malla original'
          : 'Check this proposal against the original curriculum',
    'duplicate_code' =>
      spanish
          ? 'Código compartido con ${relatedNames.join(', ')}'
          : 'Code shared with ${relatedNames.join(', ')}',
    _ =>
      spanish
          ? 'Comprueba que los datos coincidan con tu malla original'
          : 'Check that these details match your original curriculum',
  };
}

class MallaReviewRules {
  static String? normalizedCode(String? code) {
    final value = code?.trim().toUpperCase();
    return value == null || value.isEmpty ? null : value;
  }

  static List<String> remainingReasons(
    RamoMalla original, {
    required String? code,
    required int? credits,
    required bool verifyOther,
    bool verifyMissingCode = false,
    bool deriveMissing = false,
  }) {
    final reasons =
        original.motivosRevision.isEmpty && original.requiereRevision
        ? const ['manual_verification']
        : original.motivosRevision;
    final kept = [
      for (final reason in reasons)
        if (reason == 'credits_missing' && credits == null ||
            reason == 'code_missing' &&
                normalizedCode(code) == null &&
                !verifyMissingCode ||
            reason != 'credits_missing' &&
                reason != 'code_missing' &&
                !verifyOther)
          reason,
    ];
    if (deriveMissing) {
      if (credits == null) kept.add('credits_missing');
      if (normalizedCode(code) == null && !verifyMissingCode) {
        kept.add('code_missing');
      }
    }
    return kept.toSet().toList();
  }

  static List<String> duplicateNames(MallaCurricular malla, RamoMalla ramo) {
    return duplicateNamesForCode(malla, ramo.id, ramo.codigo);
  }

  static List<String> duplicateNamesForCode(
    MallaCurricular malla,
    String ramoId,
    String? rawCode,
  ) {
    final code = normalizedCode(rawCode);
    if (code == null) return const [];
    return [
      for (final other in malla.ramos)
        if (other.id != ramoId && normalizedCode(other.codigo) == code)
          '${other.nombre} (S${other.semestre})',
    ];
  }

  static List<MallaReviewIssue> issuesFor(
    MallaCurricular malla,
    RamoMalla ramo,
  ) {
    final reasons = remainingReasons(
      ramo,
      code: ramo.codigo,
      credits: ramo.creditos,
      verifyOther: false,
    );
    final issues = [
      for (final reason in reasons)
        MallaReviewIssue(reason, switch (reason) {
          'credits_missing' ||
          'elective_slot' ||
          'gemini_credits_conflict' => MallaReviewPriority.high,
          'code_missing' || 'semester_uncertain' => MallaReviewPriority.medium,
          _ => MallaReviewPriority.verification,
        }, const []),
    ];
    final duplicates = duplicateNames(malla, ramo);
    if (duplicates.isNotEmpty && !ramo.codigoDuplicadoVerificado) {
      issues.add(
        MallaReviewIssue(
          'duplicate_code',
          MallaReviewPriority.medium,
          duplicates,
        ),
      );
    }
    return issues;
  }

  static int pendingCount(MallaCurricular malla) =>
      malla.ramos.where((ramo) => issuesFor(malla, ramo).isNotEmpty).length;
}
