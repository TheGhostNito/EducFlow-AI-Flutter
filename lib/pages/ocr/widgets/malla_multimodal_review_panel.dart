import 'package:flutter/material.dart';

import '../../../models/malla_import_review.dart';

class MallaMultimodalReviewPanel extends StatelessWidget {
  const MallaMultimodalReviewPanel({
    super.key,
    required this.review,
    required this.spanish,
    required this.onCourseDecision,
    required this.onPrerequisiteDecision,
    required this.onConfirmPrerequisiteGroup,
    required this.onMembershipDecision,
    required this.onCertificationDecision,
    required this.onConfirmCertificationGroup,
    required this.onRequirementDecision,
    required this.onEditRequirement,
    required this.onResolveGlobal,
    required this.onEditCourse,
  });

  final MallaImportReview review;
  final bool spanish;
  final void Function(
    MallaCourseChangeProposal proposal,
    MallaProposalDecision decision,
  )
  onCourseDecision;
  final void Function(
    MallaPrerequisiteProposal proposal,
    MallaProposalDecision decision,
  )
  onPrerequisiteDecision;
  final ValueChanged<List<MallaPrerequisiteProposal>>
  onConfirmPrerequisiteGroup;
  final void Function(
    MallaCertificationMembershipProposal proposal,
    MallaProposalDecision decision,
  )
  onMembershipDecision;
  final void Function(
    MallaCertificationProposal proposal,
    MallaProposalDecision decision,
  )
  onCertificationDecision;
  final void Function(
    MallaCertificationProposal certification,
    List<MallaCertificationMembershipProposal> memberships,
  )
  onConfirmCertificationGroup;
  final void Function(
    MallaAcademicRequirementProposal proposal,
    MallaProposalDecision decision,
  )
  onRequirementDecision;
  final ValueChanged<MallaAcademicRequirementProposal> onEditRequirement;
  final ValueChanged<String> onResolveGlobal;
  final ValueChanged<String> onEditCourse;

  String _t(String es, String en) => spanish ? es : en;

  String _decisionLabel(MallaProposalDecision decision) => switch (decision) {
    MallaProposalDecision.suggested => _t('Sugerida', 'Suggested'),
    MallaProposalDecision.pending => _t('Requiere revisión', 'Needs review'),
    MallaProposalDecision.accepted => _t('Confirmada', 'Confirmed'),
    MallaProposalDecision.rejected => _t('Descartada', 'Discarded'),
  };

  IconData _decisionIcon(MallaProposalDecision decision) => switch (decision) {
    MallaProposalDecision.suggested => Icons.auto_awesome_outlined,
    MallaProposalDecision.pending => Icons.fact_check_outlined,
    MallaProposalDecision.accepted => Icons.check_circle_outline_rounded,
    MallaProposalDecision.rejected => Icons.cancel_outlined,
  };

  Widget _decisionMenu({
    required Key key,
    required MallaProposalDecision value,
    required ValueChanged<MallaProposalDecision> onSelected,
    bool allowSuggested = true,
    bool allowAccepted = true,
  }) => PopupMenuButton<MallaProposalDecision>(
    key: key,
    tooltip: _t('Cambiar revisión', 'Change review'),
    initialValue: value,
    onSelected: onSelected,
    itemBuilder: (_) => [
      for (final decision in MallaProposalDecision.values)
        if (allowSuggested || decision != MallaProposalDecision.suggested)
          if (allowAccepted || decision != MallaProposalDecision.accepted)
            PopupMenuItem(
              value: decision,
              child: Row(
                children: [
                  Icon(_decisionIcon(decision), size: 19),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_decisionLabel(decision))),
                ],
              ),
            ),
    ],
    child: _statusPill(value),
  );

  Widget _statusPill(MallaProposalDecision decision) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: _decisionColor(decision).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _decisionIcon(decision),
          size: 16,
          color: _decisionColor(decision),
        ),
        const SizedBox(width: 5),
        Text(_decisionLabel(decision)),
      ],
    ),
  );

  Widget _proposalTile({
    Key? key,
    required String title,
    required String subtitle,
    required Widget trailing,
    List<String> evidence = const [],
  }) => Padding(
    key: key,
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle),
              if (evidence.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  evidence.first,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        trailing,
      ],
    ),
  );

  int get _pendingRelationships =>
      review.prerequisites
          .where((item) => item.decision == MallaProposalDecision.pending)
          .length +
      review.certifications.fold<int>(
        0,
        (count, item) =>
            count +
            (item.decision == MallaProposalDecision.pending ? 1 : 0) +
            item.memberships
                .where(
                  (membership) =>
                      membership.decision == MallaProposalDecision.pending,
                )
                .length,
      ) +
      review.academicRequirements
          .where((item) => item.decision == MallaProposalDecision.pending)
          .length;

  int get _inspectableRelationships =>
      review.prerequisites
          .where((item) => item.decision != MallaProposalDecision.pending)
          .length +
      review.certifications.fold<int>(
        0,
        (count, item) =>
            count +
            (item.decision != MallaProposalDecision.pending ? 1 : 0) +
            item.memberships
                .where(
                  (membership) =>
                      membership.decision != MallaProposalDecision.pending,
                )
                .length,
      ) +
      review.academicRequirements
          .where((item) => item.decision != MallaProposalDecision.pending)
          .length;

  Map<String, List<String>> get _globalPendingGroups {
    final groups = <String, List<String>>{};
    for (final item in review.unresolvedGlobalPending) {
      groups.putIfAbsent(_pendingLabel(item), () => []).add(item);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = theme.brightness == Brightness.dark
        ? const Color(0xFF2B323E)
        : const Color(0xFFE7EAF0);
    return Material(
      key: const Key('malla-integrated-review'),
      color: theme.brightness == Brightness.dark
          ? const Color(0xFF191F29)
          : Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  review.pendingCount == 0
                      ? Icons.check_circle_outline_rounded
                      : Icons.fact_check_outlined,
                  color: const Color(0xFF5B5FEF),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        review.pendingCount == 0
                            ? _t(
                                'Malla organizada para revisión',
                                'Curriculum organized for review',
                              )
                            : _t(
                                'Elementos que necesitan atención',
                                'Items that need attention',
                              ),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        review.pendingCount == 0
                            ? _t(
                                'Los datos completos ya se incorporaron al borrador. Puedes inspeccionar las relaciones sugeridas.',
                                'Complete data is already in the draft. You can inspect the suggested relationships.',
                              )
                            : _t(
                                '${review.pendingCount} elementos concentran datos ausentes, contradictorios o inciertos.',
                                '${review.pendingCount} items contain missing, conflicting, or uncertain data.',
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (review.pendingCount > 0)
            ExpansionTile(
              key: const Key('malla-attention-items'),
              initiallyExpanded: true,
              leading: const Icon(Icons.warning_amber_rounded),
              title: Text(_t('Revisar ahora', 'Review now')),
              subtitle: Text('${review.pendingCount}'),
              children: [
                for (final item in review.courseAttentionItems)
                  _courseAttention(item),
                for (
                  var index = 0;
                  index < review.prerequisites.length;
                  index++
                )
                  if (review.prerequisites[index].decision ==
                      MallaProposalDecision.pending)
                    _prerequisite(review.prerequisites[index], index),
                for (final certification in review.certifications)
                  if (certification.decision == MallaProposalDecision.pending)
                    _certificationParent(certification),
                for (final certification in review.certifications)
                  for (
                    var index = 0;
                    index < certification.memberships.length;
                    index++
                  )
                    if (certification.memberships[index].decision ==
                        MallaProposalDecision.pending)
                      _membership(certification, index),
                for (final proposal in review.academicRequirements)
                  if (proposal.decision == MallaProposalDecision.pending)
                    _requirement(proposal),
                for (final entry in _globalPendingGroups.entries)
                  _globalPendingGroup(entry),
              ],
            ),
          if (_inspectableRelationships > 0)
            ExpansionTile(
              key: const Key('malla-relationship-proposals'),
              leading: const Icon(Icons.account_tree_outlined),
              title: Text(
                _t(
                  'Relaciones académicas propuestas',
                  'Proposed academic relationships',
                ),
              ),
              subtitle: Text(
                _t(
                  '$_inspectableRelationships relaciones · revisa, confirma o descarta',
                  '$_inspectableRelationships relationships · review, confirm, or discard',
                ),
              ),
              children: [
                for (final group in review.prerequisiteGroups)
                  _PrerequisiteGroupCard(
                    key: ValueKey(group.id),
                    group: group,
                    review: review,
                    spanish: spanish,
                    onConfirm: onConfirmPrerequisiteGroup,
                    onDecision: onPrerequisiteDecision,
                  ),
                for (final certification in review.certifications)
                  if (certification.decision != MallaProposalDecision.pending ||
                      certification.memberships.any(
                        (item) =>
                            item.decision != MallaProposalDecision.pending,
                      ))
                    _CertificationGroupCard(
                      key: ValueKey(
                        'certification-group-state-${certification.id}',
                      ),
                      certification: certification,
                      review: review,
                      spanish: spanish,
                      onConfirm: onConfirmCertificationGroup,
                      onCertificationDecision: onCertificationDecision,
                      onMembershipDecision: onMembershipDecision,
                      includePendingMemberships: true,
                    ),
                for (final proposal in review.academicRequirements)
                  if (proposal.decision != MallaProposalDecision.pending)
                    _requirement(proposal),
              ],
            ),
          if (_pendingRelationships > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Text(
                _t(
                  'Las relaciones inciertas permanecen sin verificar hasta que las revises.',
                  'Uncertain relationships remain unverified until you review them.',
                ),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _courseAttention(MallaCourseAttention item) {
    final proposal = review.courseChangeFor(item.courseId);
    return _proposalTile(
      key: ValueKey('malla-attention-problem-course-${item.courseId}'),
      title: review.courseName(item.courseId),
      subtitle: item.reasons.map(_pendingLabel).toSet().join(' · '),
      evidence: item.evidence,
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (proposal?.decision == MallaProposalDecision.pending)
            _decisionMenu(
              key: ValueKey('course-proposal-${item.courseId}'),
              value: proposal!.decision,
              allowSuggested: false,
              onSelected: (value) => onCourseDecision(proposal, value),
            ),
          TextButton(
            onPressed: () => onEditCourse(item.courseId),
            child: Text(_t('Corregir', 'Edit')),
          ),
        ],
      ),
    );
  }

  Widget _globalPendingGroup(MapEntry<String, List<String>> entry) {
    if (entry.value.length == 1) {
      final item = entry.value.single;
      return ListTile(
        key: ValueKey('malla-attention-problem-global-$item'),
        title: Text(entry.key),
        trailing: TextButton(
          onPressed: () => onResolveGlobal(item),
          child: Text(_t('Revisado', 'Reviewed')),
        ),
      );
    }
    return ExpansionTile(
      title: Text(entry.key),
      subtitle: Text(
        _t(
          '${entry.value.length} casos detectados',
          '${entry.value.length} detected cases',
        ),
      ),
      children: [
        for (var index = 0; index < entry.value.length; index++)
          ListTile(
            key: ValueKey(
              'malla-attention-problem-global-${entry.value[index]}',
            ),
            title: Text(_t('Caso ${index + 1}', 'Case ${index + 1}')),
            trailing: TextButton(
              onPressed: () => onResolveGlobal(entry.value[index]),
              child: Text(_t('Revisado', 'Reviewed')),
            ),
          ),
      ],
    );
  }

  Widget _prerequisite(MallaPrerequisiteProposal proposal, int index) =>
      _proposalTile(
        key: proposal.decision == MallaProposalDecision.pending
            ? ValueKey('malla-attention-problem-prerequisite-$index')
            : null,
        title: review.courseName(proposal.courseId),
        subtitle: _t(
          'Requiere ${review.courseName(proposal.requiresCourseId)}',
          'Requires ${review.courseName(proposal.requiresCourseId)}',
        ),
        evidence: proposal.evidence,
        trailing: _decisionMenu(
          key: ValueKey('prerequisite-proposal-$index'),
          value: proposal.decision,
          onSelected: (value) => onPrerequisiteDecision(proposal, value),
        ),
      );

  Widget _membership(
    MallaCertificationProposal certification,
    int index,
  ) => _proposalTile(
    key:
        certification.memberships[index].decision ==
            MallaProposalDecision.pending
        ? ValueKey(
            'malla-attention-problem-membership-${certification.id}-$index',
          )
        : null,
    title: certification.name,
    subtitle: _t(
      'Incluye ${review.courseName(certification.memberships[index].courseId)}',
      'Includes ${review.courseName(certification.memberships[index].courseId)}',
    ),
    evidence: certification.memberships[index].evidence,
    trailing: _decisionMenu(
      key: ValueKey('membership-${certification.id}-$index'),
      value: certification.memberships[index].decision,
      allowAccepted:
          certification.decision == MallaProposalDecision.suggested ||
          certification.decision == MallaProposalDecision.accepted,
      onSelected: (value) {
        if (value == MallaProposalDecision.accepted) {
          onConfirmCertificationGroup(certification, [
            certification.memberships[index],
          ]);
        } else {
          onMembershipDecision(certification.memberships[index], value);
        }
      },
    ),
  );

  Widget _certificationParent(MallaCertificationProposal certification) =>
      _proposalTile(
        key: ValueKey(
          'malla-attention-problem-certification-${certification.id}',
        ),
        title: certification.name,
        subtitle: _t(
          'La certificación requiere revisión individual',
          'The certification requires individual review',
        ),
        evidence: certification.evidence,
        trailing: _decisionMenu(
          key: ValueKey('certification-${certification.id}'),
          value: certification.decision,
          onSelected: (value) => onCertificationDecision(certification, value),
        ),
      );

  Widget _requirement(MallaAcademicRequirementProposal proposal) {
    final item = proposal.requirement;
    final target = item.targetCourseId == null
        ? item.targetLabel
        : review.courseName(item.targetCourseId!);
    return _proposalTile(
      key: proposal.decision == MallaProposalDecision.pending
          ? ValueKey('malla-attention-problem-requirement-${item.id}')
          : null,
      title: target ?? _t('Requisito general', 'General requirement'),
      subtitle: '${item.description} · ${_requirementType(item.type)}',
      evidence: item.evidence,
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _decisionMenu(
            key: ValueKey('requirement-${item.id}'),
            value: proposal.decision,
            onSelected: (value) => onRequirementDecision(proposal, value),
          ),
          TextButton(
            key: ValueKey('edit-requirement-${item.id}'),
            onPressed: () => onEditRequirement(proposal),
            child: Text(_t('Corregir', 'Correct')),
          ),
        ],
      ),
    );
  }

  String _requirementType(String value) => switch (value) {
    'approved_level' => _t('Niveles aprobados', 'Approved levels'),
    'completed_periods' => _t('Períodos completados', 'Completed periods'),
    'practice_eligibility' => _t('Acceso a práctica', 'Practice eligibility'),
    'capstone_eligibility' => _t('Acceso a Capstone', 'Capstone eligibility'),
    'other' => _t('Otro requisito', 'Other requirement'),
    _ => _t('Tipo por comprobar', 'Type to verify'),
  };

  String _pendingLabel(String value) {
    if (value.startsWith('uncertain_prerequisite_relation:')) {
      return _t(
        'Hay una relación de prerrequisito ambigua',
        'A prerequisite relationship is ambiguous',
      );
    }
    if (value.startsWith('uncertain_certification_membership:')) {
      return _t(
        'Hay una pertenencia a certificación dudosa',
        'A certification membership is uncertain',
      );
    }
    if (value.startsWith('invalid_certification')) {
      return _t(
        'Comprueba una certificación detectada',
        'Check a detected certification',
      );
    }
    return switch (value) {
      'code_missing' ||
      'code_uncertain' => _t('Código sin confirmar', 'Code not confirmed'),
      'credits_missing' || 'credits_uncertain' => _t(
        'Créditos sin confirmar',
        'Credits not confirmed',
      ),
      'semester_uncertain' ||
      'period_uncertain' ||
      'gemini_period_conflict' ||
      'gemini_period_invalid' => _t(
        'Período por comprobar',
        'Period to verify',
      ),
      'gemini_name_conflict' => _t(
        'Nombres contradictorios',
        'Conflicting names',
      ),
      'gemini_name_uncertain' => _t('Nombre por comprobar', 'Name to verify'),
      'gemini_code_conflict' => _t(
        'Códigos contradictorios',
        'Conflicting codes',
      ),
      'gemini_code_uncertain' => _t('Código por comprobar', 'Code to verify'),
      'gemini_credits_conflict' => _t(
        'Créditos contradictorios',
        'Conflicting credits',
      ),
      'gemini_credits_uncertain' => _t(
        'Créditos por comprobar',
        'Credits to verify',
      ),
      'gemini_category_uncertain' => _t(
        'Categoría por comprobar',
        'Category to verify',
      ),
      'gemini_period_uncertain' => _t(
        'Período por comprobar',
        'Period to verify',
      ),
      'gemini_change_without_evidence' || 'gemini_change_uncertain' => _t(
        'Propuesta académica incierta',
        'Uncertain academic proposal',
      ),
      'name_association_uncertain' => _t(
        'Nombre por comprobar',
        'Name to verify',
      ),
      'elective_slot' => _t('Electivo por definir', 'Elective to define'),
      'duplicate_code' => _t(
        'Código compartido por comprobar',
        'Shared code to verify',
      ),
      'requirement_type_uncertain' => _t(
        'Tipo de requisito por comprobar',
        'Requirement type to verify',
      ),
      _ => _t(
        'Comprueba este dato con la malla original',
        'Check this item against the original curriculum',
      ),
    };
  }
}

class MallaPersistedRelationshipGroups extends StatefulWidget {
  const MallaPersistedRelationshipGroups({
    super.key,
    required this.review,
    required this.spanish,
    required this.onConfirmPrerequisites,
    required this.onDecidePrerequisite,
    required this.onConfirmCertification,
    required this.onDecideMembership,
    this.includePrerequisites = true,
    this.includeCertifications = true,
    this.showHeader = true,
  });

  final MallaImportReview review;
  final bool spanish;
  final Future<bool> Function(List<MallaPrerequisiteProposal> prerequisites)
  onConfirmPrerequisites;
  final Future<bool> Function(
    MallaPrerequisiteProposal prerequisite,
    MallaProposalDecision decision,
  )
  onDecidePrerequisite;
  final Future<bool> Function(
    MallaCertificationProposal certification,
    List<MallaCertificationMembershipProposal> memberships,
  )
  onConfirmCertification;
  final Future<bool> Function(
    MallaCertificationProposal certification,
    MallaCertificationMembershipProposal membership,
    MallaProposalDecision decision,
  )
  onDecideMembership;
  final bool includePrerequisites;
  final bool includeCertifications;
  final bool showHeader;

  @override
  State<MallaPersistedRelationshipGroups> createState() =>
      _MallaPersistedRelationshipGroupsState();
}

class _MallaPersistedRelationshipGroupsState
    extends State<MallaPersistedRelationshipGroups> {
  bool _saving = false;

  String _t(String es, String en) => widget.spanish ? es : en;

  Future<void> _run(Future<bool> Function() operation) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await operation();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prerequisiteGroups = widget.includePrerequisites
        ? widget.review.prerequisiteGroups
        : const <MallaPrerequisiteGroup>[];
    final certifications =
        (widget.includeCertifications
                ? widget.review.certifications
                : const <MallaCertificationProposal>[])
            .where(
              (item) =>
                  item.decision != MallaProposalDecision.pending ||
                  item.memberships.any(
                    (membership) =>
                        membership.decision != MallaProposalDecision.pending,
                  ),
            )
            .toList();
    return Column(
      key: const Key('malla-persisted-relationship-groups'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeader) ...[
          Text(
            _t('Relaciones académicas', 'Academic relationships'),
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            _t(
              'Confirma sugerencias por conjuntos o revisa cada relación individualmente.',
              'Confirm suggestions in groups or review each relationship individually.',
            ),
          ),
        ],
        if (_saving) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(
            key: Key('malla-persisted-group-saving'),
          ),
        ],
        const SizedBox(height: 7),
        AbsorbPointer(
          absorbing: _saving,
          child: Column(
            children: [
              for (final group in prerequisiteGroups)
                _PrerequisiteGroupCard(
                  key: ValueKey('persisted-${group.id}'),
                  group: group,
                  review: widget.review,
                  spanish: widget.spanish,
                  allowedDecisions: const {
                    MallaProposalDecision.accepted,
                    MallaProposalDecision.rejected,
                  },
                  onConfirm: (selected) =>
                      _run(() => widget.onConfirmPrerequisites(selected)),
                  onDecision: (proposal, decision) => _run(
                    () => widget.onDecidePrerequisite(proposal, decision),
                  ),
                ),
              for (final certification in certifications)
                _CertificationGroupCard(
                  key: ValueKey('persisted-certification-${certification.id}'),
                  certification: certification,
                  review: widget.review,
                  spanish: widget.spanish,
                  parentAllowedDecisions: const {
                    MallaProposalDecision.accepted,
                  },
                  membershipAllowedDecisions: const {
                    MallaProposalDecision.accepted,
                    MallaProposalDecision.rejected,
                  },
                  includePendingMemberships: true,
                  onConfirm: (parent, selected) => _run(
                    () => widget.onConfirmCertification(parent, selected),
                  ),
                  onCertificationDecision: (parent, decision) {
                    if (decision == MallaProposalDecision.accepted) {
                      _run(
                        () => widget.onConfirmCertification(parent, const []),
                      );
                    }
                  },
                  onMembershipDecision: (membership, decision) => _run(
                    () => widget.onDecideMembership(
                      certification,
                      membership,
                      decision,
                    ),
                  ),
                ),
              if (prerequisiteGroups.isEmpty && certifications.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    _t(
                      'No hay relaciones académicas para revisar.',
                      'There are no academic relationships to review.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PrerequisiteGroupCard extends StatefulWidget {
  const _PrerequisiteGroupCard({
    super.key,
    required this.group,
    required this.review,
    required this.spanish,
    required this.onConfirm,
    required this.onDecision,
    this.allowedDecisions,
  });

  final MallaPrerequisiteGroup group;
  final MallaImportReview review;
  final bool spanish;
  final ValueChanged<List<MallaPrerequisiteProposal>> onConfirm;
  final void Function(
    MallaPrerequisiteProposal proposal,
    MallaProposalDecision decision,
  )
  onDecision;
  final Set<MallaProposalDecision>? allowedDecisions;

  @override
  State<_PrerequisiteGroupCard> createState() => _PrerequisiteGroupCardState();
}

class _PrerequisiteGroupCardState extends State<_PrerequisiteGroupCard> {
  final Set<String> _excluded = {};

  String _t(String es, String en) => widget.spanish ? es : en;
  String _key(MallaPrerequisiteProposal item) =>
      '${item.requiresCourseId}>${item.courseId}';

  @override
  Widget build(BuildContext context) {
    final suggested = widget.group.prerequisites
        .where((item) => item.decision == MallaProposalDecision.suggested)
        .toList();
    final selected = suggested
        .where((item) => !_excluded.contains(_key(item)))
        .toList();
    return Card(
      key: ValueKey('prerequisite-card-${widget.group.id}'),
      margin: const EdgeInsets.fromLTRB(12, 5, 12, 7),
      elevation: 0,
      child: ExpansionTile(
        key: ValueKey('prerequisite-group-${widget.group.id}'),
        leading: const Icon(Icons.account_tree_outlined),
        title: Text(_t('Cadena o conjunto académico', 'Academic chain or set')),
        subtitle: Text(
          _t(
            '${widget.group.prerequisites.length} relaciones · ${selected.length} seleccionadas',
            '${widget.group.prerequisites.length} relationships · ${selected.length} selected',
          ),
        ),
        children: [
          for (final proposal in widget.group.prerequisites)
            _relationRow(proposal),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: ValueKey('confirm-prerequisite-group-${widget.group.id}'),
                onPressed: selected.isEmpty
                    ? null
                    : () => widget.onConfirm(selected),
                child: Text(
                  _t(
                    'Confirmar selección (${selected.length})',
                    'Confirm selection (${selected.length})',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _relationRow(MallaPrerequisiteProposal proposal) {
    final suggested = proposal.decision == MallaProposalDecision.suggested;
    final selected = suggested && !_excluded.contains(_key(proposal));
    final source = widget.review.courseName(proposal.requiresCourseId);
    final target = widget.review.courseName(proposal.courseId);
    return ListTile(
      key: ValueKey('grouped-prerequisite-${_key(proposal)}'),
      leading: suggested
          ? Checkbox(
              key: ValueKey('select-prerequisite-${_key(proposal)}'),
              value: selected,
              onChanged: (value) => setState(() {
                if (value == true) {
                  _excluded.remove(_key(proposal));
                } else {
                  _excluded.add(_key(proposal));
                }
              }),
            )
          : Icon(_decisionIcon(proposal.decision)),
      title: Text('$source → $target'),
      subtitle: Text(
        [
          _t(
            '$source es requisito de $target',
            '$source is required by $target',
          ),
          if (proposal.evidence.isNotEmpty) proposal.evidence.first,
        ].join('\n'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _ReviewDecisionMenu(
        key: ValueKey('grouped-prerequisite-menu-${_key(proposal)}'),
        value: proposal.decision,
        spanish: widget.spanish,
        allowedDecisions: widget.allowedDecisions,
        onSelected: (value) => widget.onDecision(proposal, value),
      ),
    );
  }
}

class _CertificationGroupCard extends StatefulWidget {
  const _CertificationGroupCard({
    super.key,
    required this.certification,
    required this.review,
    required this.spanish,
    required this.onConfirm,
    required this.onCertificationDecision,
    required this.onMembershipDecision,
    this.parentAllowedDecisions,
    this.membershipAllowedDecisions,
    this.includePendingMemberships = false,
  });

  final MallaCertificationProposal certification;
  final MallaImportReview review;
  final bool spanish;
  final void Function(
    MallaCertificationProposal certification,
    List<MallaCertificationMembershipProposal> memberships,
  )
  onConfirm;
  final void Function(
    MallaCertificationProposal proposal,
    MallaProposalDecision decision,
  )
  onCertificationDecision;
  final void Function(
    MallaCertificationMembershipProposal proposal,
    MallaProposalDecision decision,
  )
  onMembershipDecision;
  final Set<MallaProposalDecision>? parentAllowedDecisions;
  final Set<MallaProposalDecision>? membershipAllowedDecisions;
  final bool includePendingMemberships;

  @override
  State<_CertificationGroupCard> createState() =>
      _CertificationGroupCardState();
}

class _CertificationGroupCardState extends State<_CertificationGroupCard> {
  final Set<String> _excludedCourseIds = {};

  String _t(String es, String en) => widget.spanish ? es : en;

  @override
  Widget build(BuildContext context) {
    final certification = widget.certification;
    final visibleMemberships = certification.memberships
        .where(
          (item) =>
              widget.includePendingMemberships ||
              item.decision != MallaProposalDecision.pending,
        )
        .toList();
    final selected = visibleMemberships
        .where(
          (item) =>
              item.decision == MallaProposalDecision.suggested &&
              !_excludedCourseIds.contains(item.courseId),
        )
        .toList();
    final hasAcceptedMembership = certification.memberships.any(
      (item) => item.decision == MallaProposalDecision.accepted,
    );
    final parentAllowsConfirmation =
        certification.decision == MallaProposalDecision.suggested ||
        certification.decision == MallaProposalDecision.accepted;
    return Card(
      key: ValueKey('certification-card-${certification.id}'),
      margin: const EdgeInsets.fromLTRB(12, 5, 12, 7),
      elevation: 0,
      child: ExpansionTile(
        key: ValueKey('certification-group-${certification.id}'),
        leading: const Icon(Icons.workspace_premium_outlined),
        title: Text(certification.name),
        subtitle: Text(
          _t(
            '${visibleMemberships.length} asignaturas · ${selected.length} seleccionadas',
            '${visibleMemberships.length} courses · ${selected.length} selected',
          ),
        ),
        trailing: _ReviewDecisionMenu(
          key: ValueKey('certification-parent-${certification.id}'),
          value: certification.decision,
          spanish: widget.spanish,
          allowedDecisions: hasAcceptedMembership
              ? const {MallaProposalDecision.accepted}
              : widget.parentAllowedDecisions,
          onSelected: (value) =>
              widget.onCertificationDecision(certification, value),
        ),
        children: [
          if (certification.evidence.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  certification.evidence.first,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          if (hasAcceptedMembership)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _t(
                    'Descarta primero las membresías confirmadas para descartar la certificación.',
                    'Discard confirmed memberships before discarding the certification.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          for (final membership in visibleMemberships)
            _membershipRow(membership, parentAllowsConfirmation),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: ValueKey(
                  'confirm-certification-group-${certification.id}',
                ),
                onPressed: parentAllowsConfirmation && selected.isNotEmpty
                    ? () => widget.onConfirm(certification, selected)
                    : null,
                child: Text(
                  _t(
                    'Confirmar selección (${selected.length})',
                    'Confirm selection (${selected.length})',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _membershipRow(
    MallaCertificationMembershipProposal membership,
    bool parentAllowsConfirmation,
  ) {
    final suggested = membership.decision == MallaProposalDecision.suggested;
    final selected =
        suggested && !_excludedCourseIds.contains(membership.courseId);
    return ListTile(
      key: ValueKey(
        'grouped-membership-${widget.certification.id}-${membership.courseId}',
      ),
      leading: suggested
          ? Checkbox(
              key: ValueKey(
                'select-membership-${widget.certification.id}-${membership.courseId}',
              ),
              value: selected,
              onChanged: (value) => setState(() {
                if (value == true) {
                  _excludedCourseIds.remove(membership.courseId);
                } else {
                  _excludedCourseIds.add(membership.courseId);
                }
              }),
            )
          : Icon(_decisionIcon(membership.decision)),
      title: Text(widget.review.courseName(membership.courseId)),
      subtitle: membership.evidence.isEmpty
          ? null
          : Text(
              membership.evidence.first,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: _ReviewDecisionMenu(
        key: ValueKey(
          'grouped-membership-menu-${widget.certification.id}-${membership.courseId}',
        ),
        value: membership.decision,
        spanish: widget.spanish,
        allowAccepted: parentAllowsConfirmation,
        allowedDecisions: widget.membershipAllowedDecisions,
        onSelected: (value) {
          if (value == MallaProposalDecision.accepted) {
            widget.onConfirm(widget.certification, [membership]);
          } else {
            widget.onMembershipDecision(membership, value);
          }
        },
      ),
    );
  }
}

class _ReviewDecisionMenu extends StatelessWidget {
  const _ReviewDecisionMenu({
    super.key,
    required this.value,
    required this.spanish,
    required this.onSelected,
    this.allowAccepted = true,
    this.allowedDecisions,
  });

  final MallaProposalDecision value;
  final bool spanish;
  final ValueChanged<MallaProposalDecision> onSelected;
  final bool allowAccepted;
  final Set<MallaProposalDecision>? allowedDecisions;

  String _t(String es, String en) => spanish ? es : en;

  String _label(MallaProposalDecision decision) => switch (decision) {
    MallaProposalDecision.suggested => _t('Sugerida', 'Suggested'),
    MallaProposalDecision.pending => _t('Requiere revisión', 'Needs review'),
    MallaProposalDecision.accepted => _t('Confirmada', 'Confirmed'),
    MallaProposalDecision.rejected => _t('Descartada', 'Discarded'),
  };

  @override
  Widget build(BuildContext context) => PopupMenuButton<MallaProposalDecision>(
    tooltip: _t('Cambiar revisión', 'Change review'),
    initialValue: value,
    onSelected: onSelected,
    itemBuilder: (_) => [
      for (final decision in MallaProposalDecision.values)
        if ((allowedDecisions == null ||
                allowedDecisions!.contains(decision)) &&
            (allowAccepted || decision != MallaProposalDecision.accepted))
          PopupMenuItem(
            value: decision,
            child: Row(
              children: [
                Icon(_decisionIcon(decision), size: 19),
                const SizedBox(width: 8),
                Expanded(child: Text(_label(decision))),
              ],
            ),
          ),
    ],
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _decisionColor(value).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(_decisionIcon(value), size: 18, color: _decisionColor(value)),
    ),
  );
}

IconData _decisionIcon(MallaProposalDecision decision) => switch (decision) {
  MallaProposalDecision.suggested => Icons.auto_awesome_outlined,
  MallaProposalDecision.pending => Icons.fact_check_outlined,
  MallaProposalDecision.accepted => Icons.check_circle_outline_rounded,
  MallaProposalDecision.rejected => Icons.cancel_outlined,
};

Color _decisionColor(MallaProposalDecision decision) => switch (decision) {
  MallaProposalDecision.suggested => const Color(0xFF5B5FEF),
  MallaProposalDecision.pending => const Color(0xFFB26A00),
  MallaProposalDecision.accepted => const Color(0xFF18864B),
  MallaProposalDecision.rejected => const Color(0xFFB3261E),
};
