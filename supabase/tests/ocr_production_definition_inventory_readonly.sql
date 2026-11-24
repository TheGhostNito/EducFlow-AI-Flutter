-- Inventario de solo lectura para contrastar la definición OCR real de
-- Producción. No crea, modifica ni elimina objetos o datos.
-- Ejecutar por separado en Producción únicamente si se autoriza la consulta.

BEGIN TRANSACTION READ ONLY;

SELECT
  columns.table_name,
  columns.ordinal_position,
  columns.column_name,
  columns.data_type,
  columns.udt_name,
  columns.is_nullable,
  columns.column_default,
  columns.is_identity,
  columns.identity_generation
FROM information_schema.columns AS columns
WHERE columns.table_schema = 'public'
  AND columns.table_name IN (
    'ocr_cache',
    'ocr_usage',
    'ocr_monthly_usage',
    'ocr_daily_user_usage'
  )
ORDER BY columns.table_name, columns.ordinal_position;

SELECT
  namespace.nspname AS schema_name,
  relation.relname AS table_name,
  constraint_definition.conname AS constraint_name,
  constraint_definition.contype AS constraint_type,
  pg_catalog.pg_get_constraintdef(constraint_definition.oid, true) AS definition
FROM pg_catalog.pg_constraint AS constraint_definition
JOIN pg_catalog.pg_class AS relation
  ON relation.oid = constraint_definition.conrelid
JOIN pg_catalog.pg_namespace AS namespace
  ON namespace.oid = relation.relnamespace
WHERE namespace.nspname = 'public'
  AND relation.relname IN (
    'ocr_cache',
    'ocr_usage',
    'ocr_monthly_usage',
    'ocr_daily_user_usage'
  )
ORDER BY relation.relname, constraint_definition.conname;

SELECT
  index_definition.tablename,
  index_definition.indexname,
  index_definition.indexdef
FROM pg_catalog.pg_indexes AS index_definition
WHERE index_definition.schemaname = 'public'
  AND index_definition.tablename IN (
    'ocr_cache',
    'ocr_usage',
    'ocr_monthly_usage',
    'ocr_daily_user_usage'
  )
ORDER BY index_definition.tablename, index_definition.indexname;

SELECT
  procedure.proname,
  pg_catalog.pg_get_userbyid(procedure.proowner) AS owner,
  procedure.prosecdef AS security_definer,
  procedure.proconfig,
  procedure.proacl,
  pg_catalog.pg_get_functiondef(procedure.oid) AS definition
FROM pg_catalog.pg_proc AS procedure
JOIN pg_catalog.pg_namespace AS namespace
  ON namespace.oid = procedure.pronamespace
WHERE namespace.nspname = 'public'
  AND procedure.oid = pg_catalog.to_regprocedure(
    'public.reserve_ocr_vision_usage(text,integer,integer,integer)'
  );

SELECT
  namespace.nspname AS schema_name,
  relation.relname AS table_name,
  relation.relrowsecurity AS rls_enabled,
  relation.relforcerowsecurity AS rls_forced,
  relation.relacl
FROM pg_catalog.pg_class AS relation
JOIN pg_catalog.pg_namespace AS namespace
  ON namespace.oid = relation.relnamespace
WHERE namespace.nspname = 'public'
  AND relation.relname IN (
    'ocr_cache',
    'ocr_usage',
    'ocr_monthly_usage',
    'ocr_daily_user_usage'
  )
ORDER BY relation.relname;

SELECT id, name, public, file_size_limit, allowed_mime_types
FROM storage.buckets
WHERE id = 'ocr-temp';

SELECT policyname, roles, cmd, qual, with_check
FROM pg_catalog.pg_policies
WHERE schemaname = 'storage'
  AND tablename = 'objects'
ORDER BY policyname;

ROLLBACK;
