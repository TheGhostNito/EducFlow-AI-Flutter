-- Preflight de solo lectura para Supabase Testing.
-- Ejecutar únicamente en el proyecto Testing (ref oxrvksaljxcwdhkeapej).
-- No comprueba secretos de Edge Functions ni sustituye una prueba con un
-- Firebase ID token real. No ejecutar en Producción.

BEGIN TRANSACTION READ ONLY;

DO $preflight$
DECLARE
  v_missing text[];
  v_bucket record;
  v_insert_policies integer;
  v_select_policies integer;
  v_delete_policies integer;
  v_table text;
  v_role text;
  v_privilege text;
  v_policy record;
  v_expression text;
  v_bucket_policy_count integer;
BEGIN
  IF pg_catalog.to_regprocedure('public.current_firebase_uid()') IS NULL
     OR pg_catalog.to_regprocedure(
       'public.is_educflow_firebase_user()'
     ) IS NULL THEN
    RAISE EXCEPTION 'ocr_testing_missing_firebase_identity_functions';
  END IF;

  IF POSITION(
    'eduflow-ai-testing' IN pg_catalog.pg_get_functiondef(
      pg_catalog.to_regprocedure('public.is_educflow_firebase_user()')
    )
  ) = 0 THEN
    RAISE EXCEPTION 'ocr_testing_wrong_firebase_project_identity';
  END IF;

  IF NOT pg_catalog.has_function_privilege(
    'authenticated', 'public.current_firebase_uid()', 'EXECUTE'
  ) OR NOT pg_catalog.has_function_privilege(
    'authenticated', 'public.is_educflow_firebase_user()', 'EXECUTE'
  ) OR pg_catalog.has_function_privilege(
    'anon', 'public.current_firebase_uid()', 'EXECUTE'
  ) OR pg_catalog.has_function_privilege(
    'anon', 'public.is_educflow_firebase_user()', 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'ocr_testing_firebase_identity_function_permissions_invalid';
  END IF;

  SELECT pg_catalog.array_agg(candidate.object_name ORDER BY candidate.object_name)
    INTO v_missing
    FROM (
      VALUES
        ('public.ocr_cache', 'r'),
        ('public.ocr_usage', 'r'),
        ('public.ocr_monthly_usage', 'r'),
        ('public.ocr_daily_user_usage', 'r')
    ) AS candidate(object_name, expected_kind)
   WHERE pg_catalog.to_regclass(candidate.object_name) IS NULL;

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION USING
      MESSAGE = 'ocr_testing_missing_backend_objects',
      DETAIL = pg_catalog.array_to_string(v_missing, ', ');
  END IF;

  IF pg_catalog.to_regprocedure(
    'public.reserve_ocr_vision_usage(text,integer,integer,integer)'
  ) IS NULL THEN
    RAISE EXCEPTION 'ocr_testing_missing_reserve_rpc';
  END IF;

  FOREACH v_table IN ARRAY ARRAY[
    'public.ocr_cache',
    'public.ocr_usage',
    'public.ocr_monthly_usage',
    'public.ocr_daily_user_usage'
  ] LOOP
    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
      FOREACH v_privilege IN ARRAY ARRAY[
        'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE',
        'REFERENCES', 'TRIGGER'
      ] LOOP
        IF pg_catalog.has_table_privilege(v_role, v_table, v_privilege) THEN
          RAISE EXCEPTION USING
            MESSAGE = 'ocr_testing_internal_table_exposed_to_client',
            DETAIL = v_role || ' tiene ' || v_privilege || ' sobre ' || v_table;
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;

  IF pg_catalog.has_function_privilege(
       'anon',
       'public.reserve_ocr_vision_usage(text,integer,integer,integer)',
       'EXECUTE'
     )
     OR pg_catalog.has_function_privilege(
       'authenticated',
       'public.reserve_ocr_vision_usage(text,integer,integer,integer)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'ocr_testing_reserve_rpc_exposed_to_clients';
  END IF;

  IF NOT pg_catalog.has_function_privilege(
    'service_role',
    'public.reserve_ocr_vision_usage(text,integer,integer,integer)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'ocr_testing_service_role_cannot_reserve_quota';
  END IF;

  SELECT id, name, public, file_size_limit, allowed_mime_types
    INTO v_bucket
    FROM storage.buckets
   WHERE id = 'ocr-temp';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ocr_testing_missing_private_bucket';
  END IF;

  IF v_bucket.name <> 'ocr-temp' OR v_bucket.public THEN
    RAISE EXCEPTION 'ocr_testing_bucket_must_be_private';
  END IF;

  IF v_bucket.file_size_limit IS DISTINCT FROM 10485760 THEN
    RAISE EXCEPTION 'ocr_testing_bucket_limit_must_be_10_mib';
  END IF;

  IF v_bucket.allowed_mime_types IS NULL
     OR NOT v_bucket.allowed_mime_types @> ARRAY[
       'image/jpeg',
       'image/png',
       'image/webp',
       'application/pdf'
     ]::text[]
     OR pg_catalog.cardinality(v_bucket.allowed_mime_types) <> 4 THEN
    RAISE EXCEPTION 'ocr_testing_bucket_mime_types_are_not_exact';
  END IF;

  SELECT pg_catalog.count(*)
    INTO v_select_policies
    FROM pg_catalog.pg_policies
   WHERE schemaname = 'storage'
     AND tablename = 'objects'
     AND cmd IN ('SELECT', 'ALL')
     AND 'authenticated' = ANY(roles)
     AND COALESCE(qual, '') LIKE '%ocr-temp%'
     AND COALESCE(qual, '') LIKE '%current_firebase_uid%'
     AND COALESCE(qual, '') LIKE '%is_educflow_firebase_user%';

  IF v_select_policies = 0 THEN
    RAISE EXCEPTION 'ocr_testing_missing_uid_scoped_select_policy';
  END IF;

  SELECT pg_catalog.count(*)
    INTO v_insert_policies
    FROM pg_catalog.pg_policies
   WHERE schemaname = 'storage'
     AND tablename = 'objects'
     AND cmd IN ('INSERT', 'ALL')
     AND 'authenticated' = ANY(roles)
     AND COALESCE(with_check, '') LIKE '%ocr-temp%'
     AND COALESCE(with_check, '') LIKE '%current_firebase_uid%'
     AND COALESCE(with_check, '') LIKE '%is_educflow_firebase_user%';

  IF v_insert_policies = 0 THEN
    RAISE EXCEPTION 'ocr_testing_missing_uid_scoped_insert_policy';
  END IF;

  SELECT pg_catalog.count(*)
    INTO v_delete_policies
    FROM pg_catalog.pg_policies
   WHERE schemaname = 'storage'
     AND tablename = 'objects'
     AND cmd IN ('DELETE', 'ALL')
     AND 'authenticated' = ANY(roles)
     AND COALESCE(qual, '') LIKE '%ocr-temp%'
     AND COALESCE(qual, '') LIKE '%current_firebase_uid%'
     AND COALESCE(qual, '') LIKE '%is_educflow_firebase_user%';

  IF v_delete_policies = 0 THEN
    RAISE EXCEPTION 'ocr_testing_missing_uid_scoped_delete_policy';
  END IF;

  SELECT pg_catalog.count(*)
    INTO v_bucket_policy_count
    FROM pg_catalog.pg_policies
   WHERE schemaname = 'storage'
     AND tablename = 'objects'
     AND (
       COALESCE(qual, '') LIKE '%ocr-temp%'
       OR COALESCE(with_check, '') LIKE '%ocr-temp%'
     );

  IF v_bucket_policy_count <> 3 THEN
    RAISE EXCEPTION 'ocr_testing_bucket_must_have_exactly_three_policies';
  END IF;

  FOR v_policy IN
    SELECT policyname, cmd, roles, qual, with_check
      FROM pg_catalog.pg_policies
     WHERE schemaname = 'storage'
       AND tablename = 'objects'
       AND cmd IN ('SELECT', 'INSERT', 'DELETE', 'ALL')
       AND ('authenticated' = ANY(roles) OR 'public' = ANY(roles))
  LOOP
    v_expression := COALESCE(v_policy.qual, '') || ' ' ||
      COALESCE(v_policy.with_check, '');

    IF v_expression LIKE '%ocr-temp%' AND (
      v_expression NOT LIKE '%current_firebase_uid%'
      OR v_expression NOT LIKE '%is_educflow_firebase_user%'
    ) THEN
      RAISE EXCEPTION USING
        MESSAGE = 'ocr_testing_bucket_policy_is_not_uid_scoped',
        DETAIL = v_policy.policyname;
    END IF;

    IF v_expression !~* 'bucket_id\s*=\s*''[^'']+'''
       OR v_expression ~* '(^|[^a-z])(or|any|in)([^a-z]|$)'
       OR v_expression ~* '(< >|<>|!=|is\s+null|is\s+not\s+null)' THEN
      RAISE EXCEPTION USING
        MESSAGE = 'ocr_testing_storage_policy_scope_requires_review',
        DETAIL = v_policy.policyname;
    END IF;
  END LOOP;
END;
$preflight$;

-- Evidencia revisable: las expresiones deben restringir bucket_id a ocr-temp
-- y la primera carpeta a current_firebase_uid(). El preflight anterior exige
-- esos elementos, pero la revisión humana sigue siendo necesaria antes del
-- primer archivo real.
SELECT policyname, roles, cmd, qual, with_check
  FROM pg_catalog.pg_policies
 WHERE schemaname = 'storage'
   AND tablename = 'objects'
   AND (
     COALESCE(qual, '') LIKE '%ocr-temp%'
     OR COALESCE(with_check, '') LIKE '%ocr-temp%'
   )
 ORDER BY policyname;

SELECT id, name, public, file_size_limit, allowed_mime_types
  FROM storage.buckets
 WHERE id = 'ocr-temp';

ROLLBACK;
