import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/malla_curricular.dart';
import 'ocr_document_service.dart';

abstract interface class MallaCurricularGateway {
  Future<bool> existe();
  Future<MallaCurricular?> cargar();
  Future<MallaCurricular> procesar(
    OcrDocumentResult upload, {
    required String fileName,
  });
  Future<MallaCurricular> confirmar(MallaCurricular preview);
  Future<void> cambiarEstado(RamoMalla ramo, String estado);
  Future<MallaCurricular> editarRamo(
    MallaCurricular malla,
    RamoMalla ramo, {
    required bool confirmarRevision,
    required bool codigoDuplicadoVerificado,
  });
}

class MallaCurricularService implements MallaCurricularGateway {
  MallaCurricularService({FirebaseAuth? auth, SupabaseClient? client})
    : _auth = auth ?? FirebaseAuth.instance,
      _client = client ?? Supabase.instance.client;

  final FirebaseAuth _auth;
  final SupabaseClient _client;

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
  Future<MallaCurricular> procesar(
    OcrDocumentResult upload, {
    required String fileName,
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
    return MallaOcrParser.parse(response.data, fileName: fileName);
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
    final updated = await cargar();
    if (updated == null) {
      throw StateError('No se pudo recuperar la malla guardada.');
    }
    return updated;
  }
}
