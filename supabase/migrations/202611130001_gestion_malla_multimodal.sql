-- Gestión posterior de una malla multimodal confirmada.
-- Aplicar después de 202611110001_malla_multimodal.sql.
-- No concede escritura directa: todas las mutaciones pasan por RPC autenticadas.
begin;

alter table public.prerrequisitos_malla
  add column if not exists corregida_manualmente boolean not null default false;

create or replace function public.gestionar_revision_malla_multimodal(
  p_expected_uid text,
  p_malla_id uuid,
  p_cambios jsonb
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid text;
  v_item jsonb;
  v_prerequisite public.prerrequisitos_malla%rowtype;
  v_membership public.membresias_certificacion_malla%rowtype;
  v_certification public.certificaciones_malla%rowtype;
  v_requirement public.requisitos_academicos_malla%rowtype;
  v_pending public.pendientes_revision_malla%rowtype;
  v_course_id text;
  v_requires_course_id text;
  v_result_course_id text;
  v_result_requires_course_id text;
  v_certification_id text;
  v_entity_key text;
  v_decision text;
  v_type text;
  v_status text;
  v_resolution text;
  v_review_state text;
  v_change_count integer;
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
    or pg_catalog.jsonb_typeof(p_cambios) is distinct from 'object'
    or pg_catalog.octet_length(p_cambios::text) > 1000000
    or not (p_cambios ?& array[
      'prerequisites', 'certifications', 'memberships',
      'academic_requirements', 'pending_items'
    ])
    or exists (
      select 1 from pg_catalog.jsonb_object_keys(p_cambios) as field(name)
      where field.name not in (
        'prerequisites', 'certifications', 'memberships',
        'academic_requirements', 'pending_items'
      )
    ) then
    raise exception using errcode = '22023',
      message = 'cambios_malla_formato_invalido';
  end if;
  if pg_catalog.jsonb_typeof(p_cambios -> 'prerequisites') is distinct from 'array'
    or pg_catalog.jsonb_typeof(p_cambios -> 'certifications') is distinct from 'array'
    or pg_catalog.jsonb_typeof(p_cambios -> 'memberships') is distinct from 'array'
    or pg_catalog.jsonb_typeof(p_cambios -> 'academic_requirements') is distinct from 'array'
    or pg_catalog.jsonb_typeof(p_cambios -> 'pending_items') is distinct from 'array'
    or pg_catalog.jsonb_array_length(p_cambios -> 'prerequisites') > 2000
    or pg_catalog.jsonb_array_length(p_cambios -> 'certifications') > 200
    or pg_catalog.jsonb_array_length(p_cambios -> 'memberships') > 5000
    or pg_catalog.jsonb_array_length(p_cambios -> 'academic_requirements') > 500
    or pg_catalog.jsonb_array_length(p_cambios -> 'pending_items') > 2000 then
    raise exception using errcode = '22023',
      message = 'cambios_malla_coleccion_invalida';
  end if;
  v_change_count := pg_catalog.jsonb_array_length(p_cambios -> 'prerequisites')
    + pg_catalog.jsonb_array_length(p_cambios -> 'certifications')
    + pg_catalog.jsonb_array_length(p_cambios -> 'memberships')
    + pg_catalog.jsonb_array_length(p_cambios -> 'academic_requirements')
    + pg_catalog.jsonb_array_length(p_cambios -> 'pending_items');
  if v_change_count = 0 then
    raise exception using errcode = '22023', message = 'cambios_malla_vacios';
  end if;

  -- Un único bloqueo del padre serializa todas las decisiones de la malla.
  perform 1 from public.mallas_curriculares as m
    where m.usuario_uid = v_uid and m.id = p_malla_id
    for update of m;
  if not found then
    raise exception using errcode = 'P0002', message = 'malla_no_encontrada';
  end if;

  if (select count(*) from pg_catalog.jsonb_array_elements(
        p_cambios -> 'certifications'))
      <> (select count(distinct value ->> 'id')
          from pg_catalog.jsonb_array_elements(
            p_cambios -> 'certifications'))
    or (select count(*) from pg_catalog.jsonb_array_elements(
          p_cambios -> 'academic_requirements'))
      <> (select count(distinct value ->> 'id')
          from pg_catalog.jsonb_array_elements(
            p_cambios -> 'academic_requirements'))
    or (select count(*) from pg_catalog.jsonb_array_elements(
          p_cambios -> 'pending_items'))
      <> (select count(distinct value ->> 'id')
          from pg_catalog.jsonb_array_elements(
            p_cambios -> 'pending_items'))
    or (select count(*) from pg_catalog.jsonb_array_elements(
          p_cambios -> 'memberships'))
      <> (select count(distinct
            (value ->> 'certification_id') || ':' || (value ->> 'course_id'))
          from pg_catalog.jsonb_array_elements(
            p_cambios -> 'memberships'))
    or (select count(*) from pg_catalog.jsonb_array_elements(
          p_cambios -> 'prerequisites'))
      <> (select count(distinct
            (value ->> 'course_id') || '>' ||
            (value ->> 'requires_course_id'))
          from pg_catalog.jsonb_array_elements(
            p_cambios -> 'prerequisites')) then
    raise exception using errcode = '22023',
      message = 'cambios_malla_duplicados';
  end if;

  -- La certificación se procesa antes de sus membresías para que una
  -- membresía solo pueda aceptarse dentro de una certificación aceptada.
  for v_item in
    select value from pg_catalog.jsonb_array_elements(
      p_cambios -> 'certifications')
  loop
    if pg_catalog.jsonb_typeof(v_item) is distinct from 'object'
      or not (v_item ?& array['id', 'decision'])
      or exists (
        select 1 from pg_catalog.jsonb_object_keys(v_item) as field(name)
        where field.name not in ('id', 'decision')
      )
      or pg_catalog.jsonb_typeof(v_item -> 'id') is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_item -> 'decision') is distinct from 'string'
      or v_item ->> 'id' !~ '^[A-Za-z0-9_-]{1,64}$'
      or v_item ->> 'decision' not in
        ('suggested', 'pending', 'accepted', 'rejected') then
      raise exception using errcode = '22023',
        message = 'cambio_certificacion_invalido';
    end if;
    v_certification_id := v_item ->> 'id';
    v_decision := v_item ->> 'decision';
    select c.* into v_certification
      from public.certificaciones_malla as c
      where c.usuario_uid = v_uid and c.malla_id = p_malla_id
        and c.id = v_certification_id
      for update of c;
    if not found then
      raise exception using errcode = 'P0002',
        message = 'certificacion_no_encontrada';
    end if;
    if v_decision = 'pending'
      and pg_catalog.jsonb_array_length(
        v_certification.motivos_pendientes) = 0 then
      raise exception using errcode = '22023',
        message = 'certificacion_pendiente_sin_motivo';
    end if;
    update public.certificaciones_malla
      set decision = v_decision,
          motivos_pendientes = case
            when v_decision in ('accepted', 'rejected') then '[]'::jsonb
            else motivos_pendientes
          end
      where usuario_uid = v_uid and malla_id = p_malla_id
        and id = v_certification_id;
    if v_decision = 'rejected' then
      update public.pendientes_revision_malla as pending_item
        set estado = 'resolved',
            resolucion = 'parent_certification:rejected'
        where pending_item.usuario_uid = v_uid
          and pending_item.malla_id = p_malla_id
          and pending_item.entidad_tipo = 'membership'
          and pg_catalog.split_part(pending_item.entidad_clave, ':', 1) =
            v_certification_id
          and exists (
            select 1 from public.membresias_certificacion_malla as membership
            where membership.usuario_uid = v_uid
              and membership.malla_id = p_malla_id
              and membership.certificacion_id = v_certification_id
              and membership.ramo_id = pg_catalog.split_part(
                pending_item.entidad_clave, ':', 2)
              and membership.decision in
                ('accepted', 'suggested', 'pending'));
      update public.membresias_certificacion_malla
        set decision = 'rejected', motivos_pendientes = '[]'::jsonb
        where usuario_uid = v_uid and malla_id = p_malla_id
          and certificacion_id = v_certification_id
          and decision in ('accepted', 'suggested', 'pending');
      update public.pendientes_revision_malla as pending_item
        set estado = 'resolved',
            resolucion = 'decision:rejected'
        where pending_item.usuario_uid = v_uid
          and pending_item.malla_id = p_malla_id
          and pending_item.entidad_tipo = 'membership'
          and pg_catalog.split_part(pending_item.entidad_clave, ':', 1) =
            v_certification_id
          and pending_item.estado = 'pending';
    elsif v_decision in ('suggested', 'pending') then
      update public.pendientes_revision_malla as pending_item
        set estado = 'pending', resolucion = null
        where pending_item.usuario_uid = v_uid
          and pending_item.malla_id = p_malla_id
          and pending_item.entidad_tipo = 'membership'
          and pg_catalog.split_part(pending_item.entidad_clave, ':', 1) =
            v_certification_id
          and exists (
            select 1 from public.membresias_certificacion_malla as membership
            where membership.usuario_uid = v_uid
              and membership.malla_id = p_malla_id
              and membership.certificacion_id = v_certification_id
              and membership.ramo_id = pg_catalog.split_part(
                pending_item.entidad_clave, ':', 2)
              and membership.decision in
                ('accepted', 'suggested', 'pending'));
      update public.membresias_certificacion_malla
        set decision = 'pending',
            motivos_pendientes = case
              when motivos_pendientes @> '["parent_certification_pending"]'::jsonb
                then motivos_pendientes
              else motivos_pendientes || '["parent_certification_pending"]'::jsonb
            end
        where usuario_uid = v_uid and malla_id = p_malla_id
          and certificacion_id = v_certification_id
          and decision = 'accepted';
      update public.pendientes_revision_malla as pending_item
        set estado = 'resolved',
            resolucion = 'decision:rejected'
        where pending_item.usuario_uid = v_uid
          and pending_item.malla_id = p_malla_id
          and pending_item.entidad_tipo = 'membership'
          and pg_catalog.split_part(pending_item.entidad_clave, ':', 1) =
            v_certification_id
          and pending_item.estado = 'pending'
          and exists (
            select 1 from public.membresias_certificacion_malla as membership
            where membership.usuario_uid = v_uid
              and membership.malla_id = p_malla_id
              and membership.certificacion_id = v_certification_id
              and membership.ramo_id = pg_catalog.split_part(
                pending_item.entidad_clave, ':', 2)
              and membership.decision = 'rejected');
    end if;
    update public.pendientes_revision_malla
      set estado = case when v_decision in ('accepted', 'rejected')
            then 'resolved' else 'pending' end,
          resolucion = case when v_decision in ('accepted', 'rejected')
            then 'decision:' || v_decision else null end
      where usuario_uid = v_uid and malla_id = p_malla_id
        and entidad_tipo = 'certification'
        and entidad_clave = v_certification_id;
  end loop;

  for v_item in
    select value from pg_catalog.jsonb_array_elements(
      p_cambios -> 'prerequisites')
  loop
    if pg_catalog.jsonb_typeof(v_item) is distinct from 'object'
      or not (v_item ?& array[
        'course_id', 'requires_course_id', 'result_course_id',
        'result_requires_course_id', 'decision'
      ])
      or exists (
        select 1 from pg_catalog.jsonb_object_keys(v_item) as field(name)
        where field.name not in (
          'course_id', 'requires_course_id', 'result_course_id',
          'result_requires_course_id', 'decision'
        )
      )
      or pg_catalog.jsonb_typeof(v_item -> 'course_id') is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_item -> 'requires_course_id') is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_item -> 'result_course_id') is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_item -> 'result_requires_course_id') is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_item -> 'decision') is distinct from 'string'
      or v_item ->> 'course_id' !~ '^[A-Za-z0-9_-]{1,64}$'
      or v_item ->> 'requires_course_id' !~ '^[A-Za-z0-9_-]{1,64}$'
      or v_item ->> 'result_course_id' !~ '^[A-Za-z0-9_-]{1,64}$'
      or v_item ->> 'result_requires_course_id' !~ '^[A-Za-z0-9_-]{1,64}$'
      or v_item ->> 'result_course_id' =
        v_item ->> 'result_requires_course_id'
      or v_item ->> 'decision' not in
        ('suggested', 'pending', 'accepted', 'rejected') then
      raise exception using errcode = '22023',
        message = 'cambio_prerrequisito_invalido';
    end if;
    v_course_id := v_item ->> 'course_id';
    v_requires_course_id := v_item ->> 'requires_course_id';
    v_result_course_id := v_item ->> 'result_course_id';
    v_result_requires_course_id :=
      v_item ->> 'result_requires_course_id';
    v_decision := v_item ->> 'decision';
    select p.* into v_prerequisite
      from public.prerrequisitos_malla as p
      where p.usuario_uid = v_uid and p.malla_id = p_malla_id
        and p.ramo_id = v_course_id
        and p.requisito_ramo_id = v_requires_course_id
      for update of p;
    if not found then
      raise exception using errcode = 'P0002',
        message = 'prerrequisito_no_encontrado';
    end if;
    if not exists (
        select 1 from public.ramos_malla as r
        where r.usuario_uid = v_uid and r.malla_id = p_malla_id
          and r.id = v_result_course_id)
      or not exists (
        select 1 from public.ramos_malla as r
        where r.usuario_uid = v_uid and r.malla_id = p_malla_id
          and r.id = v_result_requires_course_id) then
      raise exception using errcode = '22023',
        message = 'prerrequisito_referencia_invalida';
    end if;
    if exists (
      select 1 from public.prerrequisitos_malla as p
      where p.usuario_uid = v_uid and p.malla_id = p_malla_id
        and p.ramo_id = v_result_course_id
        and p.requisito_ramo_id = v_result_requires_course_id
        and (p.ramo_id, p.requisito_ramo_id) is distinct from
          (v_course_id, v_requires_course_id)
    ) then
      raise exception using errcode = '23505',
        message = 'prerrequisito_duplicado';
    end if;
    if v_decision = 'pending'
      and pg_catalog.jsonb_array_length(
        v_prerequisite.motivos_pendientes) = 0 then
      raise exception using errcode = '22023',
        message = 'prerrequisito_pendiente_sin_motivo';
    end if;
    update public.prerrequisitos_malla
      set ramo_id = v_result_course_id,
          requisito_ramo_id = v_result_requires_course_id,
          decision = v_decision,
          certeza = case v_decision
            when 'accepted' then 'confirmed'
            when 'rejected' then 'unknown'
            else 'uncertain'
          end,
          corregida_manualmente = corregida_manualmente
            or ((ramo_id, requisito_ramo_id) is distinct from
              (v_result_course_id, v_result_requires_course_id)),
          motivos_pendientes = case
            when v_decision in ('accepted', 'rejected') then '[]'::jsonb
            else motivos_pendientes
          end
      where usuario_uid = v_uid and malla_id = p_malla_id
        and ramo_id = v_course_id
        and requisito_ramo_id = v_requires_course_id;
    v_entity_key := v_result_course_id || '>' ||
      v_result_requires_course_id;
    update public.pendientes_revision_malla
      set entidad_clave = v_entity_key,
          estado = case when v_decision in ('accepted', 'rejected')
            then 'resolved' else 'pending' end,
          resolucion = case when v_decision in ('accepted', 'rejected')
            then 'decision:' || v_decision else null end
      where usuario_uid = v_uid and malla_id = p_malla_id
        and entidad_tipo = 'prerequisite'
        and entidad_clave = v_course_id || '>' || v_requires_course_id;
  end loop;

  for v_item in
    select value from pg_catalog.jsonb_array_elements(
      p_cambios -> 'memberships')
  loop
    if pg_catalog.jsonb_typeof(v_item) is distinct from 'object'
      or not (v_item ?& array['certification_id', 'course_id', 'decision'])
      or exists (
        select 1 from pg_catalog.jsonb_object_keys(v_item) as field(name)
        where field.name not in ('certification_id', 'course_id', 'decision')
      )
      or pg_catalog.jsonb_typeof(v_item -> 'certification_id') is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_item -> 'course_id') is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_item -> 'decision') is distinct from 'string'
      or v_item ->> 'certification_id' !~ '^[A-Za-z0-9_-]{1,64}$'
      or v_item ->> 'course_id' !~ '^[A-Za-z0-9_-]{1,64}$'
      or v_item ->> 'decision' not in
        ('suggested', 'pending', 'accepted', 'rejected') then
      raise exception using errcode = '22023',
        message = 'cambio_membresia_invalido';
    end if;
    v_certification_id := v_item ->> 'certification_id';
    v_course_id := v_item ->> 'course_id';
    v_decision := v_item ->> 'decision';
    select membership.* into v_membership
      from public.membresias_certificacion_malla as membership
      where membership.usuario_uid = v_uid
        and membership.malla_id = p_malla_id
        and membership.certificacion_id = v_certification_id
        and membership.ramo_id = v_course_id
      for update of membership;
    if not found then
      raise exception using errcode = 'P0002',
        message = 'membresia_no_encontrada';
    end if;
    if v_decision = 'accepted' and not exists (
      select 1 from public.certificaciones_malla as c
      where c.usuario_uid = v_uid and c.malla_id = p_malla_id
        and c.id = v_certification_id and c.decision = 'accepted'
    ) then
      raise exception using errcode = '22023',
        message = 'membresia_sin_certificacion_aceptada';
    end if;
    if v_decision = 'pending'
      and pg_catalog.jsonb_array_length(
        v_membership.motivos_pendientes) = 0 then
      raise exception using errcode = '22023',
        message = 'membresia_pendiente_sin_motivo';
    end if;
    update public.membresias_certificacion_malla
      set decision = v_decision,
          motivos_pendientes = case
            when v_decision in ('accepted', 'rejected') then '[]'::jsonb
            else motivos_pendientes
          end
      where usuario_uid = v_uid and malla_id = p_malla_id
        and certificacion_id = v_certification_id
        and ramo_id = v_course_id;
    update public.pendientes_revision_malla
      set estado = case when v_decision in ('accepted', 'rejected')
            then 'resolved' else 'pending' end,
          resolucion = case when v_decision in ('accepted', 'rejected')
            then 'decision:' || v_decision else null end
      where usuario_uid = v_uid and malla_id = p_malla_id
        and entidad_tipo = 'membership'
        and entidad_clave = v_certification_id || ':' || v_course_id;
  end loop;

  for v_item in
    select value from pg_catalog.jsonb_array_elements(
      p_cambios -> 'academic_requirements')
  loop
    if pg_catalog.jsonb_typeof(v_item) is distinct from 'object'
      or not (v_item ?& array['id', 'type', 'decision'])
      or exists (
        select 1 from pg_catalog.jsonb_object_keys(v_item) as field(name)
        where field.name not in ('id', 'type', 'decision')
      )
      or pg_catalog.jsonb_typeof(v_item -> 'id') is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_item -> 'type') is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_item -> 'decision') is distinct from 'string'
      or v_item ->> 'id' !~ '^[A-Za-z0-9_-]{1,64}$'
      or pg_catalog.length(pg_catalog.btrim(v_item ->> 'type'))
        not between 1 and 64
      or (v_item ->> 'type') ~ '[[:cntrl:]]'
      or v_item ->> 'decision' not in
        ('suggested', 'pending', 'accepted', 'rejected')
      or v_item ->> 'decision' = 'accepted'
        and pg_catalog.lower(pg_catalog.btrim(v_item ->> 'type')) =
          'unknown' then
      raise exception using errcode = '22023',
        message = 'cambio_requisito_invalido';
    end if;
    v_decision := v_item ->> 'decision';
    v_type := pg_catalog.btrim(v_item ->> 'type');
    select requirement.* into v_requirement
      from public.requisitos_academicos_malla as requirement
      where requirement.usuario_uid = v_uid
        and requirement.malla_id = p_malla_id
        and requirement.id = v_item ->> 'id'
      for update of requirement;
    if not found then
      raise exception using errcode = 'P0002',
        message = 'requisito_no_encontrado';
    end if;
    if v_decision = 'pending'
      and pg_catalog.jsonb_array_length(
        v_requirement.motivos_pendientes) = 0 then
      raise exception using errcode = '22023',
        message = 'requisito_pendiente_sin_motivo';
    end if;
    update public.requisitos_academicos_malla
      set tipo = v_type,
          decision = v_decision,
          motivos_pendientes = case
            when v_decision in ('accepted', 'rejected') then '[]'::jsonb
            else motivos_pendientes
          end
      where usuario_uid = v_uid and malla_id = p_malla_id
        and id = v_item ->> 'id';
    update public.pendientes_revision_malla
      set estado = case when v_decision in ('accepted', 'rejected')
            then 'resolved' else 'pending' end,
          resolucion = case when v_decision in ('accepted', 'rejected')
            then 'decision:' || v_decision else null end
      where usuario_uid = v_uid and malla_id = p_malla_id
        and entidad_tipo = 'requirement'
        and entidad_clave = v_item ->> 'id';
  end loop;

  for v_item in
    select value from pg_catalog.jsonb_array_elements(
      p_cambios -> 'pending_items')
  loop
    if pg_catalog.jsonb_typeof(v_item) is distinct from 'object'
      or not (v_item ?& array['id', 'status', 'resolution'])
      or exists (
        select 1 from pg_catalog.jsonb_object_keys(v_item) as field(name)
        where field.name not in ('id', 'status', 'resolution')
      )
      or pg_catalog.jsonb_typeof(v_item -> 'id') is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_item -> 'status') is distinct from 'string'
      or v_item ->> 'id' !~ '^[A-Za-z0-9_-]{1,64}$'
      or v_item ->> 'status' not in ('pending', 'resolved', 'dismissed')
      or pg_catalog.jsonb_typeof(v_item -> 'resolution') not in
        ('null', 'string')
      or pg_catalog.length(coalesce(v_item ->> 'resolution', '')) > 500
      or coalesce(v_item ->> 'resolution', '') ~ '[[:cntrl:]]'
      or v_item ->> 'status' = 'pending'
        and (v_item ->> 'resolution') is not null
      or v_item ->> 'status' in ('resolved', 'dismissed')
        and pg_catalog.length(pg_catalog.btrim(
          coalesce(v_item ->> 'resolution', ''))) = 0 then
      raise exception using errcode = '22023',
        message = 'cambio_pendiente_invalido';
    end if;
    v_status := v_item ->> 'status';
    v_resolution := nullif(pg_catalog.btrim(v_item ->> 'resolution'), '');
    select pending.* into v_pending
      from public.pendientes_revision_malla as pending
      where pending.usuario_uid = v_uid and pending.malla_id = p_malla_id
        and pending.id = v_item ->> 'id'
      for update of pending;
    if not found then
      raise exception using errcode = 'P0002',
        message = 'pendiente_no_encontrado';
    end if;
    if v_pending.entidad_tipo = 'course'
      and v_status in ('resolved', 'dismissed')
      and (
        not exists (
          select 1 from public.ramos_malla as course
          where course.usuario_uid = v_uid and course.malla_id = p_malla_id
            and course.id = v_pending.entidad_clave
            and course.codigo is not null
            and pg_catalog.length(pg_catalog.btrim(course.codigo)) between 1 and 64
            and course.creditos is not null
            and course.creditos between 0 and 999
            and course.semestre between 1 and 30)
        or exists (
          select 1 from public.ramos_malla as course
          join public.ramos_malla as duplicate
            on duplicate.usuario_uid = course.usuario_uid
            and duplicate.malla_id = course.malla_id
            and duplicate.id <> course.id
            and pg_catalog.upper(pg_catalog.btrim(duplicate.codigo)) =
              pg_catalog.upper(pg_catalog.btrim(course.codigo))
          where course.usuario_uid = v_uid and course.malla_id = p_malla_id
            and course.id = v_pending.entidad_clave
            and not course.codigo_duplicado_verificado)
      ) then
      raise exception using errcode = '22023',
        message = 'ramo_incompleto_o_invalido_no_resoluble';
    end if;
    if v_status in ('resolved', 'dismissed') and (
      v_pending.entidad_tipo = 'prerequisite' and not exists (
        select 1 from public.prerrequisitos_malla as p
        where p.usuario_uid = v_uid and p.malla_id = p_malla_id
          and p.ramo_id = pg_catalog.split_part(v_pending.entidad_clave, '>', 1)
          and p.requisito_ramo_id = pg_catalog.split_part(
            v_pending.entidad_clave, '>', 2)
          and p.decision in ('accepted', 'rejected'))
      or v_pending.entidad_tipo = 'certification' and not exists (
        select 1 from public.certificaciones_malla as c
        where c.usuario_uid = v_uid and c.malla_id = p_malla_id
          and c.id = v_pending.entidad_clave
          and c.decision in ('accepted', 'rejected'))
      or v_pending.entidad_tipo = 'membership' and not exists (
        select 1 from public.membresias_certificacion_malla as membership
        where membership.usuario_uid = v_uid
          and membership.malla_id = p_malla_id
          and membership.certificacion_id = pg_catalog.split_part(
            v_pending.entidad_clave, ':', 1)
          and membership.ramo_id = pg_catalog.split_part(
            v_pending.entidad_clave, ':', 2)
          and membership.decision in ('accepted', 'rejected'))
      or v_pending.entidad_tipo = 'requirement' and not exists (
        select 1 from public.requisitos_academicos_malla as requirement
        where requirement.usuario_uid = v_uid
          and requirement.malla_id = p_malla_id
          and requirement.id = v_pending.entidad_clave
          and requirement.decision in ('accepted', 'rejected'))
    ) then
      raise exception using errcode = '22023',
        message = 'pendiente_entidad_sin_decision_final';
    end if;
    update public.pendientes_revision_malla
      set estado = v_status, resolucion = v_resolution
      where usuario_uid = v_uid and malla_id = p_malla_id
        and id = v_item ->> 'id';
    if v_pending.entidad_tipo = 'course' then
      if v_status = 'pending' then
        update public.ramos_malla
          set estado_revision = 'pending', requiere_revision = true,
              motivos_revision = v_pending.motivos
          where usuario_uid = v_uid and malla_id = p_malla_id
            and id = v_pending.entidad_clave;
      elsif not exists (
          select 1 from public.pendientes_revision_malla as pending
          where pending.usuario_uid = v_uid and pending.malla_id = p_malla_id
            and pending.entidad_tipo = 'course'
            and pending.entidad_clave = v_pending.entidad_clave
            and pending.estado = 'pending'
      ) then
        update public.ramos_malla
          set estado_revision = 'manual', requiere_revision = false,
              motivos_revision = '[]'::jsonb
          where usuario_uid = v_uid and malla_id = p_malla_id
            and id = v_pending.entidad_clave;
      end if;
    end if;
  end loop;

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
    'review_state', v_review_state,
    'pending_count', (
      select count(*) from public.pendientes_revision_malla as pending
      where pending.usuario_uid = v_uid and pending.malla_id = p_malla_id
        and pending.estado = 'pending'),
    'accepted_prerequisites', (
      select count(*) from public.prerrequisitos_malla as p
      where p.usuario_uid = v_uid and p.malla_id = p_malla_id
        and p.decision = 'accepted'),
    'accepted_memberships', (
      select count(*)
      from public.membresias_certificacion_malla as membership
      join public.certificaciones_malla as certification
        using (usuario_uid, malla_id)
      where membership.usuario_uid = v_uid
        and membership.malla_id = p_malla_id
        and membership.certificacion_id = certification.id
        and membership.decision = 'accepted'
        and certification.decision = 'accepted')
  );
end;
$$;

create or replace function public.eliminar_malla_curricular_confirmada(
  p_expected_uid text,
  p_malla_id uuid
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid text;
  v_deleted_id uuid;
begin
  if public.is_educflow_firebase_user() is distinct from true then
    raise exception using errcode = '42501',
      message = 'usuario_firebase_no_valido';
  end if;
  v_uid := public.current_firebase_uid();
  if v_uid is null or v_uid is distinct from p_expected_uid then
    raise exception using errcode = '42501', message = 'uid_firebase_no_valido';
  end if;
  if p_malla_id is null then
    raise exception using errcode = '22023', message = 'malla_id_invalido';
  end if;
  perform 1 from public.mallas_curriculares as m
    where m.usuario_uid = v_uid and m.id = p_malla_id
    for update of m;
  if not found then
    raise exception using errcode = 'P0002', message = 'malla_no_encontrada';
  end if;
  delete from public.mallas_curriculares
    where usuario_uid = v_uid and id = p_malla_id
    returning id into v_deleted_id;
  if v_deleted_id is null then
    raise exception using errcode = 'P0002', message = 'malla_no_encontrada';
  end if;
  return v_deleted_id;
end;
$$;

revoke all on function public.gestionar_revision_malla_multimodal(
  text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.gestionar_revision_malla_multimodal(
  text, uuid, jsonb) to authenticated;
revoke all on function public.eliminar_malla_curricular_confirmada(
  text, uuid) from public, anon, authenticated;
grant execute on function public.eliminar_malla_curricular_confirmada(
  text, uuid) to authenticated;

-- Las tablas continúan siendo de solo lectura para clientes. SECURITY DEFINER
-- no sustituye estas revocaciones ni las políticas RLS existentes.
revoke insert, update, delete on public.mallas_curriculares,
  public.ramos_malla, public.prerrequisitos_malla,
  public.certificaciones_malla, public.membresias_certificacion_malla,
  public.requisitos_academicos_malla, public.pendientes_revision_malla
  from anon, authenticated;

commit;
