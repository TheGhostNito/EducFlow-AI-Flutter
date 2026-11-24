-- Validación posterior a 202611230002 en Supabase Testing.
-- Es de solo lectura y no sustituye las pruebas con cuentas Firebase reales.

begin transaction read only;

do $validation$
declare
  v_definition text;
  v_rpc text;
begin
  if pg_catalog.to_regprocedure(
    'public.uid_importacion_horario_autorizado()'
  ) is null then
    raise exception 'Falta uid_importacion_horario_autorizado()';
  end if;

  select pg_catalog.pg_get_functiondef(
    pg_catalog.to_regprocedure(
      'public.uid_importacion_horario_autorizado()'
    )
  ) into v_definition;

  if v_definition not like '%is_educflow_firebase_user()%'
      or v_definition not like '%current_firebase_uid()%'
      or v_definition not like '%control.habilitado is false%'
      or v_definition not like '%importacion_horario_bloqueada%'
      or v_definition like '%if not exists (%horario_importacion_autorizaciones%'
      or v_definition like '%importacion_horario_no_autorizada%' then
    raise exception 'La función no implementa el acceso automático esperado';
  end if;

  select pg_catalog.pg_get_functiondef(
    'public.is_educflow_firebase_user()'::pg_catalog.regprocedure
  ) into v_definition;
  if v_definition not like
       '%https://securetoken.google.com/eduflow-ai-testing%'
      or v_definition not like '%''aud'' = ''eduflow-ai-testing''%'
      or v_definition not like '%''role'' = ''authenticated''%'
      or v_definition not like '%->>''sub''%' then
    raise exception 'La identidad SQL no corresponde a Firebase Testing';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'uid_importacion_horario_autorizado'
      and procedure.prosecdef
      and pg_catalog.pg_get_userbyid(procedure.proowner) = 'postgres'
      and exists (
        select 1
        from pg_catalog.unnest(procedure.proconfig) as setting(value)
        where setting.value ~ '^search_path=(|"")$'
      )
  ) then
    raise exception 'La función perdió SECURITY DEFINER o search_path seguro';
  end if;

  if pg_catalog.has_function_privilege(
       'anon',
       'public.uid_importacion_horario_autorizado()',
       'EXECUTE'
     )
      or not pg_catalog.has_function_privilege(
        'authenticated',
        'public.uid_importacion_horario_autorizado()',
        'EXECUTE'
      ) then
    raise exception 'Permisos inválidos en la función de identidad';
  end if;

  if pg_catalog.has_table_privilege(
       'authenticated',
       'public.horario_importacion_autorizaciones',
       'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
     )
      or pg_catalog.has_table_privilege(
        'anon',
        'public.horario_importacion_autorizaciones',
        'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
      ) then
    raise exception 'El cliente puede modificar el control administrativo';
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
    raise exception 'RLS no está habilitado en el control administrativo';
  end if;

  foreach v_rpc in array array[
    'public.confirmar_importacion_horario(jsonb)',
    'public.listar_importaciones_horario()',
    'public.eliminar_importacion_horario(text)',
    'public.confirmar_importacion_horario_con_documento(jsonb)',
    'public.asociar_documento_importacion_horario(text,jsonb)',
    'public.listar_importaciones_horario_con_documento()',
    'public.eliminar_importacion_horario_con_documento(text)'
  ] loop
    if pg_catalog.to_regprocedure(v_rpc) is null then
      raise exception 'Falta RPC de importación: %', v_rpc;
    end if;
    if not pg_catalog.has_function_privilege(
      'authenticated', v_rpc, 'EXECUTE'
    ) or pg_catalog.has_function_privilege('anon', v_rpc, 'EXECUTE') then
      raise exception 'Permisos inválidos en RPC: %', v_rpc;
    end if;
  end loop;

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
    raise exception 'La política de documentos no conserva UID y autorización';
  end if;

  if pg_catalog.to_regprocedure(
       'public.reserve_ocr_vision_usage(text,integer,integer,integer)'
     ) is null
      or pg_catalog.has_function_privilege(
        'authenticated',
        'public.reserve_ocr_vision_usage(text,integer,integer,integer)',
        'EXECUTE'
      )
      or not pg_catalog.has_function_privilege(
        'service_role',
        'public.reserve_ocr_vision_usage(text,integer,integer,integer)',
        'EXECUTE'
      ) then
    raise exception 'Las cuotas OCR cambiaron o quedaron expuestas';
  end if;
end;
$validation$;

rollback;
