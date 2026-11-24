-- Edición posterior de datos académicos multimodales.
-- Aplicar después de 202611130001_gestion_malla_multimodal.sql.
-- Migración aditiva: no reemplaza RPC ni concede escritura directa.
begin;

alter table public.mallas_curriculares enable row level security;
alter table public.ramos_malla enable row level security;
alter table public.requisitos_academicos_malla enable row level security;
alter table public.pendientes_revision_malla enable row level security;

create or replace function public.confirmar_ramo_sin_codigo_malla(
  p_expected_uid text,
  p_malla_id uuid,
  p_ramo_id text
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid text;
  v_course public.ramos_malla%rowtype;
  v_remaining jsonb;
  v_review_state text;
begin
  if public.is_educflow_firebase_user() is distinct from true then
    raise exception using errcode = '42501',
      message = 'usuario_firebase_no_valido';
  end if;
  v_uid := public.current_firebase_uid();
  if v_uid is null or v_uid is distinct from p_expected_uid then
    raise exception using errcode = '42501', message = 'uid_firebase_no_valido';
  end if;
  if p_malla_id is null
    or p_ramo_id is null
    or p_ramo_id !~ '^[A-Za-z0-9_-]{1,64}$' then
    raise exception using errcode = '22023', message = 'ramo_id_invalido';
  end if;

  perform 1 from public.mallas_curriculares as m
    where m.usuario_uid = v_uid and m.id = p_malla_id
    for update of m;
  if not found then
    raise exception using errcode = 'P0002', message = 'malla_no_encontrada';
  end if;

  select course.* into v_course
    from public.ramos_malla as course
    where course.usuario_uid = v_uid
      and course.malla_id = p_malla_id
      and course.id = p_ramo_id
    for update of course;
  if not found then
    raise exception using errcode = 'P0002', message = 'ramo_malla_no_encontrado';
  end if;
  if v_course.codigo is not null
    or not v_course.motivos_revision @> '["code_missing"]'::jsonb then
    raise exception using errcode = '22023',
      message = 'ramo_sin_codigo_no_confirmable';
  end if;

  select coalesce(pg_catalog.jsonb_agg(reason.value order by reason.ord), '[]'::jsonb)
    into v_remaining
    from pg_catalog.jsonb_array_elements(v_course.motivos_revision)
      with ordinality as reason(value, ord)
    where reason.value #>> '{}' <> 'code_missing';

  update public.ramos_malla
    set motivos_revision = v_remaining,
        requiere_revision = pg_catalog.jsonb_array_length(v_remaining) > 0,
        estado_revision = case
          when pg_catalog.jsonb_array_length(v_remaining) = 0 then 'manual'
          when v_remaining ?| array[
            'credits_missing', 'semester_uncertain'
          ] then 'incomplete'
          else 'pending'
        end
    where usuario_uid = v_uid and malla_id = p_malla_id and id = p_ramo_id;

  update public.pendientes_revision_malla as pending
    set motivos = coalesce((
          select pg_catalog.jsonb_agg(reason.value order by reason.ord)
          from pg_catalog.jsonb_array_elements(pending.motivos)
            with ordinality as reason(value, ord)
          where reason.value #>> '{}' <> 'code_missing'
        ), '[]'::jsonb)
    where pending.usuario_uid = v_uid
      and pending.malla_id = p_malla_id
      and pending.entidad_tipo = 'course'
      and pending.entidad_clave = p_ramo_id
      and pending.estado = 'pending'
      and pending.motivos @> '["code_missing"]'::jsonb;

  update public.pendientes_revision_malla as pending
    set estado = 'resolved', resolucion = 'verified:code_absent_in_source'
    where pending.usuario_uid = v_uid
      and pending.malla_id = p_malla_id
      and pending.entidad_tipo = 'course'
      and pending.entidad_clave = p_ramo_id
      and pending.estado = 'pending'
      and pg_catalog.jsonb_array_length(pending.motivos) = 0;

  v_review_state := case when
    exists (
      select 1 from public.ramos_malla as r
      where r.usuario_uid = v_uid and r.malla_id = p_malla_id
        and (r.requiere_revision
          or r.estado_revision in ('suggested', 'pending', 'incomplete')))
    or exists (
      select 1 from public.prerrequisitos_malla as p
      where p.usuario_uid = v_uid and p.malla_id = p_malla_id
        and p.decision in ('suggested', 'pending'))
    or exists (
      select 1 from public.certificaciones_malla as c
      where c.usuario_uid = v_uid and c.malla_id = p_malla_id
        and c.decision in ('suggested', 'pending'))
    or exists (
      select 1 from public.membresias_certificacion_malla as membership
      where membership.usuario_uid = v_uid
        and membership.malla_id = p_malla_id
        and membership.decision in ('suggested', 'pending'))
    or exists (
      select 1 from public.requisitos_academicos_malla as requirement
      where requirement.usuario_uid = v_uid
        and requirement.malla_id = p_malla_id
        and requirement.decision in ('suggested', 'pending'))
    or exists (
      select 1 from public.pendientes_revision_malla as pending
      where pending.usuario_uid = v_uid and pending.malla_id = p_malla_id
        and pending.estado = 'pending')
    then 'pending' else 'confirmed' end;
  update public.mallas_curriculares
    set estado_revision = v_review_state
    where usuario_uid = v_uid and id = p_malla_id;

  return pg_catalog.jsonb_build_object(
    'malla_id', p_malla_id,
    'ramo_id', p_ramo_id,
    'review_state', v_review_state
  );
end;
$$;

create or replace function public.editar_requisito_academico_malla(
  p_expected_uid text,
  p_malla_id uuid,
  p_requisito_id text,
  p_descripcion text,
  p_nivel_minimo integer
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid text;
  v_requirement public.requisitos_academicos_malla%rowtype;
  v_description text;
  v_reasons jsonb;
  v_pending_id text;
begin
  if public.is_educflow_firebase_user() is distinct from true then
    raise exception using errcode = '42501',
      message = 'usuario_firebase_no_valido';
  end if;
  v_uid := public.current_firebase_uid();
  if v_uid is null or v_uid is distinct from p_expected_uid then
    raise exception using errcode = '42501', message = 'uid_firebase_no_valido';
  end if;
  v_description := pg_catalog.btrim(p_descripcion);
  if p_malla_id is null
    or p_requisito_id is null
    or p_requisito_id !~ '^[A-Za-z0-9_-]{1,64}$'
    or v_description is null
    or pg_catalog.length(v_description) not between 1 and 1000
    or v_description ~ '[[:cntrl:]]'
    or p_nivel_minimo is not null and p_nivel_minimo not between 1 and 30 then
    raise exception using errcode = '22023',
      message = 'edicion_requisito_invalida';
  end if;

  perform 1 from public.mallas_curriculares as m
    where m.usuario_uid = v_uid and m.id = p_malla_id
    for update of m;
  if not found then
    raise exception using errcode = 'P0002', message = 'malla_no_encontrada';
  end if;

  select requirement.* into v_requirement
    from public.requisitos_academicos_malla as requirement
    where requirement.usuario_uid = v_uid
      and requirement.malla_id = p_malla_id
      and requirement.id = p_requisito_id
    for update of requirement;
  if not found then
    raise exception using errcode = 'P0002', message = 'requisito_no_encontrado';
  end if;

  select coalesce(pg_catalog.jsonb_agg(reason.value order by reason.ord), '[]'::jsonb)
    into v_reasons
    from pg_catalog.jsonb_array_elements(v_requirement.motivos_pendientes)
      with ordinality as reason(value, ord)
    where reason.value #>> '{}' not in (
      'requirement_level_conflict', 'minimum_level_uncertain',
      'manual_confirmation_required'
    );
  if pg_catalog.jsonb_array_length(v_reasons) >= 20 then
    raise exception using errcode = '22023',
      message = 'requisito_demasiados_motivos_pendientes';
  end if;
  v_reasons := v_reasons || '["manual_confirmation_required"]'::jsonb;

  update public.requisitos_academicos_malla
    set descripcion = v_description,
        nivel_minimo = p_nivel_minimo,
        decision = 'pending',
        motivos_pendientes = v_reasons
    where usuario_uid = v_uid
      and malla_id = p_malla_id
      and id = p_requisito_id;

  select pending.id into v_pending_id
    from public.pendientes_revision_malla as pending
    where pending.usuario_uid = v_uid
      and pending.malla_id = p_malla_id
      and pending.entidad_tipo = 'requirement'
      and pending.entidad_clave = p_requisito_id
    order by case when pending.estado = 'pending' then 0 else 1 end, pending.id
    limit 1
    for update of pending;

  if v_pending_id is null then
    v_pending_id := 'reqedit_' || pg_catalog.substring(
      pg_catalog.md5(p_malla_id::text || ':' || p_requisito_id), 1, 32
    );
    insert into public.pendientes_revision_malla (
      usuario_uid, malla_id, id, entidad_tipo, entidad_clave,
      motivos, evidencias, estado, resolucion
    ) values (
      v_uid, p_malla_id, v_pending_id, 'requirement', p_requisito_id,
      v_reasons, v_requirement.evidencias, 'pending', null
    );
  else
    update public.pendientes_revision_malla
      set motivos = v_reasons,
          evidencias = v_requirement.evidencias,
          estado = 'pending',
          resolucion = null
      where usuario_uid = v_uid
        and malla_id = p_malla_id
        and id = v_pending_id;
  end if;

  update public.mallas_curriculares
    set estado_revision = 'pending'
    where usuario_uid = v_uid and id = p_malla_id;

  return pg_catalog.jsonb_build_object(
    'malla_id', p_malla_id,
    'requisito_id', p_requisito_id,
    'review_state', 'pending'
  );
end;
$$;

revoke all on function public.confirmar_ramo_sin_codigo_malla(
  text, uuid, text) from public, anon, authenticated;
grant execute on function public.confirmar_ramo_sin_codigo_malla(
  text, uuid, text) to authenticated;
revoke all on function public.editar_requisito_academico_malla(
  text, uuid, text, text, integer) from public, anon, authenticated;
grant execute on function public.editar_requisito_academico_malla(
  text, uuid, text, text, integer) to authenticated;

-- Se mantienen las tablas como solo lectura para los clientes.
revoke insert, update, delete on public.mallas_curriculares,
  public.ramos_malla, public.requisitos_academicos_malla,
  public.pendientes_revision_malla from anon, authenticated;

commit;
