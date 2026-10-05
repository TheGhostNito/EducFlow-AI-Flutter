-- Corte de Tareas a PostgreSQL/Supabase.
-- La identidad efectiva siempre se obtiene desde el JWT Firebase validado.

begin;

-- No se corrigen datos silenciosamente: la migración aborta si alguna fila no
-- cumple la regla bidireccional entre estado y completada_en.
do $$
begin
  if exists (
    select 1
    from public.tareas
    where (estado = 'pendiente' and completada_en is not null)
       or (estado = 'completada' and completada_en is null)
  ) then
    raise exception using
      errcode = '23514',
      message = 'tareas_estado_completada_incoherente';
  end if;
end;
$$;

alter table public.tareas
  drop constraint if exists tareas_check;
alter table public.tareas
  drop constraint if exists tareas_estado_completada_check;
alter table public.tareas
  add constraint tareas_estado_completada_check check (
    (estado = 'pendiente' and completada_en is null)
    or (estado = 'completada' and completada_en is not null)
  );

create or replace function public.guardar_tarea(
  p_operacion text,
  p_tarea jsonb
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
  v_descripcion text;
  v_asignatura_id text;
  v_prioridad text;
  v_estado text;
  v_fecha_entrega date;
  v_hora_entrega time;
  v_tarea public.tareas%rowtype;
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
  if pg_catalog.jsonb_typeof(p_tarea) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'payload_tarea_no_valido';
  end if;

  v_titulo := pg_catalog.btrim(coalesce(p_tarea ->> 'titulo', ''));
  v_descripcion := nullif(
    pg_catalog.btrim(p_tarea ->> 'descripcion'),
    ''
  );
  v_asignatura_id := nullif(
    pg_catalog.btrim(p_tarea ->> 'asignatura_id'),
    ''
  );
  v_prioridad := coalesce(nullif(p_tarea ->> 'prioridad', ''), 'media');
  v_estado := coalesce(nullif(p_tarea ->> 'estado', ''), 'pendiente');

  if v_titulo = '' then
    raise exception using errcode = '23514', message = 'titulo_tarea_obligatorio';
  end if;
  if v_prioridad not in ('baja', 'media', 'alta') then
    raise exception using errcode = '23514', message = 'prioridad_tarea_no_valida';
  end if;
  if v_estado not in ('pendiente', 'completada') then
    raise exception using errcode = '23514', message = 'estado_tarea_no_valido';
  end if;

  begin
    v_fecha_entrega := nullif(p_tarea ->> 'fecha_entrega', '')::date;
    v_hora_entrega := nullif(p_tarea ->> 'hora_entrega', '')::time;
  exception
    when invalid_text_representation
      or invalid_datetime_format
      or datetime_field_overflow then
      raise exception using errcode = '22023', message = 'formato_tarea_no_valido';
  end;

  if v_asignatura_id is not null and not exists (
    select 1
    from public.asignaturas
    where usuario_uid = v_uid and id = v_asignatura_id
  ) then
    raise exception using
      errcode = '23503',
      message = 'asignatura_tarea_no_encontrada';
  end if;

  -- completada_en nunca se confía al cliente: se deriva de la transición de
  -- estado y PostgreSQL fija el instante de la primera finalización.
  if p_operacion = 'crear' then
    v_id := pg_catalog.gen_random_uuid()::text;
    insert into public.tareas (
      usuario_uid,
      id,
      titulo,
      descripcion,
      asignatura_id,
      prioridad,
      estado,
      fecha_entrega,
      hora_entrega,
      creada_en,
      actualizada_en,
      completada_en
    ) values (
      v_uid,
      v_id,
      v_titulo,
      v_descripcion,
      v_asignatura_id,
      v_prioridad,
      v_estado,
      v_fecha_entrega,
      v_hora_entrega,
      pg_catalog.now(),
      pg_catalog.now(),
      case
        when v_estado = 'completada' then pg_catalog.now()
        else null
      end
    )
    returning * into v_tarea;
  else
    v_id := pg_catalog.btrim(coalesce(p_tarea ->> 'id', ''));
    if v_id = '' then
      raise exception using errcode = '23514', message = 'tarea_id_obligatorio';
    end if;

    update public.tareas as tarea_actual
    set titulo = v_titulo,
        descripcion = v_descripcion,
        asignatura_id = v_asignatura_id,
        prioridad = v_prioridad,
        estado = v_estado,
        fecha_entrega = v_fecha_entrega,
        hora_entrega = v_hora_entrega,
        actualizada_en = pg_catalog.now(),
        completada_en = case
          when v_estado = 'pendiente' then null
          when tarea_actual.estado = 'completada'
               and tarea_actual.completada_en is not null
            then tarea_actual.completada_en
          else pg_catalog.now()
        end
    where tarea_actual.usuario_uid = v_uid and tarea_actual.id = v_id
    returning * into v_tarea;

    if not found then
      raise exception using errcode = 'P0002', message = 'tarea_no_encontrada';
    end if;
  end if;

  return pg_catalog.to_jsonb(v_tarea);
end;
$$;

create or replace function public.eliminar_tarea(
  p_tarea_id text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid text;
  v_id text := pg_catalog.btrim(coalesce(p_tarea_id, ''));
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
    raise exception using errcode = '22023', message = 'tarea_id_obligatorio';
  end if;

  -- DELETE ya es idempotente cuando no existe una fila propia con ese ID.
  delete from public.tareas
  where usuario_uid = v_uid and id = v_id;
end;
$$;

revoke all on function public.guardar_tarea(text, jsonb)
  from public, anon;
grant execute on function public.guardar_tarea(text, jsonb)
  to authenticated;

revoke all on function public.eliminar_tarea(text)
  from public, anon;
grant execute on function public.eliminar_tarea(text)
  to authenticated;

-- authenticated conserva solo el CRUD requerido por PostgREST y las RPC.
-- La política RLS existente continúa limitando cada fila al UID Firebase.
revoke all on table public.tareas from public, anon, authenticated;
grant select, insert, update, delete on table public.tareas
  to authenticated;

-- FULL conserva usuario_uid en el registro OLD para filtrar eventos DELETE.
alter table public.tareas replica identity full;

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'tareas'
  ) then
    alter publication supabase_realtime add table public.tareas;
  end if;
end;
$$;

commit;
