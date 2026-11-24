import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_environment_config.dart';
import '../core/config/backend_config.dart';
import 'malla_multimodal_persistence_service.dart';
import 'malla_multimodal_testing_fixture.dart';

abstract interface class MallaWriteDiagnosticGateway {
  bool get enabled;
  Future<MallaWriteDiagnosticResult> run(String foreignMallaId);
}

abstract interface class MallaWriteDiagnosticClient {
  Future<List<Map<String, dynamic>>> ownMallas();
  Future<List<Map<String, dynamic>>> acceptedPrerequisites(String mallaId);
  Future<dynamic> invoke(String function, Map<String, dynamic> params);
}

class SupabaseMallaWriteDiagnosticClient implements MallaWriteDiagnosticClient {
  SupabaseMallaWriteDiagnosticClient(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> ownMallas() async {
    final rows = await _client
        .from('mallas_curriculares')
        .select('usuario_uid,id');
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  @override
  Future<List<Map<String, dynamic>>> acceptedPrerequisites(
    String mallaId,
  ) async {
    final rows = await _client
        .from('prerrequisitos_malla')
        .select(
          'usuario_uid,malla_id,ramo_id,requisito_ramo_id,procedencia,'
          'decision,certeza,evidencias,motivos_pendientes,'
          'corregida_manualmente',
        )
        .eq('malla_id', mallaId)
        .eq('decision', 'accepted');
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  @override
  Future<dynamic> invoke(String function, Map<String, dynamic> params) =>
      _client.rpc<dynamic>(function, params: params);
}

class MallaWriteFirebaseIdentity {
  const MallaWriteFirebaseIdentity({
    required this.uid,
    required this.hasIdToken,
    required this.authenticatedRole,
  });

  final String uid;
  final bool hasIdToken;
  final bool authenticatedRole;
}

class MallaWriteDiagnosticConfig {
  const MallaWriteDiagnosticConfig({required this.requested});

  static const environment = MallaWriteDiagnosticConfig(
    requested: bool.fromEnvironment(
      'EDUFLOW_MULTIMODAL_WRITE_DIAGNOSTIC_ENABLED',
    ),
  );

  final bool requested;
}

class MallaWriteDiagnosticResult {
  const MallaWriteDiagnosticResult({
    required this.ownMallaId,
    required this.foreignMallaId,
    required this.prerequisiteKey,
    required this.reviewState,
    required this.pendingCount,
  });

  final String ownMallaId;
  final String foreignMallaId;
  final String prerequisiteKey;
  final String reviewState;
  final int pendingCount;

  String safeReport({required bool spanish}) => spanish
      ? 'Diagnóstico de escritura · Firebase Testing\n'
            'JWT Firebase activo: verificado\n'
            'Malla propia: $ownMallaId\n'
            'Malla ajena comprobada: $foreignMallaId\n'
            'Relación idempotente: $prerequisiteKey\n'
            'UID incorrecto: rechazado\n'
            'Malla ajena: rechazada\n'
            'Datos antes/después: idénticos\n'
            'Estado de revisión: $reviewState\n'
            'Pendientes explícitos: $pendingCount\n'
            'Resultado: APROBADO'
      : 'Write diagnostics · Firebase Testing\n'
            'Active Firebase JWT: verified\n'
            'Own curriculum: $ownMallaId\n'
            'Foreign curriculum checked: $foreignMallaId\n'
            'Idempotent relation: $prerequisiteKey\n'
            'Incorrect UID: rejected\n'
            'Foreign curriculum: rejected\n'
            'Before/after data: identical\n'
            'Review state: $reviewState\n'
            'Explicit pending items: $pendingCount\n'
            'Result: PASSED';
}

class MallaWriteDiagnosticException implements Exception {
  const MallaWriteDiagnosticException(this.safeMessage);

  final String safeMessage;

  @override
  String toString() => safeMessage;
}

class MallaMultimodalWriteDiagnosticService
    implements MallaWriteDiagnosticGateway {
  factory MallaMultimodalWriteDiagnosticService({
    MallaWriteDiagnosticClient? client,
    Future<MallaWriteFirebaseIdentity?> Function()? identityProvider,
    String? Function()? currentUidProvider,
    String Function()? firebaseProjectIdProvider,
    String? supabaseProjectRef,
    MallaWriteDiagnosticConfig diagnosticConfig =
        MallaWriteDiagnosticConfig.environment,
    MallaMultimodalTestingConfig testingConfig =
        MallaMultimodalTestingConfig.environment,
    MallaMultimodalPersistenceConfig persistenceConfig =
        MallaMultimodalPersistenceConfig.environment,
    bool? debugMode,
    bool? android,
    EducFlowEnvironment? appEnvironment,
  }) => MallaMultimodalWriteDiagnosticService._(
    client,
    identityProvider ?? _firebaseIdentity,
    currentUidProvider ?? (() => FirebaseAuth.instance.currentUser?.uid),
    firebaseProjectIdProvider ??
        (() => FirebaseAuth.instance.app.options.projectId),
    supabaseProjectRef ?? BackendConfig.supabaseProjectRef,
    diagnosticConfig,
    testingConfig,
    persistenceConfig,
    debugMode,
    android,
    appEnvironment,
  );

  MallaMultimodalWriteDiagnosticService._(
    this._client,
    this._identityProvider,
    this._currentUidProvider,
    this._firebaseProjectIdProvider,
    this._supabaseProjectRef,
    this._diagnosticConfig,
    this._testingConfig,
    this._persistenceConfig,
    this._debugMode,
    this._android,
    this._appEnvironment,
  );

  static const _uuidPattern =
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$';
  static const _incorrectUid = 'diagnostic_uid_incorrecto';
  static const _emptyChanges = <String, dynamic>{
    'prerequisites': <dynamic>[],
    'certifications': <dynamic>[],
    'memberships': <dynamic>[],
    'academic_requirements': <dynamic>[],
    'pending_items': <dynamic>[],
  };

  final MallaWriteDiagnosticClient? _client;
  final Future<MallaWriteFirebaseIdentity?> Function() _identityProvider;
  final String? Function() _currentUidProvider;
  final String Function() _firebaseProjectIdProvider;
  final String _supabaseProjectRef;
  final MallaWriteDiagnosticConfig _diagnosticConfig;
  final MallaMultimodalTestingConfig _testingConfig;
  final MallaMultimodalPersistenceConfig _persistenceConfig;
  final bool? _debugMode;
  final bool? _android;
  final EducFlowEnvironment? _appEnvironment;

  MallaWriteDiagnosticClient get _rpc =>
      _client ?? SupabaseMallaWriteDiagnosticClient(Supabase.instance.client);

  @override
  bool get enabled {
    if (!_diagnosticConfig.requested ||
        !_testingConfig.requested ||
        !_persistenceConfig.requested) {
      return false;
    }
    final firebaseProjectId = _firebaseProjectIdProvider();
    final persistenceEnabled = _persistenceConfig.allows(
      firebaseProjectId: firebaseProjectId,
      supabaseProjectRef: _supabaseProjectRef,
    );
    return _testingConfig.allows(
      firebaseProjectId: firebaseProjectId,
      supabaseProjectRef: _supabaseProjectRef,
      persistenceEnabled: persistenceEnabled,
      debugMode: _debugMode,
      android: _android,
      appEnvironment: _appEnvironment,
    );
  }

  @override
  Future<MallaWriteDiagnosticResult> run(String foreignMallaId) async {
    if (!enabled) {
      throw const MallaWriteDiagnosticException(
        'El diagnóstico de escritura no está habilitado en este entorno.',
      );
    }
    final foreignId = foreignMallaId.trim().toLowerCase();
    if (!RegExp(_uuidPattern).hasMatch(foreignId)) {
      throw const MallaWriteDiagnosticException(
        'Ingresa un UUID de malla válido de la otra cuenta.',
      );
    }

    final identity = await _identityProvider();
    if (identity == null ||
        !identity.hasIdToken ||
        !identity.authenticatedRole ||
        identity.uid.isEmpty) {
      throw const MallaWriteDiagnosticException(
        'La sesión Firebase no tiene un JWT authenticated válido.',
      );
    }
    _ensureSession(identity.uid);

    final ownRows = await _rpc.ownMallas();
    _ensureSession(identity.uid);
    if (ownRows.length != 1 || ownRows.single['usuario_uid'] != identity.uid) {
      throw const MallaWriteDiagnosticException(
        'La cuenta debe tener exactamente una malla propia para esta prueba.',
      );
    }
    final ownMallaId = ownRows.single['id']?.toString().toLowerCase() ?? '';
    if (!RegExp(_uuidPattern).hasMatch(ownMallaId) || ownMallaId == foreignId) {
      throw const MallaWriteDiagnosticException(
        'Los UUID de malla propia y ajena no son válidos para la prueba.',
      );
    }

    final before = _asMap(
      await _rpc.invoke('obtener_malla_multimodal', {
        'p_expected_uid': identity.uid,
      }),
      'No fue posible recuperar la malla antes del diagnóstico.',
    );
    _ensureSession(identity.uid);
    final prerequisites = await _rpc.acceptedPrerequisites(ownMallaId);
    _ensureSession(identity.uid);
    final candidate = _safeCandidate(
      prerequisites,
      _listOfMaps(before['pending_items']),
      identity.uid,
      ownMallaId,
    );
    if (candidate == null) {
      throw const MallaWriteDiagnosticException(
        'No existe un prerrequisito aceptado que pueda repetirse sin cambios.',
      );
    }

    final courseId = candidate['ramo_id'] as String;
    final requiresCourseId = candidate['requisito_ramo_id'] as String;
    final changes = <String, dynamic>{
      ..._emptyChanges,
      'prerequisites': [
        {
          'course_id': courseId,
          'requires_course_id': requiresCourseId,
          'result_course_id': courseId,
          'result_requires_course_id': requiresCourseId,
          'decision': 'accepted',
        },
      ],
    };

    await _expectRejected(
      uid: identity.uid,
      expectedCodes: const {'42501'},
      params: {
        'p_expected_uid': _incorrectUid,
        'p_malla_id': ownMallaId,
        'p_cambios': changes,
      },
      safeFailure: 'La RPC no rechazó el UID incorrecto.',
    );
    await _expectRejected(
      uid: identity.uid,
      expectedCodes: const {'P0002'},
      params: {
        'p_expected_uid': identity.uid,
        'p_malla_id': foreignId,
        'p_cambios': changes,
      },
      safeFailure: 'La RPC no rechazó la escritura sobre la malla ajena.',
    );

    final rawResult = await _rpc.invoke('gestionar_revision_malla_multimodal', {
      'p_expected_uid': identity.uid,
      'p_malla_id': ownMallaId,
      'p_cambios': changes,
    });
    _ensureSession(identity.uid);
    final result = _asMap(
      rawResult,
      'La RPC de gestión devolvió un resultado inválido.',
    );
    final after = _asMap(
      await _rpc.invoke('obtener_malla_multimodal', {
        'p_expected_uid': identity.uid,
      }),
      'No fue posible recuperar la malla después del diagnóstico.',
    );
    _ensureSession(identity.uid);
    final candidatesAfter = await _rpc.acceptedPrerequisites(ownMallaId);
    _ensureSession(identity.uid);
    final candidateAfter = candidatesAfter.where(
      (row) =>
          row['ramo_id'] == courseId &&
          row['requisito_ramo_id'] == requiresCourseId,
    );
    if (candidateAfter.length != 1 ||
        _canonical(candidateAfter.single) != _canonical(candidate) ||
        _canonical(after) != _canonical(before)) {
      throw const MallaWriteDiagnosticException(
        'La operación idempotente alteró datos de la malla.',
      );
    }

    final pendingCount = _listOfMaps(after['pending_items'])
        .where((item) => item['status'] == 'pending')
        .length;
    final reviewState = after['review_state']?.toString() ?? '';
    if (result['malla_id']?.toString().toLowerCase() != ownMallaId ||
        result['pending_count'] != pendingCount ||
        result['review_state'] != reviewState) {
      throw const MallaWriteDiagnosticException(
        'El resultado de la RPC no coincide con la malla recuperada.',
      );
    }

    return MallaWriteDiagnosticResult(
      ownMallaId: ownMallaId,
      foreignMallaId: foreignId,
      prerequisiteKey: '$courseId>$requiresCourseId',
      reviewState: reviewState,
      pendingCount: pendingCount,
    );
  }

  Future<void> _expectRejected({
    required String uid,
    required Set<String> expectedCodes,
    required Map<String, dynamic> params,
    required String safeFailure,
  }) async {
    try {
      await _rpc.invoke('gestionar_revision_malla_multimodal', params);
      _ensureSession(uid);
    } on PostgrestException catch (error) {
      _ensureSession(uid);
      if (expectedCodes.contains(error.code)) return;
      throw const MallaWriteDiagnosticException(
        'La RPC rechazó la prueba con una respuesta inesperada.',
      );
    }
    throw MallaWriteDiagnosticException(safeFailure);
  }

  Map<String, dynamic>? _safeCandidate(
    List<Map<String, dynamic>> rows,
    List<Map<String, dynamic>> pendingItems,
    String uid,
    String mallaId,
  ) {
    for (final row in rows) {
      final courseId = row['ramo_id'];
      final requiresCourseId = row['requisito_ramo_id'];
      if (row['usuario_uid'] != uid ||
          row['malla_id']?.toString() != mallaId ||
          row['decision'] != 'accepted' ||
          row['certeza'] != 'confirmed' ||
          courseId is! String ||
          courseId.isEmpty ||
          requiresCourseId is! String ||
          requiresCourseId.isEmpty ||
          _asList(row['motivos_pendientes']).isNotEmpty) {
        continue;
      }
      final key = '$courseId>$requiresCourseId';
      final relatedPending = pendingItems.where(
        (item) =>
            item['entity_type'] == 'prerequisite' && item['entity_key'] == key,
      );
      if (relatedPending.every(
        (item) =>
            item['status'] == 'resolved' &&
            item['resolution'] == 'decision:accepted',
      )) {
        return row;
      }
    }
    return null;
  }

  Map<String, dynamic> _asMap(dynamic value, String safeMessage) {
    if (value is! Map) throw MallaWriteDiagnosticException(safeMessage);
    return Map<String, dynamic>.from(value);
  }

  List<Map<String, dynamic>> _listOfMaps(dynamic value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }

  List<dynamic> _asList(dynamic value) => value is List ? value : const [];

  String _canonical(dynamic value) => jsonEncode(_canonicalValue(value));

  dynamic _canonicalValue(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _canonicalValue(value[key])};
    }
    if (value is List) return value.map(_canonicalValue).toList();
    return value;
  }

  void _ensureSession(String uid) {
    if (_currentUidProvider() != uid) {
      throw const MallaWriteDiagnosticException(
        'La sesión cambió durante el diagnóstico de escritura.',
      );
    }
  }

  static Future<MallaWriteFirebaseIdentity?> _firebaseIdentity() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final result = await user.getIdTokenResult();
    return MallaWriteFirebaseIdentity(
      uid: user.uid,
      hasIdToken: result.token?.isNotEmpty == true,
      authenticatedRole: result.claims?['role'] == 'authenticated',
    );
  }
}
