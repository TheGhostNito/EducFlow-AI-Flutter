import 'malla_curricular.dart';
import 'malla_multimodal_review.dart';
import 'malla_review.dart';

enum MallaProposalDecision { suggested, pending, accepted, rejected }

enum MallaCourseSource { vision, gemini, merged, manual }

class MallaCourseAttention {
  const MallaCourseAttention({
    required this.courseId,
    required this.reasons,
    required this.evidence,
  });

  final String courseId;
  final List<String> reasons;
  final List<String> evidence;
}

class MallaCourseChangeProposal {
  MallaCourseChangeProposal({
    required this.review,
    required this.originalName,
    required this.originalCode,
    required this.originalCredits,
    required this.originalPeriod,
    required this.automaticallyAppliedFields,
    required this.attentionReasons,
  }) : decision = attentionReasons.isEmpty
           ? MallaProposalDecision.accepted
           : MallaProposalDecision.pending;

  final MallaCourseReview review;
  final String originalName;
  final String? originalCode;
  final int? originalCredits;
  final int originalPeriod;
  final Set<String> automaticallyAppliedFields;
  final List<String> attentionReasons;
  MallaProposalDecision decision;
}

class MallaPrerequisiteProposal {
  MallaPrerequisiteProposal({
    required this.courseId,
    required this.requiresCourseId,
    required this.evidence,
    required this.pendingReasons,
  }) : decision = evidence.isNotEmpty && pendingReasons.isEmpty
           ? MallaProposalDecision.suggested
           : MallaProposalDecision.pending;

  final String courseId;
  final String requiresCourseId;
  final List<String> evidence;
  final List<String> pendingReasons;
  MallaProposalDecision decision;
}

class MallaPrerequisiteGroup {
  const MallaPrerequisiteGroup({required this.id, required this.prerequisites});

  final String id;
  final List<MallaPrerequisiteProposal> prerequisites;
}

class MallaCertificationMembershipProposal {
  MallaCertificationMembershipProposal({
    required this.courseId,
    required this.basis,
    required this.evidence,
    this.pendingReasons = const [],
  }) : decision =
           evidence.isNotEmpty &&
               basis != 'legacy_review' &&
               pendingReasons.isEmpty
           ? MallaProposalDecision.suggested
           : MallaProposalDecision.pending;

  final String courseId;
  final String basis;
  final List<String> evidence;
  final List<String> pendingReasons;
  MallaProposalDecision decision;
}

class MallaCertificationProposal {
  MallaCertificationProposal({
    required this.id,
    required this.name,
    required this.evidence,
    required this.memberships,
    this.pendingReasons = const [],
  }) : decision = pendingReasons.isEmpty
           ? MallaProposalDecision.suggested
           : MallaProposalDecision.pending;

  final String id;
  final String name;
  final List<String> evidence;
  final List<MallaCertificationMembershipProposal> memberships;
  final List<String> pendingReasons;
  MallaProposalDecision decision;
}

class MallaAcademicRequirementProposal {
  MallaAcademicRequirementProposal({required this.requirement})
    : decision =
          requirement.evidence.isNotEmpty &&
              requirement.pendingReasons.isEmpty &&
              requirement.type != 'unknown'
          ? MallaProposalDecision.suggested
          : MallaProposalDecision.pending;

  MallaAcademicRequirement requirement;
  MallaProposalDecision decision;

  void updateDetails({required String description, int? minimumLevel}) {
    final normalizedDescription = description.trim();
    if (normalizedDescription.isEmpty) {
      throw ArgumentError(
        'La descripción del requisito no puede quedar vacía.',
      );
    }
    if (minimumLevel != null && (minimumLevel < 1 || minimumLevel > 30)) {
      throw ArgumentError('El nivel mínimo debe estar entre 1 y 30.');
    }
    requirement = MallaAcademicRequirement(
      id: requirement.id,
      type: requirement.type,
      targetCourseId: requirement.targetCourseId,
      targetLabel: requirement.targetLabel,
      description: normalizedDescription,
      minimumLevel: minimumLevel,
      evidence: requirement.evidence,
      pendingReasons: {
        for (final reason in requirement.pendingReasons)
          if (reason != 'requirement_level_conflict' &&
              reason != 'minimum_level_uncertain')
            reason,
        'manual_confirmation_required',
      }.toList(),
      source: requirement.source,
    );
    decision = MallaProposalDecision.pending;
  }
}

class MallaImportReview {
  MallaImportReview({
    required this.malla,
    required this.periodType,
    required this.periodCount,
    required this.periodEvidence,
    required this.geminiCourseIds,
    Set<String> mergedCourseIds = const {},
    required this.courseChanges,
    required this.prerequisites,
    required this.certifications,
    required this.academicRequirements,
    required this.globalPending,
    required this.deduplicatedAdditionalCourses,
  }) : mergedCourseIds = {...mergedCourseIds};

  final MallaCurricular malla;
  final String periodType;
  final int periodCount;
  final List<String> periodEvidence;
  final Set<String> geminiCourseIds;
  final Set<String> mergedCourseIds;
  final Set<String> _manualCourseIds = {};
  final Set<String> _manuallyEditedCourseIds = {};
  final List<MallaCourseChangeProposal> courseChanges;
  final List<MallaPrerequisiteProposal> prerequisites;
  final List<MallaCertificationProposal> certifications;
  final List<MallaAcademicRequirementProposal> academicRequirements;
  final List<String> globalPending;
  final List<String> deduplicatedAdditionalCourses;
  final Set<String> _resolvedGlobalPending = {};

  MallaCourseSource sourceFor(String courseId) {
    if (_manualCourseIds.contains(courseId)) return MallaCourseSource.manual;
    if (mergedCourseIds.contains(courseId) ||
        _manuallyEditedCourseIds.contains(courseId)) {
      return MallaCourseSource.merged;
    }
    if (geminiCourseIds.contains(courseId)) return MallaCourseSource.gemini;
    return MallaCourseSource.vision;
  }

  bool wasManuallyEdited(String courseId) =>
      _manualCourseIds.contains(courseId) ||
      _manuallyEditedCourseIds.contains(courseId);

  RamoMalla? courseById(String courseId) {
    for (final course in malla.ramos) {
      if (course.id == courseId) return course;
    }
    return null;
  }

  String courseName(String courseId) =>
      courseById(courseId)?.nombre ?? courseId;

  MallaCourseChangeProposal? courseChangeFor(String courseId) {
    for (final proposal in courseChanges) {
      if (proposal.review.courseId == courseId) return proposal;
    }
    return null;
  }

  String? categoryLabelFor(String courseId) {
    final proposal = courseChangeFor(courseId);
    if (proposal != null &&
        proposal.decision != MallaProposalDecision.rejected &&
        !proposal.attentionReasons.contains('gemini_category_uncertain') &&
        proposal.review.evidence.isNotEmpty) {
      return proposal.review.categoryLabel ??
          (proposal.review.category == 'unknown'
              ? null
              : proposal.review.category);
    }
    for (final additional
        in malla.multimodalReview?.additionalCourses ?? const []) {
      if (additional.id == courseId && additional.evidence.isNotEmpty) {
        return additional.categoryLabel ??
            (additional.category == 'unknown' ? null : additional.category);
      }
    }
    return null;
  }

  String categoryFor(String courseId) {
    final proposal = courseChangeFor(courseId);
    if (proposal != null &&
        proposal.decision != MallaProposalDecision.rejected &&
        proposal.review.evidence.isNotEmpty) {
      return proposal.review.category;
    }
    for (final additional
        in malla.multimodalReview?.additionalCourses ?? const []) {
      if (additional.id == courseId && additional.evidence.isNotEmpty) {
        return additional.category;
      }
    }
    return 'unknown';
  }

  List<String> evidenceFor(String courseId) {
    final proposal = courseChangeFor(courseId);
    if (proposal != null) return proposal.review.evidence;
    for (final additional
        in malla.multimodalReview?.additionalCourses ?? const []) {
      if (additional.id == courseId) return additional.evidence;
    }
    return const [];
  }

  List<String> get unresolvedGlobalPending => [
    for (final item in globalPending)
      if (!_resolvedGlobalPending.contains(item)) item,
  ];

  List<MallaCourseAttention> get courseAttentionItems {
    final result = <MallaCourseAttention>[];
    for (final course in malla.ramos) {
      final reasons = <String>{
        for (final issue in MallaReviewRules.issuesFor(malla, course))
          issue.reason,
      };
      final proposal = courseChangeFor(course.id);
      if (proposal?.decision == MallaProposalDecision.pending) {
        reasons.addAll(proposal!.attentionReasons);
      }
      if (reasons.isNotEmpty) {
        result.add(
          MallaCourseAttention(
            courseId: course.id,
            reasons: reasons.toList(),
            evidence: evidenceFor(course.id),
          ),
        );
      }
    }
    return result;
  }

  int get pendingCount {
    final pending = <String>{};
    for (final item in courseAttentionItems) {
      pending.add('course:${item.courseId}');
    }
    for (var index = 0; index < prerequisites.length; index++) {
      if (prerequisites[index].decision == MallaProposalDecision.pending) {
        pending.add('prerequisite:$index');
      }
    }
    for (final certification in certifications) {
      if (certification.decision == MallaProposalDecision.pending) {
        pending.add('certification:${certification.id}');
      }
      for (var index = 0; index < certification.memberships.length; index++) {
        if (certification.memberships[index].decision ==
            MallaProposalDecision.pending) {
          pending.add('certification:${certification.id}:$index');
        }
      }
    }
    for (final proposal in academicRequirements) {
      if (proposal.decision == MallaProposalDecision.pending) {
        pending.add('requirement:${proposal.requirement.id}');
      }
    }
    for (final item in unresolvedGlobalPending) {
      pending.add('global:$item');
    }
    return pending.length;
  }

  int get suggestionCount =>
      prerequisites
          .where((item) => item.decision == MallaProposalDecision.suggested)
          .length +
      certifications.fold<int>(
        0,
        (count, certification) =>
            count +
            (certification.decision == MallaProposalDecision.suggested
                ? 1
                : 0) +
            certification.memberships
                .where(
                  (item) => item.decision == MallaProposalDecision.suggested,
                )
                .length,
      ) +
      academicRequirements
          .where((item) => item.decision == MallaProposalDecision.suggested)
          .length;

  List<MallaPrerequisiteGroup> get prerequisiteGroups {
    const maximumRelationsPerGroup = 6;
    final candidates = <int>{
      for (var index = 0; index < prerequisites.length; index++)
        if (prerequisites[index].decision != MallaProposalDecision.pending)
          index,
    };
    final groups = <MallaPrerequisiteGroup>[];
    while (candidates.isNotEmpty) {
      final seed = candidates.reduce((a, b) => a < b ? a : b);
      candidates.remove(seed);
      final component = <int>[seed];
      final connectedCourses = <String>{
        prerequisites[seed].courseId,
        prerequisites[seed].requiresCourseId,
      };
      var expanded = true;
      while (expanded) {
        expanded = false;
        for (final index in candidates.toList()..sort()) {
          final proposal = prerequisites[index];
          if (!connectedCourses.contains(proposal.courseId) &&
              !connectedCourses.contains(proposal.requiresCourseId)) {
            continue;
          }
          candidates.remove(index);
          component.add(index);
          connectedCourses
            ..add(proposal.courseId)
            ..add(proposal.requiresCourseId);
          expanded = true;
        }
      }
      component.sort((left, right) {
        final leftProposal = prerequisites[left];
        final rightProposal = prerequisites[right];
        final leftCourse = courseById(leftProposal.courseId);
        final rightCourse = courseById(rightProposal.courseId);
        final byPeriod = (leftCourse?.semestre ?? 0).compareTo(
          rightCourse?.semestre ?? 0,
        );
        if (byPeriod != 0) return byPeriod;
        final byTarget = courseName(leftProposal.courseId)
            .compareTo(courseName(rightProposal.courseId));
        if (byTarget != 0) return byTarget;
        return left.compareTo(right);
      });
      for (
        var offset = 0;
        offset < component.length;
        offset += maximumRelationsPerGroup
      ) {
        final end = (offset + maximumRelationsPerGroup).clamp(
          0,
          component.length,
        );
        groups.add(
          MallaPrerequisiteGroup(
            id: 'prerequisite-group-$seed-${offset ~/ maximumRelationsPerGroup}',
            prerequisites: [
              for (final index in component.sublist(offset, end))
                prerequisites[index],
            ],
          ),
        );
      }
    }
    return groups;
  }

  void acceptSuggestedPrerequisites(
    Iterable<MallaPrerequisiteProposal> selected,
  ) {
    for (final proposal in selected) {
      if (prerequisites.contains(proposal) &&
          proposal.decision == MallaProposalDecision.suggested) {
        proposal.decision = MallaProposalDecision.accepted;
      }
    }
  }

  void acceptCertificationSelection(
    MallaCertificationProposal certification,
    Iterable<MallaCertificationMembershipProposal> selected,
  ) {
    if (!certifications.contains(certification) ||
        certification.decision == MallaProposalDecision.pending ||
        certification.decision == MallaProposalDecision.rejected) {
      return;
    }
    if (certification.decision == MallaProposalDecision.suggested) {
      certification.decision = MallaProposalDecision.accepted;
    }
    for (final membership in selected) {
      if (certification.memberships.contains(membership) &&
          membership.decision == MallaProposalDecision.suggested) {
        membership.decision = MallaProposalDecision.accepted;
      }
    }
  }

  void markManualCourse(String courseId) => _manualCourseIds.add(courseId);

  void removeCourse(String courseId) {
    malla.ramos.removeWhere((course) => course.id == courseId);
    geminiCourseIds.remove(courseId);
    mergedCourseIds.remove(courseId);
    _manualCourseIds.remove(courseId);
    _manuallyEditedCourseIds.remove(courseId);
  }

  void decideCourseChange(
    MallaCourseChangeProposal proposal,
    MallaProposalDecision decision,
  ) {
    final course = courseById(proposal.review.courseId);
    if (course != null) {
      if (decision == MallaProposalDecision.accepted) {
        final review = proposal.review;
        if (review.proposedName != null) course.nombre = review.proposedName!;
        if (review.proposedCode != null) course.codigo = review.proposedCode;
        if (review.proposedCredits != null) {
          course.creditos = review.proposedCredits;
        }
        if (review.proposedPeriod != null) {
          course.semestre = review.proposedPeriod!;
        }
        course.motivosRevision.removeWhere(
          (reason) => proposal.attentionReasons.contains(reason),
        );
      } else if (decision == MallaProposalDecision.rejected) {
        course
          ..nombre = proposal.originalName
          ..codigo = proposal.originalCode
          ..creditos = proposal.originalCredits
          ..semestre = proposal.originalPeriod;
        course.motivosRevision.removeWhere(
          (reason) => proposal.attentionReasons.contains(reason),
        );
      }
      course.requiereRevision = course.motivosRevision.isNotEmpty;
    }
    proposal.decision = decision;
  }

  void markCourseEdited(String courseId) {
    if (!_manualCourseIds.contains(courseId)) {
      _manuallyEditedCourseIds.add(courseId);
    }
    final proposal = courseChangeFor(courseId);
    if (proposal != null) proposal.decision = MallaProposalDecision.accepted;
  }

  void resolveGlobalPending(String item) => _resolvedGlobalPending.add(item);
}

class MallaImportReviewBuilder {
  static MallaImportReview? integrate(MallaCurricular vision) {
    final review = vision.multimodalReview;
    if (review == null) return null;

    final courses = [for (final course in vision.ramos) _copyCourse(course)];
    final referenceMap = <String, String>{
      for (final course in courses) course.id: course.id,
    };
    final geminiCourseIds = <String>{};
    final mergedCourseIds = <String>{};
    final deduplicated = <String>[];
    final courseChanges = <MallaCourseChangeProposal>[];

    for (final item in review.courseReviews) {
      final course = _courseById(courses, item.courseId);
      if (course == null) continue;
      courseChanges.add(_applyCourseReview(course, item, review.periodCount));
    }

    for (final proposal in review.additionalCourses) {
      final duplicate = _findDuplicate(courses, proposal);
      if (duplicate != null) {
        referenceMap[proposal.id] = duplicate.id;
        deduplicated.add(proposal.proposedName);
        continue;
      }
      final matchedSpecial = _findMatchingSpecial(vision.especiales, proposal);
      final reasons = <String>{
        for (final reason in proposal.pendingReasons)
          if (!_coveredByMissingField(proposal, reason))
            _normalizeProposalReason(reason),
        if (proposal.proposedCode == null && matchedSpecial?.codigo == null)
          'code_missing',
        if (proposal.proposedCredits == null &&
            matchedSpecial?.creditos == null)
          'credits_missing',
        if (proposal.proposedPeriod == null && matchedSpecial?.semestre == null)
          'semester_uncertain',
      };
      final course = RamoMalla(
        id: proposal.id,
        nombre: proposal.proposedName,
        semestre: proposal.proposedPeriod ?? matchedSpecial?.semestre ?? 1,
        codigo: proposal.proposedCode ?? matchedSpecial?.codigo,
        creditos: proposal.proposedCredits ?? matchedSpecial?.creditos,
        requiereRevision: reasons.isNotEmpty,
        motivosRevision: reasons.toList(),
      );
      courses.add(course);
      if (matchedSpecial == null) {
        geminiCourseIds.add(course.id);
      } else {
        mergedCourseIds.add(course.id);
      }
      referenceMap[proposal.id] = course.id;
    }

    String resolve(String value) => referenceMap[value] ?? value;

    final prerequisites = [
      for (final item in review.prerequisites)
        MallaPrerequisiteProposal(
          courseId: resolve(item.courseId),
          requiresCourseId: resolve(item.requiresCourseId),
          evidence: item.evidence,
          pendingReasons: item.pendingReasons,
        ),
    ];
    final certifications = [
      for (final item in review.certifications)
        MallaCertificationProposal(
          id: item.id,
          name: item.name,
          evidence: item.evidence,
          memberships: [
            for (final membership in item.memberships)
              MallaCertificationMembershipProposal(
                courseId: resolve(membership.courseId),
                basis: membership.basis,
                evidence: membership.evidence,
                pendingReasons: membership.pendingReasons,
              ),
            if (item.memberships.isEmpty)
              for (final courseId in item.courseIds)
                MallaCertificationMembershipProposal(
                  courseId: resolve(courseId),
                  basis: 'legacy_review',
                  evidence: item.evidence,
                ),
          ],
        ),
    ];
    final globalPending = review.pendingReview.toSet();
    for (final issue in review.pendingReview) {
      final parsed = _parseUncertainPrerequisite(issue);
      if (parsed == null) continue;
      final courseId = resolve(parsed.$1);
      final requiredId = resolve(parsed.$2);
      if (_courseById(courses, courseId) == null ||
          _courseById(courses, requiredId) == null ||
          courseId == requiredId) {
        continue;
      }
      final duplicate = prerequisites.any(
        (item) =>
            item.courseId == courseId && item.requiresCourseId == requiredId,
      );
      if (!duplicate) {
        prerequisites.add(
          MallaPrerequisiteProposal(
            courseId: courseId,
            requiresCourseId: requiredId,
            evidence: const [],
            pendingReasons: parsed.$3,
          ),
        );
      }
      globalPending.remove(issue);
    }
    for (final issue in review.pendingReview) {
      final parsed = _parseUncertainCertificationMembership(issue);
      if (parsed == null) continue;
      MallaCertificationProposal? certification;
      for (final item in certifications) {
        if (item.id == parsed.$1) certification = item;
      }
      final courseId = resolve(parsed.$2);
      if (certification == null || _courseById(courses, courseId) == null) {
        continue;
      }
      final duplicate = certification.memberships.any(
        (item) => item.courseId == courseId,
      );
      if (!duplicate) {
        certification.memberships.add(
          MallaCertificationMembershipProposal(
            courseId: courseId,
            basis: 'pending_review',
            evidence: const [],
            pendingReasons: const ['membership_evidence_uncertain'],
          ),
        );
      }
      globalPending.remove(issue);
    }

    final merged = MallaCurricular(
      id: vision.id,
      archivoNombre: vision.archivoNombre,
      ramos: courses,
      especiales: [
        for (final special in vision.especiales)
          if (!_isSpecialRepresentedByCourse(special, courses)) special,
      ],
      multimodalReview: review,
      multimodalDiagnostics: vision.multimodalDiagnostics,
    );

    return MallaImportReview(
      malla: merged,
      periodType: review.periodType,
      periodCount: review.periodCount,
      periodEvidence: review.periodEvidence,
      geminiCourseIds: geminiCourseIds,
      mergedCourseIds: mergedCourseIds,
      courseChanges: courseChanges,
      prerequisites: prerequisites,
      certifications: certifications,
      academicRequirements: [
        for (final item in review.academicRequirements)
          MallaAcademicRequirementProposal(
            requirement: MallaAcademicRequirement(
              id: item.id,
              type: item.type,
              targetCourseId: item.targetCourseId == null
                  ? null
                  : resolve(item.targetCourseId!),
              targetLabel: item.targetLabel,
              description: item.description,
              minimumLevel: item.minimumLevel,
              evidence: item.evidence,
              pendingReasons: item.pendingReasons,
            ),
          ),
      ],
      globalPending: globalPending.toList(),
      deduplicatedAdditionalCourses: deduplicated,
    );
  }

  static RamoMalla? _findDuplicate(
    List<RamoMalla> courses,
    MallaAdditionalCourseProposal proposal,
  ) {
    final code = _normalizeCode(proposal.proposedCode);
    final name = _normalizeWords(proposal.proposedName);
    for (final course in courses) {
      final sameCode = code != null && code == _normalizeCode(course.codigo);
      final sameName =
          name.isNotEmpty && name == _normalizeWords(course.nombre);
      if (!sameCode && !sameName) continue;
      if (proposal.proposedPeriod != null &&
          proposal.proposedPeriod != course.semestre) {
        continue;
      }
      if (proposal.proposedCredits != null &&
          course.creditos != null &&
          proposal.proposedCredits != course.creditos) {
        continue;
      }
      final samePeriod =
          proposal.proposedPeriod != null &&
          proposal.proposedPeriod == course.semestre;
      final sameCredits =
          proposal.proposedCredits != null &&
          proposal.proposedCredits == course.creditos;
      if (sameCode && (sameName || samePeriod || sameCredits)) return course;
      if (sameName && (samePeriod || sameCredits)) {
        return course;
      }
    }
    return null;
  }

  static ElementoCurricularEspecial? _findMatchingSpecial(
    List<ElementoCurricularEspecial> specials,
    MallaAdditionalCourseProposal proposal,
  ) {
    final code = _normalizeCode(proposal.proposedCode);
    final name = _normalizeWords(proposal.proposedName);
    for (final special in specials) {
      final sameCode = code != null && code == _normalizeCode(special.codigo);
      final sameName =
          name.isNotEmpty && name == _normalizeWords(special.nombre);
      final compatiblePeriod =
          proposal.proposedPeriod == null ||
          special.semestre == null ||
          proposal.proposedPeriod == special.semestre;
      if ((sameCode || sameName) && compatiblePeriod) return special;
    }
    return null;
  }

  static bool _isSpecialRepresentedByCourse(
    ElementoCurricularEspecial special,
    List<RamoMalla> courses,
  ) {
    final specialName = _normalizeWords(special.nombre);
    if (specialName.isEmpty) return false;
    final specialCode = _normalizeCode(special.codigo);
    for (final course in courses) {
      if (specialName != _normalizeWords(course.nombre)) continue;
      final courseCode = _normalizeCode(course.codigo);
      if (specialCode != null && courseCode != specialCode) continue;
      if (special.semestre != null && special.semestre != course.semestre) {
        continue;
      }
      if (special.creditos != null &&
          course.creditos != null &&
          special.creditos != course.creditos) {
        continue;
      }
      final sameCode = specialCode != null && specialCode == courseCode;
      final samePeriod =
          special.semestre != null && special.semestre == course.semestre;
      final sameCredits =
          special.creditos != null && special.creditos == course.creditos;
      if (sameCode || samePeriod || sameCredits) return true;
    }
    return false;
  }

  static RamoMalla? _courseById(List<RamoMalla> courses, String id) {
    for (final course in courses) {
      if (course.id == id) return course;
    }
    return null;
  }

  static MallaCourseChangeProposal _applyCourseReview(
    RamoMalla course,
    MallaCourseReview review,
    int periodCount,
  ) {
    final originalName = course.nombre;
    final originalCode = course.codigo;
    final originalCredits = course.creditos;
    final originalPeriod = course.semestre;
    final applied = <String>{};
    final attention = <String>{};
    final hasEvidence = review.evidence.isNotEmpty;
    final normalizedPending = [
      for (final reason in review.pendingReasons) _normalizeWords(reason),
    ];
    bool uncertainFor(List<String> terms) =>
        normalizedPending.any((reason) => terms.any(reason.contains));
    final recognizedPending = normalizedPending.where(
      (reason) => const [
        'name',
        'nombre',
        'code',
        'codigo',
        'credit',
        'period',
        'semester',
        'semestre',
        'category',
        'categoria',
      ].any(reason.contains),
    );
    final hasGeneralUncertainty =
        normalizedPending.length != recognizedPending.length;

    if (!hasEvidence) {
      attention.add('gemini_change_without_evidence');
    } else {
      if (hasGeneralUncertainty) attention.add('gemini_change_uncertain');
      final proposedName = review.proposedName;
      if (proposedName != null &&
          _normalizeWords(proposedName) != _normalizeWords(course.nombre)) {
        if (hasGeneralUncertainty || uncertainFor(const ['name', 'nombre'])) {
          attention.add('gemini_name_uncertain');
        } else if (course.motivosRevision.contains(
          'name_association_uncertain',
        )) {
          course.nombre = proposedName;
          course.motivosRevision.remove('name_association_uncertain');
          applied.add('name');
        } else {
          attention.add('gemini_name_conflict');
        }
      }

      final proposedCode = review.proposedCode;
      if (proposedCode != null &&
          _normalizeCode(proposedCode) != _normalizeCode(course.codigo)) {
        if (hasGeneralUncertainty || uncertainFor(const ['code', 'codigo'])) {
          attention.add('gemini_code_uncertain');
        } else if (_normalizeCode(course.codigo) == null ||
            course.motivosRevision.contains('code_missing')) {
          course.codigo = proposedCode;
          course.motivosRevision.remove('code_missing');
          applied.add('code');
        } else {
          attention.add('gemini_code_conflict');
        }
      }

      final proposedCredits = review.proposedCredits;
      if (proposedCredits != null) {
        final creditsUncertain = uncertainFor(const ['credit']);
        if (proposedCredits == course.creditos) {
          if (!creditsUncertain) {
            course.motivosRevision.remove('credits_missing');
          }
        } else if (creditsUncertain) {
          attention.add('gemini_credits_uncertain');
        } else if (course.creditos == null) {
          course.creditos = proposedCredits;
          course.motivosRevision.remove('credits_missing');
          applied.add('credits');
        } else {
          attention.add('gemini_credits_conflict');
        }
      }

      final proposedPeriod = review.proposedPeriod;
      if (proposedPeriod != null && proposedPeriod != course.semestre) {
        if (hasGeneralUncertainty ||
            uncertainFor(const ['period', 'semester', 'semestre'])) {
          attention.add('gemini_period_uncertain');
        } else if (proposedPeriod < 1 ||
            proposedPeriod > 30 ||
            periodCount > 0 && proposedPeriod > periodCount) {
          attention.add('gemini_period_invalid');
        } else if (course.motivosRevision.contains('semester_uncertain')) {
          course.semestre = proposedPeriod;
          course.motivosRevision.remove('semester_uncertain');
          applied.add('period');
        } else {
          attention.add('gemini_period_conflict');
        }
      }
      if (review.category != 'unknown' &&
          (hasGeneralUncertainty ||
              uncertainFor(const ['category', 'categoria']))) {
        attention.add('gemini_category_uncertain');
      }
    }

    for (final reason in attention) {
      if (!course.motivosRevision.contains(reason)) {
        course.motivosRevision.add(reason);
      }
    }
    course.requiereRevision = course.motivosRevision.isNotEmpty;
    return MallaCourseChangeProposal(
      review: review,
      originalName: originalName,
      originalCode: originalCode,
      originalCredits: originalCredits,
      originalPeriod: originalPeriod,
      automaticallyAppliedFields: applied,
      attentionReasons: attention.toList(),
    );
  }

  static String _normalizeProposalReason(String reason) => switch (reason) {
    'code_uncertain' => 'gemini_code_uncertain',
    'credits_uncertain' => 'gemini_credits_uncertain',
    'period_uncertain' => 'gemini_period_uncertain',
    _ => reason,
  };

  static bool _coveredByMissingField(
    MallaAdditionalCourseProposal proposal,
    String reason,
  ) => switch (reason) {
    'code_uncertain' => proposal.proposedCode == null,
    'credits_uncertain' => proposal.proposedCredits == null,
    'period_uncertain' => proposal.proposedPeriod == null,
    _ => false,
  };

  static (String, String, List<String>)? _parseUncertainPrerequisite(
    String issue,
  ) {
    const prefix = 'uncertain_prerequisite_relation:';
    if (!issue.startsWith(prefix)) return null;
    final parts = issue.substring(prefix.length).split(':');
    final relation = parts.first.split('>');
    if (relation.length != 2 ||
        relation.first.isEmpty ||
        relation.last.isEmpty) {
      return null;
    }
    final reasons = parts.length < 2
        ? const <String>[]
        : parts
              .skip(1)
              .expand((item) => item.split(','))
              .where((item) => item.isNotEmpty)
              .toList();
    return (relation.first, relation.last, reasons);
  }

  static (String, String)? _parseUncertainCertificationMembership(
    String issue,
  ) {
    const prefix = 'uncertain_certification_membership:';
    if (!issue.startsWith(prefix)) return null;
    final parts = issue.substring(prefix.length).split(':');
    if (parts.length < 2 || parts[0].isEmpty || parts[1].isEmpty) return null;
    return (parts[0], parts[1]);
  }

  static RamoMalla _copyCourse(RamoMalla course) => RamoMalla(
    id: course.id,
    nombre: course.nombre,
    semestre: course.semestre,
    codigo: course.codigo,
    creditos: course.creditos,
    estado: course.estado,
    requiereRevision: course.requiereRevision,
    motivosRevision: List<String>.from(course.motivosRevision),
    codigoDuplicadoVerificado: course.codigoDuplicadoVerificado,
  );

  static String? _normalizeCode(String? value) {
    final normalized = value?.toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String _normalizeWords(String value) => value
      .toLowerCase()
      .replaceAll(RegExp('[áàäâ]'), 'a')
      .replaceAll(RegExp('[éèëê]'), 'e')
      .replaceAll(RegExp('[íìïî]'), 'i')
      .replaceAll(RegExp('[óòöô]'), 'o')
      .replaceAll(RegExp('[úùüû]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}
