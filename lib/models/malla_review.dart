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
    bool deriveMissing = false,
  }) {
    final reasons =
        original.motivosRevision.isEmpty && original.requiereRevision
        ? const ['manual_verification']
        : original.motivosRevision;
    final kept = [
      for (final reason in reasons)
        if (reason == 'credits_missing' && credits == null ||
            reason == 'code_missing' && normalizedCode(code) == null ||
            reason != 'credits_missing' &&
                reason != 'code_missing' &&
                !verifyOther)
          reason,
    ];
    if (deriveMissing) {
      if (credits == null) kept.add('credits_missing');
      if (normalizedCode(code) == null) kept.add('code_missing');
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
          'credits_missing' || 'elective_slot' => MallaReviewPriority.high,
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
