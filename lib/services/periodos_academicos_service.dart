import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/periodo_academico.dart';

abstract interface class PeriodosAcademicosDataSource {
  Future<List<PeriodoAcademico>> obtenerTodos(String uid);
  Future<PeriodoAcademico> agregar(String uid, PeriodoAcademico periodo);
  Future<PeriodoAcademico> actualizar(String uid, PeriodoAcademico periodo);
  Future<void> eliminar(String uid, String id);
  Future<void> asociarAsignatura(
    String uid, {
    required String asignaturaId,
    required String? periodoAcademicoId,
  });
}

class PeriodosAcademicosSqlCodec {
  const PeriodosAcademicosSqlCodec();

  PeriodoAcademico desdeFila(Map<String, dynamic> fila) {
    return PeriodoAcademico(
      id: _textoRequerido(fila['id'], 'id'),
      anio: _enteroRequerido(fila['anio'], 'anio'),
      tipo: _tipo(fila['tipo']),
      numero: _enteroRequerido(fila['numero'], 'numero'),
      nombre: _textoRequerido(fila['nombre'], 'nombre'),
      fechaInicio: _fechaNullable(fila['fecha_inicio'], 'fecha_inicio'),
      fechaFin: _fechaNullable(fila['fecha_fin'], 'fecha_fin'),
      institucion: _textoNullable(fila['institucion']),
      estado: _estado(fila['estado']),
    );
  }

  Map<String, dynamic> payload(PeriodoAcademico periodo) => {
    'id': periodo.id.trim(),
    'anio': periodo.anio,
    'tipo': switch (periodo.tipo) {
      TipoPeriodoAcademico.semestre => 'semestre',
    },
    'numero': periodo.numero,
    'nombre': periodo.nombre.trim(),
    'fecha_inicio': _fechaSql(periodo.fechaInicio),
    'fecha_fin': _fechaSql(periodo.fechaFin),
    'institucion': _limpiar(periodo.institucion),
    'estado': switch (periodo.estado) {
      EstadoPeriodoAcademico.activo => 'activo',
      EstadoPeriodoAcademico.historico => 'historico',
    },
  };

  TipoPeriodoAcademico _tipo(Object? value) {
    return switch (value?.toString()) {
      'semestre' => TipoPeriodoAcademico.semestre,
      _ => throw FormatException('Tipo de período no válido: $value'),
    };
  }

  EstadoPeriodoAcademico _estado(Object? value) {
    return switch (value?.toString()) {
      'activo' => EstadoPeriodoAcademico.activo,
      'historico' => EstadoPeriodoAcademico.historico,
      _ => throw FormatException('Estado de período no válido: $value'),
    };
  }

  DateTime? _fechaNullable(Object? value, String field) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) throw FormatException('Fecha no válida en $field.');
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  String? _fechaSql(DateTime? value) {
    if (value == null) return null;
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  int _enteroRequerido(Object? value, String field) {
    if (value is num) return value.toInt();
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed == null) throw FormatException('Entero no válido en $field.');
    return parsed;
  }

  String _textoRequerido(Object? value, String field) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) throw FormatException('Texto obligatorio en $field.');
    return text;
  }

  String? _textoNullable(Object? value) => _limpiar(value?.toString());

  String? _limpiar(String? value) {
    final clean = value?.trim() ?? '';
    return clean.isEmpty ? null : clean;
  }
}

class SupabasePeriodosAcademicosDataSource
    implements PeriodosAcademicosDataSource {
  SupabasePeriodosAcademicosDataSource(
    this._supabase, {
    this.codec = const PeriodosAcademicosSqlCodec(),
  });

  final SupabaseClient _supabase;
  final PeriodosAcademicosSqlCodec codec;

  @override
  Future<List<PeriodoAcademico>> obtenerTodos(String uid) async {
    final rows = await _supabase
        .from('periodos_academicos')
        .select(
          'id, anio, tipo, numero, nombre, fecha_inicio, fecha_fin, '
          'institucion, estado',
        )
        .eq('usuario_uid', uid)
        .order('fecha_inicio');
    return [
      for (final row in rows) codec.desdeFila(Map<String, dynamic>.from(row)),
    ];
  }

  @override
  Future<PeriodoAcademico> agregar(String uid, PeriodoAcademico periodo) {
    return _guardar('crear', periodo);
  }

  @override
  Future<PeriodoAcademico> actualizar(String uid, PeriodoAcademico periodo) {
    return _guardar('actualizar', periodo);
  }

  Future<PeriodoAcademico> _guardar(
    String operacion,
    PeriodoAcademico periodo,
  ) async {
    final result = await _supabase.rpc(
      'guardar_periodo_academico',
      params: {'p_operacion': operacion, 'p_periodo': codec.payload(periodo)},
    );
    if (result is! Map) {
      throw const FormatException('Supabase no devolvió el período guardado.');
    }
    return codec.desdeFila(Map<String, dynamic>.from(result));
  }

  @override
  Future<void> eliminar(String uid, String id) async {
    await _supabase.rpc(
      'eliminar_periodo_academico',
      params: {'p_periodo_id': id},
    );
  }

  @override
  Future<void> asociarAsignatura(
    String uid, {
    required String asignaturaId,
    required String? periodoAcademicoId,
  }) async {
    await _supabase.rpc(
      'asociar_asignatura_periodo',
      params: {
        'p_asignatura_id': asignaturaId,
        'p_periodo_academico_id': periodoAcademicoId,
      },
    );
  }
}

class PeriodosAcademicosService {
  PeriodosAcademicosService({
    PeriodosAcademicosDataSource? dataSource,
    SupabaseClient? supabase,
    FirebaseAuth? firebaseAuth,
    String Function()? uidProvider,
  }) : _dataSource =
           dataSource ??
           SupabasePeriodosAcademicosDataSource(
             supabase ?? Supabase.instance.client,
           ),
       _auth = firebaseAuth,
       _obtenerUid = uidProvider;

  final PeriodosAcademicosDataSource _dataSource;
  final FirebaseAuth? _auth;
  final String Function()? _obtenerUid;

  Future<List<PeriodoAcademico>> obtenerTodos() {
    return _dataSource.obtenerTodos(_uid());
  }

  Future<PeriodoAcademico> agregar(PeriodoAcademico periodo) {
    return _dataSource.agregar(_uid(), periodo);
  }

  Future<PeriodoAcademico> actualizar(PeriodoAcademico periodo) {
    return _dataSource.actualizar(_uid(), periodo);
  }

  Future<void> eliminar(String id) {
    return _dataSource.eliminar(_uid(), id);
  }

  Future<void> asociarAsignatura({
    required String asignaturaId,
    required String? periodoAcademicoId,
  }) {
    return _dataSource.asociarAsignatura(
      _uid(),
      asignaturaId: asignaturaId,
      periodoAcademicoId: periodoAcademicoId,
    );
  }

  String _uid() {
    final custom = _obtenerUid;
    if (custom != null) return custom();
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) {
      throw StateError('Inicia sesión antes de gestionar períodos.');
    }
    return user.uid;
  }
}
