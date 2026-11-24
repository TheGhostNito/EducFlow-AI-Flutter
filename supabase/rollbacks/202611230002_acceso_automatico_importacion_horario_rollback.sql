-- Reversión de 202611230002_acceso_automatico_importacion_horario.sql.
-- ATENCIÓN: restaura la lista blanca manual y volverá a bloquear cualquier UID
-- sin una autorización habilitada y vigente.

begin;

create or replace function public.uid_importacion_horario_autorizado()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text;
begin
  if public.is_educflow_firebase_user() is distinct from true then
    raise exception using
      errcode = '42501',
      message = 'usuario_firebase_no_valido';
  end if;

  v_uid := public.current_firebase_uid();
  if v_uid is null or pg_catalog.btrim(v_uid) = '' then
    raise exception using
      errcode = '42501',
      message = 'uid_firebase_no_valido';
  end if;

  if not exists (
    select 1
    from public.horario_importacion_autorizaciones as permiso
    where permiso.usuario_uid = v_uid
      and permiso.habilitado
      and (
        permiso.expira_en is null
        or permiso.expira_en > pg_catalog.now()
      )
  ) then
    raise exception using
      errcode = '42501',
      message = 'importacion_horario_no_autorizada';
  end if;

  return v_uid;
end;
$$;

comment on function public.uid_importacion_horario_autorizado() is
  'Devuelve el UID Firebase únicamente cuando existe una autorización administrativa habilitada y vigente.';

comment on table public.horario_importacion_autorizaciones is
  'Lista blanca administrativa de cuentas autorizadas para importar horarios.';

revoke all on function public.uid_importacion_horario_autorizado()
  from public, anon, authenticated;
grant execute on function public.uid_importacion_horario_autorizado()
  to authenticated;

commit;
