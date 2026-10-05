import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/asignatura.dart';

abstract interface class AsignaturasDataSource {
  Future<List<Asignatura>> obtenerTodas(String uid);
  Future<Asignatura?> obtenerPorId(String uid, String id);
  Future<void> agregar(String uid, Asignatura asignatura);
  Future<void> actualizar(String uid, Asignatura asignatura);
  Future<void> eliminar(String uid, String id);
  Stream<void> observarCambios(String uid);
}

class AsignaturaConEvaluacionesException implements Exception {
  const AsignaturaConEvaluacionesException();

  @override
  String toString() =>
      'No se puede eliminar la asignatura porque tiene evaluaciones asociadas.';
}

/// Traduce entre el modelo de dominio y las tres tablas SQL de asignaturas.
class AsignaturasSqlCodec {
  const AsignaturasSqlCodec();

  List<Asignatura> reconstruir({
    required List<Map<String, dynamic>> asignaturas,
    required List<Map<String, dynamic>> bloques,
    required List<Map<String, dynamic>> relaciones,
  }) {
    final bloquesPorAsignatura = <String, List<BloqueHorario>>{};
    for (final bloque in bloques) {
      final asignaturaId = bloque['asignatura_id']?.toString() ?? '';
      final dia = diaSemanaDesdeFirestore(bloque['dia']);
      if (asignaturaId.isEmpty || dia == null) continue;
      bloquesPorAsignatura
          .putIfAbsent(asignaturaId, () => [])
          .add(
            BloqueHorario(
              dia: dia,
              horaInicio: normalizarHora(bloque['hora_inicio']),
              horaFin: normalizarHora(bloque['hora_fin']),
              sala: _textoNullable(bloque['sala']),
            ),
          );
    }

    final prerrequisitosPorAsignatura = <String, List<String>>{};
    final siguientesPorAsignatura = <String, List<String>>{};
    for (final relacion in relaciones) {
      final asignaturaId = relacion['asignatura_id']?.toString() ?? '';
      final relacionadaId = relacion['relacionada_id']?.toString() ?? '';
      if (asignaturaId.isEmpty || relacionadaId.isEmpty) continue;
      switch (relacion['tipo']?.toString()) {
        case 'prerrequisito':
          prerrequisitosPorAsignatura
              .putIfAbsent(asignaturaId, () => [])
              .add(relacionadaId);
        case 'siguiente':
          siguientesPorAsignatura
              .putIfAbsent(asignaturaId, () => [])
              .add(relacionadaId);
      }
    }

    return asignaturas.map((fila) {
      final id = fila['id']?.toString() ?? '';
      return Asignatura(
        id: id,
        nombre: fila['nombre']?.toString() ?? '',
        profesor: _textoNullable(fila['profesor']),
        correoProfesor: _textoNullable(fila['correo_profesor']),
        sala: _textoNullable(fila['sala']),
        periodo: _textoNullable(fila['periodo']),
        horario: List.unmodifiable(bloquesPorAsignatura[id] ?? const []),
        estado: estadoAsignaturaDesdeFirestore(fila['estado']),
        origen: origenAsignaturaDesdeFirestore(fila['origen']),
        sigla: _textoNullable(fila['sigla']),
        seccion: _textoNullable(fila['seccion']),
        creditos: _enteroNullable(fila['creditos']),
        semestreMalla: _enteroNullable(fila['semestre_malla']),
        cursoNivel: _textoNullable(fila['curso_nivel']),
        anioAcademico: _enteroNullable(fila['anio_academico']),
        modalidad: _textoNullable(fila['modalidad']),
        lugar: _textoNullable(fila['lugar']),
        institucion: _textoNullable(fila['institucion']),
        prerrequisitosIds: List.unmodifiable(
          prerrequisitosPorAsignatura[id] ?? const [],
        ),
        asignaturasSiguientesIds: List.unmodifiable(
          siguientesPorAsignatura[id] ?? const [],
        ),
      );
    }).toList();
  }

  Map<String, dynamic> asignaturaPayload(Asignatura asignatura) => {
    'id': asignatura.id.trim(),
    'nombre': asignatura.nombre.trim(),
    'profesor': _limpiar(asignatura.profesor),
    'correo_profesor': _limpiar(asignatura.correoProfesor)?.toLowerCase(),
    'sala': _limpiar(asignatura.sala),
    'periodo': _limpiar(asignatura.periodo),
    'estado': asignatura.estado.valorFirestore,
    'origen': asignatura.origen.valorFirestore,
    'sigla': _limpiar(asignatura.sigla),
    'seccion': _limpiar(asignatura.seccion),
    'creditos': asignatura.creditos,
    'semestre_malla': asignatura.semestreMalla,
    'curso_nivel': _limpiar(asignatura.cursoNivel),
    'anio_academico': asignatura.anioAcademico,
    'modalidad': _limpiar(asignatura.modalidad),
    'lugar': _limpiar(asignatura.lugar),
    'institucion': _limpiar(asignatura.institucion),
  };

  List<Map<String, dynamic>> bloquesPayload(Asignatura asignatura) {
    return asignatura.horario
        .map(
          (bloque) => {
            'dia': bloque.dia.valorFirestore,
            'hora_inicio': bloque.horaInicio.trim(),
            'hora_fin': bloque.horaFin.trim(),
            'sala': _limpiar(bloque.sala),
          },
        )
        .toList();
  }

  List<Map<String, dynamic>> relacionesPayload(Asignatura asignatura) => [
    ...asignatura.prerrequisitosIds.map(
      (id) => {'relacionada_id': id, 'tipo': 'prerrequisito'},
    ),
    ...asignatura.asignaturasSiguientesIds.map(
      (id) => {'relacionada_id': id, 'tipo': 'siguiente'},
    ),
  ];

  String normalizarHora(Object? valor) {
    final texto = valor?.toString().trim() ?? '';
    final coincidencia = RegExp(r'^(\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?$')
        .firstMatch(texto);
    return coincidencia == null
        ? texto
        : '${coincidencia.group(1)}:${coincidencia.group(2)}';
  }

  String? _textoNullable(Object? valor) => valor?.toString();

  int? _enteroNullable(Object? valor) {
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '');
  }

  String? _limpiar(String? valor) {
    final limpio = valor?.trim() ?? '';
    return limpio.isEmpty ? null : limpio;
  }
}

class SupabaseAsignaturasDataSource implements AsignaturasDataSource {
  SupabaseAsignaturasDataSource(
    this._supabase, {
    this._codec = const AsignaturasSqlCodec(),
  });

  final SupabaseClient _supabase;
  final AsignaturasSqlCodec _codec;
  static int _canalSecuencia = 0;

  static const _columnasAsignatura =
      'id, nombre, profesor, correo_profesor, sala, periodo, estado, origen, '
      'sigla, seccion, creditos, semestre_malla, curso_nivel, anio_academico, '
      'modalidad, lugar, institucion';

  @override
  Future<List<Asignatura>> obtenerTodas(String uid) async {
    final resultados = await Future.wait<dynamic>([
      _supabase
          .from('asignaturas')
          .select(_columnasAsignatura)
          .eq('usuario_uid', uid),
      _supabase
          .from('bloques_horario')
          .select('asignatura_id, dia, hora_inicio, hora_fin, sala')
          .eq('usuario_uid', uid)
          .order('id'),
      _supabase
          .from('relaciones_asignaturas')
          .select('asignatura_id, relacionada_id, tipo')
          .eq('usuario_uid', uid),
    ]);

    return _codec.reconstruir(
      asignaturas: _filas(resultados[0]),
      bloques: _filas(resultados[1]),
      relaciones: _filas(resultados[2]),
    );
  }

  @override
  Future<Asignatura?> obtenerPorId(String uid, String id) async {
    final resultados = await Future.wait<dynamic>([
      _supabase
          .from('asignaturas')
          .select(_columnasAsignatura)
          .eq('usuario_uid', uid)
          .eq('id', id)
          .maybeSingle(),
      _supabase
          .from('bloques_horario')
          .select('asignatura_id, dia, hora_inicio, hora_fin, sala')
          .eq('usuario_uid', uid)
          .eq('asignatura_id', id)
          .order('id'),
      _supabase
          .from('relaciones_asignaturas')
          .select('asignatura_id, relacionada_id, tipo')
          .eq('usuario_uid', uid)
          .eq('asignatura_id', id),
    ]);
    final asignatura = resultados[0];
    if (asignatura == null) return null;
    return _codec
        .reconstruir(
          asignaturas: [Map<String, dynamic>.from(asignatura as Map)],
          bloques: _filas(resultados[1]),
          relaciones: _filas(resultados[2]),
        )
        .single;
  }

  @override
  Future<void> agregar(String uid, Asignatura asignatura) =>
      _guardar('crear', asignatura);

  @override
  Future<void> actualizar(String uid, Asignatura asignatura) =>
      _guardar('actualizar', asignatura);

  Future<void> _guardar(String operacion, Asignatura asignatura) async {
    await _supabase.rpc(
      'guardar_asignatura_completa',
      params: {
        'p_operacion': operacion,
        'p_asignatura': _codec.asignaturaPayload(asignatura),
        'p_bloques': _codec.bloquesPayload(asignatura),
        'p_relaciones': _codec.relacionesPayload(asignatura),
      },
    );
  }

  @override
  Future<void> eliminar(String uid, String id) async {
    try {
      await _supabase.rpc(
        'eliminar_asignatura_segura',
        params: {'p_asignatura_id': id},
      );
    } on PostgrestException catch (error) {
      if (error.message.contains('asignatura_tiene_evaluaciones')) {
        throw const AsignaturaConEvaluacionesException();
      }
      rethrow;
    }
  }

  @override
  Stream<void> observarCambios(String uid) {
    RealtimeChannel? canal;
    late StreamController<void> controlador;

    void notificar(PostgresChangePayload _) {
      if (!controlador.isClosed) controlador.add(null);
    }

    controlador = StreamController<void>(
      onListen: () {
        final filtro = PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'usuario_uid',
          value: uid,
        );
        canal = _supabase
            .channel('asignaturas-$uid-${_canalSecuencia++}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'asignaturas',
              filter: filtro,
              callback: notificar,
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'bloques_horario',
              filter: filtro,
              callback: notificar,
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'relaciones_asignaturas',
              filter: filtro,
              callback: notificar,
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

  List<Map<String, dynamic>> _filas(dynamic resultado) {
    return (resultado as List)
        .map((fila) => Map<String, dynamic>.from(fila as Map))
        .toList();
  }
}

class AsignaturasService {
  AsignaturasService({
    AsignaturasDataSource? dataSource,
    SupabaseClient? supabase,
    FirebaseAuth? firebaseAuth,
    String Function()? uidProvider,
  }) : _dataSource =
           dataSource ??
           SupabaseAsignaturasDataSource(supabase ?? Supabase.instance.client),
       _auth = firebaseAuth,
       _obtenerUid = uidProvider;

  static final AsignaturasService instance = AsignaturasService();

  final AsignaturasDataSource _dataSource;
  final FirebaseAuth? _auth;
  final String Function()? _obtenerUid;
  int _versionInterna = 0;

  int get versionDatos => _versionInterna;

  Future<List<Asignatura>> obtenerTodas() async {
    final asignaturas = await _dataSource.obtenerTodas(_obtenerUidUsuario());
    asignaturas.sort((a, b) {
      return _normalizarParaOrden(a.nombre)
          .compareTo(_normalizarParaOrden(b.nombre));
    });
    return asignaturas;
  }

  Future<Asignatura?> obtenerPorId(String id) {
    return _dataSource.obtenerPorId(_obtenerUidUsuario(), id);
  }

  Future<void> agregar(Asignatura asignatura) async {
    await _dataSource.agregar(_obtenerUidUsuario(), asignatura);
    _marcarComoActualizado();
  }

  Future<void> actualizar(Asignatura asignatura) async {
    await _dataSource.actualizar(_obtenerUidUsuario(), asignatura);
    _marcarComoActualizado();
  }

  Future<void> eliminar(String id) async {
    await _dataSource.eliminar(_obtenerUidUsuario(), id);
    _marcarComoActualizado();
  }

  Stream<void> observarCambios() {
    return _dataSource.observarCambios(_obtenerUidUsuario()).map((_) {
      _marcarComoActualizado();
    });
  }

  void _marcarComoActualizado() => _versionInterna++;

  String _obtenerUidUsuario() {
    final proveedor = _obtenerUid;
    if (proveedor != null) return proveedor();
    final usuario = (_auth ?? FirebaseAuth.instance).currentUser;
    if (usuario == null) {
      throw StateError('No existe un usuario autenticado.');
    }
    return usuario.uid;
  }

  String _normalizarParaOrden(String texto) {
    return texto
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u');
  }
}
