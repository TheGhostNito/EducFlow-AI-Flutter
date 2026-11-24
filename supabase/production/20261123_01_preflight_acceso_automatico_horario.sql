-- P0 EducFlow AI: preflight exclusivo de Supabase Producción.
-- SOLO LECTURA. Proyecto esperado: ubjmdfwkjgblnjgmufpc / educflow-ai.
-- Ejecutar antes de 202611230002. No ejecutar en Testing.

begin transaction read only;

do $preflight$
declare
  v_definition text;
  v_object text;
  v_rpc text;
begin
  if pg_catalog.to_regprocedure('public.current_firebase_uid()') is null
      or pg_catalog.to_regprocedure(
        'public.is_educflow_firebase_user()'
      ) is null then
    raise exception 'produccion_sin_funciones_identidad_firebase';
  end if;

  select pg_catalog.pg_get_functiondef(
    'public.current_firebase_uid()'::pg_catalog.regprocedure
  ) into v_definition;
  if v_definition not like '%auth.jwt()%'
      or v_definition not like '%->>''sub''%'
      or v_definition not like '%nullif%' then
    raise exception 'produccion_current_firebase_uid_incompatible';
  end if;

  select pg_catalog.pg_get_functiondef(
    'public.is_educflow_firebase_user()'::pg_catalog.regprocedure
  ) into v_definition;
  if v_definition not like '%https://securetoken.google.com/educflow-ai%'
      or v_definition not like '%''aud'' = ''educflow-ai''%'
      or v_definition not like '%''role'' = ''authenticated''%'
      or v_definition not like '%->>''sub''%'
      or v_definition like '%eduflow-ai-testing%' then
    raise exception 'entorno_no_es_firebase_produccion';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated', 'public.current_firebase_uid()', 'EXECUTE'
     )
      or not pg_catalog.has_function_privilege(
        'authenticated', 'public.is_educflow_firebase_user()', 'EXECUTE'
      )
      or pg_catalog.has_function_privilege(
        'anon', 'public.current_firebase_uid()', 'EXECUTE'
      )
      or pg_catalog.has_function_privilege(
        'anon', 'public.is_educflow_firebase_user()', 'EXECUTE'
      ) then
    raise exception 'permisos_funciones_identidad_productivas_invalidos';
  end if;

  foreach v_object in array array[
    'public.usuarios',
    'public.asignaturas',
    'public.bloques_horario',
    'public.periodos_academicos',
    'public.sesiones_clase',
    'public.importaciones_horario',
    'public.importacion_horario_asignaturas',
    'public.horario_importacion_autorizaciones',
    'public.ocr_cache',
    'public.ocr_usage',
    'public.ocr_monthly_usage',
    'public.ocr_daily_user_usage',
    'public.horario_documentos_limpieza'
  ] loop
    if pg_catalog.to_regclass(v_object) is null then
      raise exception using
        message = 'objeto_productivo_requerido_ausente', detail = v_object;
    end if;
  end loop;

  foreach v_rpc in array array[
    'public.uid_importacion_horario_autorizado()',
    'public.confirmar_importacion_horario(jsonb)',
    'public.listar_importaciones_horario()',
    'public.eliminar_importacion_horario(text)',
    'public.confirmar_importacion_horario_con_documento(jsonb)',
    'public.asociar_documento_importacion_horario(text,jsonb)',
    'public.listar_importaciones_horario_con_documento()',
    'public.eliminar_importacion_horario_con_documento(text)',
    'public.reserve_ocr_vision_usage(text,integer,integer,integer)'
  ] loop
    if pg_catalog.to_regprocedure(v_rpc) is null then
      raise exception using
        message = 'rpc_productiva_requerida_ausente', detail = v_rpc;
    end if;
  end loop;

  select pg_catalog.pg_get_functiondef(
    'public.uid_importacion_horario_autorizado()'::pg_catalog.regprocedure
  ) into v_definition;
  if v_definition not like '%importacion_horario_no_autorizada%'
      or v_definition not like
        '%horario_importacion_autorizaciones%permiso.habilitado%' then
    raise exception
      'preflight_esperaba_lista_blanca_anterior_a_202611230002';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'horario_importacion_autorizaciones'
      and column_name = 'usuario_uid'
      and data_type = 'text'
      and is_nullable = 'NO'
  ) or not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'horario_importacion_autorizaciones'
      and column_name = 'habilitado'
      and data_type = 'boolean'
      and is_nullable = 'NO'
  ) or not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'horario_importacion_autorizaciones'
      and column_name = 'expira_en'
      and data_type = 'timestamp with time zone'
  ) then
    raise exception 'tabla_autorizaciones_productiva_incompatible';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'horario_importacion_autorizaciones'
      and relation.relrowsecurity
  ) then
    raise exception 'rls_control_administrativo_productivo_deshabilitado';
  end if;

  if exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'horario_importacion_autorizaciones'
  ) then
    raise exception 'control_administrativo_productivo_expone_politicas';
  end if;

  if pg_catalog.has_table_privilege(
       'authenticated', 'public.horario_importacion_autorizaciones',
       'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
     )
      or pg_catalog.has_table_privilege(
        'anon', 'public.horario_importacion_autorizaciones',
        'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
      )
      or not pg_catalog.has_table_privilege(
        'service_role', 'public.horario_importacion_autorizaciones',
        'SELECT,INSERT,UPDATE,DELETE'
      ) then
    raise exception 'privilegios_control_administrativo_productivo_invalidos';
  end if;

  foreach v_rpc in array array[
    'public.uid_importacion_horario_autorizado()',
    'public.confirmar_importacion_horario(jsonb)',
    'public.listar_importaciones_horario()',
    'public.eliminar_importacion_horario(text)',
    'public.confirmar_importacion_horario_con_documento(jsonb)',
    'public.asociar_documento_importacion_horario(text,jsonb)',
    'public.listar_importaciones_horario_con_documento()',
    'public.eliminar_importacion_horario_con_documento(text)'
  ] loop
    if not pg_catalog.has_function_privilege(
         'authenticated', v_rpc, 'EXECUTE'
       )
        or pg_catalog.has_function_privilege('anon', v_rpc, 'EXECUTE') then
      raise exception using
        message = 'permisos_rpc_productiva_invalidos', detail = v_rpc;
    end if;

    if not exists (
      select 1
      from pg_catalog.pg_proc as procedure
      where procedure.oid = pg_catalog.to_regprocedure(v_rpc)
        and procedure.prosecdef
        and pg_catalog.pg_get_userbyid(procedure.proowner) = 'postgres'
        and exists (
          select 1
          from pg_catalog.unnest(procedure.proconfig) as setting(value)
          where setting.value ~ '^search_path=(|"")$'
        )
    ) then
      raise exception using
        message = 'seguridad_rpc_productiva_invalida', detail = v_rpc;
    end if;
  end loop;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'importaciones_horario', 'importacion_horario_asignaturas'
      )
      and 'authenticated' = any(roles)
      and coalesce(qual, '') like '%is_educflow_firebase_user%'
      and coalesce(qual, '') like '%current_firebase_uid%'
  ) <> 2 then
    raise exception 'politicas_rls_productivas_importacion_incompletas';
  end if;

  if not exists (
    select 1 from storage.buckets
    where id = 'horarios-originales'
      and public is false
      and file_size_limit = 10485760
  ) then
    raise exception 'bucket_productivo_horarios_originales_incompatible';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'horario_documento_insert_own'
      and 'authenticated' = any(roles)
      and coalesce(with_check, '') like
        '%uid_importacion_horario_autorizado%'
      and coalesce(with_check, '') like '%current_firebase_uid%'
  ) then
    raise exception 'politica_productiva_storage_horario_incompatible';
  end if;

  if pg_catalog.has_function_privilege(
       'authenticated',
       'public.reserve_ocr_vision_usage(text,integer,integer,integer)',
       'EXECUTE'
     )
      or pg_catalog.has_function_privilege(
        'anon',
        'public.reserve_ocr_vision_usage(text,integer,integer,integer)',
        'EXECUTE'
      )
      or not pg_catalog.has_function_privilege(
        'service_role',
        'public.reserve_ocr_vision_usage(text,integer,integer,integer)',
        'EXECUTE'
      ) then
    raise exception 'permisos_cuota_ocr_productiva_invalidos';
  end if;

  select pg_catalog.pg_get_functiondef(
    'public.reserve_ocr_vision_usage(text,integer,integer,integer)'::
      pg_catalog.regprocedure
  ) into v_definition;
  if v_definition not like '%DEFAULT 800%'
      or v_definition not like '%DEFAULT 10%'
      or v_definition not like '%daily_limit%'
      or v_definition not like '%monthly_limit%' then
    raise exception 'contrato_cuota_ocr_productiva_incompatible';
  end if;
end;
$preflight$;

select 'Supabase Producción compatible con 202611230002' as resultado;

rollback;
