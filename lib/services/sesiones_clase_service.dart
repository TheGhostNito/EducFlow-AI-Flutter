import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/sesion_clase.dart';

abstract interface class SesionesClaseDataSource {
  Future<List<SesionClase>> obtenerTodas(String uid);
  Future<SesionClase> agregar(String uid, SesionClase sesion);
  Future<SesionClase> actualizar(String uid, SesionClase sesion);
  Future<void> eliminar(String uid, String id);
}

class SesionesClaseSqlCodec {
  const SesionesClaseSqlCodec();

  SesionClase desdeFila(Map<String, dynamic> fila) {
    return SesionClase(
      id: _textoRequerido(fila['id'], 'id'),
      asignaturaId: _textoRequerido(fila['asignatura_id'], 'asignatura_id'),
      periodoAcademicoId: _textoRequerido(
        fila['periodo_academico_id'],
        'periodo_academico_id',
      ),
      fecha: _fecha(fila['fecha']),
      horaInicio: _hora(fila['hora_inicio']),
      horaFin: _hora(fila['hora_fin']),
      sala: _limpiar(fila['sala']?.toString()),
      origen: _origen(fila['origen']),
    );
  }

  Map<String, dynamic> payload(SesionClase sesion) => {
    'id': sesion.id.trim(),
    'asignatura_id': sesion.asignaturaId.trim(),
    'periodo_academico_id': sesion.periodoAcademicoId.trim(),
    'fecha': _fechaSql(sesion.fecha),
    'hora_inicio': sesion.horaInicio.trim(),
    'hora_fin': sesion.horaFin.trim(),
    'sala': _limpiar(sesion.sala),
    'origen': switch (sesion.origen) {
      OrigenSesionClase.manual => 'manual',
      OrigenSesionClase.horario => 'horario',
    },
  };

  OrigenSesionClase _origen(Object? value) {
    return switch (value?.toString()) {
      'manual' => OrigenSesionClase.manual,
      'horario' => OrigenSesionClase.horario,
      _ => throw FormatException('Origen de sesión no válido: $value'),
    };
  }

  DateTime _fecha(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) {
      throw const FormatException('Fecha de sesión inválida.');
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  String _hora(Object? value) {
    final text = value?.toString().trim() ?? '';
    final match = RegExp(r'^(\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?$')
        .firstMatch(text);
    if (match == null) {
      throw const FormatException('Hora de sesión inválida.');
    }
    return '${match.group(1)}:${match.group(2)}';
  }

  String _fechaSql(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _textoRequerido(Object? value, String field) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) throw FormatException('Texto obligatorio en $field.');
    return text;
  }

  String? _limpiar(String? value) {
    final clean = value?.trim() ?? '';
    return clean.isEmpty ? null : clean;
  }
}

class SupabaseSesionesClaseDataSource implements SesionesClaseDataSource {
  SupabaseSesionesClaseDataSource(
    this._supabase, {
    this.codec = const SesionesClaseSqlCodec(),
  });

  final SupabaseClient _supabase;
  final SesionesClaseSqlCodec codec;

  @override
  Future<List<SesionClase>> obtenerTodas(String uid) async {
    final rows = await _supabase
        .from('sesiones_clase')
        .select(
          'id, asignatura_id, periodo_academico_id, fecha, hora_inicio, '
          'hora_fin, sala, origen',
        )
        .eq('usuario_uid', uid)
        .order('fecha')
        .order('hora_inicio');
    return [
      for (final row in rows) codec.desdeFila(Map<String, dynamic>.from(row)),
    ];
  }

  @override
  Future<SesionClase> agregar(String uid, SesionClase sesion) {
    return _guardar('crear', sesion);
  }

  @override
  Future<SesionClase> actualizar(String uid, SesionClase sesion) {
    return _guardar('actualizar', sesion);
  }

  Future<SesionClase> _guardar(String operacion, SesionClase sesion) async {
    final result = await _supabase.rpc(
      'guardar_sesion_clase',
      params: {'p_operacion': operacion, 'p_sesion': codec.payload(sesion)},
    );
    if (result is! Map) {
      throw const FormatException('Supabase no devolvió la sesión guardada.');
    }
    return codec.desdeFila(Map<String, dynamic>.from(result));
  }

  @override
  Future<void> eliminar(String uid, String id) async {
    await _supabase.rpc('eliminar_sesion_clase', params: {'p_sesion_id': id});
  }
}

class SesionesClaseService {
  SesionesClaseService({
    SesionesClaseDataSource? dataSource,
    SupabaseClient? supabase,
    FirebaseAuth? firebaseAuth,
    String Function()? uidProvider,
  }) : _dataSource =
           dataSource ??
           SupabaseSesionesClaseDataSource(
             supabase ?? Supabase.instance.client,
           ),
       _auth = firebaseAuth,
       _obtenerUid = uidProvider;

  final SesionesClaseDataSource _dataSource;
  final FirebaseAuth? _auth;
  final String Function()? _obtenerUid;

  Future<List<SesionClase>> obtenerTodas() {
    return _dataSource.obtenerTodas(_uid());
  }

  Future<SesionClase> agregar(SesionClase sesion) {
    return _dataSource.agregar(_uid(), sesion);
  }

  Future<SesionClase> actualizar(SesionClase sesion) {
    return _dataSource.actualizar(_uid(), sesion);
  }

  Future<void> eliminar(String id) {
    return _dataSource.eliminar(_uid(), id);
  }

  String _uid() {
    final custom = _obtenerUid;
    if (custom != null) return custom();
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) {
      throw StateError('Inicia sesión antes de gestionar sesiones.');
    }
    return user.uid;
  }
}
