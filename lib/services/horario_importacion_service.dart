import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/horario_importacion.dart';
import 'asignaturas_service.dart';
import 'periodos_academicos_service.dart';

class HorarioImportacionConfig {
  const HorarioImportacionConfig._();

  static const writesEnabled = bool.fromEnvironment(
    'EDUFLOW_HORARIO_IMPORT_WRITES_ENABLED',
  );

  /// Se habilita solamente después de aplicar y validar la migración del
  /// bucket privado y sus RPC en el entorno correspondiente.
  static const documentStorageEnabled = bool.fromEnvironment(
    'EDUFLOW_HORARIO_DOCUMENT_STORAGE_ENABLED',
  );
}

abstract interface class HorarioImportacionGateway {
  Future<HorarioImportacionResultado> confirmar(
    HorarioImportacionPropuesta propuesta,
  );

  Future<List<HorarioImportacionRegistro>> listar();

  Future<List<String>> obtenerAsignaturaIds(String importacionId);

  Future<HorarioImportacionEliminada> eliminar(String importacionId);
}

abstract interface class HorarioImportacionDataSource {
  Future<Map<String, dynamic>> confirmar(
    String uid,
    Map<String, dynamic> payload,
  );

  Future<List<Map<String, dynamic>>> listar(String uid);

  Future<List<String>> obtenerAsignaturaIds(String uid, String importacionId);

  Future<Map<String, dynamic>> eliminar(String uid, String importacionId);
}

class HorarioImportacionSqlCodec {
  const HorarioImportacionSqlCodec({
    this.asignaturasCodec = const AsignaturasSqlCodec(),
    this.periodosCodec = const PeriodosAcademicosSqlCodec(),
  });

  final AsignaturasSqlCodec asignaturasCodec;
  final PeriodosAcademicosSqlCodec periodosCodec;

  Map<String, dynamic> propuesta(HorarioImportacionPropuesta value) => {
    'importacion_id': _importacionId(value.documentHash),
    'document_hash': value.documentHash.trim().toLowerCase(),
    'nombre_documento': value.nombreDocumento.trim(),
    if (value.documentoOriginal case final document?)
      'documento_original': {
        'path': document.path,
        'nombre': document.nombre,
        'mime': document.mimeType,
        'size': document.sizeBytes,
      },
    'periodo': periodosCodec.payload(value.periodo),
    'asignaturas': [
      for (final item in value.asignaturas)
        {
          'asignatura': asignaturasCodec.asignaturaPayload(item.asignatura),
          'bloques': asignaturasCodec.bloquesPayload(item.asignatura),
          'sesiones': [
            for (final sesion in item.sesiones)
              {
                'fecha': _fecha(sesion.fecha),
                'hora_inicio': sesion.horaInicio.trim(),
                'hora_fin': sesion.horaFin.trim(),
                'sala': _limpiar(sesion.sala),
                'origen': 'horario',
              },
          ],
        },
    ],
  };

  HorarioImportacionResultado resultado(Map<String, dynamic> row) =>
      HorarioImportacionResultado(
        importacionId: _texto(row['importacion_id'], 'importacion_id'),
        periodoAcademicoId: _texto(
          row['periodo_academico_id'],
          'periodo_academico_id',
        ),
        asignaturas: _entero(row['asignaturas'], 'asignaturas'),
        bloques: _entero(row['bloques'], 'bloques'),
        sesiones: _entero(row['sesiones'], 'sesiones'),
        yaExistia: row['ya_existia'] == true,
      );

  HorarioImportacionRegistro registro(Map<String, dynamic> row) =>
      HorarioImportacionRegistro(
        id: _texto(row['id'], 'id'),
        documentHash: _texto(row['document_hash'], 'document_hash'),
        nombreDocumento: _texto(row['nombre_documento'], 'nombre_documento'),
        anio: _entero(row['anio'], 'anio'),
        numeroPeriodo: _entero(row['numero_periodo'], 'numero_periodo'),
        periodoAcademicoId: _texto(
          row['periodo_academico_id'],
          'periodo_academico_id',
        ),
        asignaturas: _entero(row['asignaturas'], 'asignaturas'),
        bloques: _entero(row['bloques'], 'bloques'),
        sesiones: _entero(row['sesiones'], 'sesiones'),
        creadaEn: DateTime.tryParse(row['creada_en']?.toString() ?? ''),
        documentoOriginal: _documento(row),
      );

  HorarioImportacionEliminada eliminada(Map<String, dynamic> row) =>
      HorarioImportacionEliminada(
        importacionId: _texto(row['importacion_id'], 'importacion_id'),
        asignaturasEliminadas: _entero(
          row['asignaturas_eliminadas'],
          'asignaturas_eliminadas',
        ),
        periodoEliminado: row['periodo_eliminado'] == true,
        documentoPath: _limpiar(row['documento_path']?.toString()),
      );

  HorarioDocumentoOriginal? _documento(Map<String, dynamic> row) {
    final path = _limpiar(row['documento_path']?.toString());
    if (path == null) return null;
    return HorarioDocumentoOriginal(
      path: path,
      nombre: _texto(row['documento_nombre'], 'documento_nombre'),
      mimeType: _texto(row['documento_mime'], 'documento_mime'),
      sizeBytes: _entero(row['documento_size'], 'documento_size'),
    );
  }

  String _importacionId(String hash) {
    final normalized = hash.trim().toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(normalized)) {
      throw const FormatException('El hash del documento no es válido.');
    }
    return normalized.substring(0, 32);
  }

  String _fecha(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String? _limpiar(String? value) {
    final clean = value?.trim() ?? '';
    return clean.isEmpty ? null : clean;
  }

  String _texto(Object? value, String field) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) throw FormatException('Falta $field en la respuesta.');
    return text;
  }

  int _entero(Object? value, String field) {
    if (value is num) return value.toInt();
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed == null) throw FormatException('Falta $field en la respuesta.');
    return parsed;
  }
}

class SupabaseHorarioImportacionDataSource
    implements HorarioImportacionDataSource {
  SupabaseHorarioImportacionDataSource(
    this._supabase, {
    this.documentStorageEnabled =
        HorarioImportacionConfig.documentStorageEnabled,
  });

  final SupabaseClient _supabase;
  final bool documentStorageEnabled;

  @override
  Future<Map<String, dynamic>> confirmar(
    String uid,
    Map<String, dynamic> payload,
  ) async {
    final hasDocument = payload['documento_original'] is Map;
    final result = await _supabase.rpc(
      documentStorageEnabled && hasDocument
          ? 'confirmar_importacion_horario_con_documento'
          : 'confirmar_importacion_horario',
      params: {'p_importacion': payload},
    );
    if (result is! Map) {
      throw const FormatException('Supabase no confirmó la importación.');
    }
    return Map<String, dynamic>.from(result);
  }

  @override
  Future<List<Map<String, dynamic>>> listar(String uid) async {
    final result = await _supabase.rpc(
      documentStorageEnabled
          ? 'listar_importaciones_horario_con_documento'
          : 'listar_importaciones_horario',
    );
    if (result is! List) {
      throw const FormatException('Supabase no devolvió las importaciones.');
    }
    return [
      for (final row in result)
        if (row is Map) Map<String, dynamic>.from(row),
    ];
  }

  @override
  Future<List<String>> obtenerAsignaturaIds(
    String uid,
    String importacionId,
  ) async {
    final rows = await _supabase
        .from('importacion_horario_asignaturas')
        .select('asignatura_id')
        .eq('usuario_uid', uid)
        .eq('importacion_id', importacionId)
        .order('asignatura_id');
    return rows
        .map((row) => row['asignatura_id']?.toString().trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> eliminar(
    String uid,
    String importacionId,
  ) async {
    final result = await _supabase.rpc(
      documentStorageEnabled
          ? 'eliminar_importacion_horario_con_documento'
          : 'eliminar_importacion_horario',
      params: {'p_importacion_id': importacionId},
    );
    if (result is! Map) {
      throw const FormatException('Supabase no confirmó la eliminación.');
    }
    return Map<String, dynamic>.from(result);
  }
}

class HorarioImportacionService implements HorarioImportacionGateway {
  HorarioImportacionService({
    HorarioImportacionDataSource? dataSource,
    SupabaseClient? supabase,
    FirebaseAuth? firebaseAuth,
    this._uidProvider,
    this.codec = const HorarioImportacionSqlCodec(),
  }) : _dataSource =
           dataSource ??
           SupabaseHorarioImportacionDataSource(
             supabase ?? Supabase.instance.client,
           ),
       _auth = firebaseAuth;

  final HorarioImportacionDataSource _dataSource;
  final FirebaseAuth? _auth;
  final String Function()? _uidProvider;
  final HorarioImportacionSqlCodec codec;

  @override
  Future<HorarioImportacionResultado> confirmar(
    HorarioImportacionPropuesta propuesta,
  ) async {
    final uid = _uid();
    final row = await _dataSource.confirmar(uid, codec.propuesta(propuesta));
    _assertSameSession(uid);
    return codec.resultado(row);
  }

  @override
  Future<List<HorarioImportacionRegistro>> listar() async {
    final uid = _uid();
    final rows = await _dataSource.listar(uid);
    _assertSameSession(uid);
    return rows.map(codec.registro).toList(growable: false);
  }

  @override
  Future<List<String>> obtenerAsignaturaIds(String importacionId) async {
    final uid = _uid();
    final id = _importacionId(importacionId);
    final result = await _dataSource.obtenerAsignaturaIds(uid, id);
    _assertSameSession(uid);
    return List.unmodifiable(result);
  }

  @override
  Future<HorarioImportacionEliminada> eliminar(String importacionId) async {
    final uid = _uid();
    final id = _importacionId(importacionId);
    final row = await _dataSource.eliminar(uid, id);
    _assertSameSession(uid);
    return codec.eliminada(row);
  }

  String _importacionId(String value) {
    final id = value.trim();
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      throw const FormatException('Identificador de importación no válido.');
    }
    return id;
  }

  String _uid() {
    final custom = _uidProvider;
    if (custom != null) return custom();
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) {
      throw StateError('Inicia sesión antes de gestionar importaciones.');
    }
    return user.uid;
  }

  void _assertSameSession(String uid) {
    if (_uidProvider != null) return;
    if ((_auth ?? FirebaseAuth.instance).currentUser?.uid != uid) {
      throw StateError('La sesión cambió durante la operación.');
    }
  }
}
