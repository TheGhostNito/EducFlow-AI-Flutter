-- Validación posterior a la migración OCR en Supabase Testing.
-- Todas las escrituras funcionales se revierten al terminar.

begin;

do $schema_validation$
declare
  v_missing text[];
  v_mismatch text[];
  v_table text;
  v_role text;
  v_constraint_count integer;
begin
  select pg_catalog.array_agg(object_name order by object_name)
    into v_missing
  from pg_catalog.unnest(array[
    'public.ocr_cache',
    'public.ocr_usage',
    'public.ocr_monthly_usage',
    'public.ocr_daily_user_usage'
  ]) as expected(object_name)
  where pg_catalog.to_regclass(expected.object_name) is null;

  if v_missing is not null then
    raise exception 'Faltan tablas OCR: %', v_missing;
  end if;

  if pg_catalog.to_regprocedure(
    'public.reserve_ocr_vision_usage(text,integer,integer,integer)'
  ) is null then
    raise exception 'Falta reserve_ocr_vision_usage con el contrato esperado';
  end if;

  with expected(table_name, column_name, udt_name, is_nullable) as (
    values
      ('ocr_cache', 'document_hash', 'text', 'NO'),
      ('ocr_cache', 'mime_type', 'text', 'NO'),
      ('ocr_cache', 'result', 'jsonb', 'NO'),
      ('ocr_cache', 'page_count', 'int4', 'NO'),
      ('ocr_cache', 'course_count', 'int4', 'NO'),
      ('ocr_cache', 'vision_units', 'int4', 'NO'),
      ('ocr_cache', 'created_at', 'timestamptz', 'NO'),
      ('ocr_usage', 'id', 'int8', 'NO'),
      ('ocr_usage', 'user_id', 'text', 'NO'),
      ('ocr_usage', 'document_hash', 'text', 'NO'),
      ('ocr_usage', 'provider', 'text', 'NO'),
      ('ocr_usage', 'pages', 'int4', 'NO'),
      ('ocr_usage', 'vision_units', 'int4', 'NO'),
      ('ocr_usage', 'status', 'text', 'NO'),
      ('ocr_usage', 'created_at', 'timestamptz', 'NO'),
      ('ocr_monthly_usage', 'month_start', 'date', 'NO'),
      ('ocr_monthly_usage', 'reserved_units', 'int4', 'NO'),
      ('ocr_monthly_usage', 'updated_at', 'timestamptz', 'NO'),
      ('ocr_daily_user_usage', 'usage_date', 'date', 'NO'),
      ('ocr_daily_user_usage', 'user_id', 'text', 'NO'),
      ('ocr_daily_user_usage', 'reserved_units', 'int4', 'NO'),
      ('ocr_daily_user_usage', 'updated_at', 'timestamptz', 'NO')
  ), actual as (
    select columns.table_name, columns.column_name,
      columns.udt_name::text, columns.is_nullable::text
    from information_schema.columns
    where columns.table_schema = 'public'
      and columns.table_name in (
        'ocr_cache', 'ocr_usage', 'ocr_monthly_usage',
        'ocr_daily_user_usage'
      )
  )
  select pg_catalog.array_agg(
    COALESCE(expected.table_name, actual.table_name) || '.' ||
    COALESCE(expected.column_name, actual.column_name)
    order by 1
  )
    into v_mismatch
  from expected
  full join actual using (table_name, column_name)
  where expected.table_name is null
    or actual.table_name is null
    or expected.udt_name is distinct from actual.udt_name
    or expected.is_nullable is distinct from actual.is_nullable;

  if v_mismatch is not null then
    raise exception 'Columnas OCR incompatibles: %', v_mismatch;
  end if;

  select pg_catalog.array_agg(constraint_name order by constraint_name)
    into v_missing
  from pg_catalog.unnest(array[
    'ocr_cache_pkey',
    'ocr_cache_course_count_nonnegative',
    'ocr_cache_hash_format',
    'ocr_cache_page_count_nonnegative',
    'ocr_cache_vision_units_positive',
    'ocr_usage_pkey',
    'ocr_usage_pages_positive',
    'ocr_usage_status_valid',
    'ocr_usage_vision_units_positive',
    'ocr_monthly_usage_pkey',
    'ocr_monthly_usage_reserved_nonnegative',
    'ocr_daily_user_usage_pkey',
    'ocr_daily_user_usage_nonnegative'
  ]) as expected(constraint_name)
  where not exists (
    select 1
    from pg_catalog.pg_constraint as constraint_definition
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = constraint_definition.connamespace
    where namespace.nspname = 'public'
      and constraint_definition.conname = expected.constraint_name
  );

  if v_missing is not null then
    raise exception 'Faltan restricciones OCR: %', v_missing;
  end if;

  select pg_catalog.count(*)
    into v_constraint_count
    from pg_catalog.pg_constraint as constraint_definition
    join pg_catalog.pg_class as relation
      on relation.oid = constraint_definition.conrelid
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'ocr_cache', 'ocr_usage', 'ocr_monthly_usage',
        'ocr_daily_user_usage'
      )
      and constraint_definition.contype in ('p', 'c');

  if v_constraint_count <> 13 then
    raise exception 'Se esperaban 13 restricciones OCR PK/CHECK y existen %',
      v_constraint_count;
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'ocr_usage'
      and column_name = 'id'
      and is_identity = 'NO'
  ) then
    raise exception 'ocr_usage.id no debe ser SQL Identity';
  end if;

  if pg_catalog.to_regclass('public.ocr_usage_id_seq') is null
    or not exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'ocr_usage'
        and column_name = 'id'
        and column_default like 'nextval(%ocr_usage_id_seq%'
    ) then
    raise exception 'ocr_usage.id no conserva la secuencia BIGSERIAL esperada';
  end if;

  select pg_catalog.array_agg(object_name order by object_name)
    into v_missing
  from pg_catalog.unnest(array[
    'public.idx_ocr_usage_created_at',
    'public.idx_ocr_usage_document_hash',
    'public.idx_ocr_usage_user_created_at'
  ]) as expected(object_name)
  where pg_catalog.to_regclass(expected.object_name) is null;

  if v_missing is not null then
    raise exception 'Faltan índices OCR: %', v_missing;
  end if;

  if not exists (
    select 1 from pg_catalog.pg_indexes
    where schemaname = 'public' and tablename = 'ocr_usage'
      and indexname = 'idx_ocr_usage_created_at'
      and indexdef ~ '\(created_at\)$'
  ) or not exists (
    select 1 from pg_catalog.pg_indexes
    where schemaname = 'public' and tablename = 'ocr_usage'
      and indexname = 'idx_ocr_usage_document_hash'
      and indexdef ~ '\(document_hash\)$'
  ) or not exists (
    select 1 from pg_catalog.pg_indexes
    where schemaname = 'public' and tablename = 'ocr_usage'
      and indexname = 'idx_ocr_usage_user_created_at'
      and indexdef ~ '\(user_id, created_at\)$'
  ) then
    raise exception 'Las definiciones de los índices OCR no coinciden';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'reserve_ocr_vision_usage'
      and procedure.prosecdef
      and procedure.pronargdefaults = 3
      and pg_catalog.pg_get_expr(procedure.proargdefaults, 0) = '1, 800, 10'
      and pg_catalog.pg_get_functiondef(procedure.oid) like '%reserved_units%'
      and procedure.proowner = (
        select role.oid from pg_catalog.pg_roles as role
        where role.rolname = 'postgres'
      )
      and exists (
        select 1
        from pg_catalog.unnest(procedure.proconfig) as setting(value)
        where setting.value ~ '^search_path=(|"")$'
      )
  ) then
    raise exception 'El RPC no conserva SECURITY DEFINER, propietario o search_path seguro';
  end if;

  foreach v_table in array array[
    'ocr_cache', 'ocr_usage', 'ocr_monthly_usage', 'ocr_daily_user_usage'
  ] loop
    if not exists (
      select 1
      from pg_catalog.pg_class as relation
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = relation.relnamespace
      where namespace.nspname = 'public'
        and relation.relname = v_table
        and relation.relrowsecurity
    ) then
      raise exception 'RLS no está habilitado en public.%', v_table;
    end if;

    if exists (
      select 1 from pg_catalog.pg_policies as policy
      where policy.schemaname = 'public' and policy.tablename = v_table
    ) then
      raise exception 'La tabla interna public.% no debe exponer políticas de usuario', v_table;
    end if;

    foreach v_role in array array['anon', 'authenticated'] loop
      if pg_catalog.has_table_privilege(
        v_role, 'public.' || v_table, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
      ) then
        raise exception 'El rol % conserva privilegios sobre public.%', v_role, v_table;
      end if;
    end loop;
  end loop;

  if not pg_catalog.has_table_privilege(
    'service_role', 'public.ocr_cache', 'SELECT'
  ) or not pg_catalog.has_table_privilege(
    'service_role', 'public.ocr_cache', 'INSERT'
  ) then
    raise exception 'service_role no puede operar la caché OCR';
  end if;
  if pg_catalog.has_table_privilege(
    'service_role', 'public.ocr_cache', 'UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  ) then
    raise exception 'service_role tiene permisos excesivos sobre ocr_cache';
  end if;
  if not pg_catalog.has_table_privilege(
    'service_role', 'public.ocr_usage', 'SELECT'
  ) or not pg_catalog.has_table_privilege(
    'service_role', 'public.ocr_usage', 'INSERT'
  ) or not pg_catalog.has_table_privilege(
    'service_role', 'public.ocr_usage', 'UPDATE'
  ) then
    raise exception 'service_role no puede registrar estados OCR';
  end if;
  if pg_catalog.has_table_privilege(
    'service_role', 'public.ocr_usage', 'DELETE,TRUNCATE,REFERENCES,TRIGGER'
  ) then
    raise exception 'service_role tiene permisos excesivos sobre ocr_usage';
  end if;
  if pg_catalog.has_table_privilege(
    'service_role', 'public.ocr_monthly_usage', 'SELECT,INSERT,UPDATE,DELETE'
  ) or pg_catalog.has_table_privilege(
    'service_role', 'public.ocr_daily_user_usage', 'SELECT,INSERT,UPDATE,DELETE'
  ) then
    raise exception 'Las tablas de cuota solo deben ser accesibles mediante el RPC';
  end if;

  if not pg_catalog.has_sequence_privilege(
    'service_role', 'public.ocr_usage_id_seq', 'USAGE'
  ) or not pg_catalog.has_sequence_privilege(
    'service_role', 'public.ocr_usage_id_seq', 'SELECT'
  ) then
    raise exception 'service_role no puede usar la secuencia de ocr_usage';
  end if;
  foreach v_role in array array['anon', 'authenticated'] loop
    if pg_catalog.has_sequence_privilege(
      v_role, 'public.ocr_usage_id_seq', 'USAGE,SELECT,UPDATE'
    ) then
      raise exception 'El rol % conserva privilegios sobre ocr_usage_id_seq', v_role;
    end if;
  end loop;

  if pg_catalog.has_function_privilege(
    'anon',
    'public.reserve_ocr_vision_usage(text,integer,integer,integer)',
    'EXECUTE'
  ) or pg_catalog.has_function_privilege(
    'authenticated',
    'public.reserve_ocr_vision_usage(text,integer,integer,integer)',
    'EXECUTE'
  ) then
    raise exception 'anon/authenticated no deben ejecutar reserve_ocr_vision_usage';
  end if;
  if not pg_catalog.has_function_privilege(
    'service_role',
    'public.reserve_ocr_vision_usage(text,integer,integer,integer)',
    'EXECUTE'
  ) then
    raise exception 'service_role debe ejecutar reserve_ocr_vision_usage';
  end if;
end;
$schema_validation$;

do $quota_validation$
declare
  v_month_start date := pg_catalog.date_trunc(
    'month', pg_catalog.timezone('UTC', pg_catalog.now())
  )::date;
  v_monthly_baseline integer;
  v_result record;
begin
  delete from public.ocr_daily_user_usage
  where user_id in (
    'ocr_validation_daily_user', 'ocr_validation_monthly_user'
  );

  select COALESCE(reserved_units, 0)
    into v_monthly_baseline
  from public.ocr_monthly_usage
  where month_start = v_month_start;
  v_monthly_baseline := COALESCE(v_monthly_baseline, 0);

  select * into strict v_result
  from public.reserve_ocr_vision_usage(
    'ocr_validation_daily_user', 2, v_monthly_baseline + 100, 3
  );
  if not v_result.allowed
    or v_result.reason is not null
    or v_result.daily_used <> 2
    or v_result.daily_remaining <> 1 then
    raise exception 'Falló la reserva diaria permitida: %', v_result;
  end if;

  select * into strict v_result
  from public.reserve_ocr_vision_usage(
    'ocr_validation_daily_user', 2, v_monthly_baseline + 100, 3
  );
  if v_result.allowed
    or v_result.reason is distinct from 'daily_limit'
    or v_result.daily_used <> 2
    or v_result.daily_remaining <> 1 then
    raise exception 'Falló el bloqueo por límite diario: %', v_result;
  end if;

  -- La primera prueba consumió dos unidades dentro de esta transacción.
  select * into strict v_result
  from public.reserve_ocr_vision_usage(
    'ocr_validation_monthly_user', 2, v_monthly_baseline + 5, 100
  );
  if not v_result.allowed
    or v_result.monthly_used <> v_monthly_baseline + 4
    or v_result.monthly_remaining <> 1 then
    raise exception 'Falló la reserva mensual permitida: %', v_result;
  end if;

  select * into strict v_result
  from public.reserve_ocr_vision_usage(
    'ocr_validation_monthly_user', 2, v_monthly_baseline + 5, 100
  );
  if v_result.allowed
    or v_result.reason is distinct from 'monthly_limit'
    or v_result.monthly_used <> v_monthly_baseline + 4
    or v_result.monthly_remaining <> 1 then
    raise exception 'Falló el bloqueo por límite mensual: %', v_result;
  end if;
end;
$quota_validation$;

rollback;
