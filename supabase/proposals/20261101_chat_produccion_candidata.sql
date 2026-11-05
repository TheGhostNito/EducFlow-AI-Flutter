-- CANDIDATA LOCAL PARA REVISIÓN. NO EJECUTAR SIN RESPALDO Y AUTORIZACIÓN.
-- Destino previsto: Supabase EducFlow AI ubjmdfwkjgblnjgmufpc, base postgres.
-- Comprobar el proyecto en la consola antes de abrir el editor SQL.
-- Reutiliza chats y mensajes_chat existentes; no recrea tablas ni elimina filas.
-- Las RPC son SECURITY DEFINER de postgres: el JWT verificado, la identidad
-- Firebase y los filtros por UID de cada función son barreras obligatorias.
begin;
set local lock_timeout = '5s';

do $$
begin
  if current_user <> 'postgres' or current_database() <> 'postgres' then
    raise exception 'Ejecutar solo como postgres en la base postgres del proyecto confirmado';
  end if;
  if pg_catalog.to_regclass('public.chats') is null
     or pg_catalog.to_regclass('public.mensajes_chat') is null
     or pg_catalog.to_regprocedure('public.current_firebase_uid()') is null
     or pg_catalog.to_regprocedure('public.current_educflow_firebase_uid()') is null
     or pg_catalog.to_regprocedure('public.is_educflow_firebase_user()') is null then
    raise exception 'Faltan tablas o funciones de identidad esperadas';
  end if;
  if (
    select pg_catalog.count(*) from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('current_firebase_uid',
                        'current_educflow_firebase_uid',
                        'is_educflow_firebase_user')
      and not p.prosecdef
      and pg_catalog.pg_get_userbyid(p.proowner) = 'postgres'
      and p.proconfig = array['search_path=""']::text[]
  ) <> 3 then
    raise exception 'Funciones de identidad cambiaron: revisar antes de aplicar';
  end if;
  if exists (
    select 1 from pg_catalog.pg_attribute
    where attrelid = 'public.chats'::pg_catalog.regclass
      and attname = 'ultima_operacion_estado_id' and not attisdropped
  ) or pg_catalog.to_regclass('public.chats_un_activo_por_uid') is not null then
    raise exception 'El esquema cambió: revisar columna e índice antes de aplicar';
  end if;
  if exists (
    select 1 from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('chat_cipher_v1_bytes', 'crear_chat_ia',
                        'guardar_mensaje_chat_ia', 'cambiar_estado_chat_ia',
                        'eliminar_chat_ia')
  ) then
    raise exception 'Ya existe una función de chat: revisar diferencias antes de aplicar';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_class c
    where c.oid = 'public.chats'::pg_catalog.regclass
      and c.relrowsecurity
      and pg_catalog.pg_get_userbyid(c.relowner) = 'postgres'
  ) or not exists (
    select 1 from pg_catalog.pg_class c
    where c.oid = 'public.mensajes_chat'::pg_catalog.regclass
      and c.relrowsecurity
      and pg_catalog.pg_get_userbyid(c.relowner) = 'postgres'
  ) then
    raise exception 'Dueño o RLS de chat inesperado';
  end if;
  if (
    select pg_catalog.count(*) from pg_catalog.pg_policies
    where schemaname = 'public' and tablename in ('chats', 'mensajes_chat')
  ) <> 2 or (
    select pg_catalog.count(*) from pg_catalog.pg_policies
    where schemaname = 'public'
      and ((tablename = 'chats' and policyname = 'chats_propios')
           or (tablename = 'mensajes_chat' and policyname = 'mensajes_propios'))
      and cmd = 'ALL' and roles = array['authenticated']::name[]
  ) <> 2 then
    raise exception 'Políticas de chat cambiaron: revisar antes de aplicar';
  end if;
  if exists (
    select 1 from pg_catalog.pg_attribute a
    where a.attrelid in ('public.chats'::pg_catalog.regclass,
                         'public.mensajes_chat'::pg_catalog.regclass)
      and a.attnum > 0 and not a.attisdropped and a.attacl is not null
  ) then
    raise exception 'Existen grants por columna: revisar antes de aplicar';
  end if;
  if exists (
    select 1 from public.chats where archivado = false
    group by usuario_uid having count(*) > 1
  ) then
    raise exception using errcode = '23505', message = 'chats_activos_duplicados';
  end if;
end;
$$;
alter table public.chats
  add column ultima_operacion_estado_id text;
create unique index chats_un_activo_por_uid
  on public.chats (usuario_uid) where archivado = false;

create or replace function public.chat_cipher_v1_bytes(p_payload jsonb)
returns table(ciphertext bytea, nonce bytea, auth_tag bytea)
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v_cipher text;
  v_nonce text;
  v_tag text;
begin
  if pg_catalog.jsonb_typeof(p_payload) is distinct from 'object'
     or p_payload ->> 'algorithm' is distinct from 'aes-256-gcm'
     or p_payload ->> 'version' is distinct from '1' then
    raise exception using errcode = '22023', message = 'chat_cifrado_incompatible';
  end if;
  v_cipher := p_payload ->> 'ciphertext_hex';
  v_nonce := p_payload ->> 'nonce_hex';
  v_tag := p_payload ->> 'auth_tag_hex';
  if v_cipher is null or pg_catalog.length(v_cipher) > 200000
     or pg_catalog.length(v_cipher) % 2 <> 0
     or v_cipher !~ '^[0-9a-fA-F]*$'
     or v_nonce !~ '^[0-9a-fA-F]{24}$'
     or v_tag !~ '^[0-9a-fA-F]{32}$' then
    raise exception using errcode = '22023', message = 'chat_bytes_invalidos';
  end if;
  return query select pg_catalog.decode(v_cipher, 'hex'),
                      pg_catalog.decode(v_nonce, 'hex'),
                      pg_catalog.decode(v_tag, 'hex');
end;
$$;

create or replace function public.crear_chat_ia(
  p_expected_uid text, p_chat_id text, p_title jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text := public.current_educflow_firebase_uid();
  v_row public.chats%rowtype;
  v_cipher bytea;
  v_nonce bytea;
  v_tag bytea;
  v_now timestamptz;
begin
  if v_uid is null or v_uid is distinct from p_expected_uid then
    raise exception using errcode = '42501', message = 'usuario_firebase_no_valido';
  end if;
  if p_chat_id is null or p_chat_id !~ '^[A-Za-z0-9_-]{1,128}$' then
    raise exception using errcode = '22023', message = 'chat_id_invalido';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('educflow-chat:' || v_uid, 0));
  v_now := pg_catalog.clock_timestamp();
  select * into v_row from public.chats
    where usuario_uid = v_uid and id = p_chat_id for update;
  if found then return pg_catalog.to_jsonb(v_row); end if;
  select ciphertext, nonce, auth_tag into v_cipher, v_nonce, v_tag
    from public.chat_cipher_v1_bytes(p_title);
  update public.chats set archivado = true, ultima_salida_en = v_now
    where usuario_uid = v_uid and archivado = false;
  insert into public.chats (
    usuario_uid, id, titulo_cifrado, titulo_nonce, titulo_auth_tag,
    creado_en, actualizado_en, ultimo_mensaje_en, ultima_salida_en,
    cantidad_mensajes, archivado, algoritmo_cifrado, version_cifrado
  ) values (
    v_uid, p_chat_id, v_cipher, v_nonce, v_tag,
    v_now, v_now, v_now, null, 0, false, 'aes-256-gcm', 1
  ) returning * into v_row;
  return pg_catalog.to_jsonb(v_row);
end;
$$;

create or replace function public.guardar_mensaje_chat_ia(
  p_expected_uid text, p_chat_id text, p_message_id text, p_role text, p_content jsonb,
  p_is_error boolean default false, p_clear_error_message_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text := public.current_educflow_firebase_uid();
  v_chat public.chats%rowtype;
  v_row public.mensajes_chat%rowtype;
  v_cipher bytea;
  v_nonce bytea;
  v_tag bytea;
  v_deleted integer := 0;
  v_existing boolean := false;
  v_now timestamptz;
begin
  if v_uid is null or v_uid is distinct from p_expected_uid then
    raise exception using errcode = '42501', message = 'usuario_firebase_no_valido';
  end if;
  if p_chat_id is null or p_chat_id !~ '^[A-Za-z0-9_-]{1,128}$'
     or p_message_id is null or p_message_id !~ '^[A-Za-z0-9_-]{1,128}$'
     or (p_clear_error_message_id is not null and
         p_clear_error_message_id !~ '^[A-Za-z0-9_-]{1,128}$')
     or p_role is null or p_role not in ('user', 'assistant')
     or p_is_error is null then
    raise exception using errcode = '22023', message = 'chat_identificador_o_rol_invalido';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('educflow-chat:' || v_uid, 0));
  v_now := pg_catalog.clock_timestamp();
  select * into v_chat from public.chats
    where usuario_uid = v_uid and id = p_chat_id for update;
  if not found then
    raise exception using errcode = '22023', message = 'chat_no_existe';
  end if;
  select * into v_row from public.mensajes_chat
    where usuario_uid = v_uid and chat_id = p_chat_id and id = p_message_id
    for update;
  v_existing := found;
  if v_existing and v_row.rol <> p_role then
    raise exception using errcode = '22023', message = 'chat_rol_inmutable';
  end if;
  if v_existing and v_row.es_error and not p_is_error then
    raise exception using errcode = '22023', message = 'chat_id_error_en_uso';
  end if;
  if v_existing and not (p_is_error and v_row.es_error) then
    if p_clear_error_message_id is not null and not p_is_error then
      delete from public.mensajes_chat
        where usuario_uid = v_uid and chat_id = p_chat_id
          and id = p_clear_error_message_id and es_error = true;
      get diagnostics v_deleted = row_count;
      if v_deleted > 0 then
        update public.chats set cantidad_mensajes = cantidad_mensajes - v_deleted
          where usuario_uid = v_uid and id = p_chat_id;
      end if;
    end if;
    return pg_catalog.to_jsonb(v_row);
  end if;
  if v_chat.archivado then
    raise exception using errcode = '22023', message = 'chat_no_activo';
  end if;
  select ciphertext, nonce, auth_tag into v_cipher, v_nonce, v_tag
    from public.chat_cipher_v1_bytes(p_content);
  if v_existing then
    if v_row.rol <> p_role then
      raise exception using errcode = '22023', message = 'chat_rol_inmutable';
    end if;
    update public.mensajes_chat set
      contenido_cifrado = v_cipher, contenido_nonce = v_nonce,
      contenido_auth_tag = v_tag, creado_en = v_now
      where usuario_uid = v_uid and chat_id = p_chat_id and id = p_message_id
      returning * into v_row;
    update public.chats set actualizado_en = v_now, ultimo_mensaje_en = v_now
      where usuario_uid = v_uid and id = p_chat_id;
    return pg_catalog.to_jsonb(v_row);
  end if;
  if p_clear_error_message_id is not null then
    delete from public.mensajes_chat
      where usuario_uid = v_uid and chat_id = p_chat_id
        and id = p_clear_error_message_id and es_error = true;
    get diagnostics v_deleted = row_count;
  end if;
  insert into public.mensajes_chat (
    usuario_uid, chat_id, id, rol, contenido_cifrado, contenido_nonce,
    contenido_auth_tag, creado_en, es_error, algoritmo_cifrado, version_cifrado
  ) values (
    v_uid, p_chat_id, p_message_id, p_role, v_cipher, v_nonce,
    v_tag, v_now, coalesce(p_is_error, false), 'aes-256-gcm', 1
  ) returning * into v_row;
  update public.chats set
    actualizado_en = v_now, ultimo_mensaje_en = v_now,
    ultima_salida_en = null,
    cantidad_mensajes = cantidad_mensajes + 1 - v_deleted
    where usuario_uid = v_uid and id = p_chat_id;
  return pg_catalog.to_jsonb(v_row);
end;
$$;

create or replace function public.cambiar_estado_chat_ia(
  p_expected_uid text, p_chat_id text, p_action text, p_operation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text := public.current_educflow_firebase_uid();
  v_row public.chats%rowtype;
  v_now timestamptz;
begin
  if v_uid is null or v_uid is distinct from p_expected_uid then
    raise exception using errcode = '42501', message = 'usuario_firebase_no_valido';
  end if;
  if p_chat_id is null or p_chat_id !~ '^[A-Za-z0-9_-]{1,128}$'
     or p_action is null
     or p_action not in ('enter', 'exit', 'archive', 'reactivate')
     or p_operation_id is null
     or p_operation_id !~ '^[A-Za-z0-9_-]{1,128}$' then
    raise exception using errcode = '22023', message = 'chat_estado_invalido';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('educflow-chat:' || v_uid, 0));
  select * into v_row from public.chats
    where usuario_uid = v_uid and id = p_chat_id for update;
  if not found then
    raise exception using errcode = '22023', message = 'chat_no_existe';
  end if;
  if v_row.ultima_operacion_estado_id = p_operation_id then
    return pg_catalog.to_jsonb(v_row);
  end if;
  v_now := pg_catalog.clock_timestamp();
  if p_action in ('enter', 'reactivate') then
    update public.chats set archivado = true, ultima_salida_en = v_now
      where usuario_uid = v_uid and id <> p_chat_id and archivado = false;
  end if;
  update public.chats set
    archivado = case when p_action = 'archive' then true
                    when p_action in ('enter', 'reactivate') then false
                    else archivado end,
    ultima_salida_en = case when p_action in ('exit', 'archive')
                              then v_now else null end,
    ultima_operacion_estado_id = p_operation_id
    where usuario_uid = v_uid and id = p_chat_id
    returning * into v_row;
  return pg_catalog.to_jsonb(v_row);
end;
$$;

create or replace function public.eliminar_chat_ia(p_expected_uid text, p_chat_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text := public.current_educflow_firebase_uid();
begin
  if v_uid is null or v_uid is distinct from p_expected_uid then
    raise exception using errcode = '42501', message = 'usuario_firebase_no_valido';
  end if;
  if p_chat_id is null or p_chat_id !~ '^[A-Za-z0-9_-]{1,128}$' then
    raise exception using errcode = '22023', message = 'chat_id_invalido';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('educflow-chat:' || v_uid, 0));
  delete from public.chats where usuario_uid = v_uid and id = p_chat_id;
  -- FK existente mensajes_chat -> chats aplica ON DELETE CASCADE.
end;
$$;

-- Los clientes conservan SELECT sujeto a RLS. Toda escritura pasa por RPC.
-- Verificar el dueño postgres y la identidad del JWT antes del corte.
drop policy chats_propios on public.chats;
create policy chats_propios on public.chats
  for select to authenticated
  using (public.is_educflow_firebase_user()
         and usuario_uid = public.current_firebase_uid());
drop policy mensajes_propios on public.mensajes_chat;
create policy mensajes_propios on public.mensajes_chat
  for select to authenticated
  using (public.is_educflow_firebase_user()
         and usuario_uid = public.current_firebase_uid());
revoke all on table public.chats, public.mensajes_chat
  from public, anon, authenticated;
grant select on table public.chats, public.mensajes_chat to authenticated;

revoke all on function public.chat_cipher_v1_bytes(jsonb) from public, anon, authenticated;
revoke all on function public.crear_chat_ia(text, text, jsonb) from public, anon;
revoke all on function public.guardar_mensaje_chat_ia(text, text, text, text, jsonb, boolean, text)
  from public, anon;
revoke all on function public.cambiar_estado_chat_ia(text, text, text, text) from public, anon;
revoke all on function public.eliminar_chat_ia(text, text) from public, anon;
grant execute on function public.crear_chat_ia(text, text, jsonb) to authenticated;
grant execute on function public.guardar_mensaje_chat_ia(text, text, text, text, jsonb, boolean, text)
  to authenticated;
grant execute on function public.cambiar_estado_chat_ia(text, text, text, text) to authenticated;
grant execute on function public.eliminar_chat_ia(text, text) to authenticated;

do $$
declare
  v_signature text;
  v_table text;
  v_privilege text;
begin
  foreach v_table in array array['public.chats', 'public.mensajes_chat'] loop
    if not pg_catalog.has_table_privilege('authenticated', v_table, 'SELECT') then
      raise exception 'SELECT de chat no concedido: %', v_table;
    end if;
    foreach v_privilege in array array[
      'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE',
      'TRIGGER', 'REFERENCES', 'MAINTAIN'
    ] loop
      if pg_catalog.has_table_privilege('authenticated', v_table, v_privilege)
         or pg_catalog.has_table_privilege('anon', v_table, v_privilege) then
        raise exception 'Privilegio directo de chat inesperado: % %',
          v_table, v_privilege;
      end if;
    end loop;
    if pg_catalog.has_table_privilege('anon', v_table, 'SELECT') then
      raise exception 'SELECT anónimo de chat inesperado: %', v_table;
    end if;
  end loop;
  if pg_catalog.has_function_privilege(
       'authenticated', 'public.chat_cipher_v1_bytes(jsonb)', 'EXECUTE')
     or pg_catalog.has_function_privilege(
       'anon', 'public.chat_cipher_v1_bytes(jsonb)', 'EXECUTE')
     or exists (
       select 1 from pg_catalog.pg_proc p
       cross join lateral pg_catalog.aclexplode(
         coalesce(
           p.proacl, pg_catalog.acldefault('f', p.proowner)
         )
       ) acl
       where p.oid = 'public.chat_cipher_v1_bytes(jsonb)'::pg_catalog.regprocedure
         and acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
     ) then
    raise exception 'Helper expuesto al cliente; transacción revertida';
  end if;
  if (select pg_catalog.count(*) from pg_catalog.pg_policies
      where schemaname = 'public'
        and tablename in ('chats', 'mensajes_chat')) <> 2
     or (select pg_catalog.count(*) from pg_catalog.pg_policies
         where schemaname = 'public'
           and ((tablename = 'chats' and policyname = 'chats_propios')
                or (tablename = 'mensajes_chat'
                    and policyname = 'mensajes_propios'))
           and cmd = 'SELECT' and roles = array['authenticated']::name[]) <> 2 then
    raise exception 'RLS de lectura inesperada; transacción revertida';
  end if;
  foreach v_signature in array array[
    'public.crear_chat_ia(text,text,jsonb)',
    'public.guardar_mensaje_chat_ia(text,text,text,text,jsonb,boolean,text)',
    'public.cambiar_estado_chat_ia(text,text,text,text)',
    'public.eliminar_chat_ia(text,text)'
  ] loop
    if not exists (
      select 1 from pg_catalog.pg_proc p
      where p.oid = pg_catalog.to_regprocedure(v_signature)
        and p.prosecdef
        and pg_catalog.pg_get_userbyid(p.proowner) = 'postgres'
        and p.proconfig = array['search_path=""']::text[]
    ) or not pg_catalog.has_function_privilege(
       'authenticated', v_signature, 'EXECUTE')
      or pg_catalog.has_function_privilege('anon', v_signature, 'EXECUTE')
      or exists (
        select 1 from pg_catalog.pg_proc p
        cross join lateral pg_catalog.aclexplode(
          coalesce(
            p.proacl, pg_catalog.acldefault('f', p.proowner)
          )
        ) acl
        where p.oid = pg_catalog.to_regprocedure(v_signature)
          and acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
      ) then
      raise exception 'RPC no cumple owner, SECURITY DEFINER o search_path: %',
        v_signature;
    end if;
  end loop;
end;
$$;
commit;
