-- Corte de Asignaturas a PostgreSQL/Supabase.
-- Las funciones usan la identidad Firebase validada por las funciones RLS
-- existentes. El cliente nunca decide libremente usuario_uid.

create or replace function public.guardar_asignatura_completa(
  p_operacion text,
  p_asignatura jsonb,
  p_bloques jsonb default '[]'::jsonb,
  p_relaciones jsonb default '[]'::jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid text;
  v_asignatura_id text;
  v_nombre text;
  v_filas integer;
begin
  if not public.is_educflow_firebase_user() then
    raise exception using
      errcode = '42501',
      message = 'usuario_firebase_no_valido';
  end if;

  v_uid := public.current_firebase_uid();
  if v_uid is null or pg_catalog.btrim(v_uid) = '' then
    raise exception using errcode = '42501', message = 'uid_firebase_no_valido';
  end if;

  if p_operacion not in ('crear', 'actualizar') then
    raise exception using errcode = '22023', message = 'operacion_no_valida';
  end if;
  if pg_catalog.jsonb_typeof(p_asignatura) <> 'object'
      or pg_catalog.jsonb_typeof(p_bloques) <> 'array'
      or pg_catalog.jsonb_typeof(p_relaciones) <> 'array' then
    raise exception using errcode = '22023', message = 'payload_asignatura_no_valido';
  end if;

  v_asignatura_id := pg_catalog.btrim(coalesce(p_asignatura ->> 'id', ''));
  v_nombre := pg_catalog.btrim(coalesce(p_asignatura ->> 'nombre', ''));
  if v_asignatura_id = '' or v_nombre = '' then
    raise exception using errcode = '23514', message = 'id_y_nombre_obligatorios';
  end if;

  if p_operacion = 'crear' then
    insert into public.asignaturas (
      usuario_uid,
      id,
      nombre,
      profesor,
      correo_profesor,
      sala,
      periodo,
      estado,
      origen,
      sigla,
      seccion,
      creditos,
      semestre_malla,
      curso_nivel,
      anio_academico,
      modalidad,
      lugar,
      institucion,
      fecha_creacion,
      fecha_actualizacion
    ) values (
      v_uid,
      v_asignatura_id,
      v_nombre,
      nullif(pg_catalog.btrim(p_asignatura ->> 'profesor'), ''),
      nullif(pg_catalog.lower(pg_catalog.btrim(p_asignatura ->> 'correo_profesor')), ''),
      nullif(pg_catalog.btrim(p_asignatura ->> 'sala'), ''),
      nullif(pg_catalog.btrim(p_asignatura ->> 'periodo'), ''),
      coalesce(nullif(p_asignatura ->> 'estado', ''), 'registrada'),
      coalesce(nullif(p_asignatura ->> 'origen', ''), 'manual'),
      nullif(pg_catalog.btrim(p_asignatura ->> 'sigla'), ''),
      nullif(pg_catalog.btrim(p_asignatura ->> 'seccion'), ''),
      nullif(p_asignatura ->> 'creditos', '')::integer,
      nullif(p_asignatura ->> 'semestre_malla', '')::integer,
      nullif(pg_catalog.btrim(p_asignatura ->> 'curso_nivel'), ''),
      nullif(p_asignatura ->> 'anio_academico', '')::integer,
      nullif(pg_catalog.btrim(p_asignatura ->> 'modalidad'), ''),
      nullif(pg_catalog.btrim(p_asignatura ->> 'lugar'), ''),
      nullif(pg_catalog.btrim(p_asignatura ->> 'institucion'), ''),
      pg_catalog.now(),
      pg_catalog.now()
    );
  else
    update public.asignaturas
    set nombre = v_nombre,
        profesor = nullif(pg_catalog.btrim(p_asignatura ->> 'profesor'), ''),
        correo_profesor = nullif(pg_catalog.lower(pg_catalog.btrim(p_asignatura ->> 'correo_profesor')), ''),
        sala = nullif(pg_catalog.btrim(p_asignatura ->> 'sala'), ''),
        periodo = nullif(pg_catalog.btrim(p_asignatura ->> 'periodo'), ''),
        estado = coalesce(nullif(p_asignatura ->> 'estado', ''), 'registrada'),
        origen = coalesce(nullif(p_asignatura ->> 'origen', ''), 'manual'),
        sigla = nullif(pg_catalog.btrim(p_asignatura ->> 'sigla'), ''),
        seccion = nullif(pg_catalog.btrim(p_asignatura ->> 'seccion'), ''),
        creditos = nullif(p_asignatura ->> 'creditos', '')::integer,
        semestre_malla = nullif(p_asignatura ->> 'semestre_malla', '')::integer,
        curso_nivel = nullif(pg_catalog.btrim(p_asignatura ->> 'curso_nivel'), ''),
        anio_academico = nullif(p_asignatura ->> 'anio_academico', '')::integer,
        modalidad = nullif(pg_catalog.btrim(p_asignatura ->> 'modalidad'), ''),
        lugar = nullif(pg_catalog.btrim(p_asignatura ->> 'lugar'), ''),
        institucion = nullif(pg_catalog.btrim(p_asignatura ->> 'institucion'), ''),
        fecha_actualizacion = pg_catalog.now()
    where usuario_uid = v_uid and id = v_asignatura_id;

    get diagnostics v_filas = row_count;
    if v_filas <> 1 then
      raise exception using errcode = 'P0002', message = 'asignatura_no_encontrada';
    end if;
  end if;

  delete from public.bloques_horario
  where usuario_uid = v_uid and asignatura_id = v_asignatura_id;

  insert into public.bloques_horario (
    usuario_uid,
    asignatura_id,
    dia,
    hora_inicio,
    hora_fin,
    sala
  )
  select
    v_uid,
    v_asignatura_id,
    elemento ->> 'dia',
    (elemento ->> 'hora_inicio')::time,
    (elemento ->> 'hora_fin')::time,
    nullif(pg_catalog.btrim(elemento ->> 'sala'), '')
  from pg_catalog.jsonb_array_elements(p_bloques) as elemento;

  delete from public.relaciones_asignaturas
  where usuario_uid = v_uid and asignatura_id = v_asignatura_id;

  insert into public.relaciones_asignaturas (
    usuario_uid,
    asignatura_id,
    relacionada_id,
    tipo
  )
  select
    v_uid,
    v_asignatura_id,
    pg_catalog.btrim(elemento ->> 'relacionada_id'),
    elemento ->> 'tipo'
  from pg_catalog.jsonb_array_elements(p_relaciones) as elemento;

  -- En una creación también deja una marca única posterior a todos los hijos.
  update public.asignaturas
  set fecha_actualizacion = pg_catalog.now()
  where usuario_uid = v_uid and id = v_asignatura_id;
end;
$$;

create or replace function public.eliminar_asignatura_segura(
  p_asignatura_id text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid text;
  v_id text := pg_catalog.btrim(coalesce(p_asignatura_id, ''));
begin
  if not public.is_educflow_firebase_user() then
    raise exception using
      errcode = '42501',
      message = 'usuario_firebase_no_valido';
  end if;

  v_uid := public.current_firebase_uid();
  if v_uid is null or pg_catalog.btrim(v_uid) = '' then
    raise exception using errcode = '42501', message = 'uid_firebase_no_valido';
  end if;
  if v_id = '' then
    raise exception using errcode = '22023', message = 'asignatura_id_obligatorio';
  end if;

  -- Serializa el borrado con cualquier inserción concurrente que necesite
  -- validar la FK contra esta asignatura. Así no puede aparecer una evaluación
  -- entre la comprobación siguiente y el DELETE con ON DELETE CASCADE.
  perform 1
  from public.asignaturas
  where usuario_uid = v_uid and id = v_id
  for update;

  if not found then
    return;
  end if;

  if exists (
    select 1
    from public.evaluaciones
    where usuario_uid = v_uid and asignatura_id = v_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'asignatura_tiene_evaluaciones';
  end if;

  delete from public.asignaturas
  where usuario_uid = v_uid and id = v_id;
end;
$$;

revoke all on function public.guardar_asignatura_completa(
  text,
  jsonb,
  jsonb,
  jsonb
) from public, anon;
grant execute on function public.guardar_asignatura_completa(
  text,
  jsonb,
  jsonb,
  jsonb
) to authenticated;

revoke all on function public.eliminar_asignatura_segura(text)
  from public, anon;
grant execute on function public.eliminar_asignatura_segura(text)
  to authenticated;

-- Los filtros Realtime sobre DELETE necesitan conservar usuario_uid.
alter table public.asignaturas replica identity full;
alter table public.bloques_horario replica identity full;
alter table public.relaciones_asignaturas replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'asignaturas'
  ) then
    alter publication supabase_realtime add table public.asignaturas;
  end if;

  if not exists (
    select 1 from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'bloques_horario'
  ) then
    alter publication supabase_realtime add table public.bloques_horario;
  end if;

  if not exists (
    select 1 from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'relaciones_asignaturas'
  ) then
    alter publication supabase_realtime add table public.relaciones_asignaturas;
  end if;
end;
$$;
