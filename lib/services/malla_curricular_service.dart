import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/backend_config.dart';
import '../models/malla_curricular.dart';
import '../models/malla_import_review.dart';
import '../models/malla_multimodal_review.dart';
import 'malla_multimodal_review_service.dart';
import 'malla_multimodal_persistence_service.dart';
import 'malla_multimodal_testing_fixture.dart';
import 'ocr_document_service.dart';
import 'ocr_file_picker_service.dart';

abstract interface class MallaCurricularGateway {
  bool get multimodalPersistenceEnabled;
  bool get multimodalTestingSampleEnabled;
  Future<bool> existe();
  Future<MallaCurricular?> cargar();
  Future<MallaImportReview?> cargarRevisionMultimodal();
  Future<MallaCurricular> procesar(
    OcrDocumentResult upload, {
    required String fileName,
    required OcrPickedFile originalFile,
  });
  Future<MallaCurricular> confirmar(MallaCurricular preview);
  Future<MallaImportReview> confirmarMultimodal(MallaImportReview review);
  Future<MallaImportReview> confirmarRelacionesAgrupadas({
    required MallaImportReview review,
    List<MallaPrerequisiteProposal> prerequisites = const [],
    List<MallaCertificationBatchSelection> certifications = const [],
  });
  Future<MallaImportReview> decidirPrerrequisito({
    required String mallaId,
    required String courseId,
    required String requiresCourseId,
    required MallaProposalDecision decision,
  });

  Future<MallaImportReview> decidirMembresiaCertificacion({
    required String mallaId,
    required String certificationId,
    required String courseId,
    required MallaProposalDecision decision,
  });
  Future<MallaImportReview> decidirRequisitoAcademico({
    required String mallaId,
    required String requirementId,
    required String type,
    required MallaProposalDecision decision,
  });
  Future<MallaImportReview> confirmarRamoSinCodigo({
    required String mallaId,
    required String ramoId,
  });
  Future<MallaImportReview> editarRequisitoAcademico({
    required String mallaId,
    required MallaAcademicRequirement requirement,
    required String description,
    required int? minimumLevel,
  });
  Future<void> eliminarMallaConfirmada(String mallaId);
  Future<void> cambiarEstado(RamoMalla ramo, String estado);
  Future<MallaCurricular> editarRamo(
    MallaCurricular malla,
    RamoMalla ramo, {
    required bool confirmarRevision,
    required bool codigoDuplicadoVerificado,
    required bool confirmarSinCodigo,
  });
}

class MallaCurricularService implements MallaCurricularGateway {
  MallaCurricularService({
    FirebaseAuth? auth,
    SupabaseClient? client,
    MallaMultimodalReviewService? multimodalReviewService,
    MallaMultimodalPersistenceRepository? multimodalPersistenceRepository,
    MallaMultimodalTestingConfig? multimodalTestingConfig,
    String? supabaseProjectRef,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _client = client ?? Supabase.instance.client,
       _multimodalReviewService =
           multimodalReviewService ?? MallaMultimodalReviewService(),
       _multimodalTestingConfig =
           multimodalTestingConfig ?? MallaMultimodalTestingConfig.environment {
    _multimodalPersistence =
        multimodalPersistenceRepository ??
        MallaMultimodalPersistenceRepository(
          rpc: SupabaseMallaMultimodalRpcClient(_client),
          uidProvider: () => _auth.currentUser?.uid,
          firebaseProjectIdProvider: () => _auth.app.options.projectId,
          supabaseProjectRef:
              supabaseProjectRef ?? BackendConfig.supabaseProjectRef,
        );
  }

  final FirebaseAuth _auth;
  final SupabaseClient _client;
  final MallaMultimodalReviewService _multimodalReviewService;
  final MallaMultimodalTestingConfig _multimodalTestingConfig;
  late final MallaMultimodalPersistenceRepository _multimodalPersistence;

  @override
  bool get multimodalPersistenceEnabled => _multimodalPersistence.enabled;

  @override
  bool get multimodalTestingSampleEnabled => _multimodalTestingConfig.allows(
    firebaseProjectId: _auth.app.options.projectId,
    supabaseProjectRef: BackendConfig.supabaseProjectRef,
    persistenceEnabled: multimodalPersistenceEnabled,
  );

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Inicia sesión antes de consultar tu malla.');
    }
    return uid;
  }

  @override
  Future<bool> existe() async {
    final uid = _uid;
    final row = await _client
        .from('mallas_curriculares')
        .select('id')
        .eq('usuario_uid', uid)
        .maybeSingle();
    if (_auth.currentUser?.uid != uid) {
      throw StateError('La sesión cambió durante la consulta.');
    }
    return row != null;
  }

  @override
  Future<MallaCurricular?> cargar() async {
    if (multimodalPersistenceEnabled) {
      return (await cargarRevisionMultimodal())?.malla;
    }
    final uid = _uid;
    final row = await _client
        .from('mallas_curriculares')
        .select('id, archivo_nombre')
        .eq('usuario_uid', uid)
        .maybeSingle();
    if (row == null) return null;
    final subjectRows = await _client
        .from('ramos_malla')
        .select(
          'id, nombre, codigo, creditos, semestre, estado, requiere_revision, motivos_revision, codigo_duplicado_verificado',
        )
        .eq('usuario_uid', uid)
        .eq('malla_id', row['id'])
        .order('semestre')
        .order('orden');
    if (_auth.currentUser?.uid != uid) {
      throw StateError('La sesión cambió durante la consulta.');
    }
    return MallaCurricular(
      id: row['id'].toString(),
      archivoNombre: row['archivo_nombre'] as String?,
      ramos: [
        for (final subject in subjectRows)
          RamoMalla.fromRow(Map<String, dynamic>.from(subject)),
      ],
    );
  }

  @override
  Future<MallaImportReview?> cargarRevisionMultimodal() async {
    try {
      return await _multimodalPersistence.load();
    } on PostgrestException catch (error) {
      if (error.code == 'P0002') return null;
      rethrow;
    }
  }

  @override
  Future<MallaCurricular> procesar(
    OcrDocumentResult upload, {
    required String fileName,
    required OcrPickedFile originalFile,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Inicia sesión antes de procesar.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('No se pudo autenticar el procesamiento OCR.');
    }
    final response = await _client.functions.invoke(
      'ocr-process',
      body: {
        'bucket': upload.bucket,
        'path': upload.path,
        'mimeType': upload.mimeType,
      },
      headers: {'Authorization': 'Bearer $token'},
    );
    if (_auth.currentUser?.uid != user.uid) {
      throw StateError('La sesión cambió durante el procesamiento.');
    }
    final visionResult = MallaOcrParser.parse(
      response.data,
      fileName: fileName,
    );
    if (!multimodalPersistenceEnabled) {
      return visionResult;
    }
    final visionPayload = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : <String, dynamic>{};
    final multimodalOutcome = await _multimodalReviewService.review(
      uid: user.uid,
      file: originalFile,
      visionPayload: visionPayload,
      visionResult: visionResult,
    );
    if (_auth.currentUser?.uid != user.uid) {
      throw StateError('La sesión cambió durante el procesamiento.');
    }
    return visionResult.withMultimodalReview(
      multimodalOutcome.review,
      diagnostics: multimodalOutcome.diagnostics,
    );
  }

  @override
  Future<MallaCurricular> confirmar(MallaCurricular preview) async {
    final uid = _uid;
    if (preview.ramos.isEmpty) {
      throw StateError('La malla debe contener al menos una asignatura.');
    }
    for (final ramo in preview.ramos) {
      if (ramo.nombre.trim().isEmpty ||
          ramo.semestre < 1 ||
          (ramo.creditos != null && ramo.creditos! < 0)) {
        throw StateError(
          'Corrige los nombres, semestres y créditos inválidos.',
        );
      }
    }
    await _client.rpc(
      'confirmar_malla_curricular',
      params: {
        'p_expected_uid': uid,
        'p_archivo_nombre': preview.archivoNombre,
        'p_ramos': [for (final ramo in preview.ramos) ramo.toPayload()],
      },
    );
    if (_auth.currentUser?.uid != uid) {
      throw StateError('La sesión cambió durante el guardado.');
    }
    final saved = await cargar();
    if (saved == null) {
      throw StateError('No se pudo recuperar la malla guardada.');
    }
    return saved;
  }

  @override
  Future<MallaImportReview> confirmarMultimodal(
    MallaImportReview review,
  ) async {
    if (review.malla.ramos.isEmpty) {
      throw const MallaMultimodalValidationException(
        'La malla debe contener al menos una asignatura.',
      );
    }
    final uid = _uid;
    final saved = await _multimodalPersistence.confirm(review);
    if (_auth.currentUser?.uid != uid) {
      throw StateError('La sesión cambió durante el guardado.');
    }
    return saved;
  }

  @override
  Future<MallaImportReview> confirmarRelacionesAgrupadas({
    required MallaImportReview review,
    List<MallaPrerequisiteProposal> prerequisites = const [],
    List<MallaCertificationBatchSelection> certifications = const [],
  }) => _multimodalPersistence.confirmRelationshipBatch(
    review: review,
    prerequisites: prerequisites,
    certifications: certifications,
  );

  @override
  Future<MallaImportReview> decidirPrerrequisito({
    required String mallaId,
    required String courseId,
    required String requiresCourseId,
    required MallaProposalDecision decision,
  }) => _multimodalPersistence.decidePrerequisite(
    mallaId: mallaId,
    courseId: courseId,
    requiresCourseId: requiresCourseId,
    decision: decision,
  );

  @override
  Future<MallaImportReview> decidirMembresiaCertificacion({
    required String mallaId,
    required String certificationId,
    required String courseId,
    required MallaProposalDecision decision,
  }) => _multimodalPersistence.decideMembership(
    mallaId: mallaId,
    certificationId: certificationId,
    courseId: courseId,
    decision: decision,
  );

  @override
  Future<MallaImportReview> decidirRequisitoAcademico({
    required String mallaId,
    required String requirementId,
    required String type,
    required MallaProposalDecision decision,
  }) => _multimodalPersistence.decideAcademicRequirement(
    mallaId: mallaId,
    requirementId: requirementId,
    type: type,
    decision: decision,
  );

  @override
  Future<MallaImportReview> confirmarRamoSinCodigo({
    required String mallaId,
    required String ramoId,
  }) => _multimodalPersistence.confirmCourseWithoutCode(
    mallaId: mallaId,
    courseId: ramoId,
  );

  @override
  Future<MallaImportReview> editarRequisitoAcademico({
    required String mallaId,
    required MallaAcademicRequirement requirement,
    required String description,
    required int? minimumLevel,
  }) => _multimodalPersistence.updateAcademicRequirement(
    mallaId: mallaId,
    requirement: requirement,
    description: description,
    minimumLevel: minimumLevel,
  );

  @override
  Future<void> eliminarMallaConfirmada(String mallaId) =>
      _multimodalPersistence.deleteConfirmed(mallaId);

  @override
  Future<void> cambiarEstado(RamoMalla ramo, String estado) async {
    if (!const {'pendiente', 'en_curso', 'aprobada'}.contains(estado)) {
      throw ArgumentError('Estado académico inválido.');
    }
    await _client.rpc(
      'cambiar_estado_ramo_malla',
      params: {
        'p_expected_uid': _uid,
        'p_ramo_id': ramo.id,
        'p_estado': estado,
      },
    );
    ramo.estado = estado;
  }

  @override
  Future<MallaCurricular> editarRamo(
    MallaCurricular malla,
    RamoMalla ramo, {
    required bool confirmarRevision,
    required bool codigoDuplicadoVerificado,
    required bool confirmarSinCodigo,
  }) async {
    final uid = _uid;
    await _client.rpc(
      'editar_ramo_malla',
      params: {
        'p_expected_uid': uid,
        'p_malla_id': malla.id,
        'p_ramo_id': ramo.id,
        'p_nombre': ramo.nombre,
        'p_codigo': ramo.codigo,
        'p_creditos': ramo.creditos,
        'p_semestre': ramo.semestre,
        'p_confirmar_revision': confirmarRevision,
        'p_codigo_duplicado_verificado': codigoDuplicadoVerificado,
      },
    );
    if (_auth.currentUser?.uid != uid) {
      throw StateError('La sesión cambió durante la edición.');
    }
    if (confirmarSinCodigo) {
      final review = await confirmarRamoSinCodigo(
        mallaId: malla.id,
        ramoId: ramo.id,
      );
      return review.malla;
    }
    final updated = await cargar();
    if (updated == null) {
      throw StateError('No se pudo recuperar la malla guardada.');
    }
    return updated;
  }
}
