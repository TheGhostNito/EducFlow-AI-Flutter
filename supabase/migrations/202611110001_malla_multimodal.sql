-- Persistencia multimodal de mallas. Aplicar después de
-- 202611050001_editar_ramo_malla.sql.
-- Migración aditiva: no modifica el contrato de confirmar_malla_curricular.
begin;

alter table public.mallas_curriculares
  add column if not exists tipo_periodo text not null default 'semester',
  add column if not exists cantidad_periodos integer not null default 1,
  add column if not exists origen_importacion text not null default 'vision',
  add column if not exists estado_revision text not null default 'confirmed';

update public.mallas_curriculares as m
set cantidad_periodos = greatest(1, coalesce((
      select max(r.semestre)
      from public.ramos_malla as r
      where r.usuario_uid = m.usuario_uid and r.malla_id = m.id
    ), 1)),
    estado_revision = case when exists (
      select 1 from public.ramos_malla as r
      where r.usuario_uid = m.usuario_uid and r.malla_id = m.id
        and r.requiere_revision
    ) then 'pending' else 'confirmed' end
where m.origen_importacion = 'vision';

alter table public.mallas_curriculares
  drop constraint if exists mallas_curriculares_tipo_periodo_check,
  add constraint mallas_curriculares_tipo_periodo_check check (
    tipo_periodo in (
      'semester', 'bimester', 'trimester', 'quarter', 'annual', 'unknown'
    )
  ),
  drop constraint if exists mallas_curriculares_cantidad_periodos_check,
  add constraint mallas_curriculares_cantidad_periodos_check check (
    cantidad_periodos between 1 and 30
  ),
  drop constraint if exists mallas_curriculares_origen_importacion_check,
  add constraint mallas_curriculares_origen_importacion_check check (
    origen_importacion in ('vision', 'multimodal')
  ),
  drop constraint if exists mallas_curriculares_estado_revision_check,
  add constraint mallas_curriculares_estado_revision_check check (
    estado_revision in ('confirmed', 'pending')
  );

alter table public.ramos_malla
  add column if not exists categoria text not null default 'unknown',
  add column if not exists categoria_etiqueta text,
  add column if not exists etiqueta_original text,
  add column if not exists procedencia text not null default 'vision',
  add column if not exists estado_revision text not null default 'confirmed',
  add column if not exists evidencias jsonb not null default '[]'::jsonb;

update public.ramos_malla
set estado_revision = case when requiere_revision then 'pending' else 'confirmed' end
where procedencia = 'vision';

alter table public.ramos_malla
  drop constraint if exists ramos_malla_categoria_check,
  add constraint ramos_malla_categoria_check check (
    pg_catalog.length(pg_catalog.btrim(categoria)) between 1 and 64
    and categoria !~ '[[:cntrl:]]'
  ),
  drop constraint if exists ramos_malla_categoria_etiqueta_check,
  add constraint ramos_malla_categoria_etiqueta_check check (
    categoria_etiqueta is null or (
      pg_catalog.length(pg_catalog.btrim(categoria_etiqueta)) between 1 and 160
      and categoria_etiqueta !~ '[[:cntrl:]]'
    )
  ),
  drop constraint if exists ramos_malla_etiqueta_original_check,
  add constraint ramos_malla_etiqueta_original_check check (
    etiqueta_original is null or (
      pg_catalog.length(pg_catalog.btrim(etiqueta_original)) between 1 and 300
      and etiqueta_original !~ '[[:cntrl:]]'
    )
  ),
  drop constraint if exists ramos_malla_procedencia_check,
  add constraint ramos_malla_procedencia_check check (
    procedencia in ('vision', 'gemini', 'merged', 'manual')
  ),
  drop constraint if exists ramos_malla_estado_revision_check,
  add constraint ramos_malla_estado_revision_check check (
    estado_revision in ('confirmed', 'manual', 'suggested', 'pending', 'incomplete')
  ),
  drop constraint if exists ramos_malla_evidencias_check,
  add constraint ramos_malla_evidencias_check check (
    pg_catalog.jsonb_typeof(evidencias) = 'array'
    and pg_catalog.jsonb_array_length(evidencias) <= 20
    and pg_catalog.octet_length(evidencias::text) <= 8192
  );

create unique index if not exists ramos_malla_scope_uid_idx
  on public.ramos_malla(usuario_uid, malla_id, id);

create table if not exists public.prerrequisitos_malla (
  usuario_uid text not null,
  malla_id uuid not null,
  ramo_id text not null,
  requisito_ramo_id text not null,
  procedencia text not null,
  decision text not null,
  certeza text not null,
  evidencias jsonb not null default '[]'::jsonb,
  motivos_pendientes jsonb not null default '[]'::jsonb,
  primary key (usuario_uid, malla_id, ramo_id, requisito_ramo_id),
  foreign key (usuario_uid, malla_id)
    references public.mallas_curriculares(usuario_uid, id) on delete cascade,
  foreign key (usuario_uid, malla_id, ramo_id)
    references public.ramos_malla(usuario_uid, malla_id, id) on delete cascade,
  foreign key (usuario_uid, malla_id, requisito_ramo_id)
    references public.ramos_malla(usuario_uid, malla_id, id) on delete cascade,
  check (ramo_id <> requisito_ramo_id),
  check (procedencia in ('gemini', 'manual')),
  check (decision in ('suggested', 'pending', 'accepted', 'rejected')),
  check (certeza in ('confirmed', 'uncertain', 'unknown')),
  check (decision <> 'accepted' or certeza = 'confirmed')
);

create table if not exists public.certificaciones_malla (
  usuario_uid text not null,
  malla_id uuid not null,
  id text not null check (id ~ '^[A-Za-z0-9_-]{1,64}$'),
  nombre text not null check (
    pg_catalog.length(pg_catalog.btrim(nombre)) between 1 and 300
    and nombre !~ '[[:cntrl:]]'
  ),
  procedencia text not null,
  decision text not null,
  evidencias jsonb not null default '[]'::jsonb,
  motivos_pendientes jsonb not null default '[]'::jsonb,
  primary key (usuario_uid, malla_id, id),
  foreign key (usuario_uid, malla_id)
    references public.mallas_curriculares(usuario_uid, id) on delete cascade,
  check (procedencia in ('gemini', 'manual')),
  check (decision in ('suggested', 'pending', 'accepted', 'rejected'))
);

create table if not exists public.membresias_certificacion_malla (
  usuario_uid text not null,
  malla_id uuid not null,
  certificacion_id text not null,
  ramo_id text not null,
  procedencia text not null,
  decision text not null,
  fundamento text not null,
  evidencias jsonb not null default '[]'::jsonb,
  motivos_pendientes jsonb not null default '[]'::jsonb,
  primary key (usuario_uid, malla_id, certificacion_id, ramo_id),
  foreign key (usuario_uid, malla_id, certificacion_id)
    references public.certificaciones_malla(usuario_uid, malla_id, id)
    on delete cascade,
  foreign key (usuario_uid, malla_id, ramo_id)
    references public.ramos_malla(usuario_uid, malla_id, id) on delete cascade,
  check (procedencia in ('gemini', 'manual')),
  check (decision in ('suggested', 'pending', 'accepted', 'rejected')),
  check (pg_catalog.length(pg_catalog.btrim(fundamento)) between 1 and 120
    and fundamento !~ '[[:cntrl:]]')
);

create table if not exists public.requisitos_academicos_malla (
  usuario_uid text not null,
  malla_id uuid not null,
  id text not null check (id ~ '^[A-Za-z0-9_-]{1,64}$'),
  tipo text not null check (
    pg_catalog.length(pg_catalog.btrim(tipo)) between 1 and 64
    and tipo !~ '[[:cntrl:]]'
  ),
  ramo_objetivo_id text,
  etiqueta_objetivo text,
  descripcion text not null check (
    pg_catalog.length(pg_catalog.btrim(descripcion)) between 1 and 1000
    and descripcion !~ '[[:cntrl:]]'
  ),
  nivel_minimo integer check (nivel_minimo between 1 and 30),
  procedencia text not null,
  decision text not null,
  evidencias jsonb not null default '[]'::jsonb,
  motivos_pendientes jsonb not null default '[]'::jsonb,
  primary key (usuario_uid, malla_id, id),
  foreign key (usuario_uid, malla_id)
    references public.mallas_curriculares(usuario_uid, id) on delete cascade,
  foreign key (usuario_uid, malla_id, ramo_objetivo_id)
    references public.ramos_malla(usuario_uid, malla_id, id) on delete cascade,
  check (procedencia in ('gemini', 'manual')),
  check (decision in ('suggested', 'pending', 'accepted', 'rejected')),
  check (etiqueta_objetivo is null or (
    pg_catalog.length(pg_catalog.btrim(etiqueta_objetivo)) between 1 and 300
    and etiqueta_objetivo !~ '[[:cntrl:]]'
  )),
  check (
    decision <> 'accepted'
    or pg_catalog.lower(pg_catalog.btrim(tipo)) <> 'unknown'
  )
);

create table if not exists public.pendientes_revision_malla (
  usuario_uid text not null,
  malla_id uuid not null,
  id text not null check (id ~ '^[A-Za-z0-9_-]{1,64}$'),
  entidad_tipo text not null check (entidad_tipo in (
    'course', 'prerequisite', 'certification', 'membership',
    'requirement', 'global'
  )),
  entidad_clave text not null check (
    pg_catalog.length(pg_catalog.btrim(entidad_clave)) between 1 and 200
    and entidad_clave !~ '[[:cntrl:]]'
  ),
  motivos jsonb not null,
  evidencias jsonb not null default '[]'::jsonb,
  estado text not null default 'pending'
    check (estado in ('pending', 'resolved', 'dismissed')),
  resolucion text check (
    resolucion is null or (
      pg_catalog.length(pg_catalog.btrim(resolucion)) between 1 and 500
      and resolucion !~ '[[:cntrl:]]'
    )
  ),
  check (
    estado = 'pending' and resolucion is null
    or estado in ('resolved', 'dismissed') and resolucion is not null
  ),
  primary key (usuario_uid, malla_id, id),
  foreign key (usuario_uid, malla_id)
    references public.mallas_curriculares(usuario_uid, id) on delete cascade
);

create index if not exists prerrequisitos_malla_estado_idx
  on public.prerrequisitos_malla(usuario_uid, malla_id, decision);
create index if not exists membresias_certificacion_malla_estado_idx
  on public.membresias_certificacion_malla(usuario_uid, malla_id, decision);
create index if not exists pendientes_revision_malla_estado_idx
  on public.pendientes_revision_malla(usuario_uid, malla_id, estado);

create or replace function public.malla_jsonb_text_array_valido(
  p_value jsonb,
  p_max_items integer,
  p_max_bytes integer,
  p_max_item_length integer
) returns boolean
language plpgsql immutable parallel safe set search_path = ''
as $$
begin
  if pg_catalog.jsonb_typeof(p_value) is distinct from 'array'
    or pg_catalog.jsonb_array_length(p_value) > p_max_items
    or pg_catalog.octet_length(p_value::text) > p_max_bytes then
    return false;
  end if;
  return not exists (
    select 1 from pg_catalog.jsonb_array_elements(p_value) as item(value)
    where pg_catalog.jsonb_typeof(item.value) is distinct from 'string'
      or pg_catalog.length(item.value #>> '{}') not between 1 and p_max_item_length
      or (item.value #>> '{}') ~ '[[:cntrl:]]'
  );
end;
$$;

-- Mantiene completos los metadatos de mallas creadas por el RPC Vision-only
-- sin cambiar su firma ni su payload histórico.
create or replace function public.sincronizar_resumen_malla_vision()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid text;
  v_malla_id uuid;
begin
  if tg_op = 'DELETE' then
    v_uid := old.usuario_uid;
    v_malla_id := old.malla_id;
  else
    v_uid := new.usuario_uid;
    v_malla_id := new.malla_id;
  end if;
  update public.mallas_curriculares as m
  set cantidad_periodos = greatest(1, coalesce((
        select max(r.semestre) from public.ramos_malla as r
        where r.usuario_uid = v_uid and r.malla_id = v_malla_id
      ), 1)),
      estado_revision = case when exists (
        select 1 from public.ramos_malla as r
        where r.usuario_uid = v_uid and r.malla_id = v_malla_id
          and r.requiere_revision
      ) then 'pending' else 'confirmed' end
  where m.usuario_uid = v_uid and m.id = v_malla_id
    and m.origen_importacion = 'vision';
  return null;
end;
$$;

drop trigger if exists sincronizar_resumen_malla_vision_trigger
  on public.ramos_malla;
create trigger sincronizar_resumen_malla_vision_trigger
after insert or update or delete
on public.ramos_malla for each row
execute function public.sincronizar_resumen_malla_vision();

create or replace function public.confirmar_malla_multimodal(
  p_expected_uid text,
  p_archivo_nombre text,
  p_malla jsonb
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid text;
  v_malla_id uuid;
  v_item jsonb;
  v_nested jsonb;
  v_count integer;
  v_entity_type text;
  v_entity_key text;
  v_certification_id text;
  v_course_id text;
begin
  if public.is_educflow_firebase_user() is distinct from true then
    raise exception using errcode = '42501', message = 'usuario_firebase_no_valido';
  end if;
  v_uid := public.current_firebase_uid();
  if v_uid is null or v_uid is distinct from p_expected_uid then
    raise exception using errcode = '42501', message = 'uid_firebase_no_valido';
  end if;
  if pg_catalog.jsonb_typeof(p_malla) is distinct from 'object'
    or pg_catalog.octet_length(p_malla::text) > 4000000 then
    raise exception using errcode = '22023', message = 'malla_multimodal_formato_invalido';
  end if;
  if not (p_malla ?& array['period_type', 'period_count', 'courses',
      'prerequisites', 'certifications', 'academic_requirements',
      'pending_items'])
    or exists (
      select 1 from pg_catalog.jsonb_object_keys(p_malla) as field(name)
      where field.name not in ('period_type', 'period_count', 'courses',
        'prerequisites', 'certifications', 'academic_requirements',
        'pending_items')
    ) then
    raise exception using errcode = '22023', message = 'malla_multimodal_campos_invalidos';
  end if;
  if p_malla ->> 'period_type' not in
      ('semester', 'bimester', 'trimester', 'quarter', 'annual', 'unknown')
    or pg_catalog.jsonb_typeof(p_malla -> 'period_count') is distinct from 'number'
    or (p_malla ->> 'period_count') !~ '^[0-9]{1,2}$'
    or (p_malla ->> 'period_count')::integer not between 1 and 30 then
    raise exception using errcode = '22023', message = 'periodos_invalidos';
  end if;
  if pg_catalog.length(coalesce(p_archivo_nombre, '')) > 255
    or p_archivo_nombre ~ '[[:cntrl:]]' then
    raise exception using errcode = '22023', message = 'archivo_nombre_invalido';
  end if;
  foreach v_entity_type in array array['courses', 'prerequisites',
      'certifications', 'academic_requirements', 'pending_items'] loop
    if pg_catalog.jsonb_typeof(p_malla -> v_entity_type) is distinct from 'array' then
      raise exception using errcode = '22023', message = 'coleccion_multimodal_invalida';
    end if;
  end loop;
  if pg_catalog.jsonb_array_length(p_malla -> 'courses') not between 1 and 500
    or pg_catalog.jsonb_array_length(p_malla -> 'prerequisites') > 2000
    or pg_catalog.jsonb_array_length(p_malla -> 'certifications') > 200
    or pg_catalog.jsonb_array_length(p_malla -> 'academic_requirements') > 500
    or pg_catalog.jsonb_array_length(p_malla -> 'pending_items') > 2000 then
    raise exception using errcode = '22023', message = 'malla_multimodal_coleccion_excesiva';
  end if;

  for v_item in select value from pg_catalog.jsonb_array_elements(p_malla -> 'courses') loop
    if pg_catalog.jsonb_typeof(v_item) is distinct from 'object'
      or not (v_item ?& array['id', 'name', 'period', 'code', 'credits',
        'category', 'category_label', 'original_label', 'source',
        'review_state', 'review_reasons', 'evidence', 'academic_state'])
      or exists (
        select 1 from pg_catalog.jsonb_object_keys(v_item) as field(name)
        where field.name not in ('id', 'name', 'period', 'code', 'credits',
          'category', 'category_label', 'original_label', 'source',
          'review_state', 'review_reasons', 'evidence', 'academic_state')
      ) then
      raise exception using errcode = '22023', message = 'ramo_multimodal_campos_invalidos';
    end if;
    if v_item ->> 'id' !~ '^[A-Za-z0-9_-]{1,64}$'
      or pg_catalog.length(pg_catalog.btrim(v_item ->> 'name')) not between 1 and 300
      or (v_item ->> 'name') ~ '[[:cntrl:]]'
      or pg_catalog.jsonb_typeof(v_item -> 'period') is distinct from 'number'
      or (v_item ->> 'period') !~ '^[0-9]{1,2}$'
      or (v_item ->> 'period')::integer not between 1 and (p_malla ->> 'period_count')::integer
      or pg_catalog.jsonb_typeof(v_item -> 'code') not in ('null', 'string')
      or pg_catalog.length(coalesce(v_item ->> 'code', '')) > 64
      or coalesce(v_item ->> 'code', '') ~ '[[:cntrl:]]'
      or pg_catalog.jsonb_typeof(v_item -> 'credits') not in ('null', 'number')
      or (v_item ->> 'credits') is not null and (
        (v_item ->> 'credits') !~ '^[0-9]{1,3}$'
        or (v_item ->> 'credits')::integer not between 0 and 999
      )
      or pg_catalog.length(pg_catalog.btrim(v_item ->> 'category')) not between 1 and 64
      or (v_item ->> 'category') ~ '[[:cntrl:]]'
      or pg_catalog.jsonb_typeof(v_item -> 'category_label') not in ('null', 'string')
      or pg_catalog.length(coalesce(v_item ->> 'category_label', '')) > 160
      or pg_catalog.jsonb_typeof(v_item -> 'original_label') not in ('null', 'string')
      or pg_catalog.length(coalesce(v_item ->> 'original_label', '')) > 300
      or v_item ->> 'source' not in ('vision', 'gemini', 'merged', 'manual')
      or v_item ->> 'review_state' not in
        ('confirmed', 'manual', 'suggested', 'pending', 'incomplete')
      or v_item ->> 'academic_state' not in ('pendiente', 'en_curso', 'aprobada')
      or not public.malla_jsonb_text_array_valido(
        v_item -> 'review_reasons', 20, 4096, 120)
      or not public.malla_jsonb_text_array_valido(
        v_item -> 'evidence', 20, 8192, 500) then
      raise exception using errcode = '22023', message = 'ramo_multimodal_invalido';
    end if;
    if v_item ->> 'review_state' in ('pending', 'incomplete')
      and pg_catalog.jsonb_array_length(v_item -> 'review_reasons') = 0 then
      raise exception using errcode = '22023', message = 'ramo_pendiente_sin_motivo';
    end if;
    if v_item ->> 'review_state' in ('confirmed', 'manual')
      and pg_catalog.jsonb_array_length(v_item -> 'review_reasons') > 0 then
      raise exception using errcode = '22023', message = 'ramo_confirmado_con_pendientes';
    end if;
  end loop;
  if (select count(*) from pg_catalog.jsonb_array_elements(p_malla -> 'courses'))
    <> (select count(distinct value ->> 'id')
        from pg_catalog.jsonb_array_elements(p_malla -> 'courses')) then
    raise exception using errcode = '22023', message = 'ramo_id_duplicado';
  end if;

  for v_item in select value from pg_catalog.jsonb_array_elements(p_malla -> 'prerequisites') loop
    if pg_catalog.jsonb_typeof(v_item) is distinct from 'object'
      or not (v_item ?& array['course_id', 'requires_course_id', 'source',
        'decision', 'certainty', 'evidence', 'pending_reasons'])
      or v_item ->> 'course_id' = v_item ->> 'requires_course_id'
      or v_item ->> 'source' not in ('gemini', 'manual')
      or v_item ->> 'decision' not in ('suggested', 'pending', 'accepted', 'rejected')
      or v_item ->> 'certainty' not in ('confirmed', 'uncertain', 'unknown')
      or v_item ->> 'decision' = 'accepted' and v_item ->> 'certainty' <> 'confirmed'
      or not public.malla_jsonb_text_array_valido(v_item -> 'evidence', 20, 8192, 500)
      or not public.malla_jsonb_text_array_valido(v_item -> 'pending_reasons', 20, 4096, 120)
      or v_item ->> 'decision' = 'accepted'
        and pg_catalog.jsonb_array_length(v_item -> 'pending_reasons') > 0
      or v_item ->> 'decision' = 'pending'
        and pg_catalog.jsonb_array_length(v_item -> 'pending_reasons') = 0
      or v_item ->> 'source' = 'gemini' and v_item ->> 'decision' = 'accepted'
        and pg_catalog.jsonb_array_length(v_item -> 'evidence') = 0
      or not exists (select 1 from pg_catalog.jsonb_array_elements(p_malla -> 'courses') c
        where c.value ->> 'id' = v_item ->> 'course_id')
      or not exists (select 1 from pg_catalog.jsonb_array_elements(p_malla -> 'courses') c
        where c.value ->> 'id' = v_item ->> 'requires_course_id') then
      raise exception using errcode = '22023', message = 'prerrequisito_invalido';
    end if;
  end loop;

  for v_item in select value from pg_catalog.jsonb_array_elements(p_malla -> 'certifications') loop
    if pg_catalog.jsonb_typeof(v_item) is distinct from 'object'
      or not (v_item ?& array['id', 'name', 'source', 'decision', 'evidence',
        'pending_reasons', 'memberships'])
      or v_item ->> 'id' !~ '^[A-Za-z0-9_-]{1,64}$'
      or pg_catalog.length(pg_catalog.btrim(v_item ->> 'name')) not between 1 and 300
      or v_item ->> 'source' not in ('gemini', 'manual')
      or v_item ->> 'decision' not in ('suggested', 'pending', 'accepted', 'rejected')
      or not public.malla_jsonb_text_array_valido(v_item -> 'evidence', 20, 8192, 500)
      or not public.malla_jsonb_text_array_valido(v_item -> 'pending_reasons', 20, 4096, 120)
      or v_item ->> 'decision' = 'accepted'
        and pg_catalog.jsonb_array_length(v_item -> 'pending_reasons') > 0
      or v_item ->> 'decision' = 'pending'
        and pg_catalog.jsonb_array_length(v_item -> 'pending_reasons') = 0
      or v_item ->> 'source' = 'gemini' and v_item ->> 'decision' = 'accepted'
        and pg_catalog.jsonb_array_length(v_item -> 'evidence') = 0
      or pg_catalog.jsonb_typeof(v_item -> 'memberships') is distinct from 'array'
      or pg_catalog.jsonb_array_length(v_item -> 'memberships') > 500 then
      raise exception using errcode = '22023', message = 'certificacion_invalida';
    end if;
    for v_nested in select value from pg_catalog.jsonb_array_elements(v_item -> 'memberships') loop
      if not (v_nested ?& array['course_id', 'source', 'decision', 'basis',
          'evidence', 'pending_reasons'])
        or v_nested ->> 'source' not in ('gemini', 'manual')
        or v_nested ->> 'decision' not in ('suggested', 'pending', 'accepted', 'rejected')
        or pg_catalog.length(pg_catalog.btrim(v_nested ->> 'basis')) not between 1 and 120
        or not public.malla_jsonb_text_array_valido(v_nested -> 'evidence', 20, 8192, 500)
        or not public.malla_jsonb_text_array_valido(v_nested -> 'pending_reasons', 20, 4096, 120)
        or v_nested ->> 'decision' = 'accepted'
          and pg_catalog.jsonb_array_length(v_nested -> 'pending_reasons') > 0
        or v_nested ->> 'decision' = 'pending'
          and pg_catalog.jsonb_array_length(v_nested -> 'pending_reasons') = 0
        or v_nested ->> 'source' = 'gemini' and v_nested ->> 'decision' = 'accepted'
          and pg_catalog.jsonb_array_length(v_nested -> 'evidence') = 0
        or v_nested ->> 'decision' = 'accepted' and v_item ->> 'decision' <> 'accepted'
        or not exists (select 1 from pg_catalog.jsonb_array_elements(p_malla -> 'courses') c
          where c.value ->> 'id' = v_nested ->> 'course_id') then
        raise exception using errcode = '22023', message = 'membresia_certificacion_invalida';
      end if;
    end loop;
  end loop;
  if (select count(*) from pg_catalog.jsonb_array_elements(p_malla -> 'certifications'))
    <> (select count(distinct value ->> 'id')
        from pg_catalog.jsonb_array_elements(p_malla -> 'certifications')) then
    raise exception using errcode = '22023', message = 'certificacion_id_duplicado';
  end if;

  for v_item in select value from pg_catalog.jsonb_array_elements(p_malla -> 'academic_requirements') loop
    if not (v_item ?& array['id', 'type', 'target_course_id', 'target_label',
        'description', 'minimum_level', 'source', 'decision', 'evidence',
        'pending_reasons'])
      or v_item ->> 'id' !~ '^[A-Za-z0-9_-]{1,64}$'
      or pg_catalog.length(pg_catalog.btrim(v_item ->> 'type')) not between 1 and 64
      or pg_catalog.jsonb_typeof(v_item -> 'target_course_id') not in ('null', 'string')
      or pg_catalog.jsonb_typeof(v_item -> 'target_label') not in ('null', 'string')
      or pg_catalog.length(coalesce(v_item ->> 'target_label', '')) > 300
      or pg_catalog.length(pg_catalog.btrim(v_item ->> 'description')) not between 1 and 1000
      or pg_catalog.jsonb_typeof(v_item -> 'minimum_level') not in ('null', 'number')
      or (v_item ->> 'minimum_level') is not null and (
        (v_item ->> 'minimum_level') !~ '^[0-9]{1,2}$'
        or (v_item ->> 'minimum_level')::integer not between 1 and 30)
      or v_item ->> 'source' not in ('gemini', 'manual')
      or v_item ->> 'decision' not in ('suggested', 'pending', 'accepted', 'rejected')
      or v_item ->> 'decision' = 'accepted'
        and pg_catalog.lower(pg_catalog.btrim(v_item ->> 'type')) = 'unknown'
      or not public.malla_jsonb_text_array_valido(v_item -> 'evidence', 20, 8192, 500)
      or not public.malla_jsonb_text_array_valido(v_item -> 'pending_reasons', 20, 4096, 120)
      or v_item ->> 'decision' = 'accepted'
        and pg_catalog.jsonb_array_length(v_item -> 'pending_reasons') > 0
      or v_item ->> 'decision' = 'pending'
        and pg_catalog.jsonb_array_length(v_item -> 'pending_reasons') = 0
      or v_item ->> 'source' = 'gemini' and v_item ->> 'decision' = 'accepted'
        and pg_catalog.jsonb_array_length(v_item -> 'evidence') = 0
      or (v_item ->> 'target_course_id') is not null and not exists (
        select 1 from pg_catalog.jsonb_array_elements(p_malla -> 'courses') c
        where c.value ->> 'id' = v_item ->> 'target_course_id') then
      raise exception using errcode = '22023', message = 'requisito_academico_invalido';
    end if;
  end loop;

  if exists (select 1 from public.mallas_curriculares where usuario_uid = v_uid) then
    raise exception using errcode = '23505', message = 'malla_ya_confirmada';
  end if;
  insert into public.mallas_curriculares(usuario_uid, archivo_nombre,
    tipo_periodo, cantidad_periodos, origen_importacion, estado_revision)
  values (v_uid, nullif(pg_catalog.btrim(p_archivo_nombre), ''),
    p_malla ->> 'period_type', (p_malla ->> 'period_count')::integer,
    'multimodal', case when
      exists (select 1 from pg_catalog.jsonb_array_elements(p_malla -> 'pending_items') x
        where x.value ->> 'status' = 'pending')
      or exists (select 1 from pg_catalog.jsonb_array_elements(p_malla -> 'courses') x
        where x.value ->> 'review_state' in ('suggested', 'pending', 'incomplete'))
      or exists (select 1 from pg_catalog.jsonb_array_elements(p_malla -> 'prerequisites') x
        where x.value ->> 'decision' in ('suggested', 'pending'))
      or exists (select 1 from pg_catalog.jsonb_array_elements(p_malla -> 'certifications') x
        where x.value ->> 'decision' in ('suggested', 'pending'))
      or exists (select 1 from pg_catalog.jsonb_array_elements(p_malla -> 'academic_requirements') x
        where x.value ->> 'decision' in ('suggested', 'pending'))
      then 'pending' else 'confirmed' end)
  returning id into v_malla_id;

  insert into public.ramos_malla(usuario_uid, malla_id, id, orden, semestre,
    nombre, codigo, creditos, requiere_revision, motivos_revision, estado,
    categoria, categoria_etiqueta, etiqueta_original, procedencia,
    estado_revision, evidencias)
  select v_uid, v_malla_id, item.value ->> 'id', item.ordinality::integer,
    (item.value ->> 'period')::integer, pg_catalog.btrim(item.value ->> 'name'),
    nullif(pg_catalog.btrim(item.value ->> 'code'), ''),
    nullif(item.value ->> 'credits', '')::integer,
    item.value ->> 'review_state' in ('pending', 'incomplete'),
    item.value -> 'review_reasons', item.value ->> 'academic_state',
    pg_catalog.btrim(item.value ->> 'category'),
    nullif(pg_catalog.btrim(item.value ->> 'category_label'), ''),
    nullif(pg_catalog.btrim(item.value ->> 'original_label'), ''),
    item.value ->> 'source', item.value ->> 'review_state', item.value -> 'evidence'
  from pg_catalog.jsonb_array_elements(p_malla -> 'courses')
    with ordinality as item(value, ordinality);
  get diagnostics v_count = row_count;
  if v_count <> pg_catalog.jsonb_array_length(p_malla -> 'courses') then
    raise exception using errcode = '22023', message = 'malla_multimodal_incompleta';
  end if;

  insert into public.prerrequisitos_malla(usuario_uid, malla_id, ramo_id,
    requisito_ramo_id, procedencia, decision, certeza, evidencias,
    motivos_pendientes)
  select v_uid, v_malla_id, value ->> 'course_id',
    value ->> 'requires_course_id', value ->> 'source', value ->> 'decision',
    value ->> 'certainty', value -> 'evidence', value -> 'pending_reasons'
  from pg_catalog.jsonb_array_elements(p_malla -> 'prerequisites');

  for v_item in select value from pg_catalog.jsonb_array_elements(p_malla -> 'certifications') loop
    insert into public.certificaciones_malla(usuario_uid, malla_id, id, nombre,
      procedencia, decision, evidencias, motivos_pendientes)
    values (v_uid, v_malla_id, v_item ->> 'id',
      pg_catalog.btrim(v_item ->> 'name'), v_item ->> 'source',
      v_item ->> 'decision', v_item -> 'evidence', v_item -> 'pending_reasons');
    insert into public.membresias_certificacion_malla(usuario_uid, malla_id,
      certificacion_id, ramo_id, procedencia, decision, fundamento,
      evidencias, motivos_pendientes)
    select v_uid, v_malla_id, v_item ->> 'id', value ->> 'course_id',
      value ->> 'source', value ->> 'decision', value ->> 'basis',
      value -> 'evidence', value -> 'pending_reasons'
    from pg_catalog.jsonb_array_elements(v_item -> 'memberships');
  end loop;

  insert into public.requisitos_academicos_malla(usuario_uid, malla_id, id,
    tipo, ramo_objetivo_id, etiqueta_objetivo, descripcion, nivel_minimo,
    procedencia, decision, evidencias, motivos_pendientes)
  select v_uid, v_malla_id, value ->> 'id', value ->> 'type',
    nullif(value ->> 'target_course_id', ''),
    nullif(pg_catalog.btrim(value ->> 'target_label'), ''),
    pg_catalog.btrim(value ->> 'description'),
    nullif(value ->> 'minimum_level', '')::integer,
    value ->> 'source', value ->> 'decision', value -> 'evidence',
    value -> 'pending_reasons'
  from pg_catalog.jsonb_array_elements(p_malla -> 'academic_requirements');

  for v_item in select value from pg_catalog.jsonb_array_elements(p_malla -> 'pending_items') loop
    if not (v_item ?& array['id', 'entity_type', 'entity_key', 'reasons',
        'evidence', 'status', 'resolution'])
      or v_item ->> 'id' !~ '^[A-Za-z0-9_-]{1,64}$'
      or v_item ->> 'entity_type' not in ('course', 'prerequisite',
        'certification', 'membership', 'requirement', 'global')
      or pg_catalog.length(pg_catalog.btrim(v_item ->> 'entity_key')) not between 1 and 200
      or not public.malla_jsonb_text_array_valido(v_item -> 'reasons', 20, 4096, 120)
      or pg_catalog.jsonb_array_length(v_item -> 'reasons') = 0
      or not public.malla_jsonb_text_array_valido(v_item -> 'evidence', 20, 8192, 500)
      or v_item ->> 'status' not in ('pending', 'resolved', 'dismissed')
      or pg_catalog.jsonb_typeof(v_item -> 'resolution') not in ('null', 'string')
      or pg_catalog.length(coalesce(v_item ->> 'resolution', '')) > 500
      or v_item ->> 'status' = 'pending'
        and (v_item ->> 'resolution') is not null
      or v_item ->> 'status' in ('resolved', 'dismissed')
        and pg_catalog.length(pg_catalog.btrim(
          coalesce(v_item ->> 'resolution', ''))) = 0 then
      raise exception using errcode = '22023', message = 'pendiente_revision_invalido';
    end if;
    v_entity_type := v_item ->> 'entity_type';
    v_entity_key := v_item ->> 'entity_key';
    if v_entity_type = 'course' and not exists (
        select 1 from public.ramos_malla where usuario_uid = v_uid
          and malla_id = v_malla_id and id = v_entity_key)
      or v_entity_type = 'certification' and not exists (
        select 1 from public.certificaciones_malla where usuario_uid = v_uid
          and malla_id = v_malla_id and id = v_entity_key)
      or v_entity_type = 'requirement' and not exists (
        select 1 from public.requisitos_academicos_malla where usuario_uid = v_uid
          and malla_id = v_malla_id and id = v_entity_key) then
      raise exception using errcode = '22023', message = 'pendiente_referencia_invalida';
    end if;
    if v_entity_type = 'prerequisite' then
      v_course_id := pg_catalog.split_part(v_entity_key, '>', 1);
      v_certification_id := pg_catalog.split_part(v_entity_key, '>', 2);
      if v_course_id = '' or v_certification_id = '' or not exists (
        select 1 from public.prerrequisitos_malla where usuario_uid = v_uid
          and malla_id = v_malla_id and ramo_id = v_course_id
          and requisito_ramo_id = v_certification_id) then
        raise exception using errcode = '22023', message = 'pendiente_referencia_invalida';
      end if;
    elsif v_entity_type = 'membership' then
      v_certification_id := pg_catalog.split_part(v_entity_key, ':', 1);
      v_course_id := pg_catalog.split_part(v_entity_key, ':', 2);
      if v_certification_id = '' or v_course_id = '' or not exists (
        select 1 from public.membresias_certificacion_malla
        where usuario_uid = v_uid and malla_id = v_malla_id
          and certificacion_id = v_certification_id and ramo_id = v_course_id) then
        raise exception using errcode = '22023', message = 'pendiente_referencia_invalida';
      end if;
    end if;
    insert into public.pendientes_revision_malla(usuario_uid, malla_id, id,
      entidad_tipo, entidad_clave, motivos, evidencias, estado, resolucion)
    values (v_uid, v_malla_id, v_item ->> 'id', v_entity_type, v_entity_key,
      v_item -> 'reasons', v_item -> 'evidence', v_item ->> 'status',
      nullif(pg_catalog.btrim(v_item ->> 'resolution'), ''));
  end loop;
  return v_malla_id;
end;
$$;

create or replace function public.obtener_malla_multimodal(
  p_expected_uid text
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid text;
  v_malla public.mallas_curriculares%rowtype;
begin
  if public.is_educflow_firebase_user() is distinct from true then
    raise exception using errcode = '42501', message = 'usuario_firebase_no_valido';
  end if;
  v_uid := public.current_firebase_uid();
  if v_uid is null or v_uid is distinct from p_expected_uid then
    raise exception using errcode = '42501', message = 'uid_firebase_no_valido';
  end if;
  select m.* into v_malla
  from public.mallas_curriculares as m
  where m.usuario_uid = v_uid;
  if not found then
    raise exception using errcode = 'P0002', message = 'malla_no_encontrada';
  end if;

  return pg_catalog.jsonb_build_object(
    'id', v_malla.id,
    'file_name', v_malla.archivo_nombre,
    'period_type', v_malla.tipo_periodo,
    'period_count', v_malla.cantidad_periodos,
    'import_source', v_malla.origen_importacion,
    'review_state', v_malla.estado_revision,
    'confirmed_at', v_malla.confirmada_en,
    'courses', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', r.id,
        'name', r.nombre,
        'period', r.semestre,
        'code', r.codigo,
        'credits', r.creditos,
        'category', r.categoria,
        'category_label', r.categoria_etiqueta,
        'original_label', r.etiqueta_original,
        'source', r.procedencia,
        'review_state', r.estado_revision,
        'review_reasons', r.motivos_revision,
        'evidence', r.evidencias,
        'academic_state', r.estado,
        'duplicate_code_verified', r.codigo_duplicado_verificado
      ) order by r.orden)
      from public.ramos_malla as r
      where r.usuario_uid = v_uid and r.malla_id = v_malla.id
    ), '[]'::jsonb),
    'prerequisites', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'course_id', p.ramo_id,
        'requires_course_id', p.requisito_ramo_id,
        'source', p.procedencia,
        'decision', p.decision,
        'certainty', p.certeza,
        'evidence', p.evidencias,
        'pending_reasons', p.motivos_pendientes
      ) order by p.ramo_id, p.requisito_ramo_id)
      from public.prerrequisitos_malla as p
      where p.usuario_uid = v_uid and p.malla_id = v_malla.id
    ), '[]'::jsonb),
    'certifications', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', c.id,
        'name', c.nombre,
        'source', c.procedencia,
        'decision', c.decision,
        'evidence', c.evidencias,
        'pending_reasons', c.motivos_pendientes,
        'memberships', coalesce((
          select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'course_id', cm.ramo_id,
            'source', cm.procedencia,
            'decision', cm.decision,
            'basis', cm.fundamento,
            'evidence', cm.evidencias,
            'pending_reasons', cm.motivos_pendientes
          ) order by cm.ramo_id)
          from public.membresias_certificacion_malla as cm
          where cm.usuario_uid = c.usuario_uid and cm.malla_id = c.malla_id
            and cm.certificacion_id = c.id
        ), '[]'::jsonb)
      ) order by c.id)
      from public.certificaciones_malla as c
      where c.usuario_uid = v_uid and c.malla_id = v_malla.id
    ), '[]'::jsonb),
    'academic_requirements', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', a.id,
        'type', a.tipo,
        'target_course_id', a.ramo_objetivo_id,
        'target_label', a.etiqueta_objetivo,
        'description', a.descripcion,
        'minimum_level', a.nivel_minimo,
        'source', a.procedencia,
        'decision', a.decision,
        'evidence', a.evidencias,
        'pending_reasons', a.motivos_pendientes
      ) order by a.id)
      from public.requisitos_academicos_malla as a
      where a.usuario_uid = v_uid and a.malla_id = v_malla.id
    ), '[]'::jsonb),
    'pending_items', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', pending.id,
        'entity_type', pending.entidad_tipo,
        'entity_key', pending.entidad_clave,
        'reasons', pending.motivos,
        'evidence', pending.evidencias,
        'status', pending.estado,
        'resolution', pending.resolucion
      ) order by pending.id)
      from public.pendientes_revision_malla as pending
      where pending.usuario_uid = v_uid and pending.malla_id = v_malla.id
    ), '[]'::jsonb)
  );
end;
$$;

alter table public.prerrequisitos_malla enable row level security;
alter table public.certificaciones_malla enable row level security;
alter table public.membresias_certificacion_malla enable row level security;
alter table public.requisitos_academicos_malla enable row level security;
alter table public.pendientes_revision_malla enable row level security;

create policy prerrequisitos_malla_lectura on public.prerrequisitos_malla
  for select to authenticated using (
    (select public.is_educflow_firebase_user()) is true
    and usuario_uid = (select public.current_firebase_uid()));
create policy certificaciones_malla_lectura on public.certificaciones_malla
  for select to authenticated using (
    (select public.is_educflow_firebase_user()) is true
    and usuario_uid = (select public.current_firebase_uid()));
create policy membresias_certificacion_malla_lectura
  on public.membresias_certificacion_malla for select to authenticated using (
    (select public.is_educflow_firebase_user()) is true
    and usuario_uid = (select public.current_firebase_uid()));
create policy requisitos_academicos_malla_lectura
  on public.requisitos_academicos_malla for select to authenticated using (
    (select public.is_educflow_firebase_user()) is true
    and usuario_uid = (select public.current_firebase_uid()));
create policy pendientes_revision_malla_lectura
  on public.pendientes_revision_malla for select to authenticated using (
    (select public.is_educflow_firebase_user()) is true
    and usuario_uid = (select public.current_firebase_uid()));

revoke all on public.prerrequisitos_malla, public.certificaciones_malla,
  public.membresias_certificacion_malla, public.requisitos_academicos_malla,
  public.pendientes_revision_malla from public, anon, authenticated;
grant select on public.prerrequisitos_malla, public.certificaciones_malla,
  public.membresias_certificacion_malla, public.requisitos_academicos_malla,
  public.pendientes_revision_malla to authenticated;

create or replace view public.prerrequisitos_malla_vigentes
with (security_invoker = true) as
select * from public.prerrequisitos_malla where decision = 'accepted';
create or replace view public.membresias_certificacion_malla_vigentes
with (security_invoker = true) as
select membership.*
from public.membresias_certificacion_malla as membership
join public.certificaciones_malla as certification
  using (usuario_uid, malla_id)
where membership.certificacion_id = certification.id
  and membership.decision = 'accepted'
  and certification.decision = 'accepted';

revoke all on public.prerrequisitos_malla_vigentes,
  public.membresias_certificacion_malla_vigentes from public, anon;
grant select on public.prerrequisitos_malla_vigentes,
  public.membresias_certificacion_malla_vigentes to authenticated;

revoke all on function public.malla_jsonb_text_array_valido(
  jsonb, integer, integer, integer) from public, anon, authenticated;
revoke all on function public.sincronizar_resumen_malla_vision()
  from public, anon, authenticated;
revoke all on function public.confirmar_malla_multimodal(text, text, jsonb)
  from public, anon;
grant execute on function public.confirmar_malla_multimodal(text, text, jsonb)
  to authenticated;
revoke all on function public.obtener_malla_multimodal(text)
  from public, anon;
grant execute on function public.obtener_malla_multimodal(text)
  to authenticated;

commit;
