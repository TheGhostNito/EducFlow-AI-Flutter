import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;
  late String functionalTestSql;

  setUpAll(() {
    sql = File(
      'supabase/testing/'
      '20261121_03_inicializacion_academica_testing.sql',
    ).readAsStringSync();
    functionalTestSql = File(
      'supabase/testing/'
      '20261121_04_prueba_funcional_seguridad_periodos_sesiones.sql',
    ).readAsStringSync();
  });

  test('crea exclusivamente los tres objetos académicos faltantes', () {
    expect(
      RegExp(r'^create table public\.', multiLine: true).allMatches(sql),
      hasLength(3),
    );
    expect(sql, contains('create table public.asignaturas'));
    expect(sql, contains('create table public.bloques_horario'));
    expect(sql, contains('create table public.relaciones_asignaturas'));
    expect(sql, contains('id bigint generated always as identity'));
    expect(
      RegExp(r'^  constraint ', multiLine: true).allMatches(sql),
      hasLength(15),
    );
    expect(
      RegExp(r'^create index ', multiLine: true).allMatches(sql),
      hasLength(5),
      reason: 'Las otras tres entradas de B3 corresponden a las PK.',
    );
  });

  test('mantiene las claves compuestas y checks productivos', () {
    expect(sql, contains('primary key (usuario_uid, id)'));
    expect(sql, contains('constraint bloques_horario_pkey primary key (id)'));
    expect(
      sql,
      contains('constraint relaciones_asignaturas_pkey primary key ('),
    );
    expect(sql, contains('hora_fin > hora_inicio'));
    expect(sql, contains('asignatura_id <> relacionada_id'));
    expect(
      'references public.asignaturas(usuario_uid, id) on delete cascade'
          .allMatches(sql),
      hasLength(3),
    );
  });

  test(
    'protege las tablas con RLS, permisos y funciones Firebase existentes',
    () {
      expect('enable row level security'.allMatches(sql), hasLength(3));
      expect(
        RegExp(r'^create policy ', multiLine: true).allMatches(sql),
        hasLength(3),
      );
      expect('to authenticated\n  using'.allMatches(sql), hasLength(3));
      expect(
        'grant select, insert, update, delete on table'.allMatches(sql),
        hasLength(3),
      );
      expect(
        sql,
        contains(
          'grant usage on sequence public.bloques_horario_id_seq '
          'to authenticated;',
        ),
      );
      expect(
        sql,
        isNot(contains('create function public.current_firebase_uid')),
      );
      expect(
        sql,
        isNot(contains('create function public.is_educflow_firebase_user')),
      );
    },
  );

  test('incorpora la RPC invoker y la publicación Realtime', () {
    expect(
      sql,
      contains('create function public.guardar_asignatura_completa('),
    );
    expect(sql, contains('security invoker'));
    expect(sql, contains("set search_path = ''"));
    expect(
      'alter publication supabase_realtime add table'.allMatches(sql),
      hasLength(3),
    );
    expect('replica identity full'.allMatches(sql), hasLength(3));
  });

  test('el inicializador es transaccional y no contiene DDL destructivo', () {
    expect(sql, startsWith('-- EducFlow AI'));
    expect(sql, contains('\nbegin;'));
    expect(sql, contains('\ncommit;'));
    expect(RegExp(r'\bdrop\b', caseSensitive: false).hasMatch(sql), isFalse);
    expect(
      RegExp(r'\btruncate\b', caseSensitive: false).hasMatch(sql),
      isFalse,
    );
    expect(sql, isNot(contains('create table if not exists')));
    expect(sql, contains('objeto_academico_testing_ya_existe'));
  });

  test('la prueba funcional usa dos claims simulados y authenticated', () {
    expect(
      "'iss', 'https://securetoken.google.com/eduflow-ai-testing'".allMatches(
        functionalTestSql,
      ),
      hasLength(2),
    );
    expect(
      "'aud', 'eduflow-ai-testing'".allMatches(functionalTestSql),
      hasLength(2),
    );
    expect(
      "'role', 'authenticated'".allMatches(functionalTestSql),
      hasLength(2),
    );
    expect(functionalTestSql, contains('set local role authenticated;'));
    expect(functionalTestSql, contains("'test_horario_a_'"));
    expect(functionalTestSql, contains("'test_horario_b_'"));
    for (final field in [
      'uid',
      'nombre',
      'correo_principal',
      'idioma',
      'perfil_completo',
      'fecha_creacion',
      'fecha_actualizacion',
    ]) {
      expect(
        functionalTestSql,
        contains(field),
        reason: 'El fixture debe completar usuarios.$field.',
      );
    }
    expect('@example.invalid'.allMatches(functionalTestSql), hasLength(2));
  });

  test('la prueba cubre flujo, aislamiento y escrituras directas', () {
    expect(functionalTestSql, contains('public.guardar_periodo_academico('));
    expect(functionalTestSql, contains('public.guardar_asignatura_completa('));
    expect(functionalTestSql, contains('public.asociar_asignatura_periodo('));
    expect(functionalTestSql, contains('public.guardar_sesion_clase('));
    expect(
      'when check_violation then'.allMatches(functionalTestSql),
      hasLength(3),
    );
    expect(
      'when no_data_found then'.allMatches(functionalTestSql),
      hasLength(2),
    );
    expect(
      'when insufficient_privilege then'.allMatches(functionalTestSql),
      hasLength(6),
    );
    expect(functionalTestSql, contains('rls_expuso_datos_del_usuario_b'));
    expect(
      functionalTestSql,
      contains('edicion_manual_perdio_asociacion_o_sesion'),
    );
  });

  test('la prueba funcional revierte todo y distingue claims de JWT real', () {
    expect(
      RegExp(r'^begin;$', multiLine: true).allMatches(functionalTestSql),
      hasLength(1),
    );
    expect(
      RegExp(r'^rollback;$', multiLine: true).allMatches(functionalTestSql),
      hasLength(1),
    );
    expect(
      RegExp(r'^commit;$', multiLine: true).hasMatch(functionalTestSql),
      isFalse,
    );
    expect(
      functionalTestSql,
      contains('NO_EQUIVALE_A_VALIDACION_DE_FIRMA_JWT_FIREBASE'),
    );
    expect(
      RegExp(
        r'\b(drop|truncate)\b',
        caseSensitive: false,
      ).hasMatch(functionalTestSql),
      isFalse,
    );
  });
}
