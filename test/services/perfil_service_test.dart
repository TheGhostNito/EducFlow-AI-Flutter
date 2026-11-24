import 'dart:async';

import 'package:eduflow_ai/services/perfil_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> row(String uid) => {
    'uid': uid,
    'nombre': 'Estudiante',
    'correo_principal': '$uid@example.com',
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
    'idioma': 'es',
    'perfil_completo': false,
  };

  test('perfil existente se reutiliza sin escritura', () async {
    final data = _FakePerfilDataSource({'a': row('a')});
    final service = PerfilService(
      dataSource: data,
      isSessionCurrent: () => true,
    );

    final result = await service.asegurarPerfilInicial(
      uid: 'a',
      nombre: 'A',
      correoPrincipal: 'a@example.com',
      idioma: 'es',
    );
    expect(result.uid, 'a');
    expect(data.insertions, 0);
  });

  test('perfil ausente se crea con valores obligatorios', () async {
    final data = _FakePerfilDataSource({});
    final service = PerfilService(
      dataSource: data,
      isSessionCurrent: () => true,
    );

    final result = await service.asegurarPerfilInicial(
      uid: 'a',
      nombre: '',
      correoPrincipal: 'A@EXAMPLE.COM',
      idioma: 'en',
    );
    expect(result.uid, 'a');
    expect(data.insertions, 1);
    expect(data.rows['a']?['nombre'], 'a');
    expect(data.rows['a']?['correo_principal'], 'a@example.com');
  });

  test('dos intentos concurrentes comparten una única creación', () async {
    final data = _FakePerfilDataSource({})..pauseInsert = Completer<void>();
    final service = PerfilService(
      dataSource: data,
      isSessionCurrent: () => true,
    );

    final first = service.asegurarPerfilInicial(
      uid: 'a',
      nombre: 'A',
      correoPrincipal: 'a@example.com',
      idioma: 'es',
    );
    final second = service.asegurarPerfilInicial(
      uid: 'a',
      nombre: 'A',
      correoPrincipal: 'a@example.com',
      idioma: 'es',
    );
    await Future<void>.delayed(Duration.zero);
    data.pauseInsert!.complete();
    final profiles = await Future.wait([first, second]);

    expect(data.insertions, 1);
    expect(profiles.map((value) => value.uid), everyElement('a'));
  });

  test('cambio de sesión antes del upsert impide toda escritura', () async {
    final data = _FakePerfilDataSource({})..pauseRead = Completer<void>();
    var valid = true;
    final service = PerfilService(
      dataSource: data,
      isSessionCurrent: () => valid,
    );

    final future = service.asegurarPerfilInicial(
      uid: 'a',
      nombre: 'A',
      correoPrincipal: 'a@example.com',
      idioma: 'es',
    );
    await Future<void>.delayed(Duration.zero);
    valid = false;
    data.pauseRead!.complete();

    await expectLater(future, throwsStateError);
    expect(data.insertions, 0);
  });
}

class _FakePerfilDataSource implements PerfilDataSource {
  _FakePerfilDataSource(this.rows);

  final Map<String, Map<String, dynamic>> rows;
  Completer<void>? pauseRead;
  Completer<void>? pauseInsert;
  int insertions = 0;

  @override
  Future<Map<String, dynamic>?> obtener(String uid) async {
    await pauseRead?.future;
    pauseRead = null;
    return rows[uid];
  }

  @override
  Future<void> insertarSiFalta(Map<String, dynamic> values) async {
    insertions++;
    await pauseInsert?.future;
    rows.putIfAbsent(
      values['uid'] as String,
      () => Map<String, dynamic>.from(values),
    );
  }

  @override
  Future<void> actualizar(String uid, Map<String, dynamic> values) async {
    rows[uid]?.addAll(values);
  }
}
