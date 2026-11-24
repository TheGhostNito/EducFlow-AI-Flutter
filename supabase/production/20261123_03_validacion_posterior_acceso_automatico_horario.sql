-- P0 EducFlow AI: validación posterior exclusiva de Supabase Producción.
-- SOLO LECTURA. Ejecutar después de 202611230002.

begin transaction read only;

do $validation$
declare
  v_definition text;
  v_rpc text;
begin
  select pg_catalog.pg_get_functiondef(
    'public.is_educflow_firebase_user()'::pg_catalog.regprocedure
  ) into v_definition;
  if v_definition not like '%https://securetoken.google.com/educflow-ai%'
      or v_definition not like '%''aud'' = ''educflow-ai''%'
      or v_definition not like '%''role'' = ''authenticated''%'
      or v_definition not like '%->>''sub''%'
      or v_definition like '%eduflow-ai-testing%' then
    raise exception 'identidad_firebase_productiva_invalida';
  end if;

  select pg_catalog.pg_get_functiondef(
    'public.uid_importacion_horario_autorizado()'::pg_catalog.regprocedure
  ) into v_definition;
  if v_definition not like '%is_educflow_firebase_user()%'
      or v_definition not like '%current_firebase_uid()%'
      or v_definition not like '%control.habilitado is false%'
      or v_definition not like '%importacion_horario_bloqueada%'
      or v_definition like '%importacion_horario_no_autorizada%' then
    raise exception 'acceso_automatico_productivo_no_instalado';
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
    if pg_catalog.to_regprocedure(v_rpc) is null
        or not pg_catalog.has_function_privilege(
          'authenticated', v_rpc, 'EXECUTE'
        )
        or pg_catalog.has_function_privilege('anon', v_rpc, 'EXECUTE') then
      raise exception using
        message = 'rpc_productiva_ausente_o_expuesta', detail = v_rpc;
    end if;
    if not exists (
      select 1 from pg_catalog.pg_proc as procedure
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
        message = 'seguridad_rpc_productiva_alterada', detail = v_rpc;
    end if;
  end loop;

  if pg_catalog.has_table_privilege(
       'authenticated', 'public.horario_importacion_autorizaciones',
       'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
     )
      or pg_catalog.has_table_privilege(
        'anon', 'public.horario_importacion_autorizaciones',
        'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
      ) then
    raise exception 'cliente_puede_operar_control_administrativo_productivo';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'horario_importacion_autorizaciones'
      and relation.relrowsecurity
  ) or exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'horario_importacion_autorizaciones'
  ) then
    raise exception 'control_administrativo_productivo_no_esta_aislado';
  end if;

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
    raise exception 'rls_productiva_por_uid_alterada';
  end if;

  if pg_catalog.has_function_privilege(
       'authenticated',
       'public.reserve_ocr_vision_usage(text,integer,integer,integer)',
       'EXECUTE'
     )
      or not pg_catalog.has_function_privilege(
        'service_role',
        'public.reserve_ocr_vision_usage(text,integer,integer,integer)',
        'EXECUTE'
      ) then
    raise exception 'cuotas_productivas_expuestas_o_inaccesibles';
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
    raise exception 'storage_productivo_no_conserva_aislamiento_uid';
  end if;
end;
$validation$;

select 'Acceso automático productivo validado estructuralmente' as resultado;

rollback;
