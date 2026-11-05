-- Edición de ramos confirmados. Aplicar después de 202611040001_malla_curricular.sql.
begin;

alter table public.ramos_malla
  add column if not exists codigo_duplicado_verificado boolean not null default false;

update public.ramos_malla
  set motivos_revision = '["manual_verification"]'::jsonb
  where requiere_revision and pg_catalog.jsonb_array_length(motivos_revision) = 0;

create or replace function public.editar_ramo_malla(
  p_expected_uid text,
  p_malla_id uuid,
  p_ramo_id text,
  p_nombre text,
  p_codigo text,
  p_creditos integer,
  p_semestre integer,
  p_confirmar_revision boolean,
  p_codigo_duplicado_verificado boolean
) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid text;
  v_malla_id uuid;
  v_ramo public.ramos_malla%rowtype;
  v_codigo text;
  v_codigo_anterior_normalizado text;
  v_codigo_nuevo_normalizado text;
  v_motivos jsonb;
  v_duplicado boolean;
begin
  if public.is_educflow_firebase_user() is distinct from true then
    raise exception using errcode = '42501', message = 'usuario_firebase_no_valido';
  end if;
  v_uid := public.current_firebase_uid();
  if v_uid is null or v_uid is distinct from p_expected_uid then
    raise exception using errcode = '42501', message = 'uid_firebase_no_valido';
  end if;
  if p_malla_id is null or p_ramo_id is null
    or p_ramo_id !~ '^[A-Za-z0-9_-]{1,64}$' then
    raise exception using errcode = '22023', message = 'ramo_id_invalido';
  end if;
  if p_nombre is null
    or pg_catalog.length(pg_catalog.btrim(p_nombre)) not between 1 and 300
    or p_nombre ~ '[[:cntrl:]]'
    or p_codigo is not null and (
      pg_catalog.length(pg_catalog.btrim(p_codigo)) > 64
      or p_codigo ~ '[[:cntrl:]]'
    )
    or p_creditos is not null and p_creditos not between 0 and 999
    or p_semestre is null or p_semestre not between 1 and 30
    or p_confirmar_revision is null
    or p_codigo_duplicado_verificado is null then
    raise exception using errcode = '22023', message = 'ramo_datos_invalidos';
  end if;
  v_codigo := nullif(pg_catalog.btrim(p_codigo), '');
  -- Todas las RPC que escriben una malla existente toman primero el padre.
  -- Esto serializa ediciones de sus ramos y evita invertir el orden de bloqueo.
  select m.id into v_malla_id
    from public.mallas_curriculares as m
    where m.usuario_uid = v_uid and m.id = p_malla_id
    for update of m;
  if not found then
    raise exception using errcode = 'P0002', message = 'malla_no_encontrada';
  end if;
  select r.* into v_ramo
    from public.ramos_malla as r
    join public.mallas_curriculares as m
      on m.id = r.malla_id and m.usuario_uid = r.usuario_uid
    where r.usuario_uid = v_uid and r.malla_id = p_malla_id
      and r.id = p_ramo_id
    for update of r;
  if not found then
    raise exception using errcode = 'P0002', message = 'ramo_malla_no_encontrado';
  end if;
  v_codigo_anterior_normalizado :=
    pg_catalog.upper(nullif(pg_catalog.btrim(v_ramo.codigo), ''));
  v_codigo_nuevo_normalizado := pg_catalog.upper(v_codigo);

  select coalesce(pg_catalog.jsonb_agg(reason.value order by reason.first_position), '[]'::jsonb)
    into v_motivos
    from (
      select item.value, min(item.ord) as first_position
      from (
        select previous.value, previous.ordinality as ord
        from pg_catalog.jsonb_array_elements(v_ramo.motivos_revision)
          with ordinality as previous(value, ordinality)
        where (previous.value #>> '{}') not in ('credits_missing', 'code_missing')
          and p_confirmar_revision is distinct from true
        union all
        select '"credits_missing"'::jsonb, 1000::bigint
          where p_creditos is null
        union all
        select '"code_missing"'::jsonb, 1001::bigint
          where v_codigo is null
      ) as item
      group by item.value
    ) as reason;

  select exists (
    select 1 from public.ramos_malla as other
    where other.usuario_uid = v_uid and other.malla_id = p_malla_id
      and other.id <> p_ramo_id and v_codigo is not null
      and pg_catalog.upper(pg_catalog.btrim(other.codigo)) =
          pg_catalog.upper(v_codigo)
  ) into v_duplicado;
  if p_codigo_duplicado_verificado and not v_duplicado then
    raise exception using errcode = '22023', message = 'codigo_duplicado_no_detectado';
  end if;
  if v_codigo_anterior_normalizado
       is distinct from v_codigo_nuevo_normalizado then
    update public.ramos_malla as other
      set codigo_duplicado_verificado = false
      where other.usuario_uid = v_uid and other.malla_id = p_malla_id
        and other.id <> p_ramo_id
        and (
          pg_catalog.upper(pg_catalog.btrim(other.codigo)) =
            v_codigo_anterior_normalizado
          or pg_catalog.upper(pg_catalog.btrim(other.codigo)) =
            v_codigo_nuevo_normalizado
        );
  end if;
  update public.ramos_malla
    set nombre = pg_catalog.btrim(p_nombre), codigo = v_codigo,
        creditos = p_creditos, semestre = p_semestre,
        motivos_revision = v_motivos,
        requiere_revision = pg_catalog.jsonb_array_length(v_motivos) > 0,
        codigo_duplicado_verificado =
          p_codigo_duplicado_verificado and v_duplicado
          and (v_codigo_anterior_normalizado
            is not distinct from v_codigo_nuevo_normalizado)
    where usuario_uid = v_uid and malla_id = p_malla_id and id = p_ramo_id;
  -- estado y orden se conservan; la operación completa es transaccional.
end;
$$;

-- La RPC de estado usa el mismo orden padre -> ramo. Conserva la firma y
-- el comportamiento de autorización de la migración anterior ya aplicada.
create or replace function public.cambiar_estado_ramo_malla(
  p_expected_uid text, p_ramo_id text, p_estado text
) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid text;
  v_malla_id uuid;
begin
  if public.is_educflow_firebase_user() is distinct from true then
    raise exception using errcode = '42501', message = 'usuario_firebase_no_valido';
  end if;
  v_uid := public.current_firebase_uid();
  if v_uid is null or v_uid is distinct from p_expected_uid then
    raise exception using errcode = '42501', message = 'uid_firebase_no_valido';
  end if;
  if p_ramo_id is null or p_ramo_id !~ '^[A-Za-z0-9_-]{1,64}$'
    or p_ramo_id ~ '[[:cntrl:]]' then
    raise exception using errcode = '22023', message = 'ramo_id_invalido';
  end if;
  if p_estado is null or p_estado not in ('pendiente', 'en_curso', 'aprobada') then
    raise exception using errcode = '22023', message = 'estado_malla_invalido';
  end if;
  select m.id into v_malla_id
    from public.mallas_curriculares as m
    where m.usuario_uid = v_uid and exists (
      select 1 from public.ramos_malla as r
      where r.usuario_uid = m.usuario_uid and r.malla_id = m.id
        and r.id = p_ramo_id
    )
    for update of m;
  if not found then
    raise exception using errcode = 'P0002', message = 'ramo_malla_no_encontrado';
  end if;
  update public.ramos_malla set estado = p_estado
    where usuario_uid = v_uid and malla_id = v_malla_id and id = p_ramo_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'ramo_malla_no_encontrado';
  end if;
end;
$$;

revoke all on function public.editar_ramo_malla(
  text, uuid, text, text, text, integer, integer, boolean, boolean
) from public, anon;
grant execute on function public.editar_ramo_malla(
  text, uuid, text, text, text, integer, integer, boolean, boolean
) to authenticated;
revoke all on function public.cambiar_estado_ramo_malla(text, text, text)
  from public, anon;
grant execute on function public.cambiar_estado_ramo_malla(text, text, text)
  to authenticated;

-- REVOKE de tabla no elimina posibles GRANT UPDATE por columna.
do $$
declare
  v_table text;
begin
  foreach v_table in array array['public.mallas_curriculares',
      'public.ramos_malla'] loop
    if pg_catalog.has_table_privilege('authenticated', v_table, 'UPDATE')
      or pg_catalog.has_any_column_privilege('authenticated', v_table, 'UPDATE')
      or pg_catalog.has_table_privilege('anon', v_table, 'UPDATE')
      or pg_catalog.has_any_column_privilege('anon', v_table, 'UPDATE') then
      raise exception using errcode = '42501',
        message = 'privilegios_update_directo_en_malla';
    end if;
  end loop;
end;
$$;
commit;
