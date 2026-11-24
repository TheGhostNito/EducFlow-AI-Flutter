import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_environment_config.dart';
import '../core/config/backend_config.dart';
import 'malla_multimodal_persistence_service.dart';
import 'malla_multimodal_testing_fixture.dart';

abstract interface class MallaRlsDiagnosticGateway {
  bool get enabled;
  Future<MallaRlsDiagnosticResult> run(String foreignMallaId);
}

abstract interface class MallaRlsReadClient {
  Future<List<Map<String, dynamic>>> select(
    String table,
    String columns, {
    String? equalsColumn,
    Object? equalsValue,
  });
}

class SupabaseMallaRlsReadClient implements MallaRlsReadClient {
  SupabaseMallaRlsReadClient(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> select(
    String table,
    String columns, {
    String? equalsColumn,
    Object? equalsValue,
  }) async {
    final query = _client.from(table).select(columns);
    final rows = equalsColumn == null
        ? await query
        : await query.eq(equalsColumn, equalsValue!);
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }
}

class MallaRlsFirebaseIdentity {
  const MallaRlsFirebaseIdentity({
    required this.uid,
    required this.hasIdToken,
    required this.authenticatedRole,
  });

  final String uid;
  final bool hasIdToken;
  final bool authenticatedRole;
}

class MallaRlsDiagnosticResult {
  const MallaRlsDiagnosticResult({
    required this.ownMallaId,
    required this.foreignMallaId,
    required this.ownRowsByTable,
    required this.foreignRowsHidden,
  });

  final String ownMallaId;
  final String foreignMallaId;
  final Map<String, int> ownRowsByTable;
  final Map<String, bool> foreignRowsHidden;

  bool get passed => foreignRowsHidden.values.every((hidden) => hidden);

  String safeReport({required bool spanish}) {
    final buffer = StringBuffer()
      ..writeln(
        spanish
            ? 'Diagnóstico RLS · Firebase Testing'
            : 'RLS diagnostics · Firebase Testing',
      )
      ..writeln(
        spanish
            ? 'JWT Firebase activo: verificado'
            : 'Active Firebase JWT: verified',
      )
      ..writeln(
        spanish ? 'Malla propia: $ownMallaId' : 'Own curriculum: $ownMallaId',
      )
      ..writeln(
        spanish
            ? 'Malla cruzada comprobada: $foreignMallaId'
            : 'Cross-account curriculum checked: $foreignMallaId',
      );
    for (final entry in ownRowsByTable.entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    buffer.writeln(
      spanish
          ? 'Filas ajenas visibles: 0 en todas las tablas'
          : 'Visible foreign rows: 0 in every table',
    );
    buffer.write(
      passed
          ? (spanish ? 'Resultado: APROBADO' : 'Result: PASSED')
          : (spanish ? 'Resultado: FALLIDO' : 'Result: FAILED'),
    );
    return buffer.toString();
  }
}

class MallaRlsDiagnosticException implements Exception {
  const MallaRlsDiagnosticException(this.safeMessage);

  final String safeMessage;

  @override
  String toString() => safeMessage;
}

class MallaMultimodalRlsDiagnosticService implements MallaRlsDiagnosticGateway {
  factory MallaMultimodalRlsDiagnosticService({
    MallaRlsReadClient? reader,
    Future<MallaRlsFirebaseIdentity?> Function()? identityProvider,
    String? Function()? currentUidProvider,
    String Function()? firebaseProjectIdProvider,
    String? supabaseProjectRef,
    MallaMultimodalTestingConfig testingConfig =
        MallaMultimodalTestingConfig.environment,
    MallaMultimodalPersistenceConfig persistenceConfig =
        MallaMultimodalPersistenceConfig.environment,
    bool? debugMode,
    bool? android,
    EducFlowEnvironment? appEnvironment,
  }) => MallaMultimodalRlsDiagnosticService._(
    reader: reader,
    identityProvider: identityProvider ?? _firebaseIdentity,
    currentUidProvider:
        currentUidProvider ?? (() => FirebaseAuth.instance.currentUser?.uid),
    firebaseProjectIdProvider:
        firebaseProjectIdProvider ??
        (() => FirebaseAuth.instance.app.options.projectId),
    supabaseProjectRef: supabaseProjectRef ?? BackendConfig.supabaseProjectRef,
    testingConfig: testingConfig,
    persistenceConfig: persistenceConfig,
    debugMode: debugMode,
    android: android,
    appEnvironment: appEnvironment,
  );

  MallaMultimodalRlsDiagnosticService._({
    required this._reader,
    required this._identityProvider,
    required this._currentUidProvider,
    required this._firebaseProjectIdProvider,
    required this._supabaseProjectRef,
    required this._testingConfig,
    required this._persistenceConfig,
    required this._debugMode,
    required this._android,
    required this._appEnvironment,
  });

  static const _uuidPattern =
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$';
  static const _relatedTables = <String>[
    'ramos_malla',
    'prerrequisitos_malla',
    'certificaciones_malla',
    'membresias_certificacion_malla',
    'requisitos_academicos_malla',
    'pendientes_revision_malla',
  ];

  final MallaRlsReadClient? _reader;
  final Future<MallaRlsFirebaseIdentity?> Function() _identityProvider;
  final String? Function() _currentUidProvider;
  final String Function() _firebaseProjectIdProvider;
  final String _supabaseProjectRef;
  final MallaMultimodalTestingConfig _testingConfig;
  final MallaMultimodalPersistenceConfig _persistenceConfig;
  final bool? _debugMode;
  final bool? _android;
  final EducFlowEnvironment? _appEnvironment;

  @override
  bool get enabled {
    // Evita inicializar Firebase/Supabase fuera de una compilación que pidió
    // explícitamente tanto la muestra como la persistencia multimodal.
    if (!_testingConfig.requested || !_persistenceConfig.requested) {
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
  Future<MallaRlsDiagnosticResult> run(String foreignMallaId) async {
    if (!enabled) {
      throw const MallaRlsDiagnosticException(
        'El diagnóstico RLS no está habilitado en este entorno.',
      );
    }
    final foreignId = foreignMallaId.trim().toLowerCase();
    if (!RegExp(_uuidPattern).hasMatch(foreignId)) {
      throw const MallaRlsDiagnosticException(
        'Ingresa un UUID de malla válido de la otra cuenta.',
      );
    }

    final identity = await _identityProvider();
    if (identity == null ||
        !identity.hasIdToken ||
        !identity.authenticatedRole ||
        identity.uid.isEmpty) {
      throw const MallaRlsDiagnosticException(
        'La sesión Firebase no tiene un JWT authenticated válido.',
      );
    }
    _ensureSession(identity.uid);

    final ownMallas = await _select(
      identity.uid,
      'mallas_curriculares',
      'usuario_uid,id',
    );
    _assertOwnership(ownMallas, identity.uid, 'mallas_curriculares');
    if (ownMallas.length != 1) {
      throw const MallaRlsDiagnosticException(
        'La cuenta debe tener exactamente una malla para ejecutar la prueba.',
      );
    }
    final ownMallaId = ownMallas.single['id']?.toString().toLowerCase() ?? '';
    if (!RegExp(_uuidPattern).hasMatch(ownMallaId)) {
      throw const MallaRlsDiagnosticException(
        'La malla propia no devolvió un UUID válido.',
      );
    }
    if (ownMallaId == foreignId) {
      throw const MallaRlsDiagnosticException(
        'El UUID cruzado debe pertenecer a la otra cuenta.',
      );
    }

    final ownCounts = <String, int>{'mallas_curriculares': 1};
    for (final table in _relatedTables) {
      final rows = await _select(
        identity.uid,
        table,
        'usuario_uid,malla_id',
        equalsColumn: 'malla_id',
        equalsValue: ownMallaId,
      );
      _assertOwnership(rows, identity.uid, table, mallaId: ownMallaId);
      ownCounts[table] = rows.length;
    }

    final foreignHidden = <String, bool>{};
    final foreignMallaRows = await _select(
      identity.uid,
      'mallas_curriculares',
      'usuario_uid,id',
      equalsColumn: 'id',
      equalsValue: foreignId,
    );
    foreignHidden['mallas_curriculares'] = foreignMallaRows.isEmpty;
    for (final table in _relatedTables) {
      final rows = await _select(
        identity.uid,
        table,
        'usuario_uid,malla_id',
        equalsColumn: 'malla_id',
        equalsValue: foreignId,
      );
      foreignHidden[table] = rows.isEmpty;
    }
    final leakingTable = foreignHidden.entries
        .where((entry) => !entry.value)
        .firstOrNull;
    if (leakingTable != null) {
      throw MallaRlsDiagnosticException(
        'RLS permitió leer datos ajenos en ${leakingTable.key}.',
      );
    }
    _ensureSession(identity.uid);

    return MallaRlsDiagnosticResult(
      ownMallaId: ownMallaId,
      foreignMallaId: foreignId,
      ownRowsByTable: ownCounts,
      foreignRowsHidden: foreignHidden,
    );
  }

  Future<List<Map<String, dynamic>>> _select(
    String uid,
    String table,
    String columns, {
    String? equalsColumn,
    Object? equalsValue,
  }) async {
    final reader =
        _reader ?? SupabaseMallaRlsReadClient(Supabase.instance.client);
    final rows = await reader.select(
      table,
      columns,
      equalsColumn: equalsColumn,
      equalsValue: equalsValue,
    );
    _ensureSession(uid);
    return rows;
  }

  void _assertOwnership(
    List<Map<String, dynamic>> rows,
    String uid,
    String table, {
    String? mallaId,
  }) {
    final invalid = rows.any(
      (row) =>
          row['usuario_uid'] != uid ||
          (mallaId != null && row['malla_id']?.toString() != mallaId),
    );
    if (invalid) {
      throw MallaRlsDiagnosticException(
        'RLS devolvió una fila fuera del ámbito esperado en $table.',
      );
    }
  }

  void _ensureSession(String uid) {
    if (_currentUidProvider() != uid) {
      throw const MallaRlsDiagnosticException(
        'La sesión cambió durante el diagnóstico RLS.',
      );
    }
  }

  static Future<MallaRlsFirebaseIdentity?> _firebaseIdentity() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final result = await user.getIdTokenResult();
    return MallaRlsFirebaseIdentity(
      uid: user.uid,
      hasIdToken: result.token?.isNotEmpty == true,
      authenticatedRole: result.claims?['role'] == 'authenticated',
    );
  }
}
