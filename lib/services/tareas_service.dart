import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/tarea.dart';
import 'notification_state_service.dart';

abstract interface class TareasDataSource {
  Future<List<Tarea>> obtenerTodas(String uid);
  Future<Tarea?> obtenerPorId(String uid, String id);
  Future<Tarea> crear(String uid, Tarea tarea);
  Future<Tarea> actualizar(String uid, Tarea tarea);
  Future<void> eliminar(String uid, String id);
  Stream<void> observarCambios(String uid);
}

class TareasSqlCodec {
  const TareasSqlCodec();

  Tarea desdeFila(Map<String, dynamic> fila) {
    final id = fila['id']?.toString().trim() ?? '';
    final titulo = fila['titulo']?.toString().trim() ?? '';
    final prioridad = prioridadTareaDesdeValor(fila['prioridad']);
    final estado = estadoTareaDesdeValor(fila['estado']);
    final completadaEn = _timestampNullable(fila['completada_en']);

    if (id.isEmpty || titulo.isEmpty) {
      throw const FormatException(
        'La tarea SQL no contiene sus campos obligatorios.',
      );
    }
    if ((estado == EstadoTarea.pendiente && completadaEn != null) ||
        (estado == EstadoTarea.completada && completadaEn == null)) {
      throw const FormatException(
        'El estado y la fecha de finalización de la tarea no son coherentes.',
      );
    }

    return Tarea(
      id: id,
      titulo: titulo,
      descripcion: _textoNullable(fila['descripcion']),
      asignaturaId: _textoNullable(fila['asignatura_id']),
      prioridad: prioridad,
      estado: estado,
      fechaEntrega: _fechaNullable(fila['fecha_entrega']),
      horaEntrega: normalizarHora(fila['hora_entrega']),
      creadaEn: _timestamp(fila['creada_en'], 'creada_en'),
      actualizadaEn: _timestamp(fila['actualizada_en'], 'actualizada_en'),
      completadaEn: completadaEn,
    );
  }

  Map<String, dynamic> payload(Tarea tarea) => {
    if (tarea.id.trim().isNotEmpty) 'id': tarea.id.trim(),
    'titulo': tarea.titulo.trim(),
    'descripcion': _limpiar(tarea.descripcion),
    'asignatura_id': _limpiar(tarea.asignaturaId),
    'prioridad': tarea.prioridad.valorPersistencia,
    'estado': tarea.estado.valorPersistencia,
    'fecha_entrega': _fechaSqlNullable(tarea.fechaEntrega),
    'hora_entrega': normalizarHora(tarea.horaEntrega),
    'completada_en': tarea.completadaEn?.toUtc().toIso8601String(),
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
    final hora = int.parse(coincidencia.group(1)!);
    final minuto = int.parse(coincidencia.group(2)!);
    if (hora > 23 || minuto > 59) {
      throw FormatException('Hora SQL no válida: $texto');
    }
    return '${coincidencia.group(1)}:${coincidencia.group(2)}';
  }

  DateTime? _fechaNullable(Object? valor) {
    if (valor == null) return null;
    if (valor is DateTime) {
      return DateTime(valor.year, valor.month, valor.day);
    }
    final texto = valor.toString().trim();
    if (texto.isEmpty) return null;
    final coincidencia = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(
      texto,
    );
    if (coincidencia == null) {
      throw FormatException('Fecha SQL no válida: $texto');
    }
    final fecha = DateTime(
      int.parse(coincidencia.group(1)!),
      int.parse(coincidencia.group(2)!),
      int.parse(coincidencia.group(3)!),
    );
    if (_fechaSqlNullable(fecha) != texto) {
      throw FormatException('Fecha SQL no válida: $texto');
    }
    return fecha;
  }

  DateTime _timestamp(Object? valor, String campo) {
    final timestamp = valor is DateTime
        ? valor
        : DateTime.tryParse(valor?.toString() ?? '');
    if (timestamp == null) {
      throw FormatException('Timestamp SQL no válido en $campo.');
    }
    return timestamp.toLocal();
  }

  DateTime? _timestampNullable(Object? valor) {
    if (valor == null || valor.toString().trim().isEmpty) return null;
    return _timestamp(valor, 'completada_en');
  }

  String? _textoNullable(Object? valor) => _limpiar(valor?.toString());

  String? _limpiar(String? valor) {
    final limpio = valor?.trim() ?? '';
    return limpio.isEmpty ? null : limpio;
  }

  String? _fechaSqlNullable(DateTime? fecha) {
    if (fecha == null) return null;
    return '${fecha.year.toString().padLeft(4, '0')}-'
        '${fecha.month.toString().padLeft(2, '0')}-'
        '${fecha.day.toString().padLeft(2, '0')}';
  }
}

class SupabaseTareasDataSource implements TareasDataSource {
  SupabaseTareasDataSource(
    this._supabase, {
    this.codec = const TareasSqlCodec(),
  });

  final SupabaseClient _supabase;
  final TareasSqlCodec codec;
  static int _canalSecuencia = 0;

  static const _columnas =
      'id, titulo, descripcion, asignatura_id, prioridad, estado, '
      'fecha_entrega, hora_entrega, creada_en, actualizada_en, completada_en';

  @override
  Future<List<Tarea>> obtenerTodas(String uid) async {
    final resultado = await _supabase
        .from('tareas')
        .select(_columnas)
        .eq('usuario_uid', uid);
    return resultado.map<Tarea>(codec.desdeFila).toList();
  }

  @override
  Future<Tarea?> obtenerPorId(String uid, String id) async {
    final resultado = await _supabase
        .from('tareas')
        .select(_columnas)
        .eq('usuario_uid', uid)
        .eq('id', id)
        .maybeSingle();
    return resultado == null ? null : codec.desdeFila(resultado);
  }

  @override
  Future<Tarea> crear(String uid, Tarea tarea) async {
    final resultado = await _supabase.rpc<dynamic>(
      'guardar_tarea',
      params: {
        'p_operacion': 'crear',
        'p_tarea': codec.payload(tarea),
      },
    );
    return codec.desdeFila(Map<String, dynamic>.from(resultado as Map));
  }

  @override
  Future<Tarea> actualizar(String uid, Tarea tarea) async {
    final resultado = await _supabase.rpc<dynamic>(
      'guardar_tarea',
      params: {
        'p_operacion': 'actualizar',
        'p_tarea': codec.payload(tarea),
      },
    );
    return codec.desdeFila(Map<String, dynamic>.from(resultado as Map));
  }

  @override
  Future<void> eliminar(String uid, String id) {
    return _supabase.rpc<void>(
      'eliminar_tarea',
      params: {'p_tarea_id': id},
    );
  }

  @override
  Stream<void> observarCambios(String uid) {
    RealtimeChannel? canal;
    late StreamController<void> controlador;

    controlador = StreamController<void>(
      onListen: () {
        canal = _supabase
            .channel('tareas-$uid-${_canalSecuencia++}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'tareas',
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

class TareasService {
  TareasService({
    TareasDataSource? dataSource,
    SupabaseClient? supabase,
    FirebaseAuth? firebaseAuth,
    String Function()? uidProvider,
    Future<void> Function(String notificationId)? limpiarEstadoNotificacion,
  }) : _dataSource =
           dataSource ??
           SupabaseTareasDataSource(supabase ?? Supabase.instance.client),
       _auth = firebaseAuth,
       _obtenerUid = uidProvider,
       _limpiarEstadoNotificacion =
           limpiarEstadoNotificacion ??
           NotificationStateService.instance.eliminarEstado;

  static final TareasService instance = TareasService();

  final TareasDataSource _dataSource;
  final FirebaseAuth? _auth;
  final String Function()? _obtenerUid;

  /// Dependencia temporal: estadoNotificaciones continúa en Firestore.
  final Future<void> Function(String notificationId)
  _limpiarEstadoNotificacion;

  int _versionDatos = 0;

  int get versionDatos => _versionDatos;

  Future<List<Tarea>> obtenerTodas() async {
    final tareas = await _dataSource.obtenerTodas(_uidActual());
    tareas.sort(_compararTareas);
    return tareas;
  }

  Future<Tarea?> obtenerPorId(String id) {
    final limpio = id.trim();
    if (limpio.isEmpty) return Future.value();
    return _dataSource.obtenerPorId(_uidActual(), limpio);
  }

  Future<Tarea> crear({
    required String titulo,
    String? descripcion,
    String? asignaturaId,
    PrioridadTarea prioridad = PrioridadTarea.media,
    DateTime? fechaEntrega,
    String? horaEntrega,
  }) async {
    final tituloLimpio = titulo.trim();
    if (tituloLimpio.isEmpty) {
      throw ArgumentError('El título de la tarea es obligatorio.');
    }

    final ahora = DateTime.now();
    final tarea = Tarea(
      id: '',
      titulo: tituloLimpio,
      descripcion: _limpiarNullable(descripcion),
      asignaturaId: _limpiarNullable(asignaturaId),
      prioridad: prioridad,
      estado: EstadoTarea.pendiente,
      fechaEntrega: fechaEntrega == null
          ? null
          : DateTime(fechaEntrega.year, fechaEntrega.month, fechaEntrega.day),
      horaEntrega: _normalizarHoraNullable(horaEntrega),
      creadaEn: ahora,
      actualizadaEn: ahora,
    );
    final creada = await _dataSource.crear(_uidActual(), tarea);
    _marcarComoActualizado();
    return creada;
  }

  Future<Tarea> actualizar(Tarea tarea) async {
    final id = tarea.id.trim();
    final titulo = tarea.titulo.trim();
    if (id.isEmpty || titulo.isEmpty) {
      throw ArgumentError('El ID y el título de la tarea son obligatorios.');
    }
    _validarCoherencia(tarea);

    final actualizada = tarea.copyWith(
      id: id,
      titulo: titulo,
      descripcion: _limpiarNullable(tarea.descripcion),
      limpiarDescripcion: _limpiarNullable(tarea.descripcion) == null,
      asignaturaId: _limpiarNullable(tarea.asignaturaId),
      limpiarAsignatura: _limpiarNullable(tarea.asignaturaId) == null,
      fechaEntrega: tarea.fechaEntrega == null
          ? null
          : DateTime(
              tarea.fechaEntrega!.year,
              tarea.fechaEntrega!.month,
              tarea.fechaEntrega!.day,
            ),
      limpiarFechaEntrega: tarea.fechaEntrega == null,
      horaEntrega: _normalizarHoraNullable(tarea.horaEntrega),
      limpiarHoraEntrega: _normalizarHoraNullable(tarea.horaEntrega) == null,
      actualizadaEn: DateTime.now(),
    );
    final guardada = await _dataSource.actualizar(_uidActual(), actualizada);
    _marcarComoActualizado();
    return guardada;
  }

  Future<Tarea> cambiarEstado({
    required Tarea tarea,
    required bool completada,
  }) {
    final ahora = DateTime.now();
    return actualizar(
      tarea.copyWith(
        estado: completada ? EstadoTarea.completada : EstadoTarea.pendiente,
        completadaEn: completada ? ahora : null,
        limpiarCompletadaEn: !completada,
        actualizadaEn: ahora,
      ),
    );
  }

  Future<void> eliminar(String id) async {
    final limpio = id.trim();
    if (limpio.isEmpty) return;

    await _dataSource.eliminar(_uidActual(), limpio);
    _marcarComoActualizado();

    try {
      await _limpiarEstadoNotificacion('tarea-$limpio');
    } catch (_) {
      // La tarea SQL ya fue eliminada. La metadata residual de Firestore se
      // limpia best-effort y nunca debe revertir ni ocultar ese resultado.
    }
  }

  Stream<void> observarCambios() {
    return _dataSource.observarCambios(_uidActual()).map((_) {
      _marcarComoActualizado();
    });
  }

  int _compararTareas(Tarea a, Tarea b) {
    if (a.estado != b.estado) return a.pendiente ? -1 : 1;
    if (a.fechaEntrega == null && b.fechaEntrega != null) return 1;
    if (a.fechaEntrega != null && b.fechaEntrega == null) return -1;
    if (a.fechaEntrega != null && b.fechaEntrega != null) {
      final fecha = a.fechaEntrega!.compareTo(b.fechaEntrega!);
      if (fecha != 0) return fecha;
      final hora = _minutosHora(a.horaEntrega).compareTo(
        _minutosHora(b.horaEntrega),
      );
      if (hora != 0) return hora;
    }
    return b.creadaEn.compareTo(a.creadaEn);
  }

  int _minutosHora(String? value) {
    final hora = value?.trim() ?? '';
    if (hora.isEmpty) return 24 * 60;
    final partes = hora.split(':');
    if (partes.length != 2) return 24 * 60;
    final horas = int.tryParse(partes[0]);
    final minutos = int.tryParse(partes[1]);
    if (horas == null ||
        minutos == null ||
        horas < 0 ||
        horas > 23 ||
        minutos < 0 ||
        minutos > 59) {
      return 24 * 60;
    }
    return (horas * 60) + minutos;
  }

  String _uidActual() {
    final proveedor = _obtenerUid;
    final uid = proveedor != null
        ? proveedor()
        : (_auth ?? FirebaseAuth.instance).currentUser?.uid;
    final limpio = uid?.trim() ?? '';
    if (limpio.isEmpty) {
      throw StateError('No existe un usuario autenticado.');
    }
    return limpio;
  }

  String? _limpiarNullable(String? value) {
    final limpio = value?.trim() ?? '';
    return limpio.isEmpty ? null : limpio;
  }

  String? _normalizarHoraNullable(String? value) {
    final limpio = value?.trim() ?? '';
    if (limpio.isEmpty) return null;
    if (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(limpio)) {
      throw ArgumentError('La hora debe utilizar el formato HH:mm.');
    }
    return limpio;
  }

  void _validarCoherencia(Tarea tarea) {
    if (tarea.estado == EstadoTarea.pendiente && tarea.completadaEn != null) {
      throw ArgumentError(
        'Una tarea pendiente no puede tener fecha de finalización.',
      );
    }
    if (tarea.estado == EstadoTarea.completada && tarea.completadaEn == null) {
      throw ArgumentError(
        'Una tarea completada debe tener fecha de finalización.',
      );
    }
  }

  void _marcarComoActualizado() => _versionDatos++;
}
