-- Permite límites temporales opcionales e independientes en períodos.
-- No completa fechas existentes ni modifica asignaturas o sesiones.

begin;

alter table public.periodos_academicos
  alter column fecha_inicio drop not null,
  alter column fecha_fin drop not null;

create or replace function public.validar_integridad_sesion_clase()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_periodo_asignatura text;
  v_inicio date;
  v_fin date;
begin
  select a.periodo_academico_id
    into v_periodo_asignatura
  from public.asignaturas as a
  where a.usuario_uid = new.usuario_uid
    and a.id = new.asignatura_id
  for share;

  if not found then
    raise exception using errcode = '23503', message = 'asignatura_sesion_no_encontrada';
  end if;
  if v_periodo_asignatura is null
      or v_periodo_asignatura is distinct from new.periodo_academico_id then
    raise exception using errcode = '23514', message = 'periodo_sesion_no_coincide';
  end if;

  select p.fecha_inicio, p.fecha_fin
    into v_inicio, v_fin
  from public.periodos_academicos as p
  where p.usuario_uid = new.usuario_uid
    and p.id = new.periodo_academico_id
  for share;

  if not found then
    raise exception using errcode = '23503', message = 'periodo_sesion_no_encontrado';
  end if;
  if (v_inicio is not null and new.fecha < v_inicio)
      or (v_fin is not null and new.fecha > v_fin) then
    raise exception using errcode = '23514', message = 'fecha_sesion_fuera_periodo';
  end if;

  new.fecha_actualizacion := pg_catalog.now();
  return new;
end;
$$;

create or replace function public.proteger_cambio_fechas_periodo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.fecha_inicio is not distinct from old.fecha_inicio
      and new.fecha_fin is not distinct from old.fecha_fin then
    return new;
  end if;
  if exists (
    select 1
    from public.sesiones_clase as s
    where s.usuario_uid = old.usuario_uid
      and s.periodo_academico_id = old.id
      and (
        (new.fecha_inicio is not null and s.fecha < new.fecha_inicio)
        or (new.fecha_fin is not null and s.fecha > new.fecha_fin)
      )
  ) then
    raise exception using
      errcode = '23514',
      message = 'periodo_dejaria_sesiones_fuera_rango';
  end if;
  return new;
end;
$$;

create or replace function public.guardar_periodo_academico(
  p_operacion text,
  p_periodo jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text;
  v_id text;
  v_anio integer;
  v_tipo text;
  v_numero integer;
  v_nombre text;
  v_fecha_inicio date;
  v_fecha_fin date;
  v_institucion text;
  v_estado text;
  v_periodo public.periodos_academicos%rowtype;
begin
  if public.is_educflow_firebase_user() is distinct from true then
    raise exception using errcode = '42501', message = 'usuario_firebase_no_valido';
  end if;
  v_uid := public.current_firebase_uid();
  if v_uid is null or pg_catalog.btrim(v_uid) = '' then
    raise exception using errcode = '42501', message = 'uid_firebase_no_valido';
  end if;
  if p_operacion is null
      or p_operacion not in ('crear', 'actualizar')
      or pg_catalog.jsonb_typeof(p_periodo) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'payload_periodo_no_valido';
  end if;

  v_id := pg_catalog.btrim(coalesce(p_periodo ->> 'id', ''));
  v_tipo := pg_catalog.btrim(coalesce(p_periodo ->> 'tipo', ''));
  v_nombre := pg_catalog.btrim(coalesce(p_periodo ->> 'nombre', ''));
  v_institucion := nullif(pg_catalog.btrim(p_periodo ->> 'institucion'), '');
  v_estado := coalesce(nullif(p_periodo ->> 'estado', ''), 'activo');
  begin
    v_anio := (p_periodo ->> 'anio')::integer;
    v_numero := (p_periodo ->> 'numero')::integer;
    v_fecha_inicio := nullif(
      pg_catalog.btrim(coalesce(p_periodo ->> 'fecha_inicio', '')),
      ''
    )::date;
    v_fecha_fin := nullif(
      pg_catalog.btrim(coalesce(p_periodo ->> 'fecha_fin', '')),
      ''
    )::date;
  exception
    when invalid_text_representation
      or invalid_datetime_format
      or datetime_field_overflow then
      raise exception using errcode = '22023', message = 'formato_periodo_no_valido';
  end;

  if v_id !~ '^[A-Za-z0-9_-]{1,64}$'
      or v_anio not between 1 and 9999
      or v_tipo not in ('semestre')
      or v_numero not between 1 and 30
      or pg_catalog.length(v_nombre) not between 1 and 160
      or (
        v_fecha_inicio is not null
        and v_fecha_fin is not null
        and v_fecha_fin < v_fecha_inicio
      )
      or v_estado not in ('activo', 'historico') then
    raise exception using errcode = '23514', message = 'periodo_no_valido';
  end if;

  if p_operacion = 'crear' then
    insert into public.periodos_academicos (
      usuario_uid, id, anio, tipo, numero, nombre, fecha_inicio, fecha_fin,
      institucion, estado
    ) values (
      v_uid, v_id, v_anio, v_tipo, v_numero, v_nombre, v_fecha_inicio,
      v_fecha_fin, v_institucion, v_estado
    ) returning * into v_periodo;
  else
    update public.periodos_academicos
    set anio = v_anio,
        tipo = v_tipo,
        numero = v_numero,
        nombre = v_nombre,
        fecha_inicio = v_fecha_inicio,
        fecha_fin = v_fecha_fin,
        institucion = v_institucion,
        estado = v_estado,
        fecha_actualizacion = pg_catalog.now()
    where usuario_uid = v_uid and id = v_id
    returning * into v_periodo;
    if not found then
      raise exception using errcode = 'P0002', message = 'periodo_no_encontrado';
    end if;
  end if;
  return pg_catalog.to_jsonb(v_periodo);
end;
$$;

commit;
