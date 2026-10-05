-- Módulo Notas de EducFlow AI.
-- Reutiliza las entidades académicas existentes en PostgreSQL. Las claves
-- compuestas evitan relacionar datos pertenecientes a usuarios distintos.

begin;

create table if not exists public.configuracion_notas (
  usuario_uid text primary key references public.usuarios(uid) on delete cascade,
  nota_minima numeric(8, 3) not null default 1.0,
  nota_maxima numeric(8, 3) not null default 7.0,
  nota_aprobacion numeric(8, 3) not null default 4.0,
  decimales smallint not null default 1,
  politica_redondeo text not null default 'mas_cercano',
  fecha_actualizacion timestamptz not null default pg_catalog.now(),
  constraint configuracion_notas_escala_check check (
    nota_minima > '-Infinity'::numeric
    and nota_minima < 'Infinity'::numeric
    and nota_maxima > '-Infinity'::numeric
    and nota_maxima < 'Infinity'::numeric
    and nota_aprobacion > '-Infinity'::numeric
    and nota_aprobacion < 'Infinity'::numeric
    and nota_minima < nota_maxima
    and nota_aprobacion between nota_minima and nota_maxima
  ),
  constraint configuracion_notas_decimales_check check (decimales between 0 and 3),
  constraint configuracion_notas_redondeo_check check (
    politica_redondeo in ('mas_cercano', 'truncar')
  )
);

create table if not exists public.notas_evaluaciones (
  usuario_uid text not null references public.usuarios(uid) on delete cascade,
  evaluacion_id text not null,
  nota numeric(8, 3) not null,
  fecha_actualizacion timestamptz not null default pg_catalog.now(),
  primary key (usuario_uid, evaluacion_id),
  constraint notas_evaluaciones_evaluacion_fkey foreign key (
    usuario_uid,
    evaluacion_id
  ) references public.evaluaciones(usuario_uid, id) on delete cascade,
  constraint notas_evaluaciones_nota_finita_check check (
    nota > '-Infinity'::numeric and nota < 'Infinity'::numeric
  )
);

create table if not exists public.objetivos_notas (
  usuario_uid text not null references public.usuarios(uid) on delete cascade,
  asignatura_id text not null,
  nota_objetivo numeric(8, 3) not null,
  fecha_actualizacion timestamptz not null default pg_catalog.now(),
  primary key (usuario_uid, asignatura_id),
  constraint objetivos_notas_asignatura_fkey foreign key (
    usuario_uid,
    asignatura_id
  ) references public.asignaturas(usuario_uid, id) on delete cascade,
  constraint objetivos_notas_nota_finita_check check (
    nota_objetivo > '-Infinity'::numeric
    and nota_objetivo < 'Infinity'::numeric
  )
);

alter table public.configuracion_notas enable row level security;
alter table public.notas_evaluaciones enable row level security;
alter table public.objetivos_notas enable row level security;

drop policy if exists configuracion_notas_propietario on public.configuracion_notas;
create policy configuracion_notas_propietario
  on public.configuracion_notas
  for all
  to authenticated
  using (
    (select public.is_educflow_firebase_user()) is true
    and usuario_uid = (select public.current_firebase_uid())
  )
  with check (
    (select public.is_educflow_firebase_user()) is true
    and usuario_uid = (select public.current_firebase_uid())
  );

drop policy if exists notas_evaluaciones_propietario on public.notas_evaluaciones;
create policy notas_evaluaciones_propietario
  on public.notas_evaluaciones
  for all
  to authenticated
  using (
    (select public.is_educflow_firebase_user()) is true
    and usuario_uid = (select public.current_firebase_uid())
  )
  with check (
    (select public.is_educflow_firebase_user()) is true
    and usuario_uid = (select public.current_firebase_uid())
  );

drop policy if exists objetivos_notas_propietario on public.objetivos_notas;
create policy objetivos_notas_propietario
  on public.objetivos_notas
  for all
  to authenticated
  using (
    (select public.is_educflow_firebase_user()) is true
    and usuario_uid = (select public.current_firebase_uid())
  )
  with check (
    (select public.is_educflow_firebase_user()) is true
    and usuario_uid = (select public.current_firebase_uid())
  );

revoke all on table public.configuracion_notas
  from public, anon, authenticated;
revoke all on table public.notas_evaluaciones
  from public, anon, authenticated;
revoke all on table public.objetivos_notas
  from public, anon, authenticated;

grant select, insert, update, delete on table public.configuracion_notas
  to authenticated;
grant select, insert, update, delete on table public.notas_evaluaciones
  to authenticated;
grant select, insert, update, delete on table public.objetivos_notas
  to authenticated;

-- Todas las escrituras de configuración, notas y objetivos de un usuario se
-- serializan con el mismo advisory lock. Esto evita que una reducción de la
-- escala compita con una nota u objetivo que todavía use la escala anterior.
create or replace function public.validar_configuracion_notas()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.usuario_uid, 0::bigint)
  );

  if exists (
    select 1
    from public.notas_evaluaciones
    where usuario_uid = new.usuario_uid
      and nota not between new.nota_minima and new.nota_maxima
  ) then
    raise exception using
      errcode = '23514',
      message = 'configuracion_deja_notas_fuera_de_escala';
  end if;

  if exists (
    select 1
    from public.objetivos_notas
    where usuario_uid = new.usuario_uid
      and nota_objetivo not between new.nota_minima and new.nota_maxima
  ) then
    raise exception using
      errcode = '23514',
      message = 'configuracion_deja_objetivos_fuera_de_escala';
  end if;

  new.fecha_actualizacion = pg_catalog.now();
  return new;
end;
$$;

create or replace function public.validar_nota_evaluacion()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_nota_minima numeric(8, 3) := 1.0;
  v_nota_maxima numeric(8, 3) := 7.0;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.usuario_uid, 0::bigint)
  );

  select nota_minima, nota_maxima
    into v_nota_minima, v_nota_maxima
  from public.configuracion_notas
  where usuario_uid = new.usuario_uid;

  if not found then
    v_nota_minima := 1.0;
    v_nota_maxima := 7.0;
  end if;

  if new.nota not between v_nota_minima and v_nota_maxima then
    raise exception using
      errcode = '23514',
      message = 'nota_fuera_de_escala_configurada';
  end if;

  new.fecha_actualizacion = pg_catalog.now();
  return new;
end;
$$;

create or replace function public.validar_objetivo_nota()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_nota_minima numeric(8, 3) := 1.0;
  v_nota_maxima numeric(8, 3) := 7.0;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.usuario_uid, 0::bigint)
  );

  select nota_minima, nota_maxima
    into v_nota_minima, v_nota_maxima
  from public.configuracion_notas
  where usuario_uid = new.usuario_uid;

  if not found then
    v_nota_minima := 1.0;
    v_nota_maxima := 7.0;
  end if;

  if new.nota_objetivo not between v_nota_minima and v_nota_maxima then
    raise exception using
      errcode = '23514',
      message = 'objetivo_fuera_de_escala_configurada';
  end if;

  new.fecha_actualizacion = pg_catalog.now();
  return new;
end;
$$;

drop trigger if exists configuracion_notas_actualizada on public.configuracion_notas;
create trigger configuracion_notas_actualizada
before insert or update on public.configuracion_notas
for each row execute function public.validar_configuracion_notas();

drop trigger if exists notas_evaluaciones_actualizadas on public.notas_evaluaciones;
create trigger notas_evaluaciones_actualizadas
before insert or update on public.notas_evaluaciones
for each row execute function public.validar_nota_evaluacion();

drop trigger if exists objetivos_notas_actualizados on public.objetivos_notas;
create trigger objetivos_notas_actualizados
before insert or update on public.objetivos_notas
for each row execute function public.validar_objetivo_nota();

-- Las funciones solo se invocan mediante sus triggers. No son una API pública.
revoke all on function public.validar_configuracion_notas()
  from public, anon, authenticated;
revoke all on function public.validar_nota_evaluacion()
  from public, anon, authenticated;
revoke all on function public.validar_objetivo_nota()
  from public, anon, authenticated;

commit;
