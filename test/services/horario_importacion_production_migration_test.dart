import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el preflight productivo falla cerrado ante identidad o esquema incorrectos', () {
    final sql = File(
      'supabase/production/'
      '20261123_01_preflight_acceso_automatico_horario.sql',
    ).readAsStringSync();

    expect(sql, contains('begin transaction read only'));
    expect(sql, contains('securetoken.google.com/educflow-ai'));
    expect(sql, contains("'aud'' = ''educflow-ai'"));
    expect(sql, contains("'role'' = ''authenticated'"));
    expect(sql, contains("like '%eduflow-ai-testing%'"));
    expect(sql, contains('uid_importacion_horario_autorizado'));
    expect(sql, contains('horario_importacion_autorizaciones'));
    expect(sql, contains('politicas_rls_productivas_importacion_incompletas'));
    expect(sql, contains('reserve_ocr_vision_usage'));
    expect(sql, contains('horarios-originales'));
    expect(sql, contains('rollback;'));
  });

  test('el respaldo productivo es de solo lectura y no exporta UIDs', () {
    final sql = File(
      'supabase/production/'
      '20261123_02_respaldo_previo_acceso_horario.sql',
    ).readAsStringSync();

    expect(sql, contains('begin transaction read only'));
    expect(sql, contains('pg_get_functiondef'));
    expect(sql, contains('pg_policies'));
    expect(sql, contains('count(*)'));
    expect(sql, isNot(contains('select usuario_uid')));
    expect(sql, isNot(contains('insert into')));
    expect(sql, isNot(contains('update public')));
    expect(sql, isNot(contains('delete from')));
    expect(sql, contains('rollback;'));
  });

  test('la validación posterior conserva identidad, RLS, cuotas y bloqueo', () {
    final sql = File(
      'supabase/production/'
      '20261123_03_validacion_posterior_acceso_automatico_horario.sql',
    ).readAsStringSync();

    expect(sql, contains('securetoken.google.com/educflow-ai'));
    expect(sql, contains('control.habilitado is false'));
    expect(sql, contains('importacion_horario_bloqueada'));
    expect(sql, contains('rls_productiva_por_uid_alterada'));
    expect(sql, contains('cuotas_productivas_expuestas_o_inaccesibles'));
    expect(sql, contains('storage_productivo_no_conserva_aislamiento_uid'));
    expect(sql, contains('rollback;'));
  });

  test('la migración reutilizada no fija un proyecto Firebase o Supabase', () {
    final sql = File(
      'supabase/migrations/'
      '202611230002_acceso_automatico_importacion_horario.sql',
    ).readAsStringSync();

    expect(sql, isNot(contains('eduflow-ai-testing')));
    expect(sql, isNot(contains('securetoken.google.com')));
    expect(sql, isNot(contains('oxrvksaljxcwdhkeapej')));
    expect(sql, isNot(contains('ubjmdfwkjgblnjgmufpc')));
    expect(sql, contains('public.is_educflow_firebase_user()'));
    expect(sql, contains('public.current_firebase_uid()'));
  });
}
