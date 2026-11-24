import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el acceso automático conserva identidad, bloqueo y permisos', () {
    final sql = File(
      'supabase/migrations/'
      '202611230002_acceso_automatico_importacion_horario.sql',
    ).readAsStringSync();

    expect(sql, contains('public.is_educflow_firebase_user()'));
    expect(sql, contains('public.current_firebase_uid()'));
    expect(sql, contains('control.habilitado is false'));
    expect(sql, contains('importacion_horario_bloqueada'));
    expect(sql, contains("set search_path = ''"));
    expect(sql, contains('from public, anon, authenticated'));
    expect(sql, contains('to authenticated'));
    expect(
      sql,
      isNot(contains('insert into public.horario_importacion_autorizaciones')),
    );
    expect(sql, isNot(contains('importacion_horario_no_autorizada')));
    expect(sql, isNot(contains('drop table')));
    expect(sql, isNot(contains('disable row level security')));
  });

  test('la reversión restaura expresamente la lista blanca anterior', () {
    final sql = File(
      'supabase/rollbacks/'
      '202611230002_acceso_automatico_importacion_horario_rollback.sql',
    ).readAsStringSync();

    expect(sql, contains('if not exists'));
    expect(sql, contains('permiso.habilitado'));
    expect(sql, contains('importacion_horario_no_autorizada'));
    expect(sql, contains("set search_path = ''"));
  });

  test('el preflight está limitado a Testing y revisa controles críticos', () {
    final sql = File(
      'supabase/testing/'
      '20261123_08_preflight_acceso_automatico_horario.sql',
    ).readAsStringSync();

    expect(sql, contains('begin transaction read only'));
    expect(sql, contains('securetoken.google.com/eduflow-ai-testing'));
    expect(sql, contains("'aud'' = ''eduflow-ai-testing'"));
    expect(sql, contains("'role'' = ''authenticated'"));
    expect(sql, contains('horario_importacion_autorizaciones'));
    expect(sql, contains('politicas_rls_importacion_incompletas'));
    expect(sql, contains('reserve_ocr_vision_usage'));
    expect(sql, contains('rollback;'));
  });

  test('la prueba SQL es reversible y no autoriza manualmente al usuario', () {
    final sql = File(
      'supabase/testing/'
      '20261123_09_prueba_acceso_automatico_horario.sql',
    ).readAsStringSync();

    expect(sql, startsWith('-- P0 EducFlow AI'));
    expect(sql, contains('begin;'));
    expect(sql, isNot(contains('cuenta_nueva_recibio_autorizacion_manual')));
    expect(sql, contains('cuenta_nueva_no_confirmo_importacion'));
    expect(sql, contains('cuenta_b_pudo_eliminar_importacion_de_a'));
    expect(sql, contains('importacion_horario_bloqueada'));
    expect(sql, contains('token_produccion_aceptado_en_testing'));
    expect(sql, contains('anon_pudo_ejecutar_rpc_importacion'));
    expect(sql, contains('rollback;'));
    final administrativeInserts = RegExp(
      r'insert into public\.horario_importacion_autorizaciones[\s\S]*?\n\);',
    ).allMatches(sql).toList();
    expect(administrativeInserts, hasLength(1));
    expect(
      administrativeInserts.single.group(0),
      contains("\n  false,"),
      reason: 'Solo debe insertar una fila deshabilitada para probar bloqueo.',
    );

    final authenticatedSections = RegExp(
      r'set local role authenticated;([\s\S]*?)reset role;',
    ).allMatches(sql);
    expect(authenticatedSections, isNotEmpty);
    for (final section in authenticatedSections) {
      expect(
        section.group(1),
        isNot(contains('public.horario_importacion_autorizaciones')),
        reason: 'authenticated no debe consultar ni modificar la tabla administrativa.',
      );
    }
  });
}
