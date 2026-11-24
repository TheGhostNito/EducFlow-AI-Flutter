-- P0 EducFlow AI: evidencia previa de Supabase Producción.
-- SOLO LECTURA. No exporta documentos ni datos académicos.

begin transaction read only;

select
  procedure.oid::pg_catalog.regprocedure as firma,
  pg_catalog.pg_get_userbyid(procedure.proowner) as propietario,
  procedure.prosecdef as security_definer,
  procedure.proconfig,
  procedure.proacl,
  pg_catalog.pg_get_functiondef(procedure.oid) as definicion
from pg_catalog.pg_proc as procedure
join pg_catalog.pg_namespace as namespace
  on namespace.oid = procedure.pronamespace
where namespace.nspname = 'public'
  and procedure.oid in (
    'public.current_firebase_uid()'::pg_catalog.regprocedure,
    'public.is_educflow_firebase_user()'::pg_catalog.regprocedure,
    'public.uid_importacion_horario_autorizado()'::pg_catalog.regprocedure,
    'public.confirmar_importacion_horario(jsonb)'::pg_catalog.regprocedure,
    'public.listar_importaciones_horario()'::pg_catalog.regprocedure,
    'public.eliminar_importacion_horario(text)'::pg_catalog.regprocedure,
    'public.confirmar_importacion_horario_con_documento(jsonb)'::
      pg_catalog.regprocedure,
    'public.asociar_documento_importacion_horario(text,jsonb)'::
      pg_catalog.regprocedure,
    'public.listar_importaciones_horario_con_documento()'::
      pg_catalog.regprocedure,
    'public.eliminar_importacion_horario_con_documento(text)'::
      pg_catalog.regprocedure,
    'public.reserve_ocr_vision_usage(text,integer,integer,integer)'::
      pg_catalog.regprocedure
  )
order by procedure.oid::pg_catalog.regprocedure::text;

select schemaname, tablename, policyname, permissive, roles, cmd, qual,
       with_check
from pg_catalog.pg_policies
where (schemaname = 'public' and tablename in (
  'importaciones_horario',
  'importacion_horario_asignaturas',
  'horario_importacion_autorizaciones'
)) or (schemaname = 'storage' and tablename = 'objects' and (
  coalesce(qual, '') like '%horarios-originales%'
  or coalesce(with_check, '') like '%horarios-originales%'
))
order by schemaname, tablename, policyname;

select
  pg_catalog.count(*) as total,
  pg_catalog.count(*) filter (where habilitado) as habilitadas,
  pg_catalog.count(*) filter (where not habilitado) as deshabilitadas,
  pg_catalog.count(*) filter (
    where expira_en is not null and expira_en <= pg_catalog.now()
  ) as expiradas
from public.horario_importacion_autorizaciones;

select id, name, public, file_size_limit, allowed_mime_types
from storage.buckets
where id in ('ocr-temp', 'horarios-originales')
order by id;

rollback;
