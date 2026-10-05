-- Corte de Evaluaciones a PostgreSQL/Supabase.
-- La identidad efectiva siempre se obtiene desde el JWT Firebase validado.

begin;

create or replace function public.guardar_evaluacion(
  p_operacion text,
  p_evaluacion jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid text;
  v_id text;
  v_titulo text;
  v_asignatura_id text;
  v_tipo text;
  v_fecha date;
  v_hora time;
  v_descripcion text;
  v_ponderacion numeric(5, 2);
  v_evaluacion public.evaluaciones%rowtype;
begin
  if public.is_educflow_firebase_user() is not true then
    raise exception using
      errcode = '42501',
      message = 'usuario_firebase_no_valido';
  end if;

  v_uid := public.current_firebase_uid();
  if v_uid is null or pg_catalog.btrim(v_uid) = '' then
    raise exception using errcode = '42501', message = 'uid_firebase_no_valido';
  end if;

  if p_operacion is null or p_operacion not in ('crear', 'actualizar') then
    raise exception using errcode = '22023', message = 'operacion_no_valida';
  end if;
  if pg_catalog.jsonb_typeof(p_evaluacion) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'payload_evaluacion_no_valido';
  end if;

  v_titulo := pg_catalog.btrim(coalesce(p_evaluacion ->> 'titulo', ''));
  v_asignatura_id := pg_catalog.btrim(
    coalesce(p_evaluacion ->> 'asignatura_id', '')
  );
  v_tipo := coalesce(nullif(p_evaluacion ->> 'tipo', ''), 'prueba');

  if v_titulo = '' or v_asignatura_id = '' then
    raise exception using
      errcode = '23514',
      message = 'titulo_y_asignatura_obligatorios';
  end if;
  if v_tipo not in ('prueba', 'examen', 'control', 'quiz', 'presentacion', 'otro') then
    raise exception using errcode = '23514', message = 'tipo_evaluacion_no_valido';
  end if;

  begin
    v_fecha := nullif(p_evaluacion ->> 'fecha', '')::date;
    v_hora := nullif(p_evaluacion ->> 'hora', '')::time;
    v_ponderacion := nullif(p_evaluacion ->> 'ponderacion', '')::numeric(5, 2);
  exception
    when invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
      raise exception using errcode = '22023', message = 'formato_evaluacion_no_valido';
  end;

  if v_fecha is null then
    raise exception using errcode = '23514', message = 'fecha_evaluacion_obligatoria';
  end if;
  if v_ponderacion is not null and (v_ponderacion < 0 or v_ponderacion > 100) then
    raise exception using errcode = '23514', message = 'ponderacion_fuera_de_rango';
  end if;

  v_descripcion := nullif(
    pg_catalog.btrim(p_evaluacion ->> 'descripcion'),
    ''
  );

  if p_operacion = 'crear' then
    v_id := pg_catalog.gen_random_uuid()::text;
    insert into public.evaluaciones (
      usuario_uid,
      id,
      asignatura_id,
      titulo,
      tipo,
      fecha,
      hora,
      descripcion,
      ponderacion,
      creada_en,
      actualizada_en
    ) values (
      v_uid,
      v_id,
      v_asignatura_id,
      v_titulo,
      v_tipo,
      v_fecha,
      v_hora,
      v_descripcion,
      v_ponderacion,
      pg_catalog.now(),
      pg_catalog.now()
    )
    returning * into v_evaluacion;
  else
    v_id := pg_catalog.btrim(coalesce(p_evaluacion ->> 'id', ''));
    if v_id = '' then
      raise exception using errcode = '23514', message = 'evaluacion_id_obligatorio';
    end if;

    update public.evaluaciones
    set asignatura_id = v_asignatura_id,
        titulo = v_titulo,
        tipo = v_tipo,
        fecha = v_fecha,
        hora = v_hora,
        descripcion = v_descripcion,
        ponderacion = v_ponderacion,
        actualizada_en = pg_catalog.now()
    where usuario_uid = v_uid and id = v_id
    returning * into v_evaluacion;

    if not found then
      raise exception using errcode = 'P0002', message = 'evaluacion_no_encontrada';
    end if;
  end if;

  return pg_catalog.to_jsonb(v_evaluacion);
end;
$$;

-- La RPC es la interfaz normal de borrado, pero SECURITY INVOKER requiere que
-- authenticated conserve DELETE. Este trigger impide eludir la protección
-- mediante un DELETE directo cuando la tabla de Notas exista.
create or replace function public.proteger_evaluacion_con_nota()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_tiene_nota boolean := false;
begin
  if pg_catalog.to_regclass('public.notas_evaluaciones') is null then
    return old;
  end if;

  execute
    'select exists (
       select 1
       from public.notas_evaluaciones
       where usuario_uid = $1 and evaluacion_id = $2
     )'
    into v_tiene_nota
    using old.usuario_uid, old.id;

  if v_tiene_nota then
    raise exception using errcode = 'P0001', message = 'evaluacion_tiene_nota';
  end if;

  return old;
end;
$$;

drop trigger if exists proteger_evaluacion_con_nota
  on public.evaluaciones;
create trigger proteger_evaluacion_con_nota
before delete on public.evaluaciones
for each row execute function public.proteger_evaluacion_con_nota();

create or replace function public.eliminar_evaluacion_segura(
  p_evaluacion_id text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid text;
  v_id text := pg_catalog.btrim(coalesce(p_evaluacion_id, ''));
  v_tiene_nota boolean := false;
begin
  if public.is_educflow_firebase_user() is not true then
    raise exception using
      errcode = '42501',
      message = 'usuario_firebase_no_valido';
  end if;

  v_uid := public.current_firebase_uid();
  if v_uid is null or pg_catalog.btrim(v_uid) = '' then
    raise exception using errcode = '42501', message = 'uid_firebase_no_valido';
  end if;
  if v_id = '' then
    raise exception using errcode = '22023', message = 'evaluacion_id_obligatorio';
  end if;

  -- El bloqueo serializa el DELETE con inserciones concurrentes que validen
  -- una FK futura contra esta evaluación.
  perform 1
  from public.evaluaciones
  where usuario_uid = v_uid and id = v_id
  for update;

  if not found then
    return;
  end if;

  -- La tabla de Notas aún puede no existir. SQL dinámico evita que la creación
  -- de esta función dependa de una migración posterior.
  if pg_catalog.to_regclass('public.notas_evaluaciones') is not null then
    execute
      'select exists (
         select 1
         from public.notas_evaluaciones
         where usuario_uid = $1 and evaluacion_id = $2
       )'
      into v_tiene_nota
      using v_uid, v_id;
  end if;

  if v_tiene_nota then
    raise exception using errcode = 'P0001', message = 'evaluacion_tiene_nota';
  end if;

  delete from public.evaluaciones
  where usuario_uid = v_uid and id = v_id;
end;
$$;

revoke all on function public.guardar_evaluacion(text, jsonb)
  from public, anon;
grant execute on function public.guardar_evaluacion(text, jsonb)
  to authenticated;

revoke all on function public.eliminar_evaluacion_segura(text)
  from public, anon;
grant execute on function public.eliminar_evaluacion_segura(text)
  to authenticated;

revoke all on function public.proteger_evaluacion_con_nota()
  from public, anon, authenticated;

-- authenticated conserva solo el CRUD que necesita PostgREST. RLS continúa
-- limitando cada operación al UID Firebase efectivo.
revoke all on table public.evaluaciones from public, anon, authenticated;
grant select, insert, update, delete on table public.evaluaciones
  to authenticated;

alter table public.evaluaciones replica identity full;

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'evaluaciones'
  ) then
    alter publication supabase_realtime add table public.evaluaciones;
  end if;
end;
$$;

commit;
