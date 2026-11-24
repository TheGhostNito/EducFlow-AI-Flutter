import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;
  late String optionalDatesSql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/'
      '202611210001_periodos_sesiones_horario.sql',
    ).readAsStringSync();
    optionalDatesSql = File(
      'supabase/migrations/'
      '202611210002_periodos_fechas_opcionales.sql',
    ).readAsStringSync();
  });

  test('la migración es aditiva y no reclasifica asignaturas heredadas', () {
    expect(sql, contains('add column if not exists periodo_academico_id text'));
    expect(
      sql,
      isNot(
        contains('add column if not exists periodo_academico_id text not null'),
      ),
    );
    expect(sql, isNot(contains('where periodo_academico_id is null')));
    expect(sql, isNot(contains('truncate')));
    expect(sql, isNot(contains('drop table')));
    expect(sql, isNot(contains('guardar_asignatura_completa')));
    expect(
      'uid_firebase_no_valido'.allMatches(sql),
      hasLength(5),
      reason: 'Cada RPC expuesto debe rechazar un UID Firebase ausente.',
    );
  });

  test('protege pertenencia por usuario con claves compuestas', () {
    expect(sql, contains('foreign key (usuario_uid, periodo_academico_id)'));
    expect(sql, contains('foreign key (usuario_uid, asignatura_id)'));
    expect(sql, contains('primary key (usuario_uid, id)'));
    expect(sql, contains('periodo_sesion_no_coincide'));
    expect(sql, contains('fecha_sesion_fuera_periodo'));
    expect(sql, contains('asignatura_tiene_sesiones_otro_periodo'));
    expect(sql, contains('periodo_dejaria_sesiones_fuera_rango'));
    expect(
      'for share;'.allMatches(sql),
      hasLength(2),
      reason:
          'La sesión debe serializarse con cambios de asignatura y período.',
    );
    expect(
      sql,
      contains(
        'before update of fecha_inicio, fecha_fin '
        'on public.periodos_academicos',
      ),
    );
  });

  test(
    'RLS permite lectura propia y reserva escrituras a RPC autenticadas',
    () {
      expect('enable row level security'.allMatches(sql), hasLength(2));
      expect('for select'.allMatches(sql), hasLength(2));
      expect(
        '(select public.is_educflow_firebase_user()) is true'.allMatches(sql),
        hasLength(2),
      );
      expect(
        'usuario_uid = (select public.current_firebase_uid())'.allMatches(sql),
        hasLength(2),
      );
      expect(sql, isNot(contains('grant insert')));
      expect(sql, isNot(contains('grant update')));
      expect(sql, isNot(contains('grant delete')));
      expect('grant execute on function public.'.allMatches(sql), hasLength(5));
      expect(sql, contains("set search_path = ''"));
    },
  );

  test('la migración posterior admite fechas opcionales sin inventarlas', () {
    expect(
      optionalDatesSql,
      contains('alter column fecha_inicio drop not null'),
    );
    expect(optionalDatesSql, contains('alter column fecha_fin drop not null'));
    expect(
      optionalDatesSql,
      contains("coalesce(p_periodo ->> 'fecha_inicio', '')"),
    );
    expect(
      optionalDatesSql,
      contains("coalesce(p_periodo ->> 'fecha_fin', '')"),
    );
    expect(
      optionalDatesSql,
      isNot(contains('update public.periodos_academicos\nset fecha_')),
    );
    expect(optionalDatesSql, isNot(contains('truncate')));
    expect(optionalDatesSql, isNot(contains('drop table')));
  });

  test('las sesiones respetan cada límite conocido de forma independiente', () {
    expect(
      optionalDatesSql,
      contains('v_inicio is not null and new.fecha < v_inicio'),
    );
    expect(
      optionalDatesSql,
      contains('v_fin is not null and new.fecha > v_fin'),
    );
    expect(
      optionalDatesSql,
      contains('new.fecha_inicio is not null and s.fecha < new.fecha_inicio'),
    );
    expect(
      optionalDatesSql,
      contains('new.fecha_fin is not null and s.fecha > new.fecha_fin'),
    );
    expect("set search_path = ''".allMatches(optionalDatesSql), hasLength(3));
    expect(optionalDatesSql, contains('security definer'));
  });

  test(
    'solo impone unicidad a las sesiones nuevas, no a bloques existentes',
    () {
      expect(
        sql,
        contains(
          'unique (usuario_uid, asignatura_id, fecha, hora_inicio, hora_fin)',
        ),
      );
      expect(sql, isNot(contains('unique (usuario_uid, asignatura_id, dia')));
      expect(sql, isNot(contains('alter table public.bloques_horario')));
    },
  );
}
