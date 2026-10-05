import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/evaluacion.dart';

abstract interface class EvaluacionesDataSource {
  Future<List<Evaluacion>> obtenerTodas(String uid);
  Future<Evaluacion?> obtenerPorId(String uid, String id);
  Future<Evaluacion> crear(String uid, Evaluacion evaluacion);
  Future<void> actualizar(String uid, Evaluacion evaluacion);
  Future<void> eliminar(String uid, String id);
  Stream<void> observarCambios(String uid);
}

class EvaluacionConNotaException implements Exception {
  const EvaluacionConNotaException();

  @override
  String toString() =>
      'No se puede eliminar la evaluación porque tiene una nota asociada.';
}

class EvaluacionesSqlCodec {
  const EvaluacionesSqlCodec();

  Evaluacion desdeFila(Map<String, dynamic> fila) {
    final id = fila['id']?.toString().trim() ?? '';
    final titulo = fila['titulo']?.toString().trim() ?? '';
    final asignaturaId = fila['asignatura_id']?.toString().trim() ?? '';
    final fecha = _fecha(fila['fecha']);
    final creadaEn = _timestamp(fila['creada_en'], 'creada_en');
    final actualizadaEn = _timestamp(
      fila['actualizada_en'],
      'actualizada_en',
    );

    if (id.isEmpty || titulo.isEmpty || asignaturaId.isEmpty) {
      throw const FormatException(
        'La evaluación SQL no contiene sus campos obligatorios.',
      );
    }

    return Evaluacion(
      id: id,
      titulo: titulo,
      asignaturaId: asignaturaId,
      tipo: TipoEvaluacionFirestore.fromFirestore(fila['tipo']?.toString()),
      fecha: fecha,
      hora: normalizarHora(fila['hora']),
      descripcion: _textoNullable(fila['descripcion']),
      ponderacion: _doubleNullable(fila['ponderacion']),
      creadaEn: creadaEn,
      actualizadaEn: actualizadaEn,
    );
  }

  Map<String, dynamic> payload(Evaluacion evaluacion) => {
    if (evaluacion.id.trim().isNotEmpty) 'id': evaluacion.id.trim(),
    'titulo': evaluacion.titulo.trim(),
    'asignatura_id': evaluacion.asignaturaId.trim(),
    'tipo': evaluacion.tipo.firestoreValue,
    'fecha': _fechaSql(evaluacion.fecha),
    'hora': _limpiar(evaluacion.hora),
    'descripcion': _limpiar(evaluacion.descripcion),
    'ponderacion': evaluacion.ponderacion,
  };

  String? normalizarHora(Object? valor) {
    final texto = valor?.toString().trim() ?? '';
    if (texto.isEmpty) return null;
    final coincidencia = RegExp(
      r'^(\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?$',
    ).firstMatch(texto);
    if (coincidencia == null) {
      throw FormatException('Hora SQL no válida: $texto');
    }
    return '${coincidencia.group(1)}:${coincidencia.group(2)}';
  }

  DateTime _fecha(Object? valor) {
    final texto = valor?.toString().trim() ?? '';
    final coincidencia = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(
      texto,
    );
    if (coincidencia == null) {
      throw FormatException('Fecha SQL no válida: $texto');
    }
    return DateTime(
      int.parse(coincidencia.group(1)!),
      int.parse(coincidencia.group(2)!),
      int.parse(coincidencia.group(3)!),
    );
  }

  DateTime _timestamp(Object? valor, String campo) {
    final timestamp = DateTime.tryParse(valor?.toString() ?? '');
    if (timestamp == null) {
      throw FormatException('Timestamp SQL no válido en $campo.');
    }
    return timestamp.toLocal();
  }

  double? _doubleNullable(Object? valor) {
    if (valor == null) return null;
    if (valor is num) return valor.toDouble();
    final resultado = double.tryParse(valor.toString());
    if (resultado == null) {
      throw FormatException('Ponderación SQL no válida: $valor');
    }
    return resultado;
  }

  String? _textoNullable(Object? valor) => _limpiar(valor?.toString());

  String? _limpiar(String? valor) {
    final limpio = valor?.trim() ?? '';
    return limpio.isEmpty ? null : limpio;
  }

  String _fechaSql(DateTime fecha) {
    return '${fecha.year.toString().padLeft(4, '0')}-'
        '${fecha.month.toString().padLeft(2, '0')}-'
        '${fecha.day.toString().padLeft(2, '0')}';
  }
}

class SupabaseEvaluacionesDataSource implements EvaluacionesDataSource {
  SupabaseEvaluacionesDataSource(
    this._supabase, {
    this.codec = const EvaluacionesSqlCodec(),
  });

  final SupabaseClient _supabase;
  final EvaluacionesSqlCodec codec;
  static int _canalSecuencia = 0;

  static const _columnas =
      'id, asignatura_id, titulo, tipo, fecha, hora, descripcion, '
      'ponderacion, creada_en, actualizada_en';

  @override
  Future<List<Evaluacion>> obtenerTodas(String uid) async {
    final resultado = await _supabase
        .from('evaluaciones')
        .select(_columnas)
        .eq('usuario_uid', uid)
        .order('fecha')
        .order('hora');
    return resultado.map<Evaluacion>(codec.desdeFila).toList();
  }

  @override
  Future<Evaluacion?> obtenerPorId(String uid, String id) async {
    final resultado = await _supabase
        .from('evaluaciones')
        .select(_columnas)
        .eq('usuario_uid', uid)
        .eq('id', id)
        .maybeSingle();
    return resultado == null ? null : codec.desdeFila(resultado);
  }

  @override
  Future<Evaluacion> crear(String uid, Evaluacion evaluacion) async {
    final resultado = await _supabase.rpc<dynamic>(
      'guardar_evaluacion',
      params: {
        'p_operacion': 'crear',
        'p_evaluacion': codec.payload(evaluacion),
      },
    );
    return codec.desdeFila(Map<String, dynamic>.from(resultado as Map));
  }

  @override
  Future<void> actualizar(String uid, Evaluacion evaluacion) async {
    await _supabase.rpc<dynamic>(
      'guardar_evaluacion',
      params: {
        'p_operacion': 'actualizar',
        'p_evaluacion': codec.payload(evaluacion),
      },
    );
  }

  @override
  Future<void> eliminar(String uid, String id) async {
    try {
      await _supabase.rpc<void>(
        'eliminar_evaluacion_segura',
        params: {'p_evaluacion_id': id},
      );
    } on PostgrestException catch (error) {
      if (error.message.contains('evaluacion_tiene_nota')) {
        throw const EvaluacionConNotaException();
      }
      rethrow;
    }
  }

  @override
  Stream<void> observarCambios(String uid) {
    RealtimeChannel? canal;
    late StreamController<void> controlador;

    controlador = StreamController<void>(
      onListen: () {
        canal = _supabase
            .channel('evaluaciones-$uid-${_canalSecuencia++}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'evaluaciones',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'usuario_uid',
                value: uid,
              ),
              callback: (_) {
                if (!controlador.isClosed) controlador.add(null);
              },
            )
            .subscribe((estado, error) {
              if (error != null && !controlador.isClosed) {
                controlador.addError(error);
              }
            });
      },
      onCancel: () async {
        final canalActual = canal;
        if (canalActual != null) await _supabase.removeChannel(canalActual);
      },
    );
    return controlador.stream;
  }
}

class EvaluacionesService {
  EvaluacionesService({
    EvaluacionesDataSource? dataSource,
    SupabaseClient? supabase,
    FirebaseAuth? firebaseAuth,
    String Function()? uidProvider,
  }) : _dataSource =
           dataSource ??
           SupabaseEvaluacionesDataSource(supabase ?? Supabase.instance.client),
       _auth = firebaseAuth,
       _obtenerUid = uidProvider;

  static final EvaluacionesService instance = EvaluacionesService();

  final EvaluacionesDataSource _dataSource;
  final FirebaseAuth? _auth;
  final String Function()? _obtenerUid;
  int _versionInterna = 0;

  int get versionDatos => _versionInterna;

  Future<List<Evaluacion>> obtenerTodas() async {
    final evaluaciones = await _dataSource.obtenerTodas(_obtenerUidUsuario());
    evaluaciones.sort(_compararEvaluaciones);
    return evaluaciones;
  }

  Future<Evaluacion?> obtenerPorId(String id) {
    final limpio = id.trim();
    if (limpio.isEmpty) return Future.value();
    return _dataSource.obtenerPorId(_obtenerUidUsuario(), limpio);
  }

  Future<Evaluacion> crear({
    required String titulo,
    required String asignaturaId,
    required DateTime fecha,
    TipoEvaluacion tipo = TipoEvaluacion.prueba,
    String? descripcion,
    String? hora,
    double? ponderacion,
  }) async {
    final tituloLimpio = titulo.trim();
    final asignaturaLimpia = asignaturaId.trim();
    if (tituloLimpio.isEmpty) {
      throw ArgumentError('El título es obligatorio.');
    }
    if (asignaturaLimpia.isEmpty) {
      throw ArgumentError('La asignatura es obligatoria.');
    }
    _validarHora(hora);
    _validarPonderacion(ponderacion);

    final ahora = DateTime.now();
    final evaluacion = Evaluacion(
      id: '',
      titulo: tituloLimpio,
      asignaturaId: asignaturaLimpia,
      tipo: tipo,
      fecha: DateTime(fecha.year, fecha.month, fecha.day),
      hora: _limpiarOpcional(hora),
      descripcion: _limpiarOpcional(descripcion),
      ponderacion: ponderacion,
      creadaEn: ahora,
      actualizadaEn: ahora,
    );
    final creada = await _dataSource.crear(_obtenerUidUsuario(), evaluacion);
    _marcarComoActualizado();
    return creada;
  }

  Future<void> actualizar(Evaluacion evaluacion) async {
    final id = evaluacion.id.trim();
    final titulo = evaluacion.titulo.trim();
    final asignatura = evaluacion.asignaturaId.trim();
    if (id.isEmpty || titulo.isEmpty || asignatura.isEmpty) {
      throw ArgumentError('ID, título y asignatura son obligatorios.');
    }
    _validarHora(evaluacion.hora);
    _validarPonderacion(evaluacion.ponderacion);

    final actualizada = evaluacion.copyWith(
      titulo: titulo,
      asignaturaId: asignatura,
      actualizadaEn: DateTime.now(),
    );
    await _dataSource.actualizar(_obtenerUidUsuario(), actualizada);
    _marcarComoActualizado();
  }

  Future<void> eliminar(String id) async {
    final limpio = id.trim();
    if (limpio.isEmpty) return;
    await _dataSource.eliminar(_obtenerUidUsuario(), limpio);
    _marcarComoActualizado();
  }

  Stream<void> observarCambios() {
    return _dataSource.observarCambios(_obtenerUidUsuario()).map((_) {
      _marcarComoActualizado();
    });
  }

  int _compararEvaluaciones(Evaluacion a, Evaluacion b) {
    final fecha = a.fecha.compareTo(b.fecha);
    if (fecha != 0) return fecha;
    final horaA = a.hora?.trim().isNotEmpty == true ? a.hora! : '99:99';
    final horaB = b.hora?.trim().isNotEmpty == true ? b.hora! : '99:99';
    return horaA.compareTo(horaB);
  }

  String _obtenerUidUsuario() {
    final proveedor = _obtenerUid;
    if (proveedor != null) return proveedor();
    final usuario = (_auth ?? FirebaseAuth.instance).currentUser;
    if (usuario == null) {
      throw StateError('No existe un usuario autenticado.');
    }
    return usuario.uid;
  }

  String? _limpiarOpcional(String? value) {
    final limpio = value?.trim() ?? '';
    return limpio.isEmpty ? null : limpio;
  }

  void _validarHora(String? value) {
    final hora = value?.trim() ?? '';
    if (hora.isEmpty) return;
    if (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(hora)) {
      throw ArgumentError('La hora debe estar en formato HH:mm.');
    }
  }

  void _validarPonderacion(double? value) {
    if (value == null) return;
    if (!value.isFinite || value < 0 || value > 100) {
      throw ArgumentError('La ponderación debe estar entre 0 y 100.');
    }
  }

  void _marcarComoActualizado() => _versionInterna++;
}
