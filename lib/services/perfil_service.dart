import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../models/perfil_usuario.dart';

abstract interface class PerfilDataSource {
  Future<Map<String, dynamic>?> obtener(String uid);
  Future<void> insertarSiFalta(Map<String, dynamic> values);
  Future<void> actualizar(String uid, Map<String, dynamic> values);
}

class SupabasePerfilDataSource implements PerfilDataSource {
  SupabasePerfilDataSource(this._supabase);

  final SupabaseClient _supabase;

  @override
  Future<Map<String, dynamic>?> obtener(String uid) async {
    final resultado = await _supabase
        .from('usuarios')
        .select('''
          uid,
          nombre,
          correo_principal,
          correo_institucional,
          nivel_educativo,
          nombre_establecimiento,
          tipo_establecimiento,
          curso_actual,
          carrera,
          semestre_actual,
          anio_ingreso,
          sede,
          jornada,
          estado_academico,
          idioma,
          perfil_completo
          ''')
        .eq('uid', uid)
        .maybeSingle();
    return resultado == null ? null : Map<String, dynamic>.from(resultado);
  }

  @override
  Future<void> insertarSiFalta(Map<String, dynamic> values) async {
    await _supabase
        .from('usuarios')
        .upsert(values, onConflict: 'uid', ignoreDuplicates: true);
  }

  @override
  Future<void> actualizar(String uid, Map<String, dynamic> values) async {
    await _supabase.from('usuarios').update(values).eq('uid', uid);
  }
}

class PerfilService {
  PerfilService({
    SupabaseClient? supabase,
    this.firebaseAuth,
    PerfilDataSource? dataSource,
    this.isSessionCurrent,
  }) : _dataSource =
           dataSource ??
           SupabasePerfilDataSource(supabase ?? Supabase.instance.client);

  final PerfilDataSource _dataSource;
  final FirebaseAuth? firebaseAuth;
  final bool Function()? isSessionCurrent;
  final Map<String, Future<PerfilUsuario>> _pendingInitialProfiles = {};

  // =========================================================
  // VALIDAR USUARIO ACTUAL
  // =========================================================

  void _validarUsuario(String uid) {
    final validSession = isSessionCurrent;
    if (validSession != null && !validSession()) {
      throw StateError(
        'La operación de perfil fue invalidada por un cambio de sesión.',
      );
    }
    if (validSession != null) {
      return;
    }

    final usuarioActual = (firebaseAuth ?? FirebaseAuth.instance).currentUser;

    if (usuarioActual == null || usuarioActual.uid != uid) {
      throw StateError(
        'La operación de perfil no corresponde al usuario autenticado.',
      );
    }
  }

  // =========================================================
  // ASEGURAR PERFIL INICIAL
  // =========================================================

  Future<PerfilUsuario> asegurarPerfilInicial({
    required String uid,
    required String nombre,
    required String correoPrincipal,
    required String idioma,
  }) async {
    final existingPending = _pendingInitialProfiles[uid];
    if (existingPending != null) {
      return existingPending;
    }

    final future = _asegurarPerfilInicial(
      uid: uid,
      nombre: nombre,
      correoPrincipal: correoPrincipal,
      idioma: idioma,
    );
    _pendingInitialProfiles[uid] = future;
    try {
      return await future;
    } finally {
      if (identical(_pendingInitialProfiles[uid], future)) {
        _pendingInitialProfiles.remove(uid);
      }
    }
  }

  Future<PerfilUsuario> _asegurarPerfilInicial({
    required String uid,
    required String nombre,
    required String correoPrincipal,
    required String idioma,
  }) async {
    _validarUsuario(uid);

    final existente = await obtenerPerfil(uid);
    if (existente != null) {
      return existente;
    }

    final correo = correoPrincipal.trim().toLowerCase();
    if (correo.isEmpty) {
      throw StateError('No existe un correo seguro para crear el perfil.');
    }

    final nombreSeguro = nombre.trim().isNotEmpty
        ? nombre.trim()
        : correo.split('@').first;

    // Esta validación inmediata es deliberada: una lectura lenta no puede
    // terminar creando el perfil de un UID que ya dejó de ser la sesión.
    _validarUsuario(uid);
    await _dataSource.insertarSiFalta({
      'uid': uid,
      'nombre': nombreSeguro,
      'correo_principal': correo,
      'correo_institucional': '',
      'nivel_educativo': null,
      'nombre_establecimiento': '',
      'tipo_establecimiento': '',
      'curso_actual': '',
      'carrera': '',
      'semestre_actual': null,
      'anio_ingreso': null,
      'sede': '',
      'jornada': '',
      'estado_academico': '',
      'idioma': idioma == 'en' ? 'en' : 'es',
      'perfil_completo': false,
    });

    final creado = await obtenerPerfil(uid);
    if (creado == null) {
      throw StateError('No fue posible asegurar el perfil del usuario.');
    }
    return creado;
  }

  // =========================================================
  // OBTENER PERFIL
  // =========================================================

  Future<PerfilUsuario?> obtenerPerfil(String uid) async {
    _validarUsuario(uid);

    final resultado = await _dataSource.obtener(uid);

    if (resultado == null) {
      return null;
    }

    return PerfilUsuario.fromMap({
      'uid': resultado['uid'],
      'nombre': resultado['nombre'],
      'correoPrincipal': resultado['correo_principal'],
      'correoInstitucional': resultado['correo_institucional'],
      'nivelEducativo': resultado['nivel_educativo'],
      'nombreEstablecimiento': resultado['nombre_establecimiento'],
      'tipoEstablecimiento': resultado['tipo_establecimiento'],
      'cursoActual': resultado['curso_actual'],
      'carrera': resultado['carrera'],
      'semestreActual': resultado['semestre_actual'],
      'anioIngreso': resultado['anio_ingreso'],
      'sede': resultado['sede'],
      'jornada': resultado['jornada'],
      'estadoAcademico': resultado['estado_academico'],
      'idioma': resultado['idioma'],
      'perfilCompleto': resultado['perfil_completo'],
    }, uidFallback: uid);
  }

  // =========================================================
  // ACTUALIZAR PERFIL
  // =========================================================

  Future<void> actualizarPerfil(
    String uid,
    ActualizarPerfilUsuario datos,
  ) async {
    _validarUsuario(uid);

    final String nombre = datos.nombre.trim();

    final String correoInstitucional = datos.correoInstitucional
        .trim()
        .toLowerCase();

    final String nombreEstablecimiento = datos.nombreEstablecimiento.trim();

    final String tipoEstablecimiento = datos.tipoEstablecimiento.trim();

    final String cursoActual = datos.cursoActual.trim();

    final String carrera = datos.carrera.trim();

    final String sede = datos.sede.trim();

    final String jornada = datos.jornada.trim();

    final String estadoAcademico = datos.estadoAcademico.trim();

    final bool perfilCompleto = _comprobarPerfilCompleto(
      nombre: nombre,
      nivelEducativo: datos.nivelEducativo,
      nombreEstablecimiento: nombreEstablecimiento,
      cursoActual: cursoActual,
      carrera: carrera,
      semestreActual: datos.semestreActual,
      anioIngreso: datos.anioIngreso,
    );

    await _dataSource.actualizar(uid, {
      'nombre': nombre,
      'correo_institucional': correoInstitucional,
      'nivel_educativo': datos.nivelEducativo == NivelEducativoPerfil.vacio
          ? null
          : datos.nivelEducativo.valorFirestore,
      'nombre_establecimiento': nombreEstablecimiento,
      'tipo_establecimiento': tipoEstablecimiento,
      'curso_actual': cursoActual,
      'carrera': carrera,
      'semestre_actual': datos.semestreActual,
      'anio_ingreso': datos.anioIngreso,
      'sede': sede,
      'jornada': jornada,
      'estado_academico': estadoAcademico,
      'idioma': datos.idioma == 'en' ? 'en' : 'es',
      'perfil_completo': perfilCompleto,
      'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // =========================================================
  // COMPROBAR PERFIL COMPLETO
  // =========================================================

  bool _comprobarPerfilCompleto({
    required String nombre,
    required NivelEducativoPerfil nivelEducativo,
    required String nombreEstablecimiento,
    required String cursoActual,
    required String carrera,
    required int? semestreActual,
    required int? anioIngreso,
  }) {
    final bool datosBaseCompletos =
        nombre.trim().isNotEmpty &&
        nivelEducativo != NivelEducativoPerfil.vacio &&
        nombreEstablecimiento.trim().isNotEmpty &&
        anioIngreso != null &&
        anioIngreso > 0;

    if (!datosBaseCompletos) {
      return false;
    }

    if (nivelEducativo == NivelEducativoPerfil.basica ||
        nivelEducativo == NivelEducativoPerfil.media) {
      return cursoActual.trim().isNotEmpty;
    }

    if (nivelEducativo == NivelEducativoPerfil.superior ||
        nivelEducativo == NivelEducativoPerfil.tecnico) {
      return carrera.trim().isNotEmpty && semestreActual != null;
    }

    if (nivelEducativo == NivelEducativoPerfil.curso ||
        nivelEducativo == NivelEducativoPerfil.otro) {
      return cursoActual.trim().isNotEmpty;
    }

    return false;
  }
}
