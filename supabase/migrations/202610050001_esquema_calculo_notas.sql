-- Configuración optativa del cálculo académico por asignatura.
-- La ausencia de una fila conserva el comportamiento histórico: esquema
-- directo, donde las evaluaciones construyen el 100 % de la nota final.

begin;

create table if not exists public.configuracion_calculo_asignaturas (
  usuario_uid text not null,
  asignatura_id text not null,
  esquema text not null default 'directo',
  peso_presentacion numeric(5, 2) not null default 100,
  peso_examen numeric(5, 2) not null default 0,
  evaluacion_examen_id text,
  fecha_actualizacion timestamptz not null default pg_catalog.now(),
  primary key (usuario_uid, asignatura_id),
  constraint configuracion_calculo_asignatura_fkey foreign key (
    usuario_uid,
    asignatura_id
  ) references public.asignaturas(usuario_uid, id) on delete cascade,
  constraint configuracion_calculo_examen_fkey foreign key (
    usuario_uid,
    evaluacion_examen_id
  ) references public.evaluaciones(usuario_uid, id) on delete restrict,
  constraint configuracion_calculo_esquema_check check (
    (
      esquema = 'directo'
      and peso_presentacion = 100
      and peso_examen = 0
      and evaluacion_examen_id is null
    )
    or
    (
      esquema = 'presentacion_examen'
      and peso_presentacion > 0
      and peso_examen > 0
      and peso_presentacion + peso_examen = 100
      and evaluacion_examen_id is not null
    )
  )
);

alter table public.configuracion_calculo_asignaturas enable row level security;

drop policy if exists configuracion_calculo_asignaturas_propietario
  on public.configuracion_calculo_asignaturas;
create policy configuracion_calculo_asignaturas_propietario
  on public.configuracion_calculo_asignaturas
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

create or replace function public.validar_configuracion_calculo_asignatura()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.esquema = 'presentacion_examen' then
    perform 1
    from public.evaluaciones
    where usuario_uid = new.usuario_uid
      and id = new.evaluacion_examen_id
      and asignatura_id = new.asignatura_id
    for key share;

    if not found then
      raise exception using
        errcode = '23514',
        message = 'examen_final_no_pertenece_a_asignatura';
    end if;
  end if;

  new.fecha_actualizacion = pg_catalog.now();
  return new;
end;
$$;

drop trigger if exists configuracion_calculo_asignatura_valida
  on public.configuracion_calculo_asignaturas;
create trigger configuracion_calculo_asignatura_valida
before insert or update on public.configuracion_calculo_asignaturas
for each row execute function public.validar_configuracion_calculo_asignatura();

revoke all on table public.configuracion_calculo_asignaturas
  from public, anon, authenticated;
grant select, insert, update, delete
  on table public.configuracion_calculo_asignaturas
  to authenticated;

revoke all on function public.validar_configuracion_calculo_asignatura()
  from public, anon, authenticated;

commit;
