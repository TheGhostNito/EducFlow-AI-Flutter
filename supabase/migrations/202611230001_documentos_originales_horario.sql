-- Documentos originales privados de importaciones de horario.
-- PREPARADA LOCALMENTE: no ejecutar sin revisar primero en Supabase Testing.
-- Depende de 202611220001_importaciones_horario_atomicas.sql.

begin;

alter table public.importaciones_horario
  add column if not exists documento_path text,
  add column if not exists documento_nombre text,
  add column if not exists documento_mime text,
  add column if not exists documento_size integer;

alter table public.importaciones_horario
  add constraint importaciones_horario_documento_completo_check check (
    (documento_path is null and documento_nombre is null
      and documento_mime is null and documento_size is null)
    or
    (documento_path is not null and documento_nombre is not null
      and documento_mime in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp')
      and documento_size between 1 and 10485760
      and pg_catalog.length(pg_catalog.btrim(documento_nombre)) between 1 and 255
      and documento_nombre !~ '[[:cntrl:]]')
  );

create unique index if not exists importaciones_horario_documento_path_uidx
  on public.importaciones_horario(documento_path)
  where documento_path is not null;

create table if not exists public.horario_documentos_limpieza (
  usuario_uid text not null references public.usuarios(uid) on delete cascade,
  documento_path text not null,
  creada_en timestamptz not null default pg_catalog.now(),
  ultimo_error text,
  intentos integer not null default 0 check (intentos between 0 and 1000),
  primary key (usuario_uid, documento_path)
);

alter table public.horario_documentos_limpieza enable row level security;
revoke all on table public.horario_documentos_limpieza
  from public, anon, authenticated;
grant select, insert, update, delete on table public.horario_documentos_limpieza
  to service_role;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'horarios-originales', 'horarios-originales', false, 10485760,
  array['application/pdf', 'image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy horario_documento_insert_own
on storage.objects for insert to authenticated
with check (
  bucket_id = 'horarios-originales'
  and public.uid_importacion_horario_autorizado()
    = public.current_firebase_uid()
  and (storage.foldername(name))[1]
    = public.current_firebase_uid()
  and pg_catalog.array_length(storage.foldername(name), 1) = 2
);

create policy horario_documento_select_linked
on storage.objects for select to authenticated
using (
  bucket_id = 'horarios-originales'
  and public.is_educflow_firebase_user() is true
  and (storage.foldername(name))[1] = public.current_firebase_uid()
  and exists (
    select 1 from public.importaciones_horario i
    where i.usuario_uid = public.current_firebase_uid()
      and i.documento_path = name
  )
);

-- No se concede DELETE a authenticated. La eliminación física debe hacerse
-- con la API de Storage desde un proceso backend con service_role. Así no
-- depende de que el objeto siga cumpliendo una política SELECT de usuario.

create or replace function public.proteger_eliminacion_importacion_documentada()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.documento_path is not null and not exists (
    select 1
    from public.horario_documentos_limpieza as tarea
    where tarea.usuario_uid = old.usuario_uid
      and tarea.documento_path = old.documento_path
  ) then
    raise exception using
      errcode = '23514',
      message = 'documento_requiere_eliminacion_segura';
  end if;
  return old;
end;
$$;

drop trigger if exists importaciones_horario_proteger_documento
  on public.importaciones_horario;
create trigger importaciones_horario_proteger_documento
before delete on public.importaciones_horario
for each row execute function public.proteger_eliminacion_importacion_documentada();

create or replace function public.confirmar_importacion_horario_con_documento(
  p_importacion jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text := public.uid_importacion_horario_autorizado();
  v_resultado jsonb;
  v_documento jsonb := p_importacion -> 'documento_original';
  v_id text;
  v_path text;
  v_nombre text;
  v_mime text;
  v_size integer;
begin
  if v_documento is null or pg_catalog.jsonb_typeof(v_documento) <> 'object' then
    raise exception using errcode = '22023', message = 'documento_original_requerido';
  end if;
  v_path := pg_catalog.btrim(coalesce(v_documento ->> 'path', ''));
  v_nombre := pg_catalog.btrim(coalesce(v_documento ->> 'nombre', ''));
  v_mime := pg_catalog.btrim(coalesce(v_documento ->> 'mime', ''));
  v_size := (v_documento ->> 'size')::integer;
  v_resultado := public.confirmar_importacion_horario(p_importacion - 'documento_original');
  v_id := v_resultado ->> 'importacion_id';
  if pg_catalog.split_part(v_path, '/', 1) <> v_uid
      or pg_catalog.split_part(v_path, '/', 2) <> v_id
      or pg_catalog.array_length(pg_catalog.string_to_array(v_path, '/'), 1) <> 3
      or v_mime not in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp')
      or v_size not between 1 and 10485760
      or pg_catalog.length(v_nombre) not between 1 and 255
      or v_nombre ~ '[[:cntrl:]]' then
    raise exception using errcode = '22023', message = 'documento_original_no_valido';
  end if;
  update public.importaciones_horario
  set documento_path = v_path, documento_nombre = v_nombre,
      documento_mime = v_mime, documento_size = v_size
  where usuario_uid = v_uid and id = v_id
    and (documento_path is null or documento_path = v_path);
  if not found then
    raise exception using errcode = '23505', message = 'importacion_ya_tiene_documento';
  end if;
  return v_resultado;
end;
$$;

create or replace function public.asociar_documento_importacion_horario(
  p_importacion_id text, p_documento jsonb
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid text := public.uid_importacion_horario_autorizado();
  v_path text := pg_catalog.btrim(coalesce(p_documento ->> 'path', ''));
  v_nombre text := pg_catalog.btrim(coalesce(p_documento ->> 'nombre', ''));
  v_mime text := pg_catalog.btrim(coalesce(p_documento ->> 'mime', ''));
  v_size integer := (p_documento ->> 'size')::integer;
begin
  if p_importacion_id !~ '^[a-f0-9]{32}$'
      or pg_catalog.split_part(v_path, '/', 1) <> v_uid
      or pg_catalog.split_part(v_path, '/', 2) <> p_importacion_id
      or pg_catalog.array_length(pg_catalog.string_to_array(v_path, '/'), 1) <> 3
      or v_mime not in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp')
      or v_size not between 1 and 10485760
      or pg_catalog.length(v_nombre) not between 1 and 255
      or v_nombre ~ '[[:cntrl:]]' then
    raise exception using errcode = '22023', message = 'documento_original_no_valido';
  end if;
  update public.importaciones_horario
  set documento_path = v_path, documento_nombre = v_nombre,
      documento_mime = v_mime, documento_size = v_size
  where usuario_uid = v_uid and id = p_importacion_id and documento_path is null;
  if not found then
    raise exception using errcode = '23505', message = 'importacion_no_disponible_para_asociar';
  end if;
end;
$$;

create or replace function public.listar_importaciones_horario_con_documento()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_uid text := public.uid_importacion_horario_autorizado();
begin
  return coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'id', i.id, 'document_hash', i.document_hash,
    'nombre_documento', i.nombre_documento, 'anio', i.anio,
    'numero_periodo', i.numero_periodo,
    'periodo_academico_id', i.periodo_academico_id,
    'asignaturas', i.asignaturas, 'bloques', i.bloques,
    'sesiones', i.sesiones, 'creada_en', i.creada_en,
    'documento_path', i.documento_path,
    'documento_nombre', i.documento_nombre,
    'documento_mime', i.documento_mime,
    'documento_size', i.documento_size
  ) order by i.creada_en desc)
  from public.importaciones_horario i where i.usuario_uid = v_uid), '[]'::jsonb);
end;
$$;

create or replace function public.eliminar_importacion_horario_con_documento(
  p_importacion_id text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid text := public.uid_importacion_horario_autorizado();
  v_path text;
  v_resultado jsonb;
begin
  select documento_path into v_path from public.importaciones_horario
  where usuario_uid = v_uid and id = p_importacion_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'importacion_horario_no_encontrada';
  end if;
  if v_path is not null then
    insert into public.horario_documentos_limpieza(usuario_uid, documento_path)
    values (v_uid, v_path) on conflict do nothing;
  end if;
  v_resultado := public.eliminar_importacion_horario(p_importacion_id);
  return v_resultado || pg_catalog.jsonb_build_object('documento_path', v_path);
end;
$$;

create or replace function public.registrar_limpieza_documento_horario(
  p_documento_path text
)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid text := public.uid_importacion_horario_autorizado();
begin
  if pg_catalog.split_part(p_documento_path, '/', 1) <> v_uid
      or pg_catalog.split_part(p_documento_path, '/', 2) !~ '^[a-f0-9]{32}$'
      or pg_catalog.array_length(
        pg_catalog.string_to_array(p_documento_path, '/'), 1
      ) <> 3 then
    raise exception using errcode = '42501', message = 'documento_no_pertenece_al_usuario';
  end if;
  if exists (select 1 from public.importaciones_horario
      where usuario_uid = v_uid and documento_path = p_documento_path) then
    raise exception using errcode = '23514', message = 'documento_aun_asociado';
  end if;
  insert into public.horario_documentos_limpieza(usuario_uid, documento_path)
  values (v_uid, p_documento_path) on conflict do nothing;
end;
$$;

create or replace function public.confirmar_limpieza_documento_horario(
  p_documento_path text
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid text;
begin
  select tarea.usuario_uid into v_uid
  from public.horario_documentos_limpieza as tarea
  where tarea.documento_path = p_documento_path
  for update;
  if not found then
    raise exception using
      errcode = 'P0002', message = 'tarea_limpieza_no_encontrada';
  end if;
  if exists (
    select 1 from storage.objects as objeto
    where objeto.bucket_id = 'horarios-originales'
      and objeto.name = p_documento_path
  ) then
    raise exception using
      errcode = '23514', message = 'archivo_storage_aun_existe';
  end if;
  if exists (
    select 1 from public.importaciones_horario as importacion
    where importacion.usuario_uid = v_uid
      and importacion.documento_path = p_documento_path
  ) then
    raise exception using
      errcode = '23514', message = 'documento_aun_asociado';
  end if;
  delete from public.horario_documentos_limpieza
  where usuario_uid = v_uid and documento_path = p_documento_path;
end;
$$;

revoke all on function public.confirmar_importacion_horario_con_documento(jsonb)
  from public, anon, authenticated;
revoke all on function public.asociar_documento_importacion_horario(text, jsonb)
  from public, anon, authenticated;
revoke all on function public.listar_importaciones_horario_con_documento()
  from public, anon, authenticated;
revoke all on function public.eliminar_importacion_horario_con_documento(text)
  from public, anon, authenticated;
revoke all on function public.registrar_limpieza_documento_horario(text)
  from public, anon, authenticated;
revoke all on function public.confirmar_limpieza_documento_horario(text)
  from public, anon, authenticated;

grant execute on function public.confirmar_importacion_horario_con_documento(jsonb) to authenticated;
grant execute on function public.asociar_documento_importacion_horario(text, jsonb) to authenticated;
grant execute on function public.listar_importaciones_horario_con_documento() to authenticated;
grant execute on function public.eliminar_importacion_horario_con_documento(text) to authenticated;
grant execute on function public.registrar_limpieza_documento_horario(text) to authenticated;
grant execute on function public.confirmar_limpieza_documento_horario(text) to service_role;

commit;
