-- Acceso automático y aislado a la importación de horarios.
-- PREPARADA LOCALMENTE: no ejecutar sin validar primero en Supabase Testing.
-- Depende de 202611220001_importaciones_horario_atomicas.sql.

begin;

-- Conserva el nombre usado por todas las RPC y políticas existentes, pero
-- elimina la lista blanca manual. La identidad continúa derivándose solamente
-- del JWT Firebase validado por las funciones de identidad de EducFlow AI.
--
-- horario_importacion_autorizaciones queda como control administrativo de
-- suspensión: únicamente una fila deshabilitada y vigente bloquea al UID. El
-- cliente no tiene privilegios sobre esa tabla y no puede habilitarse ni
-- bloquear a otras cuentas.
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

  if exists (
    select 1
    from public.horario_importacion_autorizaciones as control
    where control.usuario_uid = v_uid
      and control.habilitado is false
      and (
        control.expira_en is null
        or control.expira_en > pg_catalog.now()
      )
  ) then
    raise exception using
      errcode = '42501',
      message = 'importacion_horario_bloqueada';
  end if;

  return v_uid;
end;
$$;

comment on function public.uid_importacion_horario_autorizado() is
  'Devuelve el UID Firebase validado. Las cuentas acceden automáticamente; una fila administrativa deshabilitada y vigente bloquea la importación.';

comment on table public.horario_importacion_autorizaciones is
  'Control administrativo opcional de importación. La ausencia de fila permite acceso; habilitado=false bloquea al UID mientras la fila esté vigente.';

revoke all on function public.uid_importacion_horario_autorizado()
  from public, anon, authenticated;
grant execute on function public.uid_importacion_horario_autorizado()
  to authenticated;

commit;
