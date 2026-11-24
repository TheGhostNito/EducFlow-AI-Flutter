-- Base académica para períodos y sesiones de clase con fecha específica.
-- Esta migración es aditiva: no asocia períodos ni modifica datos existentes.

begin;

create table if not exists public.periodos_academicos (
  usuario_uid text not null references public.usuarios(uid) on delete cascade,
  id text not null check (
    id ~ '^[A-Za-z0-9_-]{1,64}$' and id !~ '[[:cntrl:]]'
  ),
  anio integer not null check (anio between 1 and 9999),
  tipo text not null check (tipo in ('semestre')),
  numero integer not null check (numero between 1 and 30),
  nombre text not null check (
    pg_catalog.length(pg_catalog.btrim(nombre)) between 1 and 160
    and nombre !~ '[[:cntrl:]]'
  ),
  fecha_inicio date not null,
  fecha_fin date not null,
  institucion text check (
    institucion is null or (
      pg_catalog.length(pg_catalog.btrim(institucion)) between 1 and 200
      and institucion !~ '[[:cntrl:]]'
    )
  ),
  estado text not null default 'activo'
    check (estado in ('activo', 'historico')),
  fecha_creacion timestamptz not null default pg_catalog.now(),
  fecha_actualizacion timestamptz not null default pg_catalog.now(),
  primary key (usuario_uid, id),
  check (fecha_fin >= fecha_inicio)
);

alter table public.asignaturas
  add column if not exists periodo_academico_id text;

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.asignaturas'::pg_catalog.regclass
      and conname = 'asignaturas_periodo_academico_fkey'
  ) then
    alter table public.asignaturas
      add constraint asignaturas_periodo_academico_fkey
      foreign key (usuario_uid, periodo_academico_id)
      references public.periodos_academicos(usuario_uid, id)
      on delete restrict;
  end if;
end;
$$;

create table if not exists public.sesiones_clase (
  usuario_uid text not null,
  id text not null check (
    id ~ '^[A-Za-z0-9_-]{1,64}$' and id !~ '[[:cntrl:]]'
  ),
  asignatura_id text not null,
  periodo_academico_id text not null,
  fecha date not null,
  hora_inicio time not null,
  hora_fin time not null,
  sala text check (
    sala is null or (
      pg_catalog.length(pg_catalog.btrim(sala)) between 1 and 160
      and sala !~ '[[:cntrl:]]'
    )
  ),
  origen text not null default 'manual'
    check (origen in ('manual', 'horario')),
  fecha_creacion timestamptz not null default pg_catalog.now(),
  fecha_actualizacion timestamptz not null default pg_catalog.now(),
  primary key (usuario_uid, id),
  foreign key (usuario_uid, asignatura_id)
    references public.asignaturas(usuario_uid, id) on delete cascade,
  foreign key (usuario_uid, periodo_academico_id)
    references public.periodos_academicos(usuario_uid, id) on delete restrict,
  unique (usuario_uid, asignatura_id, fecha, hora_inicio, hora_fin),
  check (hora_fin > hora_inicio)
);

create index if not exists asignaturas_periodo_academico_idx
  on public.asignaturas(usuario_uid, periodo_academico_id)
  where periodo_academico_id is not null;

create index if not exists periodos_academicos_fechas_idx
  on public.periodos_academicos(usuario_uid, fecha_inicio, fecha_fin);

create index if not exists sesiones_clase_fecha_idx
  on public.sesiones_clase(usuario_uid, fecha, hora_inicio);

create index if not exists sesiones_clase_asignatura_idx
  on public.sesiones_clase(usuario_uid, asignatura_id, fecha);

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
  if new.fecha not between v_inicio and v_fin then
    raise exception using errcode = '23514', message = 'fecha_sesion_fuera_periodo';
  end if;

  new.fecha_actualizacion := pg_catalog.now();
  return new;
end;
$$;

drop trigger if exists sesiones_clase_integridad on public.sesiones_clase;
create trigger sesiones_clase_integridad
before insert or update on public.sesiones_clase
for each row execute function public.validar_integridad_sesion_clase();

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
      and s.fecha not between new.fecha_inicio and new.fecha_fin
  ) then
    raise exception using
      errcode = '23514',
      message = 'periodo_dejaria_sesiones_fuera_rango';
  end if;
  return new;
end;
$$;

drop trigger if exists periodos_proteger_cambio_fechas
  on public.periodos_academicos;
create trigger periodos_proteger_cambio_fechas
before update of fecha_inicio, fecha_fin on public.periodos_academicos
for each row execute function public.proteger_cambio_fechas_periodo();

create or replace function public.proteger_cambio_periodo_asignatura()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.periodo_academico_id is not distinct from old.periodo_academico_id then
    return new;
  end if;
  if exists (
    select 1
    from public.sesiones_clase as s
    where s.usuario_uid = old.usuario_uid
      and s.asignatura_id = old.id
      and s.periodo_academico_id is distinct from new.periodo_academico_id
  ) then
    raise exception using errcode = '23514', message = 'asignatura_tiene_sesiones_otro_periodo';
  end if;
  return new;
end;
$$;

drop trigger if exists asignaturas_proteger_cambio_periodo
  on public.asignaturas;
create trigger asignaturas_proteger_cambio_periodo
before update of periodo_academico_id on public.asignaturas
for each row execute function public.proteger_cambio_periodo_asignatura();

alter table public.periodos_academicos enable row level security;
alter table public.sesiones_clase enable row level security;

drop policy if exists periodos_academicos_lectura
  on public.periodos_academicos;
create policy periodos_academicos_lectura
  on public.periodos_academicos
  for select
  to authenticated
  using (
    (select public.is_educflow_firebase_user()) is true
    and usuario_uid = (select public.current_firebase_uid())
  );

drop policy if exists sesiones_clase_lectura on public.sesiones_clase;
create policy sesiones_clase_lectura
  on public.sesiones_clase
  for select
  to authenticated
  using (
    (select public.is_educflow_firebase_user()) is true
    and usuario_uid = (select public.current_firebase_uid())
  );

revoke all on table public.periodos_academicos
  from public, anon, authenticated;
revoke all on table public.sesiones_clase
  from public, anon, authenticated;
grant select on table public.periodos_academicos to authenticated;
grant select on table public.sesiones_clase to authenticated;

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
    v_fecha_inicio := (p_periodo ->> 'fecha_inicio')::date;
    v_fecha_fin := (p_periodo ->> 'fecha_fin')::date;
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
      or v_fecha_fin < v_fecha_inicio
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

create or replace function public.eliminar_periodo_academico(
  p_periodo_id text
)
returns void
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
  delete from public.periodos_academicos
  where usuario_uid = v_uid and id = pg_catalog.btrim(coalesce(p_periodo_id, ''));
end;
$$;

create or replace function public.asociar_asignatura_periodo(
  p_asignatura_id text,
  p_periodo_academico_id text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text;
  v_periodo_id text := nullif(
    pg_catalog.btrim(coalesce(p_periodo_academico_id, '')),
    ''
  );
begin
  if public.is_educflow_firebase_user() is distinct from true then
    raise exception using errcode = '42501', message = 'usuario_firebase_no_valido';
  end if;
  v_uid := public.current_firebase_uid();
  if v_uid is null or pg_catalog.btrim(v_uid) = '' then
    raise exception using errcode = '42501', message = 'uid_firebase_no_valido';
  end if;
  if v_periodo_id is not null and not exists (
    select 1 from public.periodos_academicos
    where usuario_uid = v_uid and id = v_periodo_id
  ) then
    raise exception using errcode = '23503', message = 'periodo_no_encontrado';
  end if;
  update public.asignaturas
  set periodo_academico_id = v_periodo_id,
      fecha_actualizacion = pg_catalog.now()
  where usuario_uid = v_uid
    and id = pg_catalog.btrim(coalesce(p_asignatura_id, ''));
  if not found then
    raise exception using errcode = 'P0002', message = 'asignatura_no_encontrada';
  end if;
end;
$$;

create or replace function public.guardar_sesion_clase(
  p_operacion text,
  p_sesion jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text;
  v_id text;
  v_asignatura_id text;
  v_periodo_id text;
  v_fecha date;
  v_hora_inicio time;
  v_hora_fin time;
  v_sala text;
  v_origen text;
  v_sesion public.sesiones_clase%rowtype;
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
      or pg_catalog.jsonb_typeof(p_sesion) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'payload_sesion_no_valido';
  end if;

  v_id := pg_catalog.btrim(coalesce(p_sesion ->> 'id', ''));
  v_asignatura_id := pg_catalog.btrim(coalesce(p_sesion ->> 'asignatura_id', ''));
  v_periodo_id := pg_catalog.btrim(coalesce(p_sesion ->> 'periodo_academico_id', ''));
  v_sala := nullif(pg_catalog.btrim(p_sesion ->> 'sala'), '');
  v_origen := coalesce(nullif(p_sesion ->> 'origen', ''), 'manual');
  begin
    v_fecha := (p_sesion ->> 'fecha')::date;
    v_hora_inicio := (p_sesion ->> 'hora_inicio')::time;
    v_hora_fin := (p_sesion ->> 'hora_fin')::time;
  exception
    when invalid_text_representation
      or invalid_datetime_format
      or datetime_field_overflow then
      raise exception using errcode = '22023', message = 'formato_sesion_no_valido';
  end;

  if v_id !~ '^[A-Za-z0-9_-]{1,64}$'
      or v_asignatura_id = ''
      or v_periodo_id = ''
      or v_hora_fin <= v_hora_inicio
      or v_origen not in ('manual', 'horario') then
    raise exception using errcode = '23514', message = 'sesion_no_valida';
  end if;

  if p_operacion = 'crear' then
    insert into public.sesiones_clase (
      usuario_uid, id, asignatura_id, periodo_academico_id, fecha,
      hora_inicio, hora_fin, sala, origen
    ) values (
      v_uid, v_id, v_asignatura_id, v_periodo_id, v_fecha,
      v_hora_inicio, v_hora_fin, v_sala, v_origen
    ) returning * into v_sesion;
  else
    update public.sesiones_clase
    set asignatura_id = v_asignatura_id,
        periodo_academico_id = v_periodo_id,
        fecha = v_fecha,
        hora_inicio = v_hora_inicio,
        hora_fin = v_hora_fin,
        sala = v_sala,
        origen = v_origen,
        fecha_actualizacion = pg_catalog.now()
    where usuario_uid = v_uid and id = v_id
    returning * into v_sesion;
    if not found then
      raise exception using errcode = 'P0002', message = 'sesion_no_encontrada';
    end if;
  end if;
  return pg_catalog.to_jsonb(v_sesion);
end;
$$;

create or replace function public.eliminar_sesion_clase(
  p_sesion_id text
)
returns void
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
  delete from public.sesiones_clase
  where usuario_uid = v_uid and id = pg_catalog.btrim(coalesce(p_sesion_id, ''));
end;
$$;

revoke all on function public.validar_integridad_sesion_clase()
  from public, anon, authenticated;
revoke all on function public.proteger_cambio_fechas_periodo()
  from public, anon, authenticated;
revoke all on function public.proteger_cambio_periodo_asignatura()
  from public, anon, authenticated;

revoke all on function public.guardar_periodo_academico(text, jsonb)
  from public, anon;
grant execute on function public.guardar_periodo_academico(text, jsonb)
  to authenticated;
revoke all on function public.eliminar_periodo_academico(text)
  from public, anon;
grant execute on function public.eliminar_periodo_academico(text)
  to authenticated;
revoke all on function public.asociar_asignatura_periodo(text, text)
  from public, anon;
grant execute on function public.asociar_asignatura_periodo(text, text)
  to authenticated;
revoke all on function public.guardar_sesion_clase(text, jsonb)
  from public, anon;
grant execute on function public.guardar_sesion_clase(text, jsonb)
  to authenticated;
revoke all on function public.eliminar_sesion_clase(text)
  from public, anon;
grant execute on function public.eliminar_sesion_clase(text)
  to authenticated;

commit;
