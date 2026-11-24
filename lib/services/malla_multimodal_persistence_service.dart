import 'dart:collection';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/malla_curricular.dart';
import '../models/malla_import_review.dart';
import '../models/malla_multimodal_review.dart';

class MallaMultimodalValidationException implements Exception {
  const MallaMultimodalValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MallaMultimodalIntegrityException extends FormatException {
  MallaMultimodalIntegrityException({
    required this.fileNameMismatch,
    required this.differencePaths,
  }) : super(
         'Supabase guardó la malla, pero la recuperación no superó la comprobación de integridad.',
       );

  final bool fileNameMismatch;
  final List<String> differencePaths;
}

class MallaCertificationBatchSelection {
  const MallaCertificationBatchSelection({
    required this.certification,
    required this.memberships,
  });

  final MallaCertificationProposal certification;
  final List<MallaCertificationMembershipProposal> memberships;
}

class MallaMultimodalPersistenceConfig {
  const MallaMultimodalPersistenceConfig({
    required this.requested,
    required this.expectedFirebaseProjectId,
    required this.expectedSupabaseProjectRef,
  });

  static const environment = MallaMultimodalPersistenceConfig(
    requested: bool.fromEnvironment('EDUFLOW_MULTIMODAL_PERSISTENCE_ENABLED'),
    expectedFirebaseProjectId: String.fromEnvironment(
      'EDUFLOW_MULTIMODAL_FIREBASE_PROJECT_ID',
    ),
    expectedSupabaseProjectRef: String.fromEnvironment(
      'EDUFLOW_MULTIMODAL_SUPABASE_PROJECT_REF',
    ),
  );

  final bool requested;
  final String expectedFirebaseProjectId;
  final String expectedSupabaseProjectRef;

  bool allows({
    required String firebaseProjectId,
    required String supabaseProjectRef,
  }) =>
      requested &&
      expectedFirebaseProjectId.isNotEmpty &&
      expectedSupabaseProjectRef.isNotEmpty &&
      expectedFirebaseProjectId == firebaseProjectId &&
      expectedSupabaseProjectRef == supabaseProjectRef;
}

abstract interface class MallaMultimodalRpcClient {
  Future<dynamic> invoke(String function, Map<String, dynamic> params);
}

class SupabaseMallaMultimodalRpcClient implements MallaMultimodalRpcClient {
  SupabaseMallaMultimodalRpcClient(this._client);

  final SupabaseClient _client;

  @override
  Future<dynamic> invoke(String function, Map<String, dynamic> params) =>
      _client.rpc<dynamic>(function, params: params);
}

class MallaMultimodalPersistenceRepository {
  factory MallaMultimodalPersistenceRepository({
    required MallaMultimodalRpcClient rpc,
    required String? Function() uidProvider,
    required String Function() firebaseProjectIdProvider,
    required String supabaseProjectRef,
    MallaMultimodalPersistenceConfig config =
        MallaMultimodalPersistenceConfig.environment,
    MallaMultimodalPersistenceCodec? codec,
  }) => MallaMultimodalPersistenceRepository._(
    rpc,
    uidProvider,
    firebaseProjectIdProvider,
    supabaseProjectRef,
    config,
    codec ?? const MallaMultimodalPersistenceCodec(),
  );

  MallaMultimodalPersistenceRepository._(
    this._rpc,
    this._uidProvider,
    this._firebaseProjectIdProvider,
    this._supabaseProjectRef,
    this.config,
    this._codec,
  );

  final MallaMultimodalRpcClient _rpc;
  final String? Function() _uidProvider;
  final String Function() _firebaseProjectIdProvider;
  final String _supabaseProjectRef;
  final MallaMultimodalPersistenceCodec _codec;
  final MallaMultimodalPersistenceConfig config;
  bool _saving = false;
  bool _managingReview = false;
  bool _deleting = false;

  bool get enabled => config.allows(
    firebaseProjectId: _firebaseProjectIdProvider(),
    supabaseProjectRef: _supabaseProjectRef,
  );

  Future<MallaImportReview> confirm(MallaImportReview review) async {
    final uid = _requireEnabledUid();
    if (_saving || _managingReview || _deleting) {
      throw StateError('Ya hay una importación multimodal en curso.');
    }
    _saving = true;
    try {
      final expectedPayload = _codec.encode(review);
      final expectedFileName = _codec.normalizeFileName(
        review.malla.archivoNombre,
      );
      final result = await _rpc.invoke('confirmar_malla_multimodal', {
        'p_expected_uid': uid,
        'p_archivo_nombre': expectedFileName,
        'p_malla': expectedPayload,
      });
      _ensureSession(uid);
      final saved = await _loadFor(uid);
      if (saved == null ||
          result == null ||
          saved.malla.id != result.toString()) {
        throw const FormatException(
          'Supabase no devolvió la malla multimodal confirmada.',
        );
      }
      final actualPayload = _codec.encode(saved);
      final differencePaths = _codec.differencePaths(
        expectedPayload,
        actualPayload,
      );
      final fileNameMismatch = saved.malla.archivoNombre != expectedFileName;
      if (fileNameMismatch || differencePaths.isNotEmpty) {
        throw MallaMultimodalIntegrityException(
          fileNameMismatch: fileNameMismatch,
          differencePaths: differencePaths,
        );
      }
      return saved;
    } finally {
      _saving = false;
    }
  }

  Future<MallaImportReview?> load() async {
    final uid = _requireEnabledUid();
    return _loadFor(uid);
  }

  Future<MallaImportReview> confirmRelationshipBatch({
    required MallaImportReview review,
    List<MallaPrerequisiteProposal> prerequisites = const [],
    List<MallaCertificationBatchSelection> certifications = const [],
  }) async {
    final mallaId = review.malla.id;
    if (mallaId.isEmpty) {
      throw ArgumentError('La malla guardada no es válida.');
    }
    final prerequisiteKeys = <String>{};
    for (final proposal in prerequisites) {
      final key = '${proposal.courseId}>${proposal.requiresCourseId}';
      if (!review.prerequisites.contains(proposal) ||
          proposal.decision != MallaProposalDecision.suggested ||
          !prerequisiteKeys.add(key)) {
        throw ArgumentError(
          'El lote contiene un prerrequisito no sugerido o duplicado.',
        );
      }
    }
    final certificationIds = <String>{};
    final membershipKeys = <String>{};
    for (final selection in certifications) {
      final certification = selection.certification;
      if (!review.certifications.contains(certification) ||
          !certificationIds.add(certification.id) ||
          (certification.decision != MallaProposalDecision.suggested &&
              certification.decision != MallaProposalDecision.accepted)) {
        throw ArgumentError(
          'El lote contiene una certificación no confirmable o duplicada.',
        );
      }
      for (final membership in selection.memberships) {
        final key = '${certification.id}:${membership.courseId}';
        if (!certification.memberships.contains(membership) ||
            membership.decision != MallaProposalDecision.suggested ||
            !membershipKeys.add(key)) {
          throw ArgumentError(
            'El lote contiene una membresía no sugerida o duplicada.',
          );
        }
      }
      if (certification.decision == MallaProposalDecision.accepted &&
          selection.memberships.isEmpty) {
        throw ArgumentError('El lote de certificación no contiene cambios.');
      }
    }
    if (prerequisites.isEmpty && certifications.isEmpty) {
      throw ArgumentError('Selecciona al menos una relación sugerida.');
    }
    final uid = _requireEnabledUid();
    if (_saving || _managingReview || _deleting) {
      throw StateError('Ya hay una decisión de revisión en curso.');
    }
    _managingReview = true;
    try {
      final result = await _rpc.invoke('gestionar_revision_malla_multimodal', {
        'p_expected_uid': uid,
        'p_malla_id': mallaId,
        'p_cambios': {
          'prerequisites': [
            for (final proposal in prerequisites)
              {
                'course_id': proposal.courseId,
                'requires_course_id': proposal.requiresCourseId,
                'result_course_id': proposal.courseId,
                'result_requires_course_id': proposal.requiresCourseId,
                'decision': MallaProposalDecision.accepted.name,
              },
          ],
          'certifications': [
            for (final selection in certifications)
              if (selection.certification.decision ==
                  MallaProposalDecision.suggested)
                {
                  'id': selection.certification.id,
                  'decision': MallaProposalDecision.accepted.name,
                },
          ],
          'memberships': [
            for (final selection in certifications)
              for (final membership in selection.memberships)
                {
                  'certification_id': selection.certification.id,
                  'course_id': membership.courseId,
                  'decision': MallaProposalDecision.accepted.name,
                },
          ],
          'academic_requirements': <dynamic>[],
          'pending_items': <dynamic>[],
        },
      });
      _ensureSession(uid);
      if (result is! Map || result['malla_id']?.toString() != mallaId) {
        throw const FormatException(
          'Supabase no confirmó la gestión agrupada de relaciones.',
        );
      }
      final saved = await _loadFor(uid);
      if (saved == null || saved.malla.id != mallaId) {
        throw const FormatException(
          'No se pudo recuperar la malla después de la confirmación agrupada.',
        );
      }
      for (final proposal in prerequisites) {
        final matches = saved.prerequisites.where(
          (item) =>
              item.courseId == proposal.courseId &&
              item.requiresCourseId == proposal.requiresCourseId &&
              item.decision == MallaProposalDecision.accepted,
        );
        if (matches.length != 1) {
          throw const FormatException(
            'Un prerrequisito agrupado no quedó confirmado.',
          );
        }
      }
      for (final selection in certifications) {
        final matches = saved.certifications.where(
          (item) => item.id == selection.certification.id,
        );
        if (matches.length != 1 ||
            matches.single.decision != MallaProposalDecision.accepted) {
          throw const FormatException(
            'Una certificación agrupada no quedó confirmada.',
          );
        }
        for (final membership in selection.memberships) {
          final membershipMatches = matches.single.memberships.where(
            (item) =>
                item.courseId == membership.courseId &&
                item.decision == MallaProposalDecision.accepted,
          );
          if (membershipMatches.length != 1) {
            throw const FormatException(
              'Una membresía agrupada no quedó confirmada.',
            );
          }
        }
      }
      return saved;
    } finally {
      _managingReview = false;
    }
  }

  Future<MallaImportReview> decidePrerequisite({
    required String mallaId,
    required String courseId,
    required String requiresCourseId,
    required MallaProposalDecision decision,
  }) async {
    if (decision != MallaProposalDecision.accepted &&
        decision != MallaProposalDecision.rejected) {
      throw ArgumentError(
        'Solo se puede confirmar o rechazar un prerrequisito.',
      );
    }
    if (mallaId.isEmpty || courseId.isEmpty || requiresCourseId.isEmpty) {
      throw ArgumentError('La relación de prerrequisito está incompleta.');
    }
    final uid = _requireEnabledUid();
    if (_saving || _managingReview || _deleting) {
      throw StateError('Ya hay una decisión de revisión en curso.');
    }
    _managingReview = true;
    try {
      final result = await _rpc.invoke('gestionar_revision_malla_multimodal', {
        'p_expected_uid': uid,
        'p_malla_id': mallaId,
        'p_cambios': {
          'prerequisites': [
            {
              'course_id': courseId,
              'requires_course_id': requiresCourseId,
              'result_course_id': courseId,
              'result_requires_course_id': requiresCourseId,
              'decision': decision.name,
            },
          ],
          'certifications': <dynamic>[],
          'memberships': <dynamic>[],
          'academic_requirements': <dynamic>[],
          'pending_items': <dynamic>[],
        },
      });
      _ensureSession(uid);
      if (result is! Map || result['malla_id']?.toString() != mallaId) {
        throw const FormatException(
          'Supabase no confirmó la gestión del prerrequisito.',
        );
      }
      final saved = await _loadFor(uid);
      if (saved == null || saved.malla.id != mallaId) {
        throw const FormatException(
          'No se pudo recuperar la malla después de la decisión.',
        );
      }
      final matches = saved.prerequisites.where(
        (item) =>
            item.courseId == courseId &&
            item.requiresCourseId == requiresCourseId &&
            item.decision == decision,
      );
      if (matches.length != 1) {
        throw const FormatException(
          'La decisión del prerrequisito no quedó reflejada en la malla.',
        );
      }
      return saved;
    } finally {
      _managingReview = false;
    }
  }

  Future<MallaImportReview> decideMembership({
    required String mallaId,
    required String certificationId,
    required String courseId,
    required MallaProposalDecision decision,
  }) async {
    if (decision != MallaProposalDecision.accepted &&
        decision != MallaProposalDecision.rejected) {
      throw ArgumentError('Solo se puede confirmar o rechazar una membresía.');
    }
    if (mallaId.isEmpty || certificationId.isEmpty || courseId.isEmpty) {
      throw ArgumentError('La membresía de certificación está incompleta.');
    }
    final uid = _requireEnabledUid();
    if (_saving || _managingReview || _deleting) {
      throw StateError('Ya hay una decisión de revisión en curso.');
    }
    _managingReview = true;
    try {
      final result = await _rpc.invoke('gestionar_revision_malla_multimodal', {
        'p_expected_uid': uid,
        'p_malla_id': mallaId,
        'p_cambios': {
          'prerequisites': <dynamic>[],
          'certifications': <dynamic>[],
          'memberships': [
            {
              'certification_id': certificationId,
              'course_id': courseId,
              'decision': decision.name,
            },
          ],
          'academic_requirements': <dynamic>[],
          'pending_items': <dynamic>[],
        },
      });
      _ensureSession(uid);
      if (result is! Map || result['malla_id']?.toString() != mallaId) {
        throw const FormatException(
          'Supabase no confirmó la gestión de la membresía.',
        );
      }
      final saved = await _loadFor(uid);
      if (saved == null || saved.malla.id != mallaId) {
        throw const FormatException(
          'No se pudo recuperar la malla después de la decisión.',
        );
      }
      final certifications = saved.certifications.where(
        (item) => item.id == certificationId,
      );
      if (certifications.length != 1) {
        throw const FormatException(
          'La certificación actualizada no está disponible.',
        );
      }
      final matches = certifications.single.memberships.where(
        (item) => item.courseId == courseId && item.decision == decision,
      );
      if (matches.length != 1) {
        throw const FormatException(
          'La decisión de la membresía no quedó reflejada en la malla.',
        );
      }
      return saved;
    } finally {
      _managingReview = false;
    }
  }

  Future<MallaImportReview> decideAcademicRequirement({
    required String mallaId,
    required String requirementId,
    required String type,
    required MallaProposalDecision decision,
  }) async {
    if (decision != MallaProposalDecision.accepted &&
        decision != MallaProposalDecision.rejected) {
      throw ArgumentError(
        'Solo se puede confirmar o rechazar un requisito académico.',
      );
    }
    final normalizedType = type.trim();
    if (mallaId.isEmpty || requirementId.isEmpty || normalizedType.isEmpty) {
      throw ArgumentError('El requisito académico está incompleto.');
    }
    if (decision == MallaProposalDecision.accepted &&
        normalizedType.toLowerCase() == 'unknown') {
      throw const MallaMultimodalValidationException(
        'Un requisito desconocido no puede confirmarse.',
      );
    }
    final uid = _requireEnabledUid();
    if (_saving || _managingReview || _deleting) {
      throw StateError('Ya hay una decisión de revisión en curso.');
    }
    _managingReview = true;
    try {
      final result = await _rpc.invoke('gestionar_revision_malla_multimodal', {
        'p_expected_uid': uid,
        'p_malla_id': mallaId,
        'p_cambios': {
          'prerequisites': <dynamic>[],
          'certifications': <dynamic>[],
          'memberships': <dynamic>[],
          'academic_requirements': [
            {
              'id': requirementId,
              'type': normalizedType,
              'decision': decision.name,
            },
          ],
          'pending_items': <dynamic>[],
        },
      });
      _ensureSession(uid);
      if (result is! Map || result['malla_id']?.toString() != mallaId) {
        throw const FormatException(
          'Supabase no confirmó la gestión del requisito académico.',
        );
      }
      final saved = await _loadFor(uid);
      if (saved == null || saved.malla.id != mallaId) {
        throw const FormatException(
          'No se pudo recuperar la malla después de la decisión.',
        );
      }
      final matches = saved.academicRequirements.where(
        (item) =>
            item.requirement.id == requirementId &&
            item.requirement.type == normalizedType &&
            item.decision == decision,
      );
      if (matches.length != 1) {
        throw const FormatException(
          'La decisión del requisito no quedó reflejada en la malla.',
        );
      }
      return saved;
    } finally {
      _managingReview = false;
    }
  }

  Future<MallaImportReview> confirmCourseWithoutCode({
    required String mallaId,
    required String courseId,
  }) async {
    if (mallaId.isEmpty || courseId.isEmpty) {
      throw ArgumentError('La asignatura que se confirmará está incompleta.');
    }
    final uid = _requireEnabledUid();
    if (_saving || _managingReview || _deleting) {
      throw StateError('Ya hay una decisión de revisión en curso.');
    }
    _managingReview = true;
    try {
      final result = await _rpc.invoke('confirmar_ramo_sin_codigo_malla', {
        'p_expected_uid': uid,
        'p_malla_id': mallaId,
        'p_ramo_id': courseId,
      });
      _ensureSession(uid);
      if (result is! Map ||
          result['malla_id']?.toString() != mallaId ||
          result['ramo_id']?.toString() != courseId) {
        throw const FormatException(
          'Supabase no confirmó la asignatura sin código.',
        );
      }
      final saved = await _loadFor(uid);
      final course = saved?.courseById(courseId);
      if (saved == null ||
          saved.malla.id != mallaId ||
          course == null ||
          course.codigo != null ||
          course.motivosRevision.contains('code_missing')) {
        throw const FormatException(
          'La confirmación sin código no quedó reflejada en la malla.',
        );
      }
      return saved;
    } finally {
      _managingReview = false;
    }
  }

  Future<MallaImportReview> updateAcademicRequirement({
    required String mallaId,
    required MallaAcademicRequirement requirement,
    required String description,
    required int? minimumLevel,
  }) async {
    final normalizedDescription = description.trim();
    if (mallaId.isEmpty || requirement.id.isEmpty) {
      throw ArgumentError('El requisito académico está incompleto.');
    }
    if (normalizedDescription.isEmpty || normalizedDescription.length > 1000) {
      throw ArgumentError(
        'La descripción debe tener entre 1 y 1000 caracteres.',
      );
    }
    if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(normalizedDescription)) {
      throw ArgumentError('La descripción contiene caracteres no válidos.');
    }
    if (minimumLevel != null && (minimumLevel < 1 || minimumLevel > 30)) {
      throw ArgumentError('El nivel mínimo debe estar entre 1 y 30.');
    }
    final uid = _requireEnabledUid();
    if (_saving || _managingReview || _deleting) {
      throw StateError('Ya hay una decisión de revisión en curso.');
    }
    _managingReview = true;
    try {
      final result = await _rpc.invoke('editar_requisito_academico_malla', {
        'p_expected_uid': uid,
        'p_malla_id': mallaId,
        'p_requisito_id': requirement.id,
        'p_descripcion': normalizedDescription,
        'p_nivel_minimo': minimumLevel,
      });
      _ensureSession(uid);
      if (result is! Map ||
          result['malla_id']?.toString() != mallaId ||
          result['requisito_id']?.toString() != requirement.id) {
        throw const FormatException(
          'Supabase no confirmó la edición del requisito académico.',
        );
      }
      final saved = await _loadFor(uid);
      final matches = saved?.academicRequirements.where(
        (item) => item.requirement.id == requirement.id,
      );
      if (saved == null ||
          saved.malla.id != mallaId ||
          matches == null ||
          matches.length != 1) {
        throw const FormatException(
          'No se recuperó el requisito académico editado.',
        );
      }
      final updated = matches.single;
      final value = updated.requirement;
      if (value.description != normalizedDescription ||
          value.minimumLevel != minimumLevel ||
          value.type != requirement.type ||
          value.targetCourseId != requirement.targetCourseId ||
          value.targetLabel != requirement.targetLabel ||
          value.source != requirement.source ||
          !_sameStrings(value.evidence, requirement.evidence) ||
          updated.decision != MallaProposalDecision.pending ||
          !value.pendingReasons.contains('manual_confirmation_required')) {
        throw const FormatException(
          'La edición alteró datos protegidos o no quedó pendiente de revisión.',
        );
      }
      return saved;
    } finally {
      _managingReview = false;
    }
  }

  static bool _sameStrings(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  Future<void> deleteConfirmed(String mallaId) async {
    if (mallaId.isEmpty) {
      throw ArgumentError('La malla que se eliminará no es válida.');
    }
    final uid = _requireEnabledUid();
    if (_saving || _managingReview || _deleting) {
      throw StateError('Ya hay una operación de malla en curso.');
    }
    _deleting = true;
    try {
      final result = await _rpc.invoke('eliminar_malla_curricular_confirmada', {
        'p_expected_uid': uid,
        'p_malla_id': mallaId,
      });
      _ensureSession(uid);
      if (result?.toString() != mallaId) {
        throw const FormatException(
          'Supabase no confirmó la eliminación de la malla.',
        );
      }
      try {
        final remaining = await _loadFor(uid);
        if (remaining != null) {
          throw const FormatException(
            'La malla continúa disponible después de eliminarla.',
          );
        }
      } on PostgrestException catch (error) {
        _ensureSession(uid);
        if (error.code != 'P0002') rethrow;
      }
    } finally {
      _deleting = false;
    }
  }

  Future<MallaImportReview?> _loadFor(String uid) async {
    final response = await _rpc.invoke('obtener_malla_multimodal', {
      'p_expected_uid': uid,
    });
    _ensureSession(uid);
    if (response == null) return null;
    if (response is! Map) {
      throw const FormatException(
        'Supabase devolvió una malla multimodal con formato inválido.',
      );
    }
    return _codec.decode(Map<String, dynamic>.from(response));
  }

  String _requireEnabledUid() {
    if (!enabled) {
      throw StateError(
        'La persistencia multimodal no está habilitada para este entorno.',
      );
    }
    final uid = _uidProvider();
    if (uid == null || uid.isEmpty) {
      throw StateError('Inicia sesión antes de guardar tu malla.');
    }
    return uid;
  }

  void _ensureSession(String uid) {
    if (_uidProvider() != uid) {
      throw StateError('La sesión cambió durante la operación multimodal.');
    }
  }
}

class MallaMultimodalPersistenceCodec {
  const MallaMultimodalPersistenceCodec();

  Map<String, dynamic> encode(MallaImportReview review) {
    if (review.malla.ramos.isEmpty) {
      throw const MallaMultimodalValidationException(
        'La malla debe contener al menos una asignatura.',
      );
    }
    var pendingId = 0;
    String nextPendingId() => 'pending_${++pendingId}';
    final pendingItems = <Map<String, dynamic>>[];

    final courses = <Map<String, dynamic>>[];
    for (final course in review.malla.ramos) {
      final reasons = <String>{...course.motivosRevision};
      final change = review.courseChangeFor(course.id);
      if (change?.decision == MallaProposalDecision.pending) {
        reasons.addAll(change!.attentionReasons);
      }
      final source = review.sourceFor(course.id).name;
      final reviewState = reasons.isNotEmpty
          ? reasons.any(
                  const {
                    'code_missing',
                    'credits_missing',
                    'semester_uncertain',
                  }.contains,
                )
                ? 'incomplete'
                : 'pending'
          : review.wasManuallyEdited(course.id)
          ? 'manual'
          : 'confirmed';
      final evidence = review.evidenceFor(course.id);
      courses.add({
        'id': course.id,
        'name': course.nombre.trim(),
        'period': course.semestre,
        'code': _nullableText(course.codigo),
        'credits': course.creditos,
        'category': review.categoryFor(course.id),
        'category_label': review.categoryLabelFor(course.id),
        'original_label': change?.originalName ?? course.nombre.trim(),
        'source': source,
        'review_state': reviewState,
        'review_reasons': reasons.toList(),
        'evidence': evidence,
        'academic_state': course.estado,
      });
      if (reasons.isNotEmpty) {
        pendingItems.add({
          'id': nextPendingId(),
          'entity_type': 'course',
          'entity_key': course.id,
          'reasons': reasons.toList(),
          'evidence': evidence,
          'status': 'pending',
          'resolution': null,
        });
      }
    }

    final prerequisites = <Map<String, dynamic>>[];
    for (final proposal in review.prerequisites) {
      final pendingReasons = proposal.decision == MallaProposalDecision.accepted
          ? const <String>[]
          : proposal.pendingReasons;
      _validateAcceptedEvidence(
        decision: proposal.decision,
        evidence: proposal.evidence,
        label: 'prerrequisito',
      );
      prerequisites.add({
        'course_id': proposal.courseId,
        'requires_course_id': proposal.requiresCourseId,
        'source': 'gemini',
        'decision': proposal.decision.name,
        'certainty': proposal.decision == MallaProposalDecision.accepted
            ? 'confirmed'
            : pendingReasons.isNotEmpty
            ? 'uncertain'
            : 'unknown',
        'evidence': proposal.evidence,
        'pending_reasons': pendingReasons,
      });
      if (proposal.decision == MallaProposalDecision.pending) {
        final reasons = pendingReasons.isEmpty
            ? const ['prerequisite_relation_uncertain']
            : pendingReasons;
        pendingItems.add({
          'id': nextPendingId(),
          'entity_type': 'prerequisite',
          'entity_key': '${proposal.courseId}>${proposal.requiresCourseId}',
          'reasons': reasons,
          'evidence': proposal.evidence,
          'status': 'pending',
          'resolution': null,
        });
      }
    }

    final certifications = <Map<String, dynamic>>[];
    for (final certification in review.certifications) {
      final hasAcceptedMembership = certification.memberships.any(
        (item) => item.decision == MallaProposalDecision.accepted,
      );
      final certificationDecision = hasAcceptedMembership
          ? MallaProposalDecision.accepted
          : certification.decision;
      _validateAcceptedEvidence(
        decision: certificationDecision,
        evidence: certification.evidence,
        label: 'certificación',
      );
      final certificationPending =
          certificationDecision == MallaProposalDecision.pending
          ? certification.pendingReasons.isEmpty
                ? const ['certification_uncertain']
                : certification.pendingReasons
          : certificationDecision == MallaProposalDecision.accepted
          ? const <String>[]
          : certification.pendingReasons;
      final memberships = <Map<String, dynamic>>[];
      for (final membership in certification.memberships) {
        _validateAcceptedEvidence(
          decision: membership.decision,
          evidence: membership.evidence,
          label: 'pertenencia a certificación',
        );
        final membershipPending =
            membership.decision == MallaProposalDecision.pending
            ? membership.pendingReasons.isEmpty
                  ? const ['certification_membership_uncertain']
                  : membership.pendingReasons
            : membership.decision == MallaProposalDecision.accepted
            ? const <String>[]
            : membership.pendingReasons;
        memberships.add({
          'course_id': membership.courseId,
          'source': 'gemini',
          'decision': membership.decision.name,
          'basis': membership.basis,
          'evidence': membership.evidence,
          'pending_reasons': membershipPending,
        });
        if (membership.decision == MallaProposalDecision.pending) {
          pendingItems.add({
            'id': nextPendingId(),
            'entity_type': 'membership',
            'entity_key': '${certification.id}:${membership.courseId}',
            'reasons': membershipPending,
            'evidence': membership.evidence,
            'status': 'pending',
            'resolution': null,
          });
        }
      }
      certifications.add({
        'id': certification.id,
        'name': certification.name,
        'source': 'gemini',
        'decision': certificationDecision.name,
        'evidence': certification.evidence,
        'pending_reasons': certificationPending,
        'memberships': memberships,
      });
      if (certificationDecision == MallaProposalDecision.pending) {
        pendingItems.add({
          'id': nextPendingId(),
          'entity_type': 'certification',
          'entity_key': certification.id,
          'reasons': certificationPending,
          'evidence': certification.evidence,
          'status': 'pending',
          'resolution': null,
        });
      }
    }

    final requirements = <Map<String, dynamic>>[];
    for (final proposal in review.academicRequirements) {
      final requirement = proposal.requirement;
      _validateAcceptedEvidence(
        decision: proposal.decision,
        evidence: requirement.evidence,
        label: 'requisito académico',
      );
      if (proposal.decision == MallaProposalDecision.accepted &&
          requirement.type == 'unknown') {
        throw const MallaMultimodalValidationException(
          'Un requisito académico aceptado debe tener un tipo identificado.',
        );
      }
      final pendingReasons = proposal.decision == MallaProposalDecision.pending
          ? requirement.pendingReasons.isEmpty
                ? const ['academic_requirement_uncertain']
                : requirement.pendingReasons
          : proposal.decision == MallaProposalDecision.accepted
          ? const <String>[]
          : requirement.pendingReasons;
      requirements.add({
        'id': requirement.id,
        'type': requirement.type,
        'target_course_id': requirement.targetCourseId,
        'target_label': requirement.targetLabel,
        'description': requirement.description,
        'minimum_level': requirement.minimumLevel,
        'source': requirement.source,
        'decision': proposal.decision.name,
        'evidence': requirement.evidence,
        'pending_reasons': pendingReasons,
      });
      if (proposal.decision == MallaProposalDecision.pending) {
        pendingItems.add({
          'id': nextPendingId(),
          'entity_type': 'requirement',
          'entity_key': requirement.id,
          'reasons': pendingReasons,
          'evidence': requirement.evidence,
          'status': 'pending',
          'resolution': null,
        });
      }
    }

    for (final item in review.unresolvedGlobalPending) {
      pendingItems.add({
        'id': nextPendingId(),
        'entity_type': 'global',
        'entity_key': item,
        'reasons': const ['global_review_required'],
        'evidence': const <String>[],
        'status': 'pending',
        'resolution': null,
      });
    }

    return {
      'period_type': review.periodType,
      'period_count': review.periodCount,
      'courses': courses,
      'prerequisites': prerequisites,
      'certifications': certifications,
      'academic_requirements': requirements,
      'pending_items': pendingItems,
    };
  }

  bool equivalentPayloads(
    Map<String, dynamic> expected,
    Map<String, dynamic> actual,
  ) => differencePaths(expected, actual).isEmpty;

  List<String> differencePaths(
    Map<String, dynamic> expected,
    Map<String, dynamic> actual,
  ) {
    final differences = <String>[];
    _collectDifferencePaths(
      _canonicalPayload(expected),
      _canonicalPayload(actual),
      '',
      differences,
    );
    return List.unmodifiable(differences);
  }

  String? normalizeFileName(String? value) => _nullableText(value);

  static Object? _canonicalPayload(Map<String, dynamic> source) {
    final copy = <String, dynamic>{...source};
    final pending = copy['pending_items'];
    if (pending is List) {
      copy['pending_items'] = [
        for (final value in pending)
          if (value is Map)
            Map<String, dynamic>.from(value)..remove('id')
          else
            value,
      ];
    }
    return _canonicalize(copy);
  }

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final result = SplayTreeMap<String, Object?>();
      for (final entry in value.entries) {
        result[entry.key.toString()] = _canonicalize(entry.value);
      }
      return result;
    }
    if (value is List) {
      final result = [for (final item in value) _canonicalize(item)];
      result.sort((left, right) {
        return jsonEncode(left).compareTo(jsonEncode(right));
      });
      return result;
    }
    return value;
  }

  static void _collectDifferencePaths(
    Object? expected,
    Object? actual,
    String path,
    List<String> differences,
  ) {
    if (expected is Map && actual is Map) {
      final keys = <String>{
        for (final key in expected.keys) key.toString(),
        for (final key in actual.keys) key.toString(),
      }.toList()..sort();
      for (final key in keys) {
        final childPath = path.isEmpty ? key : '$path.$key';
        if (!expected.containsKey(key) || !actual.containsKey(key)) {
          differences.add(childPath);
          continue;
        }
        _collectDifferencePaths(
          expected[key],
          actual[key],
          childPath,
          differences,
        );
      }
      return;
    }
    if (expected is List && actual is List) {
      if (expected.length != actual.length) {
        differences.add(path.isEmpty ? 'length' : '$path.length');
      }
      final sharedLength = expected.length < actual.length
          ? expected.length
          : actual.length;
      for (var index = 0; index < sharedLength; index++) {
        _collectDifferencePaths(
          expected[index],
          actual[index],
          '$path[$index]',
          differences,
        );
      }
      return;
    }
    if (expected != actual) {
      differences.add(path.isEmpty ? 'payload' : path);
    }
  }

  MallaImportReview decode(Map<String, dynamic> root) {
    final coursesJson = _list(root, 'courses');
    final courses = <RamoMalla>[];
    final courseChanges = <MallaCourseChangeProposal>[];
    final geminiIds = <String>{};
    final mergedIds = <String>{};
    final manualIds = <String>{};
    final manuallyEditedIds = <String>{};
    for (final value in coursesJson) {
      final item = _map(value, 'course');
      final id = _text(item, 'id');
      final reasons = _strings(item, 'review_reasons');
      final evidence = _strings(item, 'evidence');
      final course = RamoMalla(
        id: id,
        nombre: _text(item, 'name'),
        semestre: _integer(item, 'period'),
        codigo: _nullableString(item['code'], 'code'),
        creditos: _nullableInteger(item['credits'], 'credits'),
        estado: _text(item, 'academic_state'),
        requiereRevision: reasons.isNotEmpty,
        motivosRevision: reasons,
        codigoDuplicadoVerificado: item['duplicate_code_verified'] == true,
      );
      courses.add(course);
      final source = _text(item, 'source');
      if (source == 'gemini') geminiIds.add(id);
      if (source == 'merged') mergedIds.add(id);
      if (source == 'manual') manualIds.add(id);
      final reviewState = _text(item, 'review_state');
      final proposal = MallaCourseChangeProposal(
        review: MallaCourseReview(
          courseId: id,
          proposedName: course.nombre,
          proposedCode: course.codigo,
          proposedCredits: course.creditos,
          proposedPeriod: course.semestre,
          category: _text(item, 'category'),
          categoryLabel: _nullableString(
            item['category_label'],
            'category_label',
          ),
          prerequisiteStatus: 'unknown',
          evidence: evidence,
          pendingReasons: reasons,
        ),
        originalName:
            _nullableString(item['original_label'], 'original_label') ??
            course.nombre,
        originalCode: course.codigo,
        originalCredits: course.creditos,
        originalPeriod: course.semestre,
        automaticallyAppliedFields: const {},
        attentionReasons: reasons,
      );
      proposal.decision = _courseDecision(reviewState);
      if (reviewState == 'manual' && source != 'manual') {
        manuallyEditedIds.add(id);
      }
      courseChanges.add(proposal);
    }

    final curriculum = MallaCurricular(
      id: _text(root, 'id'),
      archivoNombre: _nullableString(root['file_name'], 'file_name'),
      ramos: courses,
    );
    final review = MallaImportReview(
      malla: curriculum,
      periodType: _text(root, 'period_type'),
      periodCount: _integer(root, 'period_count'),
      periodEvidence: const [],
      geminiCourseIds: geminiIds,
      mergedCourseIds: mergedIds,
      courseChanges: courseChanges,
      prerequisites: [
        for (final value in _list(root, 'prerequisites'))
          _decodePrerequisite(_map(value, 'prerequisite')),
      ],
      certifications: [
        for (final value in _list(root, 'certifications'))
          _decodeCertification(_map(value, 'certification')),
      ],
      academicRequirements: [
        for (final value in _list(root, 'academic_requirements'))
          _decodeRequirement(_map(value, 'academic_requirement')),
      ],
      globalPending: [
        for (final value in _list(root, 'pending_items'))
          if (_map(value, 'pending_item')['entity_type'] == 'global' &&
              _map(value, 'pending_item')['status'] == 'pending')
            _text(_map(value, 'pending_item'), 'entity_key'),
      ],
      deduplicatedAdditionalCourses: const [],
    );
    for (final id in manualIds) {
      review.markManualCourse(id);
    }
    for (final id in manuallyEditedIds) {
      review.markCourseEdited(id);
    }
    return review;
  }

  MallaPrerequisiteProposal _decodePrerequisite(Map<String, dynamic> item) {
    final proposal = MallaPrerequisiteProposal(
      courseId: _text(item, 'course_id'),
      requiresCourseId: _text(item, 'requires_course_id'),
      evidence: _strings(item, 'evidence'),
      pendingReasons: _strings(item, 'pending_reasons'),
    );
    proposal.decision = _decision(item, 'decision');
    return proposal;
  }

  MallaCertificationProposal _decodeCertification(Map<String, dynamic> item) {
    final proposal = MallaCertificationProposal(
      id: _text(item, 'id'),
      name: _text(item, 'name'),
      evidence: _strings(item, 'evidence'),
      pendingReasons: _strings(item, 'pending_reasons'),
      memberships: [
        for (final value in _list(item, 'memberships'))
          _decodeMembership(_map(value, 'membership')),
      ],
    );
    proposal.decision = _decision(item, 'decision');
    return proposal;
  }

  MallaCertificationMembershipProposal _decodeMembership(
    Map<String, dynamic> item,
  ) {
    final proposal = MallaCertificationMembershipProposal(
      courseId: _text(item, 'course_id'),
      basis: _text(item, 'basis'),
      evidence: _strings(item, 'evidence'),
      pendingReasons: _strings(item, 'pending_reasons'),
    );
    proposal.decision = _decision(item, 'decision');
    return proposal;
  }

  MallaAcademicRequirementProposal _decodeRequirement(
    Map<String, dynamic> item,
  ) {
    final proposal = MallaAcademicRequirementProposal(
      requirement: MallaAcademicRequirement(
        id: _text(item, 'id'),
        type: _text(item, 'type'),
        targetCourseId: _nullableString(
          item['target_course_id'],
          'target_course_id',
        ),
        targetLabel: _nullableString(item['target_label'], 'target_label'),
        description: _text(item, 'description'),
        minimumLevel: _nullableInteger(item['minimum_level'], 'minimum_level'),
        evidence: _strings(item, 'evidence'),
        pendingReasons: _strings(item, 'pending_reasons'),
        source: _text(item, 'source'),
      ),
    );
    proposal.decision = _decision(item, 'decision');
    return proposal;
  }

  static void _validateAcceptedEvidence({
    required MallaProposalDecision decision,
    required List<String> evidence,
    required String label,
  }) {
    if (decision == MallaProposalDecision.accepted && evidence.isEmpty) {
      throw MallaMultimodalValidationException(
        'No se puede aceptar $label sin evidencia académica.',
      );
    }
  }

  static MallaProposalDecision _courseDecision(String value) => switch (value) {
    'confirmed' || 'manual' => MallaProposalDecision.accepted,
    'suggested' => MallaProposalDecision.suggested,
    'pending' || 'incomplete' => MallaProposalDecision.pending,
    _ => throw FormatException(
      'Estado de revisión de asignatura inválido: $value',
    ),
  };

  static MallaProposalDecision _decision(
    Map<String, dynamic> item,
    String key,
  ) {
    final value = _text(item, key);
    return MallaProposalDecision.values.firstWhere(
      (decision) => decision.name == value,
      orElse: () => throw FormatException('Decisión inválida: $value'),
    );
  }

  static Map<String, dynamic> _map(Object? value, String field) {
    if (value is! Map) throw FormatException('$field debe ser un objeto.');
    return Map<String, dynamic>.from(value);
  }

  static List<dynamic> _list(Map<String, dynamic> map, String field) {
    final value = map[field];
    if (value is! List) throw FormatException('$field debe ser una lista.');
    return value;
  }

  static String _text(Map<String, dynamic> map, String field) {
    final value = map[field];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$field debe ser texto no vacío.');
    }
    return value;
  }

  static int _integer(Map<String, dynamic> map, String field) {
    final value = map[field];
    if (value is! num || value.toInt() != value) {
      throw FormatException('$field debe ser un entero.');
    }
    return value.toInt();
  }

  static int? _nullableInteger(Object? value, String field) {
    if (value == null) return null;
    if (value is! num || value.toInt() != value) {
      throw FormatException('$field debe ser entero o nulo.');
    }
    return value.toInt();
  }

  static String? _nullableString(Object? value, String field) {
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('$field debe ser texto o nulo.');
    }
    return value.trim().isEmpty ? null : value;
  }

  static List<String> _strings(Map<String, dynamic> map, String field) {
    final value = _list(map, field);
    if (value.any((item) => item is! String || item.trim().isEmpty)) {
      throw FormatException('$field debe contener solo textos no vacíos.');
    }
    return [for (final item in value) item as String];
  }

  static String? _nullableText(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
