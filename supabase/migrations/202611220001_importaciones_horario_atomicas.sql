-- Confirmación y eliminación atómicas de horarios OCR revisados.
-- Depende de 202611210001 y 202611210002. No importa datos por sí sola.

begin;

create table if not exists public.importaciones_horario (
  usuario_uid text not null references public.usuarios(uid) on delete cascade,
  id text not null check (id ~ '^[a-f0-9]{32}$'),
  document_hash text not null check (document_hash ~ '^[a-f0-9]{64}$'),
  nombre_documento text not null check (
    pg_catalog.length(pg_catalog.btrim(nombre_documento)) between 1 and 255
    and nombre_documento !~ '[[:cntrl:]]'
  ),
  periodo_academico_id text not null,
  anio integer not null check (anio between 1 and 9999),
  numero_periodo integer not null check (numero_periodo between 1 and 30),
  asignaturas integer not null check (asignaturas between 1 and 100),
  bloques integer not null check (bloques between 0 and 1000),
  sesiones integer not null check (sesiones between 0 and 1000),
  creada_en timestamptz not null default pg_catalog.now(),
  primary key (usuario_uid, id),
  unique (usuario_uid, document_hash),
  foreign key (usuario_uid, periodo_academico_id)
    references public.periodos_academicos(usuario_uid, id) on delete restrict
);

-- Lista de acceso administrada exclusivamente desde backend. Permite habilitar
-- una cuenta de prueba sin publicar UID en Flutter ni en esta migración.
create table if not exists public.horario_importacion_autorizaciones (
  usuario_uid text primary key references public.usuarios(uid) on delete cascade,
  habilitado boolean not null default true,
  expira_en timestamptz,
  comentario text check (
    comentario is null
    or pg_catalog.length(pg_catalog.btrim(comentario)) between 1 and 255
  ),
  creada_en timestamptz not null default pg_catalog.now(),
  actualizada_en timestamptz not null default pg_catalog.now()
);

create table if not exists public.importacion_horario_asignaturas (
  usuario_uid text not null,
  importacion_id text not null,
  asignatura_id text not null,
  primary key (usuario_uid, importacion_id, asignatura_id),
  unique (usuario_uid, asignatura_id),
  foreign key (usuario_uid, importacion_id)
    references public.importaciones_horario(usuario_uid, id)
    on delete cascade,
  foreign key (usuario_uid, asignatura_id)
    references public.asignaturas(usuario_uid, id)
    on delete restrict
);

create index if not exists importaciones_horario_periodo_idx
  on public.importaciones_horario(usuario_uid, periodo_academico_id);

alter table public.importaciones_horario enable row level security;
alter table public.importacion_horario_asignaturas enable row level security;
alter table public.horario_importacion_autorizaciones enable row level security;

drop policy if exists importaciones_horario_lectura
  on public.importaciones_horario;
create policy importaciones_horario_lectura
  on public.importaciones_horario
  for select
  to authenticated
  using (
    (select public.is_educflow_firebase_user()) is true
    and usuario_uid = (select public.current_firebase_uid())
  );

drop policy if exists importacion_horario_asignaturas_lectura
  on public.importacion_horario_asignaturas;
create policy importacion_horario_asignaturas_lectura
  on public.importacion_horario_asignaturas
  for select
  to authenticated
  using (
    (select public.is_educflow_firebase_user()) is true
    and usuario_uid = (select public.current_firebase_uid())
  );

revoke all on table public.importaciones_horario
  from public, anon, authenticated;
revoke all on table public.importacion_horario_asignaturas
  from public, anon, authenticated;
revoke all on table public.horario_importacion_autorizaciones
  from public, anon, authenticated;
grant select on table public.importaciones_horario to authenticated;
grant select on table public.importacion_horario_asignaturas to authenticated;
grant select, insert, update, delete
  on table public.horario_importacion_autorizaciones to service_role;

create or replace function public.uid_importacion_horario_autorizado()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text;
begin
  if public.is_educflow_firebase_user() is distinct from true then
    raise exception using errcode = '42501', message = 'usuario_firebase_no_valido';
  end if;
  v_uid := public.current_firebase_uid();
  if v_uid is null or pg_catalog.btrim(v_uid) = '' then
    raise exception using errcode = '42501', message = 'uid_firebase_no_valido';
  end if;
  if not exists (
    select 1
    from public.horario_importacion_autorizaciones as permiso
    where permiso.usuario_uid = v_uid
      and permiso.habilitado
      and (permiso.expira_en is null or permiso.expira_en > pg_catalog.now())
  ) then
    raise exception using
      errcode = '42501',
      message = 'importacion_horario_no_autorizada';
  end if;
  return v_uid;
end;
$$;

create or replace function public.proteger_identidad_asignatura_importada()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_importacion_id text;
begin
  select m.importacion_id
    into v_importacion_id
  from public.importacion_horario_asignaturas as m
  where m.usuario_uid = old.usuario_uid
    and m.asignatura_id = old.id;

  if not found then return new; end if;

  if new.periodo_academico_id is distinct from old.periodo_academico_id
      or new.origen is distinct from old.origen then
    raise exception using
      errcode = '23514',
      message = 'identidad_importacion_horario_inmutable';
  end if;
  return new;
end;
$$;

drop trigger if exists asignaturas_proteger_importacion_horario_identidad
  on public.asignaturas;
create trigger asignaturas_proteger_importacion_horario_identidad
before update of periodo_academico_id, origen
on public.asignaturas
for each row execute function public.proteger_identidad_asignatura_importada();

create or replace function public.confirmar_importacion_horario(
  p_importacion jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text;
  v_importacion_id text;
  v_hash text;
  v_nombre_documento text;
  v_periodo jsonb;
  v_periodo_id text;
  v_anio integer;
  v_numero integer;
  v_items jsonb;
  v_item jsonb;
  v_asignatura jsonb;
  v_bloques_payload jsonb;
  v_sesiones jsonb;
  v_sesion jsonb;
  v_asignatura_id text;
  v_sesion_id text;
  v_nombre text;
  v_sigla text;
  v_seccion text;
  v_asignaturas integer := 0;
  v_total_bloques integer := 0;
  v_total_sesiones integer := 0;
  v_subject_index integer;
  v_session_index integer;
  v_existing public.importaciones_horario%rowtype;
begin
  v_uid := public.uid_importacion_horario_autorizado();
  if pg_catalog.jsonb_typeof(p_importacion) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'payload_importacion_no_valido';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_uid || ':horario_importacion', 0::bigint)
  );

  v_importacion_id := pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_importacion ->> 'importacion_id', ''))
  );
  v_hash := pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_importacion ->> 'document_hash', ''))
  );
  v_nombre_documento := pg_catalog.btrim(
    coalesce(p_importacion ->> 'nombre_documento', '')
  );
  v_periodo := p_importacion -> 'periodo';
  v_items := p_importacion -> 'asignaturas';

  if v_importacion_id !~ '^[a-f0-9]{32}$'
      or v_hash !~ '^[a-f0-9]{64}$'
      or pg_catalog.length(v_nombre_documento) not between 1 and 255
      or pg_catalog.jsonb_typeof(v_periodo) is distinct from 'object'
      or pg_catalog.jsonb_typeof(v_items) is distinct from 'array'
      or pg_catalog.jsonb_array_length(v_items) not between 1 and 100 then
    raise exception using errcode = '23514', message = 'importacion_horario_no_valida';
  end if;

  select * into v_existing
  from public.importaciones_horario
  where usuario_uid = v_uid and document_hash = v_hash
  for update;
  if found then
    return pg_catalog.jsonb_build_object(
      'importacion_id', v_existing.id,
      'periodo_academico_id', v_existing.periodo_academico_id,
      'asignaturas', v_existing.asignaturas,
      'bloques', v_existing.bloques,
      'sesiones', v_existing.sesiones,
      'ya_existia', true
    );
  end if;

  if exists (
    select 1 from public.importaciones_horario
    where usuario_uid = v_uid and id = v_importacion_id
  ) then
    raise exception using errcode = '23505', message = 'importacion_id_en_uso';
  end if;

  begin
    v_anio := (v_periodo ->> 'anio')::integer;
    v_numero := (v_periodo ->> 'numero')::integer;
  exception
    when invalid_text_representation or numeric_value_out_of_range then
      raise exception using errcode = '22023', message = 'periodo_importacion_no_valido';
  end;
  if v_anio not between 1 and 9999 or v_numero not between 1 and 30 then
    raise exception using errcode = '23514', message = 'periodo_importacion_no_valido';
  end if;
  if exists (
    select 1 from public.periodos_academicos
    where usuario_uid = v_uid
      and anio = v_anio
      and tipo = 'semestre'
      and numero = v_numero
  ) then
    raise exception using errcode = '23505', message = 'periodo_academico_preexistente';
  end if;

  v_periodo_id := 'horario-periodo-' || v_importacion_id;
  v_periodo := v_periodo || pg_catalog.jsonb_build_object(
    'id', v_periodo_id,
    'tipo', 'semestre',
    'estado', case
      when v_anio < extract(year from current_date)::integer
        then 'historico'
      else 'activo'
    end
  );
  perform public.guardar_periodo_academico('crear', v_periodo);

  insert into public.importaciones_horario (
    usuario_uid, id, document_hash, nombre_documento,
    periodo_academico_id, anio, numero_periodo,
    asignaturas, bloques, sesiones
  ) values (
    v_uid, v_importacion_id, v_hash, v_nombre_documento,
    v_periodo_id, v_anio, v_numero, 1, 0, 0
  );

  for v_item, v_subject_index in
    select value, ordinality::integer
    from pg_catalog.jsonb_array_elements(v_items) with ordinality
  loop
    if pg_catalog.jsonb_typeof(v_item) is distinct from 'object'
        or pg_catalog.jsonb_typeof(v_item -> 'asignatura') is distinct from 'object'
        or pg_catalog.jsonb_typeof(v_item -> 'bloques') is distinct from 'array'
        or pg_catalog.jsonb_typeof(v_item -> 'sesiones') is distinct from 'array' then
      raise exception using errcode = '22023', message = 'asignatura_importacion_no_valida';
    end if;
    v_asignatura := v_item -> 'asignatura';
    v_bloques_payload := v_item -> 'bloques';
    v_sesiones := v_item -> 'sesiones';
    v_nombre := pg_catalog.btrim(coalesce(v_asignatura ->> 'nombre', ''));
    v_sigla := nullif(pg_catalog.upper(pg_catalog.btrim(v_asignatura ->> 'sigla')), '');
    v_seccion := nullif(pg_catalog.upper(pg_catalog.btrim(v_asignatura ->> 'seccion')), '');
    if v_nombre = ''
        or pg_catalog.jsonb_array_length(v_bloques_payload) > 100
        or pg_catalog.jsonb_array_length(v_sesiones) > 100 then
      raise exception using errcode = '23514', message = 'asignatura_importacion_no_valida';
    end if;

    if exists (
      select 1
      from public.asignaturas as a
      where a.usuario_uid = v_uid
        and a.anio_academico = v_anio
        and (
          (v_sigla is not null and pg_catalog.upper(a.sigla) = v_sigla
            and pg_catalog.upper(a.seccion) is not distinct from v_seccion)
          or (v_sigla is null and pg_catalog.lower(a.nombre) = pg_catalog.lower(v_nombre))
        )
    ) then
      raise exception using errcode = '23505', message = 'asignatura_academica_preexistente';
    end if;

    v_asignatura_id := 'horario-' || v_importacion_id || '-a-' || v_subject_index;
    if exists (
      select 1 from public.asignaturas
      where usuario_uid = v_uid and id = v_asignatura_id
    ) then
      raise exception using errcode = '23505', message = 'asignatura_id_en_uso';
    end if;

    v_asignatura := v_asignatura || pg_catalog.jsonb_build_object(
      'id', v_asignatura_id,
      'estado', case
        when v_anio < extract(year from current_date)::integer
          then 'registrada'
        else 'en_curso'
      end,
      'origen', 'horario',
      'anio_academico', v_anio,
      'periodo', v_numero || '° semestre ' || v_anio
    );
    perform public.guardar_asignatura_completa(
      'crear', v_asignatura, v_bloques_payload, '[]'::jsonb
    );
    perform public.asociar_asignatura_periodo(
      v_asignatura_id, v_periodo_id
    );

    insert into public.importacion_horario_asignaturas (
      usuario_uid, importacion_id, asignatura_id
    ) values (v_uid, v_importacion_id, v_asignatura_id);

    for v_sesion, v_session_index in
      select value, ordinality::integer
      from pg_catalog.jsonb_array_elements(v_sesiones) with ordinality
    loop
      if pg_catalog.jsonb_typeof(v_sesion) is distinct from 'object' then
        raise exception using errcode = '22023', message = 'sesion_importacion_no_valida';
      end if;
      v_sesion_id := v_asignatura_id || '-s-' || v_session_index;
      v_sesion := v_sesion || pg_catalog.jsonb_build_object(
        'id', v_sesion_id,
        'asignatura_id', v_asignatura_id,
        'periodo_academico_id', v_periodo_id,
        'origen', 'horario'
      );
      perform public.guardar_sesion_clase('crear', v_sesion);
    end loop;

    v_asignaturas := v_asignaturas + 1;
    v_total_sesiones := v_total_sesiones + pg_catalog.jsonb_array_length(v_sesiones);
  end loop;

  select coalesce(
    pg_catalog.sum(pg_catalog.jsonb_array_length(entry.value -> 'bloques')),
    0
  )::integer
    into v_total_bloques
  from pg_catalog.jsonb_array_elements(v_items) as entry(value);

  if v_total_bloques > 1000 or v_total_sesiones > 1000 then
    raise exception using errcode = '23514', message = 'importacion_excede_limites';
  end if;

  update public.importaciones_horario
  set asignaturas = v_asignaturas,
      bloques = v_total_bloques,
      sesiones = v_total_sesiones
  where usuario_uid = v_uid and id = v_importacion_id;

  return pg_catalog.jsonb_build_object(
    'importacion_id', v_importacion_id,
    'periodo_academico_id', v_periodo_id,
    'asignaturas', v_asignaturas,
    'bloques', v_total_bloques,
    'sesiones', v_total_sesiones,
    'ya_existia', false
  );
end;
$$;

create or replace function public.listar_importaciones_horario()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text;
  v_resultado jsonb;
begin
  v_uid := public.uid_importacion_horario_autorizado();

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'id', i.id,
        'document_hash', i.document_hash,
        'nombre_documento', i.nombre_documento,
        'anio', i.anio,
        'numero_periodo', i.numero_periodo,
        'periodo_academico_id', i.periodo_academico_id,
        'asignaturas', i.asignaturas,
        'bloques', i.bloques,
        'sesiones', i.sesiones,
        'creada_en', i.creada_en
      ) order by i.creada_en desc
    ),
    '[]'::jsonb
  ) into v_resultado
  from public.importaciones_horario as i
  where i.usuario_uid = v_uid;
  return v_resultado;
end;
$$;

create or replace function public.eliminar_importacion_horario(
  p_importacion_id text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text;
  v_id text := pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_importacion_id, ''))
  );
  v_periodo_id text;
  v_ids text[];
  v_esperadas integer;
  v_bloques_esperados integer;
  v_sesiones_esperadas integer;
  v_bloques_actuales integer;
  v_sesiones_actuales integer;
  v_eliminadas integer;
  v_vinculos_eliminados integer;
  v_dependencia boolean := false;
  v_periodo_eliminado boolean := false;
  v_fk record;
begin
  v_uid := public.uid_importacion_horario_autorizado();
  if v_id !~ '^[a-f0-9]{32}$' then
    raise exception using errcode = '22023', message = 'importacion_id_no_valido';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_uid || ':horario_importacion', 0::bigint)
  );
  select periodo_academico_id, asignaturas, bloques, sesiones
    into v_periodo_id, v_esperadas, v_bloques_esperados, v_sesiones_esperadas
  from public.importaciones_horario
  where usuario_uid = v_uid and id = v_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'importacion_horario_no_encontrada';
  end if;

  select pg_catalog.array_agg(asignatura_id order by asignatura_id)
    into v_ids
  from public.importacion_horario_asignaturas
  where usuario_uid = v_uid and importacion_id = v_id;
  if coalesce(pg_catalog.array_length(v_ids, 1), 0) <> v_esperadas then
    raise exception using errcode = '23514', message = 'importacion_horario_incompleta';
  end if;
  if exists (
    select 1 from public.asignaturas
    where usuario_uid = v_uid
      and id = any(v_ids)
      and (origen <> 'horario' or periodo_academico_id <> v_periodo_id)
  ) then
    raise exception using errcode = '23514', message = 'identidad_importacion_horario_alterada';
  end if;
  select pg_catalog.count(*)::integer
    into v_bloques_actuales
  from public.bloques_horario
  where usuario_uid = v_uid and asignatura_id = any(v_ids);
  select pg_catalog.count(*)::integer
    into v_sesiones_actuales
  from public.sesiones_clase
  where usuario_uid = v_uid and asignatura_id = any(v_ids);
  if v_bloques_actuales <> v_bloques_esperados
      or v_sesiones_actuales <> v_sesiones_esperadas
      or exists (
        select 1 from public.sesiones_clase
        where usuario_uid = v_uid
          and asignatura_id = any(v_ids)
          and origen <> 'horario'
      ) then
    raise exception using
      errcode = '23514',
      message = 'ocurrencias_importacion_modificadas';
  end if;
  if exists (
    select 1 from public.relaciones_asignaturas
    where usuario_uid = v_uid
      and (asignatura_id = any(v_ids) or relacionada_id = any(v_ids))
  ) then
    raise exception using errcode = '23514', message = 'importacion_tiene_relaciones';
  end if;

  if pg_catalog.to_regclass('public.evaluaciones') is not null then
    execute 'select exists (
      select 1 from public.evaluaciones
      where usuario_uid = $1 and asignatura_id = any($2)
    )' into v_dependencia using v_uid, v_ids;
    if v_dependencia then
      raise exception using errcode = '23514', message = 'importacion_tiene_evaluaciones';
    end if;
  end if;
  if pg_catalog.to_regclass('public.tareas') is not null then
    execute 'select exists (
      select 1 from public.tareas
      where usuario_uid = $1 and asignatura_id = any($2)
    )' into v_dependencia using v_uid, v_ids;
    if v_dependencia then
      raise exception using errcode = '23514', message = 'importacion_tiene_tareas';
    end if;
  end if;
  if pg_catalog.to_regclass('public.objetivos_notas') is not null then
    execute 'select exists (
      select 1 from public.objetivos_notas
      where usuario_uid = $1 and asignatura_id = any($2)
    )' into v_dependencia using v_uid, v_ids;
    if v_dependencia then
      raise exception using errcode = '23514', message = 'importacion_tiene_objetivos_notas';
    end if;
  end if;
  if pg_catalog.to_regclass('public.configuracion_calculo_asignaturas') is not null then
    execute 'select exists (
      select 1 from public.configuracion_calculo_asignaturas
      where usuario_uid = $1 and asignatura_id = any($2)
    )' into v_dependencia using v_uid, v_ids;
    if v_dependencia then
      raise exception using errcode = '23514', message = 'importacion_tiene_configuracion_notas';
    end if;
  end if;

  -- Protección futura: cualquier FK nueva hacia asignaturas bloquea el borrado
  -- salvo los bloques, sesiones y vínculos técnicos creados por la importación.
  for v_fk in
    select
      child_ns.nspname as schema_name,
      child.relname as table_name,
      constraint_row.conname,
      pg_catalog.max(child_att.attname::text)
        filter (where parent_att.attname = 'usuario_uid') as uid_column,
      pg_catalog.max(child_att.attname::text)
        filter (where parent_att.attname = 'id') as id_column
    from pg_catalog.pg_constraint as constraint_row
    join pg_catalog.pg_class as child
      on child.oid = constraint_row.conrelid
    join pg_catalog.pg_namespace as child_ns
      on child_ns.oid = child.relnamespace
    cross join lateral pg_catalog.unnest(constraint_row.conkey)
      with ordinality as child_key(attnum, position)
    join lateral pg_catalog.unnest(constraint_row.confkey)
      with ordinality as parent_key(attnum, position)
      on parent_key.position = child_key.position
    join pg_catalog.pg_attribute as child_att
      on child_att.attrelid = constraint_row.conrelid
      and child_att.attnum = child_key.attnum
    join pg_catalog.pg_attribute as parent_att
      on parent_att.attrelid = constraint_row.confrelid
      and parent_att.attnum = parent_key.attnum
    where constraint_row.contype = 'f'
      and constraint_row.confrelid = 'public.asignaturas'::pg_catalog.regclass
    group by child_ns.nspname, child.relname, constraint_row.conname
  loop
    if v_fk.schema_name = 'public'
        and v_fk.table_name in (
          'bloques_horario',
          'sesiones_clase',
          'importacion_horario_asignaturas'
        ) then
      continue;
    end if;
    if v_fk.uid_column is null or v_fk.id_column is null then
      raise exception using
        errcode = '23514',
        message = 'dependencia_asignatura_no_compatible',
        detail = v_fk.schema_name || '.' || v_fk.table_name || ':' || v_fk.conname;
    end if;
    execute pg_catalog.format(
      'select exists (select 1 from %I.%I where %I = $1 and %I = any($2))',
      v_fk.schema_name,
      v_fk.table_name,
      v_fk.uid_column,
      v_fk.id_column
    ) into v_dependencia using v_uid, v_ids;
    if v_dependencia then
      raise exception using
        errcode = '23514',
        message = 'importacion_tiene_dependencias',
        detail = v_fk.schema_name || '.' || v_fk.table_name || ':' || v_fk.conname;
    end if;
  end loop;

  delete from public.importacion_horario_asignaturas
  where usuario_uid = v_uid and importacion_id = v_id;
  get diagnostics v_vinculos_eliminados = row_count;
  if v_vinculos_eliminados <> v_esperadas then
    raise exception using errcode = '23514', message = 'desvinculacion_importacion_incompleta';
  end if;

  delete from public.asignaturas
  where usuario_uid = v_uid and id = any(v_ids);
  get diagnostics v_eliminadas = row_count;
  if v_eliminadas <> v_esperadas then
    raise exception using errcode = '23514', message = 'eliminacion_importacion_incompleta';
  end if;

  delete from public.importaciones_horario
  where usuario_uid = v_uid and id = v_id;
  if not exists (
    select 1 from public.asignaturas
    where usuario_uid = v_uid and periodo_academico_id = v_periodo_id
  ) then
    delete from public.periodos_academicos
    where usuario_uid = v_uid and id = v_periodo_id;
    v_periodo_eliminado := found;
  end if;

  return pg_catalog.jsonb_build_object(
    'importacion_id', v_id,
    'asignaturas_eliminadas', v_eliminadas,
    'periodo_eliminado', v_periodo_eliminado
  );
end;
$$;

revoke all on function public.uid_importacion_horario_autorizado()
  from public, anon, authenticated;
revoke all on function public.proteger_identidad_asignatura_importada()
  from public, anon, authenticated;
revoke all on function public.confirmar_importacion_horario(jsonb)
  from public, anon, authenticated;
revoke all on function public.listar_importaciones_horario()
  from public, anon, authenticated;
revoke all on function public.eliminar_importacion_horario(text)
  from public, anon, authenticated;
grant execute on function public.confirmar_importacion_horario(jsonb)
  to authenticated;
grant execute on function public.listar_importaciones_horario()
  to authenticated;
grant execute on function public.eliminar_importacion_horario(text)
  to authenticated;

commit;
