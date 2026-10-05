import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../models/nota.dart';
import '../models/asignatura.dart';
import '../models/evaluacion.dart';
import '../models/perfil_usuario.dart';

class DatosNotasUsuario {
  const DatosNotasUsuario({
    required this.asignaturas,
    required this.evaluaciones,
    required this.configuracion,
    required this.calificaciones,
    required this.objetivos,
    this.configuracionesCalculo = const {},
    this.nivelEducativo = NivelEducativoPerfil.vacio,
  });

  final List<Asignatura> asignaturas;
  final List<Evaluacion> evaluaciones;
  final ConfiguracionNotas configuracion;
  final Map<String, CalificacionEvaluacion> calificaciones;
  final Map<String, ObjetivoNotaAsignatura> objetivos;
  final Map<String, ConfiguracionCalculoAsignatura> configuracionesCalculo;
  final NivelEducativoPerfil nivelEducativo;
}

abstract interface class NotasDataSource {
  Future<List<Map<String, dynamic>>> obtenerAsignaturas(String uid);
  Future<List<Map<String, dynamic>>> obtenerEvaluaciones(String uid);
  Future<Map<String, dynamic>?> obtenerConfiguracion(String uid);
  Future<List<Map<String, dynamic>>> obtenerCalificaciones(String uid);
  Future<List<Map<String, dynamic>>> obtenerObjetivos(String uid);
  Future<List<Map<String, dynamic>>> obtenerConfiguracionesCalculo(String uid);
  Future<Map<String, dynamic>?> obtenerNivelEducativo(String uid);
  Future<void> guardarConfiguracion(Map<String, dynamic> values);
  Future<void> guardarCalificacion(Map<String, dynamic> values);
  Future<void> eliminarCalificacion(String uid, String evaluacionId);
  Future<void> guardarObjetivo(Map<String, dynamic> values);
  Future<void> guardarConfiguracionCalculo(Map<String, dynamic> values);
  Future<void> guardarPonderacion(
    String uid,
    String evaluacionId,
    double? ponderacion,
  );
}

class SupabaseNotasDataSource implements NotasDataSource {
  SupabaseNotasDataSource(this._supabase);

  final SupabaseClient _supabase;

  @override
  Future<List<Map<String, dynamic>>> obtenerAsignaturas(String uid) async {
    final resultado = await _supabase
        .from('asignaturas')
        .select(
          'id, nombre, profesor, correo_profesor, sala, periodo, estado, '
          'origen, sigla, seccion, creditos, semestre_malla, curso_nivel, '
          'anio_academico, modalidad, lugar, institucion',
        )
        .eq('usuario_uid', uid)
        .order('nombre');
    return resultado
        .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> obtenerEvaluaciones(String uid) async {
    final resultado = await _supabase
        .from('evaluaciones')
        .select(
          'id, asignatura_id, titulo, tipo, fecha, hora, descripcion, '
          'ponderacion, creada_en, actualizada_en',
        )
        .eq('usuario_uid', uid)
        .order('fecha');
    return resultado
        .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  @override
  Future<Map<String, dynamic>?> obtenerConfiguracion(String uid) async {
    final resultado = await _supabase
        .from('configuracion_notas')
        .select()
        .eq('usuario_uid', uid)
        .maybeSingle();
    return resultado == null ? null : Map<String, dynamic>.from(resultado);
  }

  @override
  Future<List<Map<String, dynamic>>> obtenerCalificaciones(String uid) async {
    final resultado = await _supabase
        .from('notas_evaluaciones')
        .select('evaluacion_id, nota')
        .eq('usuario_uid', uid);
    return resultado
        .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> obtenerObjetivos(String uid) async {
    final resultado = await _supabase
        .from('objetivos_notas')
        .select('asignatura_id, nota_objetivo')
        .eq('usuario_uid', uid);
    return resultado
        .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> obtenerConfiguracionesCalculo(
    String uid,
  ) async {
    final resultado = await _supabase
        .from('configuracion_calculo_asignaturas')
        .select(
          'asignatura_id, esquema, peso_presentacion, peso_examen, '
          'evaluacion_examen_id',
        )
        .eq('usuario_uid', uid);
    return resultado
        .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  @override
  Future<Map<String, dynamic>?> obtenerNivelEducativo(String uid) async {
    final resultado = await _supabase
        .from('usuarios')
        .select('nivel_educativo')
        .eq('uid', uid)
        .maybeSingle();
    return resultado == null ? null : Map<String, dynamic>.from(resultado);
  }

  @override
  Future<void> guardarConfiguracion(Map<String, dynamic> values) async {
    await _supabase
        .from('configuracion_notas')
        .upsert(values, onConflict: 'usuario_uid');
  }

  @override
  Future<void> guardarCalificacion(Map<String, dynamic> values) async {
    await _supabase
        .from('notas_evaluaciones')
        .upsert(values, onConflict: 'usuario_uid,evaluacion_id');
  }

  @override
  Future<void> eliminarCalificacion(String uid, String evaluacionId) async {
    await _supabase
        .from('notas_evaluaciones')
        .delete()
        .eq('usuario_uid', uid)
        .eq('evaluacion_id', evaluacionId);
  }

  @override
  Future<void> guardarObjetivo(Map<String, dynamic> values) async {
    await _supabase
        .from('objetivos_notas')
        .upsert(values, onConflict: 'usuario_uid,asignatura_id');
  }

  @override
  Future<void> guardarConfiguracionCalculo(Map<String, dynamic> values) async {
    await _supabase
        .from('configuracion_calculo_asignaturas')
        .upsert(values, onConflict: 'usuario_uid,asignatura_id');
  }

  @override
  Future<void> guardarPonderacion(
    String uid,
    String evaluacionId,
    double? ponderacion,
  ) async {
    await _supabase
        .from('evaluaciones')
        .update({
          'ponderacion': ponderacion,
          'actualizada_en': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('usuario_uid', uid)
        .eq('id', evaluacionId);
  }
}

class NotasService {
  NotasService({
    NotasDataSource? dataSource,
    this._firebaseAuth,
    this._uidProvider,
    SupabaseClient? supabase,
  }) : _dataSource =
           dataSource ??
           SupabaseNotasDataSource(supabase ?? Supabase.instance.client);

  static final NotasService instance = NotasService();

  final NotasDataSource _dataSource;
  final FirebaseAuth? _firebaseAuth;
  final String Function()? _uidProvider;

  String get _uid {
    final providedUid = _uidProvider?.call().trim();
    if (providedUid != null && providedUid.isNotEmpty) return providedUid;
    final usuario = (_firebaseAuth ?? FirebaseAuth.instance).currentUser;
    if (usuario == null) {
      throw StateError('No existe un usuario autenticado.');
    }
    return usuario.uid;
  }

  Future<DatosNotasUsuario> obtenerDatos() async {
    final String uid = _uid;
    final resultados = await Future.wait<Object?>([
      _dataSource.obtenerAsignaturas(uid),
      _dataSource.obtenerEvaluaciones(uid),
      _dataSource.obtenerConfiguracion(uid),
      _dataSource.obtenerCalificaciones(uid),
      _dataSource.obtenerObjetivos(uid),
      _dataSource.obtenerConfiguracionesCalculo(uid),
      _dataSource.obtenerNivelEducativo(uid),
    ]);

    final asignaturasMap = resultados[0] as List<Map<String, dynamic>>;
    final evaluacionesMap = resultados[1] as List<Map<String, dynamic>>;
    final configuracionMap = resultados[2] as Map<String, dynamic>?;
    final calificacionesMap = resultados[3] as List<Map<String, dynamic>>;
    final objetivosMap = resultados[4] as List<Map<String, dynamic>>;
    final configuracionesCalculoMap =
        resultados[5] as List<Map<String, dynamic>>;
    final nivelEducativoMap = resultados[6] as Map<String, dynamic>?;

    final asignaturas = asignaturasMap.map(_asignaturaDesdeSql).toList();
    final evaluaciones = evaluacionesMap.map(_evaluacionDesdeSql).toList();

    final ConfiguracionNotas configuracion = configuracionMap == null
        ? ConfiguracionNotas.predeterminada
        : ConfiguracionNotas.fromMap(configuracionMap);
    if (!configuracion.esValida) {
      throw const FormatException(
        'La configuración de notas almacenada no es válida.',
      );
    }

    final calificaciones = <String, CalificacionEvaluacion>{};
    for (final map in calificacionesMap) {
      final item = CalificacionEvaluacion.fromMap(map);
      if (item.evaluacionId.isNotEmpty) {
        calificaciones[item.evaluacionId] = item;
      }
    }

    final objetivos = <String, ObjetivoNotaAsignatura>{};
    for (final map in objetivosMap) {
      final item = ObjetivoNotaAsignatura.fromMap(map);
      if (item.asignaturaId.isNotEmpty) {
        objetivos[item.asignaturaId] = item;
      }
    }

    final configuracionesCalculo = <String, ConfiguracionCalculoAsignatura>{};
    for (final map in configuracionesCalculoMap) {
      final item = ConfiguracionCalculoAsignatura.fromMap(map);
      if (!item.esValida) {
        throw const FormatException(
          'La configuración académica de una asignatura no es válida.',
        );
      }
      configuracionesCalculo[item.asignaturaId] = item;
    }

    return DatosNotasUsuario(
      asignaturas: List.unmodifiable(asignaturas),
      evaluaciones: List.unmodifiable(evaluaciones),
      configuracion: configuracion,
      calificaciones: Map.unmodifiable(calificaciones),
      objetivos: Map.unmodifiable(objetivos),
      configuracionesCalculo: Map.unmodifiable(configuracionesCalculo),
      nivelEducativo: nivelEducativoDesdeFirestore(
        nivelEducativoMap?['nivel_educativo'],
      ),
    );
  }

  Future<void> guardarConfiguracion(ConfiguracionNotas configuracion) async {
    if (!configuracion.esValida) {
      throw ArgumentError('La configuración de notas no es válida.');
    }
    await _dataSource.guardarConfiguracion(configuracion.toMap(_uid));
  }

  Future<void> guardarCalificacion(
    CalificacionEvaluacion calificacion,
    ConfiguracionNotas configuracion,
  ) async {
    if (!calificacion.nota.isFinite ||
        calificacion.nota < configuracion.notaMinima ||
        calificacion.nota > configuracion.notaMaxima) {
      throw ArgumentError('La nota está fuera de la escala configurada.');
    }
    if (calificacion.evaluacionId.trim().isEmpty) {
      throw ArgumentError('La evaluación es obligatoria.');
    }
    await _dataSource.guardarCalificacion(calificacion.toMap(_uid));
  }

  Future<void> guardarPonderacion(
    String evaluacionId,
    double? ponderacion,
  ) async {
    final cleanId = evaluacionId.trim();
    if (cleanId.isEmpty) {
      throw ArgumentError('La evaluación es obligatoria.');
    }
    if (ponderacion != null &&
        (!ponderacion.isFinite || ponderacion < 0 || ponderacion > 100)) {
      throw ArgumentError('La ponderación debe estar entre 0 y 100.');
    }
    await _dataSource.guardarPonderacion(_uid, cleanId, ponderacion);
  }

  Future<void> eliminarCalificacion(String evaluacionId) async {
    final cleanId = evaluacionId.trim();
    if (cleanId.isEmpty) return;
    await _dataSource.eliminarCalificacion(_uid, cleanId);
  }

  Future<void> guardarObjetivo(
    ObjetivoNotaAsignatura objetivo,
    ConfiguracionNotas configuracion,
  ) async {
    if (!objetivo.notaObjetivo.isFinite ||
        objetivo.notaObjetivo < configuracion.notaMinima ||
        objetivo.notaObjetivo > configuracion.notaMaxima) {
      throw ArgumentError('El objetivo está fuera de la escala configurada.');
    }
    if (objetivo.asignaturaId.trim().isEmpty) {
      throw ArgumentError('La asignatura es obligatoria.');
    }
    await _dataSource.guardarObjetivo(objetivo.toMap(_uid));
  }

  Future<void> guardarConfiguracionCalculo(
    ConfiguracionCalculoAsignatura configuracion,
  ) async {
    if (!configuracion.esValida) {
      throw ArgumentError('La configuración académica no es válida.');
    }
    await _dataSource.guardarConfiguracionCalculo(configuracion.toMap(_uid));
  }
}

Asignatura _asignaturaDesdeSql(Map<String, dynamic> data) {
  return Asignatura(
    id: data['id']?.toString() ?? '',
    nombre: data['nombre']?.toString() ?? '',
    profesor: data['profesor']?.toString(),
    correoProfesor: data['correo_profesor']?.toString(),
    sala: data['sala']?.toString(),
    periodo: data['periodo']?.toString(),
    estado: estadoAsignaturaDesdeFirestore(data['estado']),
    origen: origenAsignaturaDesdeFirestore(data['origen']),
    sigla: data['sigla']?.toString(),
    seccion: data['seccion']?.toString(),
    creditos: _intSql(data['creditos']),
    semestreMalla: _intSql(data['semestre_malla']),
    cursoNivel: data['curso_nivel']?.toString(),
    anioAcademico: _intSql(data['anio_academico']),
    modalidad: data['modalidad']?.toString(),
    lugar: data['lugar']?.toString(),
    institucion: data['institucion']?.toString(),
  );
}

Evaluacion _evaluacionDesdeSql(Map<String, dynamic> data) {
  final fecha = DateTime.tryParse(data['fecha']?.toString() ?? '');
  if (fecha == null) {
    throw const FormatException('La fecha de una evaluación no es válida.');
  }
  final creadaEn = DateTime.tryParse(data['creada_en']?.toString() ?? '');
  final actualizadaEn = DateTime.tryParse(
    data['actualizada_en']?.toString() ?? '',
  );
  return Evaluacion(
    id: data['id']?.toString() ?? '',
    titulo: data['titulo']?.toString() ?? '',
    asignaturaId: data['asignatura_id']?.toString() ?? '',
    tipo: TipoEvaluacionFirestore.fromFirestore(data['tipo']?.toString()),
    fecha: fecha,
    hora: data['hora']?.toString(),
    descripcion: data['descripcion']?.toString(),
    ponderacion: _doubleSql(data['ponderacion']),
    creadaEn: creadaEn ?? fecha,
    actualizadaEn: actualizadaEn ?? creadaEn ?? fecha,
  );
}

int? _intSql(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _doubleSql(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}
