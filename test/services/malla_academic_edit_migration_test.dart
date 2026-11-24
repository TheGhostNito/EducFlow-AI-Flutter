import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/'
      '202611200001_edicion_academica_malla_multimodal.sql',
    ).readAsStringSync();
  });

  test('las RPC validan Firebase, UID y propiedad de la malla', () {
    expect('public.is_educflow_firebase_user()'.allMatches(sql), hasLength(2));
    expect('public.current_firebase_uid()'.allMatches(sql), hasLength(2));
    expect(
      'v_uid is distinct from p_expected_uid'.allMatches(sql),
      hasLength(2),
    );
    expect(
      'where m.usuario_uid = v_uid and m.id = p_malla_id'.allMatches(sql),
      hasLength(2),
    );
  });

  test(
    'solo authenticated recibe ejecución y no obtiene escritura directa',
    () {
      expect(
        sql,
        contains(
          'revoke all on function public.confirmar_ramo_sin_codigo_malla',
        ),
      );
      expect(
        sql,
        contains(
          'grant execute on function public.editar_requisito_academico_malla',
        ),
      );
      expect(
        sql,
        contains('revoke insert, update, delete on public.mallas_curriculares'),
      );
      expect('enable row level security'.allMatches(sql), hasLength(4));
      expect(sql, isNot(contains('grant insert')));
      expect(sql, isNot(contains('grant update')));
      expect(sql, isNot(contains('grant delete')));
    },
  );

  test('la migración es aditiva y preserva evidencia y procedencia', () {
    expect(sql, isNot(contains('drop table')));
    expect(sql, isNot(contains('truncate')));
    expect(sql, isNot(contains('delete from')));
    expect(sql, isNot(contains('set procedencia')));
    expect(sql, isNot(contains('set evidencias')));
    expect(sql, contains('v_requirement.evidencias'));
    expect(sql, contains('manual_confirmation_required'));
  });
}
