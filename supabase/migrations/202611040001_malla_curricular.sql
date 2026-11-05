-- Primera etapa OCR. Aplicar tras revisar el esquema Firebase/Supabase existente.
-- No altera asignaturas inscritas ni datos académicos previos.
begin;

create table if not exists public.mallas_curriculares (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  usuario_uid text not null unique references public.usuarios(uid) on delete cascade,
  archivo_nombre text,
  confirmada_en timestamptz not null default pg_catalog.now(),
  unique (usuario_uid, id)
);

create table if not exists public.ramos_malla (
  usuario_uid text not null,
  malla_id uuid not null,
  id text not null check (
    id ~ '^[A-Za-z0-9_-]{1,64}$' and id !~ '[[:cntrl:]]'
  ),
  orden integer not null,
  semestre integer not null check (semestre between 1 and 30),
  nombre text not null check (
    pg_catalog.length(pg_catalog.btrim(nombre)) between 1 and 300
    and nombre !~ '[[:cntrl:]]'
  ),
  codigo text check (
    codigo is null or (
      pg_catalog.length(pg_catalog.btrim(codigo)) between 1 and 64
      and codigo !~ '[[:cntrl:]]'
    )
  ),
  creditos integer check (creditos between 0 and 999),
  requiere_revision boolean not null default false,
  motivos_revision jsonb not null default '[]'::jsonb
    check (
      pg_catalog.jsonb_typeof(motivos_revision) = 'array'
      and pg_catalog.jsonb_array_length(motivos_revision) <= 12
      and pg_catalog.octet_length(motivos_revision::text) <= 2048
    ),
  estado text not null default 'pendiente'
    check (estado in ('pendiente', 'en_curso', 'aprobada')),
  primary key (usuario_uid, id),
  foreign key (usuario_uid, malla_id)
    references public.mallas_curriculares(usuario_uid, id) on delete cascade,
  unique (malla_id, orden),
  unique (malla_id, id)
);

create index if not exists ramos_malla_semestre_idx
  on public.ramos_malla(usuario_uid, semestre, orden);

alter table public.mallas_curriculares enable row level security;
alter table public.ramos_malla enable row level security;

drop policy if exists mallas_curriculares_lectura on public.mallas_curriculares;
create policy mallas_curriculares_lectura on public.mallas_curriculares
  for select to authenticated
  using (public.is_educflow_firebase_user()
    and usuario_uid = public.current_firebase_uid());

drop policy if exists ramos_malla_lectura on public.ramos_malla;
create policy ramos_malla_lectura on public.ramos_malla
  for select to authenticated
  using (public.is_educflow_firebase_user()
    and usuario_uid = public.current_firebase_uid());

revoke all on public.mallas_curriculares, public.ramos_malla from public, anon, authenticated;
grant select on public.mallas_curriculares, public.ramos_malla to authenticated;

create or replace function public.confirmar_malla_curricular(
  p_expected_uid text, p_archivo_nombre text, p_ramos jsonb
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid text;
  v_malla_id uuid;
  v_count integer;
  v_ramo jsonb;
  v_motivo jsonb;
  v_codigo text;
  v_nombre text;
  v_semestre text;
  v_creditos text;
begin
  if public.is_educflow_firebase_user() is distinct from true then
    raise exception using errcode = '42501', message = 'usuario_firebase_no_valido';
  end if;
  v_uid := public.current_firebase_uid();
  if v_uid is null or v_uid is distinct from p_expected_uid then
    raise exception using errcode = '42501', message = 'uid_firebase_no_valido';
  end if;
  if pg_catalog.jsonb_typeof(p_ramos) is distinct from 'array' then
    raise exception using errcode = '22023', message = 'malla_formato_invalido';
  end if;
  if pg_catalog.jsonb_array_length(p_ramos) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'malla_vacia_o_excesiva';
  end if;
  if pg_catalog.octet_length(p_ramos::text) > 2000000 then
    raise exception using errcode = '22023', message = 'malla_payload_excesivo';
  end if;
  if pg_catalog.length(coalesce(p_archivo_nombre, '')) > 255
    or p_archivo_nombre ~ '[[:cntrl:]]' then
    raise exception using errcode = '22023', message = 'archivo_nombre_invalido';
  end if;
  -- IDs Flutter: ocr_N, manual_N y special_N. El límite de 64 deja margen
  -- sin permitir identificadores arbitrariamente largos.
  for v_ramo in select value from pg_catalog.jsonb_array_elements(p_ramos) loop
    if pg_catalog.jsonb_typeof(v_ramo) is distinct from 'object' then
      raise exception using errcode = '22023', message = 'ramo_formato_invalido';
    end if;
    if not (v_ramo ?& array[
      'id', 'nombre', 'semestre', 'codigo', 'creditos',
      'requiere_revision', 'motivos_revision'
    ]) then
      raise exception using errcode = '22023', message = 'ramo_campos_incompletos';
    end if;
    if exists (
      select 1 from pg_catalog.jsonb_object_keys(v_ramo) as campo(nombre)
      where campo.nombre not in (
        'id', 'nombre', 'semestre', 'codigo', 'creditos',
        'requiere_revision', 'motivos_revision'
      )
    ) then
      raise exception using errcode = '22023', message = 'ramo_campos_inesperados';
    end if;
    if pg_catalog.jsonb_typeof(v_ramo -> 'id') is distinct from 'string'
      or pg_catalog.btrim(v_ramo ->> 'id') !~ '^[A-Za-z0-9_-]{1,64}$'
      or (v_ramo ->> 'id') ~ '[[:cntrl:]]' then
      raise exception using errcode = '22023', message = 'ramo_id_invalido';
    end if;
    v_nombre := v_ramo ->> 'nombre';
    if pg_catalog.jsonb_typeof(v_ramo -> 'nombre') is distinct from 'string'
      or pg_catalog.length(pg_catalog.btrim(v_nombre)) not between 1 and 300
      or v_nombre ~ '[[:cntrl:]]' then
      raise exception using errcode = '22023', message = 'ramo_nombre_invalido';
    end if;
    v_semestre := v_ramo ->> 'semestre';
    if pg_catalog.jsonb_typeof(v_ramo -> 'semestre') is distinct from 'number'
      or v_semestre !~ '^[0-9]{1,2}$' then
      raise exception using errcode = '22023', message = 'ramo_semestre_invalido';
    end if;
    if v_semestre::integer not between 1 and 30 then
      raise exception using errcode = '22023', message = 'ramo_semestre_invalido';
    end if;
    if pg_catalog.jsonb_typeof(v_ramo -> 'codigo') not in ('null', 'string') then
      raise exception using errcode = '22023', message = 'ramo_codigo_invalido';
    end if;
    v_codigo := v_ramo ->> 'codigo';
    if pg_catalog.length(coalesce(v_codigo, '')) > 64
      or v_codigo ~ '[[:cntrl:]]' then
      raise exception using errcode = '22023', message = 'ramo_codigo_invalido';
    end if;
    if pg_catalog.jsonb_typeof(v_ramo -> 'creditos') not in ('null', 'number') then
      raise exception using errcode = '22023', message = 'ramo_creditos_invalidos';
    end if;
    v_creditos := v_ramo ->> 'creditos';
    if v_creditos is not null and v_creditos !~ '^[0-9]{1,3}$' then
      raise exception using errcode = '22023', message = 'ramo_creditos_invalidos';
    end if;
    if pg_catalog.jsonb_typeof(v_ramo -> 'requiere_revision') is distinct from 'boolean' then
      raise exception using errcode = '22023', message = 'ramo_revision_invalida';
    end if;
    if pg_catalog.jsonb_typeof(v_ramo -> 'motivos_revision') is distinct from 'array' then
      raise exception using errcode = '22023', message = 'motivos_revision_invalidos';
    end if;
    if pg_catalog.jsonb_array_length(v_ramo -> 'motivos_revision') > 12
      or pg_catalog.octet_length((v_ramo -> 'motivos_revision')::text) > 2048 then
      raise exception using errcode = '22023', message = 'motivos_revision_excesivos';
    end if;
    for v_motivo in
      select value from pg_catalog.jsonb_array_elements(v_ramo -> 'motivos_revision')
    loop
      if pg_catalog.jsonb_typeof(v_motivo) is distinct from 'string'
        or (v_motivo #>> '{}') !~ '^[A-Za-z0-9_:-]{1,120}$'
        or (v_motivo #>> '{}') ~ '[[:cntrl:]]' then
        raise exception using errcode = '22023', message = 'motivo_revision_invalido';
      end if;
    end loop;
  end loop;
  -- La restricción unique(usuario_uid) también protege llamadas simultáneas.
  if exists (select 1 from public.mallas_curriculares where usuario_uid = v_uid) then
    raise exception using errcode = '23505', message = 'malla_ya_confirmada';
  end if;
  insert into public.mallas_curriculares(usuario_uid, archivo_nombre)
    values (v_uid, p_archivo_nombre) returning id into v_malla_id;

  insert into public.ramos_malla(
    usuario_uid, malla_id, id, orden, semestre, nombre, codigo,
    creditos, requiere_revision, motivos_revision
  )
  select v_uid, v_malla_id,
    pg_catalog.btrim(item.value ->> 'id'), item.ordinality::integer,
    (item.value ->> 'semestre')::integer,
    pg_catalog.btrim(item.value ->> 'nombre'),
    nullif(pg_catalog.btrim(item.value ->> 'codigo'), ''),
    nullif(item.value ->> 'creditos', '')::integer,
    coalesce((item.value ->> 'requiere_revision')::boolean, false),
    coalesce(item.value -> 'motivos_revision', '[]'::jsonb)
  from pg_catalog.jsonb_array_elements(p_ramos) with ordinality as item(value, ordinality);
  get diagnostics v_count = row_count;
  if v_count <> pg_catalog.jsonb_array_length(p_ramos) then
    raise exception using errcode = '22023', message = 'malla_incompleta';
  end if;
  return v_malla_id;
end;
$$;

create or replace function public.cambiar_estado_ramo_malla(
  p_expected_uid text, p_ramo_id text, p_estado text
) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid text;
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
  update public.ramos_malla set estado = p_estado
    where usuario_uid = v_uid and id = p_ramo_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'ramo_malla_no_encontrado';
  end if;
end;
$$;

revoke all on function public.confirmar_malla_curricular(text, text, jsonb)
  from public, anon;
revoke all on function public.cambiar_estado_ramo_malla(text, text, text)
  from public, anon;
grant execute on function public.confirmar_malla_curricular(text, text, jsonb)
  to authenticated;
grant execute on function public.cambiar_estado_ramo_malla(text, text, text)
  to authenticated;
commit;
