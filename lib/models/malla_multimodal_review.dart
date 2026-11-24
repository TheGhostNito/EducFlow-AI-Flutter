import 'package:flutter/foundation.dart';

@immutable
class MallaMultimodalDiagnostics {
  const MallaMultimodalDiagnostics({
    required this.status,
    required this.geminiRequestExecuted,
    required this.successful,
    required this.cacheHit,
    required this.fallbackToVision,
    required this.elapsedMilliseconds,
    this.provider,
    this.model,
    this.stage,
    this.attachmentMimeType,
    this.attachmentBytes,
    this.structuredOutput,
    this.promptTokens,
    this.outputTokens,
    this.thinkingTokens,
    this.totalTokens,
    this.finishReason,
    this.responseLength,
    this.truncated,
    this.failure,
    this.errorCategory,
    this.errorType,
    this.httpStatus,
    this.backendStatus,
    this.technicalMessage,
    this.retryable,
  });

  final String status;
  final bool geminiRequestExecuted;
  final bool successful;
  final bool cacheHit;
  final bool fallbackToVision;
  final int elapsedMilliseconds;
  final String? provider;
  final String? model;
  final String? stage;
  final String? attachmentMimeType;
  final int? attachmentBytes;
  final bool? structuredOutput;
  final int? promptTokens;
  final int? outputTokens;
  final int? thinkingTokens;
  final int? totalTokens;
  final String? finishReason;
  final int? responseLength;
  final bool? truncated;
  final String? failure;
  final String? errorCategory;
  final String? errorType;
  final int? httpStatus;
  final String? backendStatus;
  final String? technicalMessage;
  final bool? retryable;

  Map<String, Object?> toJson() => {
    'status': status,
    'geminiRequestExecuted': geminiRequestExecuted,
    'successful': successful,
    'cacheHit': cacheHit,
    'fallbackToVision': fallbackToVision,
    'elapsedMilliseconds': elapsedMilliseconds,
    'provider': provider,
    'model': model,
    'stage': stage,
    'request': {
      'attachmentMimeType': attachmentMimeType,
      'attachmentBytes': attachmentBytes,
      'structuredOutput': structuredOutput,
    },
    'tokens': {
      'prompt': promptTokens,
      'output': outputTokens,
      'thinking': thinkingTokens,
      'total': totalTokens,
    },
    'response': {
      'finishReason': finishReason,
      'length': responseLength,
      'truncated': truncated,
    },
    'failure': failure,
    'errorCategory': errorCategory,
    'errorType': errorType,
    'httpStatus': httpStatus,
    'backendStatus': backendStatus,
    'technicalMessage': technicalMessage,
    'retryable': retryable,
  };
}

@immutable
class MallaVisualAudit {
  const MallaVisualAudit({
    required this.certificationContainersInspected,
    required this.certificationContainerCount,
    required this.certificationTitles,
    required this.courseArrowsInspected,
    required this.coursePrerequisiteConnectionCount,
    required this.unresolvedVisualSignals,
  });

  final bool certificationContainersInspected;
  final int certificationContainerCount;
  final List<String> certificationTitles;
  final bool courseArrowsInspected;
  final int coursePrerequisiteConnectionCount;
  final List<String> unresolvedVisualSignals;

  Map<String, Object?> toJson() => {
    'certificationContainersInspected': certificationContainersInspected,
    'certificationContainerCount': certificationContainerCount,
    'certificationTitles': certificationTitles,
    'courseArrowsInspected': courseArrowsInspected,
    'coursePrerequisiteConnectionCount': coursePrerequisiteConnectionCount,
    'unresolvedVisualSignals': unresolvedVisualSignals,
  };
}

@immutable
class MallaMultimodalReview {
  const MallaMultimodalReview({
    required this.model,
    required this.processorVersion,
    required this.documentHash,
    required this.periodType,
    required this.periodCount,
    required this.periodEvidence,
    required this.courseReviews,
    this.additionalCourses = const [],
    required this.prerequisites,
    required this.certifications,
    this.academicRequirements = const [],
    required this.pendingReview,
    this.visualAudit,
  });

  final String model;
  final String processorVersion;
  final String documentHash;
  final String periodType;
  final int periodCount;
  final List<String> periodEvidence;
  final List<MallaCourseReview> courseReviews;
  final List<MallaAdditionalCourseProposal> additionalCourses;
  final List<MallaPrerequisiteReview> prerequisites;
  final List<MallaCertificationReview> certifications;
  final List<MallaAcademicRequirement> academicRequirements;
  final List<String> pendingReview;
  final MallaVisualAudit? visualAudit;

  Map<String, Object?> toJson() => {
    'model': model,
    'processorVersion': processorVersion,
    'documentHash': documentHash,
    'periodOrganization': {
      'type': periodType,
      'count': periodCount,
      'evidence': periodEvidence,
    },
    'courseReviews': [for (final item in courseReviews) item.toJson()],
    'additionalCourses': [for (final item in additionalCourses) item.toJson()],
    'prerequisites': [for (final item in prerequisites) item.toJson()],
    'certifications': [for (final item in certifications) item.toJson()],
    'academicRequirements': [
      for (final item in academicRequirements) item.toJson(),
    ],
    'pendingReview': pendingReview,
    if (visualAudit != null) 'visualAudit': visualAudit!.toJson(),
  };
}

@immutable
class MallaCourseReview {
  const MallaCourseReview({
    required this.courseId,
    required this.proposedName,
    required this.proposedCode,
    required this.proposedCredits,
    required this.proposedPeriod,
    required this.category,
    this.categoryLabel,
    required this.prerequisiteStatus,
    this.prerequisiteStatusEvidence = const [],
    required this.evidence,
    required this.pendingReasons,
  });

  final String courseId;
  final String? proposedName;
  final String? proposedCode;
  final int? proposedCredits;
  final int? proposedPeriod;
  final String category;
  final String? categoryLabel;
  final String prerequisiteStatus;
  final List<String> prerequisiteStatusEvidence;
  final List<String> evidence;
  final List<String> pendingReasons;

  Map<String, Object?> toJson() => {
    'courseId': courseId,
    'proposedName': proposedName,
    'proposedCode': proposedCode,
    'proposedCredits': proposedCredits,
    'proposedPeriod': proposedPeriod,
    'category': category,
    'categoryLabel': categoryLabel,
    'prerequisiteStatus': prerequisiteStatus,
    'prerequisiteStatusEvidence': prerequisiteStatusEvidence,
    'evidence': evidence,
    'pendingReasons': pendingReasons,
  };
}

@immutable
class MallaAdditionalCourseProposal {
  const MallaAdditionalCourseProposal({
    required this.id,
    required this.proposedName,
    required this.proposedCode,
    required this.proposedCredits,
    required this.proposedPeriod,
    required this.category,
    required this.categoryLabel,
    required this.evidence,
    required this.pendingReasons,
  });

  final String id;
  final String proposedName;
  final String? proposedCode;
  final int? proposedCredits;
  final int? proposedPeriod;
  final String category;
  final String? categoryLabel;
  final List<String> evidence;
  final List<String> pendingReasons;

  String get source => 'gemini_proposal';

  bool get requiresManualReview => pendingReasons.isNotEmpty;

  Map<String, Object?> toJson() => {
    'id': id,
    'source': source,
    'proposedName': proposedName,
    'proposedCode': proposedCode,
    'proposedCredits': proposedCredits,
    'proposedPeriod': proposedPeriod,
    'category': category,
    'categoryLabel': categoryLabel,
    'evidence': evidence,
    'pendingReasons': pendingReasons,
    'requiresManualReview': requiresManualReview,
  };
}

@immutable
class MallaPrerequisiteReview {
  const MallaPrerequisiteReview({
    required this.courseId,
    required this.requiresCourseId,
    required this.evidence,
    this.certainty = 'confirmed',
    this.pendingReasons = const [],
  });

  final String courseId;
  final String requiresCourseId;
  final List<String> evidence;
  final String certainty;
  final List<String> pendingReasons;

  Map<String, Object?> toJson() => {
    'courseId': courseId,
    'requiresCourseId': requiresCourseId,
    'evidence': evidence,
    'certainty': certainty,
    'pendingReasons': pendingReasons,
  };
}

@immutable
class MallaCertificationReview {
  const MallaCertificationReview({
    required this.id,
    required this.name,
    required this.courseIds,
    required this.evidence,
    this.memberships = const [],
  });

  final String id;
  final String name;
  final List<String> courseIds;
  final List<String> evidence;
  final List<MallaCertificationMembership> memberships;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'courseIds': courseIds,
    'evidence': evidence,
    'memberships': [for (final item in memberships) item.toJson()],
  };
}

@immutable
class MallaCertificationMembership {
  const MallaCertificationMembership({
    required this.courseId,
    required this.basis,
    required this.evidence,
    this.pendingReasons = const [],
  });

  final String courseId;
  final String basis;
  final List<String> evidence;
  final List<String> pendingReasons;

  Map<String, Object?> toJson() => {
    'courseId': courseId,
    'basis': basis,
    'evidence': evidence,
    'pendingReasons': pendingReasons,
  };
}

@immutable
class MallaAcademicRequirement {
  const MallaAcademicRequirement({
    required this.id,
    required this.type,
    required this.targetCourseId,
    required this.targetLabel,
    required this.description,
    required this.minimumLevel,
    required this.evidence,
    required this.pendingReasons,
    this.source = 'gemini',
  });

  final String id;
  final String type;
  final String? targetCourseId;
  final String? targetLabel;
  final String description;
  final int? minimumLevel;
  final List<String> evidence;
  final List<String> pendingReasons;
  final String source;

  bool get requiresManualReview => pendingReasons.isNotEmpty;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'targetCourseId': targetCourseId,
    'targetLabel': targetLabel,
    'description': description,
    'minimumLevel': minimumLevel,
    'evidence': evidence,
    'pendingReasons': pendingReasons,
    'source': source,
    'requiresManualReview': requiresManualReview,
  };
}
