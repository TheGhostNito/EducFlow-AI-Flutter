import 'package:flutter/material.dart';

import '../../../models/malla_curricular.dart';
import '../../../models/malla_import_review.dart';
import '../../../models/malla_multimodal_review.dart';

class MallaCourseAcademicDetails extends StatelessWidget {
  const MallaCourseAcademicDetails({
    super.key,
    required this.review,
    required this.course,
    required this.spanish,
    this.onDecidePrerequisite,
  });

  final MallaImportReview review;
  final RamoMalla course;
  final bool spanish;
  final Future<bool> Function(
    MallaPrerequisiteProposal prerequisite,
    MallaProposalDecision decision,
  )?
  onDecidePrerequisite;

  String _t(String es, String en) => spanish ? es : en;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = _categoryLabel(_persistedCategory());
    final prerequisites =
        review.prerequisites
            .where(
              (item) =>
                  item.courseId == course.id &&
                  item.decision != MallaProposalDecision.rejected,
            )
            .toList()
          ..sort(
            (left, right) =>
                _decisionOrder(left.decision)
                    .compareTo(_decisionOrder(right.decision)),
          );
    return Column(
      key: const Key('malla-course-academic-details'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (category != null) ...[
          const SizedBox(height: 4),
          Text(_t('Categoría: $category', 'Category: $category')),
        ],
        const SizedBox(height: 18),
        Text(
          _t('Prerrequisitos', 'Prerequisites'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (prerequisites.isEmpty)
          Text(
            _t(
              'No hay prerrequisitos registrados para esta asignatura.',
              'No prerequisites are registered for this course.',
            ),
            key: const Key('malla-course-prerequisites-empty'),
          )
        else
          for (final prerequisite in prerequisites)
            Column(
              key: ValueKey(
                'malla-course-prerequisite-${prerequisite.requiresCourseId}',
              ),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RelationTile(
                  title: review.courseName(prerequisite.requiresCourseId),
                  code: review
                      .courseById(prerequisite.requiresCourseId)
                      ?.codigo,
                  confirmed:
                      prerequisite.decision == MallaProposalDecision.accepted,
                  spanish: spanish,
                ),
                if (prerequisite.decision != MallaProposalDecision.accepted &&
                    onDecidePrerequisite != null)
                  _PendingPrerequisiteAction(
                    review: review,
                    course: course,
                    prerequisite: prerequisite,
                    spanish: spanish,
                    onDecide: onDecidePrerequisite!,
                  ),
              ],
            ),
      ],
    );
  }

  int _decisionOrder(MallaProposalDecision decision) =>
      decision == MallaProposalDecision.accepted ? 0 : 1;

  String? _persistedCategory() {
    final proposal = review.courseChangeFor(course.id);
    if (proposal == null ||
        proposal.decision == MallaProposalDecision.rejected) {
      return null;
    }
    return proposal.review.categoryLabel ?? proposal.review.category;
  }

  String? _categoryLabel(String? value) => switch (value) {
    null => null,
    'specialty' => _t('Especialidad', 'Specialty'),
    'institutional' => _t('Formación institucional', 'Institutional'),
    'mandatory' => _t('Obligatoria', 'Mandatory'),
    'elective' => _t('Electiva', 'Elective'),
    'general' => _t('Formación general', 'General education'),
    'capstone' => _t('Proyecto final', 'Capstone'),
    'other' || 'unknown' => null,
    _ => value,
  };
}

class _PendingPrerequisiteAction extends StatefulWidget {
  const _PendingPrerequisiteAction({
    required this.review,
    required this.course,
    required this.prerequisite,
    required this.spanish,
    required this.onDecide,
  });

  final MallaImportReview review;
  final RamoMalla course;
  final MallaPrerequisiteProposal prerequisite;
  final bool spanish;
  final Future<bool> Function(
    MallaPrerequisiteProposal prerequisite,
    MallaProposalDecision decision,
  )
  onDecide;

  @override
  State<_PendingPrerequisiteAction> createState() =>
      _PendingPrerequisiteActionState();
}

class _PendingPrerequisiteActionState
    extends State<_PendingPrerequisiteAction> {
  bool _saving = false;

  String _t(String es, String en) => widget.spanish ? es : en;

  Future<void> _review() async {
    if (_saving) return;
    final prerequisite = widget.prerequisite;
    final requiredCourse = widget.review.courseById(
      prerequisite.requiresCourseId,
    );
    final decision = await showDialog<MallaProposalDecision>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Revisar prerrequisito', 'Review prerequisite')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t(
                '${widget.course.nombre} depende de ${requiredCourse?.nombre ?? prerequisite.requiresCourseId}.',
                '${widget.course.nombre} depends on ${requiredCourse?.nombre ?? prerequisite.requiresCourseId}.',
              ),
              key: const Key('malla-prerequisite-direction'),
            ),
            if (prerequisite.evidence.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _t(
                  'Evidencia: ${prerequisite.evidence.join(' · ')}',
                  'Evidence: ${prerequisite.evidence.join(' · ')}',
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              _t(
                'La decisión se guardará en tu malla. La evidencia original se conservará.',
                'The decision will be saved to your curriculum. Original evidence will be preserved.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('malla-prerequisite-cancel'),
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_t('Cancelar', 'Cancel')),
          ),
          TextButton(
            key: const Key('malla-prerequisite-reject'),
            onPressed: () =>
                Navigator.pop(dialogContext, MallaProposalDecision.rejected),
            child: Text(_t('Rechazar', 'Reject')),
          ),
          FilledButton(
            key: const Key('malla-prerequisite-confirm'),
            onPressed: () =>
                Navigator.pop(dialogContext, MallaProposalDecision.accepted),
            child: Text(_t('Confirmar', 'Confirm')),
          ),
        ],
      ),
    );
    if (!mounted || decision == null) return;
    setState(() => _saving = true);
    try {
      await widget.onDecide(prerequisite, decision);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: TextButton.icon(
      key: ValueKey(
        'malla-prerequisite-review-${widget.prerequisite.courseId}-${widget.prerequisite.requiresCourseId}',
      ),
      onPressed: _saving ? null : _review,
      icon: _saving
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.fact_check_outlined),
      label: Text(_t('Revisar relación', 'Review relation')),
    ),
  );
}

class MallaCertificationsSection extends StatelessWidget {
  const MallaCertificationsSection({
    super.key,
    required this.review,
    required this.spanish,
    this.onDecideMembership,
  });

  final MallaImportReview review;
  final bool spanish;
  final Future<bool> Function(
    MallaCertificationProposal certification,
    MallaCertificationMembershipProposal membership,
    MallaProposalDecision decision,
  )?
  onDecideMembership;

  String _t(String es, String en) => spanish ? es : en;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final certifications = review.certifications
        .where((item) => item.decision != MallaProposalDecision.rejected)
        .toList();
    return Column(
      key: const Key('malla-certifications-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _t('Certificaciones', 'Certifications'),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          _t(
            'Consulta las certificaciones guardadas y sus asignaturas relacionadas.',
            'View saved certifications and their related courses.',
          ),
        ),
        const SizedBox(height: 12),
        if (certifications.isEmpty)
          Container(
            key: const Key('malla-certifications-empty'),
            padding: const EdgeInsets.all(18),
            decoration: _panelDecoration(theme),
            child: Text(
              _t(
                'No hay certificaciones registradas en esta malla.',
                'No certifications are registered in this curriculum.',
              ),
              textAlign: TextAlign.center,
            ),
          )
        else
          for (final certification in certifications) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                key: ValueKey('malla-certification-${certification.id}'),
                color: theme.brightness == Brightness.dark
                    ? const Color(0xFF191F29)
                    : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: theme.brightness == Brightness.dark
                        ? const Color(0xFF2B323E)
                        : const Color(0xFFE7EAF0),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: Text(
                    certification.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    _decisionLabel(certification.decision),
                    key: ValueKey(
                      'malla-certification-state-${certification.id}',
                    ),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  children: _membershipChildren(certification),
                ),
              ),
            ),
          ],
      ],
    );
  }

  List<Widget> _membershipChildren(MallaCertificationProposal certification) {
    final memberships = certification.memberships
        .where((item) => item.decision != MallaProposalDecision.rejected)
        .toList();
    if (memberships.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            _t(
              'No hay asignaturas confirmadas o pendientes asociadas.',
              'No confirmed or pending courses are associated.',
            ),
            key: ValueKey(
              'malla-certification-memberships-empty-${certification.id}',
            ),
          ),
        ),
      ];
    }
    return [
      for (final membership in memberships)
        Column(
          key: ValueKey(
            'malla-certification-${certification.id}-${membership.courseId}',
          ),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RelationTile(
              title: review.courseName(membership.courseId),
              code: review.courseById(membership.courseId)?.codigo,
              confirmed: membership.decision == MallaProposalDecision.accepted,
              spanish: spanish,
            ),
            if (membership.decision != MallaProposalDecision.accepted &&
                onDecideMembership != null)
              _PendingMembershipAction(
                review: review,
                certification: certification,
                membership: membership,
                spanish: spanish,
                onDecide: onDecideMembership!,
              ),
          ],
        ),
    ];
  }

  String _decisionLabel(MallaProposalDecision decision) =>
      decision == MallaProposalDecision.accepted
      ? _t('Confirmada', 'Confirmed')
      : _t('Por revisar', 'Needs review');

  BoxDecoration _panelDecoration(ThemeData theme) => BoxDecoration(
    color: theme.brightness == Brightness.dark
        ? const Color(0xFF191F29)
        : Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(
      color: theme.brightness == Brightness.dark
          ? const Color(0xFF2B323E)
          : const Color(0xFFE7EAF0),
    ),
  );
}

class _PendingMembershipAction extends StatefulWidget {
  const _PendingMembershipAction({
    required this.review,
    required this.certification,
    required this.membership,
    required this.spanish,
    required this.onDecide,
  });

  final MallaImportReview review;
  final MallaCertificationProposal certification;
  final MallaCertificationMembershipProposal membership;
  final bool spanish;
  final Future<bool> Function(
    MallaCertificationProposal certification,
    MallaCertificationMembershipProposal membership,
    MallaProposalDecision decision,
  )
  onDecide;

  @override
  State<_PendingMembershipAction> createState() =>
      _PendingMembershipActionState();
}

class _PendingMembershipActionState extends State<_PendingMembershipAction> {
  bool _saving = false;

  String _t(String es, String en) => widget.spanish ? es : en;

  Future<void> _review() async {
    if (_saving) return;
    final course = widget.review.courseById(widget.membership.courseId);
    final canConfirm =
        widget.certification.decision == MallaProposalDecision.accepted;
    final decision = await showDialog<MallaProposalDecision>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Revisar membresía', 'Review membership')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t(
                '${course?.nombre ?? widget.membership.courseId} pertenece a ${widget.certification.name}.',
                '${course?.nombre ?? widget.membership.courseId} belongs to ${widget.certification.name}.',
              ),
              key: const Key('malla-membership-direction'),
            ),
            if (course?.codigo != null) ...[
              const SizedBox(height: 6),
              Text(_t('Código: ${course!.codigo}', 'Code: ${course.codigo}')),
            ],
            const SizedBox(height: 6),
            Text(_t('Estado: Por revisar', 'Status: Needs review')),
            if (widget.membership.evidence.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _t(
                  'Evidencia: ${widget.membership.evidence.join(' · ')}',
                  'Evidence: ${widget.membership.evidence.join(' · ')}',
                ),
              ),
            ],
            if (!canConfirm) ...[
              const SizedBox(height: 12),
              Text(
                _t(
                  'Esta membresía no puede confirmarse mientras la certificación principal no esté aceptada.',
                  'This membership cannot be confirmed until its parent certification is accepted.',
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              _t(
                'La decisión se guardará en tu malla. La evidencia original se conservará.',
                'The decision will be saved to your curriculum. Original evidence will be preserved.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('malla-membership-cancel'),
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_t('Cancelar', 'Cancel')),
          ),
          TextButton(
            key: const Key('malla-membership-reject'),
            onPressed: () =>
                Navigator.pop(dialogContext, MallaProposalDecision.rejected),
            child: Text(_t('Rechazar', 'Reject')),
          ),
          if (canConfirm)
            FilledButton(
              key: const Key('malla-membership-confirm'),
              onPressed: () =>
                  Navigator.pop(dialogContext, MallaProposalDecision.accepted),
              child: Text(_t('Confirmar', 'Confirm')),
            ),
        ],
      ),
    );
    if (!mounted || decision == null) return;
    setState(() => _saving = true);
    try {
      await widget.onDecide(widget.certification, widget.membership, decision);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: TextButton.icon(
      key: ValueKey(
        'malla-membership-review-${widget.certification.id}-${widget.membership.courseId}',
      ),
      onPressed: _saving ? null : _review,
      icon: _saving
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.fact_check_outlined),
      label: Text(_t('Revisar relación', 'Review relation')),
    ),
  );
}

class MallaAcademicRequirementsSection extends StatelessWidget {
  const MallaAcademicRequirementsSection({
    super.key,
    required this.review,
    required this.spanish,
    this.onDecideRequirement,
    this.onEditRequirement,
  });

  final MallaImportReview review;
  final bool spanish;
  final Future<bool> Function(
    MallaAcademicRequirementProposal proposal,
    MallaProposalDecision decision,
  )?
  onDecideRequirement;
  final ValueChanged<MallaAcademicRequirementProposal>? onEditRequirement;

  String _t(String es, String en) => spanish ? es : en;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final requirements = review.academicRequirements;
    return Column(
      key: const Key('malla-academic-requirements-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _t('Requisitos académicos', 'Academic requirements'),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          _t(
            'Consulta condiciones especiales guardadas sin convertirlas en prerrequisitos entre asignaturas.',
            'View saved special conditions without treating them as course prerequisites.',
          ),
        ),
        const SizedBox(height: 12),
        if (requirements.isEmpty)
          Container(
            key: const Key('malla-academic-requirements-empty'),
            padding: const EdgeInsets.all(18),
            decoration: _panelDecoration(theme),
            child: Text(
              _t(
                'No hay requisitos académicos especiales registrados.',
                'No special academic requirements are registered.',
              ),
              textAlign: TextAlign.center,
            ),
          )
        else
          for (final proposal in requirements) ...[
            Builder(
              builder: (_) {
                final target = _requirementTarget(proposal.requirement);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    key: ValueKey(
                      'malla-academic-requirement-${proposal.requirement.id}',
                    ),
                    color: theme.brightness == Brightness.dark
                        ? const Color(0xFF191F29)
                        : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: theme.brightness == Brightness.dark
                            ? const Color(0xFF2B323E)
                            : const Color(0xFFE7EAF0),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ExpansionTile(
                      leading: const Icon(Icons.rule_folder_outlined),
                      title: Text(
                        _requirementType(proposal.requirement.type),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (target != null) Text(target),
                          Text(_decisionLabel(proposal.decision)),
                        ],
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      children: _requirementChildren(proposal),
                    ),
                  ),
                );
              },
            ),
          ],
      ],
    );
  }

  List<Widget> _requirementChildren(MallaAcademicRequirementProposal proposal) {
    final requirement = proposal.requirement;
    final target = _requirementTarget(requirement);
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(requirement.description),
      ),
      if (target != null) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _t('Asignatura relacionada: $target', 'Related course: $target'),
          ),
        ),
      ],
      if (requirement.minimumLevel != null) ...[
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _t(
              'Nivel mínimo: ${requirement.minimumLevel}',
              'Minimum level: ${requirement.minimumLevel}',
            ),
          ),
        ),
      ],
      if (requirement.evidence.isNotEmpty) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _t(
              'Evidencia: ${requirement.evidence.join(' · ')}',
              'Evidence: ${requirement.evidence.join(' · ')}',
            ),
          ),
        ),
      ],
      if (onEditRequirement != null) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: ValueKey('malla-edit-requirement-${requirement.id}'),
            onPressed: () => onEditRequirement!(proposal),
            icon: const Icon(Icons.edit_outlined),
            label: Text(_t('Corregir', 'Edit')),
          ),
        ),
      ],
      if (proposal.decision == MallaProposalDecision.pending ||
          proposal.decision == MallaProposalDecision.suggested)
        _PendingRequirementAction(
          review: review,
          proposal: proposal,
          spanish: spanish,
          onDecide: onDecideRequirement,
        ),
    ];
  }

  String? _requirementTarget(MallaAcademicRequirement requirement) {
    final course = requirement.targetCourseId == null
        ? null
        : review.courseById(requirement.targetCourseId!);
    return course == null
        ? requirement.targetLabel
        : course.codigo == null
        ? course.nombre
        : '${course.nombre} (${course.codigo})';
  }

  String _requirementType(String value) => switch (value) {
    'approved_level' => _t('Niveles aprobados', 'Approved levels'),
    'completed_periods' => _t('Períodos completados', 'Completed periods'),
    'practice_eligibility' => _t('Acceso a práctica', 'Practice eligibility'),
    'capstone_eligibility' => _t('Acceso a Capstone', 'Capstone eligibility'),
    'other' => _t('Otro requisito', 'Other requirement'),
    _ => _t('Tipo por comprobar', 'Type to verify'),
  };

  String _decisionLabel(MallaProposalDecision decision) => switch (decision) {
    MallaProposalDecision.accepted => _t('Confirmado', 'Confirmed'),
    MallaProposalDecision.rejected => _t('Rechazado', 'Rejected'),
    MallaProposalDecision.suggested ||
    MallaProposalDecision.pending => _t('Por revisar', 'Needs review'),
  };

  BoxDecoration _panelDecoration(ThemeData theme) => BoxDecoration(
    color: theme.brightness == Brightness.dark
        ? const Color(0xFF191F29)
        : Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(
      color: theme.brightness == Brightness.dark
          ? const Color(0xFF2B323E)
          : const Color(0xFFE7EAF0),
    ),
  );
}

class _PendingRequirementAction extends StatefulWidget {
  const _PendingRequirementAction({
    required this.review,
    required this.proposal,
    required this.spanish,
    required this.onDecide,
  });

  final MallaImportReview review;
  final MallaAcademicRequirementProposal proposal;
  final bool spanish;
  final Future<bool> Function(
    MallaAcademicRequirementProposal proposal,
    MallaProposalDecision decision,
  )?
  onDecide;

  @override
  State<_PendingRequirementAction> createState() =>
      _PendingRequirementActionState();
}

class _PendingRequirementActionState extends State<_PendingRequirementAction> {
  bool _saving = false;

  String _t(String es, String en) => widget.spanish ? es : en;

  Future<void> _review() async {
    final onDecide = widget.onDecide;
    if (_saving || onDecide == null) return;
    final requirement = widget.proposal.requirement;
    final course = requirement.targetCourseId == null
        ? null
        : widget.review.courseById(requirement.targetCourseId!);
    final target = course?.nombre ?? requirement.targetLabel;
    final canConfirm = requirement.type.trim().toLowerCase() != 'unknown';
    final decision = await showDialog<MallaProposalDecision>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Revisar requisito', 'Review requirement')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(requirement.description),
            if (target != null) ...[
              const SizedBox(height: 8),
              Text(_t('Relacionado con: $target', 'Related to: $target')),
            ],
            if (requirement.evidence.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _t(
                  'Evidencia: ${requirement.evidence.join(' · ')}',
                  'Evidence: ${requirement.evidence.join(' · ')}',
                ),
              ),
            ],
            if (!canConfirm) ...[
              const SizedBox(height: 12),
              Text(
                _t(
                  'Este requisito no puede confirmarse mientras su tipo siga sin identificar.',
                  'This requirement cannot be confirmed while its type remains unidentified.',
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              _t(
                'La decisión se guardará sin convertir esta condición en un prerrequisito entre asignaturas.',
                'The decision will be saved without turning this condition into a course prerequisite.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('malla-requirement-cancel'),
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_t('Cancelar', 'Cancel')),
          ),
          TextButton(
            key: const Key('malla-requirement-reject'),
            onPressed: () =>
                Navigator.pop(dialogContext, MallaProposalDecision.rejected),
            child: Text(_t('Rechazar', 'Reject')),
          ),
          if (canConfirm)
            FilledButton(
              key: const Key('malla-requirement-confirm'),
              onPressed: () =>
                  Navigator.pop(dialogContext, MallaProposalDecision.accepted),
              child: Text(_t('Confirmar', 'Confirm')),
            ),
        ],
      ),
    );
    if (!mounted || decision == null) return;
    setState(() => _saving = true);
    try {
      await onDecide(widget.proposal, decision);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: TextButton.icon(
      key: ValueKey(
        'malla-requirement-review-${widget.proposal.requirement.id}',
      ),
      onPressed: _saving || widget.onDecide == null ? null : _review,
      icon: _saving
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.fact_check_outlined),
      label: Text(_t('Revisar condición', 'Review condition')),
    ),
  );
}

class _RelationTile extends StatelessWidget {
  const _RelationTile({
    required this.title,
    required this.code,
    required this.confirmed,
    required this.spanish,
  });

  final String title;
  final String? code;
  final bool confirmed;
  final bool spanish;

  String _t(String es, String en) => spanish ? es : en;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    leading: Icon(
      confirmed ? Icons.check_circle_outline : Icons.schedule_outlined,
      color: confirmed
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.tertiary,
    ),
    title: Text(title),
    subtitle: code == null ? null : Text(_t('Código: $code', 'Code: $code')),
    trailing: Text(
      confirmed ? _t('Confirmado', 'Confirmed') : _t('Por revisar', 'Review'),
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}
