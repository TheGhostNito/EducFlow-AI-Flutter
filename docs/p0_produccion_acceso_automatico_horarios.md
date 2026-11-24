# P0 Producción: acceso automático a horarios

## Estado verificado el 23/11/2026

La migración `202611230002` fue aplicada y validada en Supabase Producción
con una cuenta Firebase nueva. La prueba confirmó autorización automática,
importación real, guardado y persistencia sin insertar una autorización
manual. No se debe volver a ejecutar la migración para preparar las versiones
oficiales.

La tabla `horario_importacion_autorizaciones` se conserva como control
administrativo para bloqueos excepcionales, temporales o permanentes; no es
una lista blanca que el cliente deba completar.

La configuración cliente productiva es coherente:

- Firebase: `educflow-ai`;
- issuer esperado: `https://securetoken.google.com/educflow-ai`;
- Supabase: `ubjmdfwkjgblnjgmufpc`;
- Android: `com.martinrozas.eduflowai`;
- importación y documentos originales habilitados;
- la aplicación solicita un ID token Firebase y exige el claim
  `role=authenticated` antes de preparar la sesión Supabase.

La migración `202611230002` no contiene identificadores de Testing ni de
Producción. Reutiliza `is_educflow_firebase_user()` y
`current_firebase_uid()`, por lo que es compatible con Producción solamente si
esas funciones desplegadas validan el proyecto `educflow-ai`. El preflight
preparado comprueba ese contrato y falla si detecta Testing.

## Separación obligatoria de `firebase-role`

El repositorio y su historial no contienen la fuente productiva desplegada de
`firebase-role`. La única fuente local disponible es no versionada y está
fijada a `eduflow-ai-testing`; no debe reutilizarse ni desplegarse en
Producción.

La validación productiva realizada antes de aplicar la P0 debía confirmar:

1. existe en Supabase Producción y no es la variante Testing;
2. la cuenta de servicio pertenece exactamente a `educflow-ai`;
3. usa Firebase Admin para `verifyIdToken(token, true)`;
4. rechaza `aud` distinto de `educflow-ai`;
5. rechaza `iss` distinto de
   `https://securetoken.google.com/educflow-ai`;
6. exige UID no vacío y coherencia `uid = sub`;
7. consulta el usuario y rechaza cuentas deshabilitadas;
8. conserva claims existentes y agrega únicamente `role=authenticated`;
9. devuelve `refreshToken=true` cuando modifica claims;
10. no registra tokens, UIDs, claims ni credenciales;
11. el secreto de cuenta de servicio no es el de Testing.

Estas comprobaciones siguen siendo requisitos para cualquier cambio futuro de
identidad. Insertar manualmente un UID no es una alternativa al contrato de
autenticación ya validado.

## SQL preparado

1. Preflight productivo de solo lectura:
   `supabase/production/20261123_01_preflight_acceso_automatico_horario.sql`.
2. Respaldo/inventario previo de solo lectura:
   `supabase/production/20261123_02_respaldo_previo_acceso_horario.sql`.
3. Migración transaccional:
   `supabase/migrations/202611230002_acceso_automatico_importacion_horario.sql`.
4. Validación posterior de solo lectura:
   `supabase/production/20261123_03_validacion_posterior_acceso_automatico_horario.sql`.
5. Reversión transaccional:
   `supabase/rollbacks/202611230002_acceso_automatico_importacion_horario_rollback.sql`.

## Procedimiento histórico de aplicación (no repetir)

Se conserva para auditoría y reversión. La migración ya fue aplicada; no
volver a ejecutar estos pasos para compilar o publicar las aplicaciones.

### 1. Confirmar proyecto y Edge Function

En el panel de Supabase comprobar que el project ref visible sea
`ubjmdfwkjgblnjgmufpc`. Revisar `firebase-role` con la lista anterior. No
continuar si aparece `oxrvksaljxcwdhkeapej` o `eduflow-ai-testing`.

### 2. Ejecutar preflight

Ejecutar completo
`20261123_01_preflight_acceso_automatico_horario.sql`. Debe terminar con:

`Supabase Producción compatible con 202611230002`

El script comprueba identidad Firebase, dependencias, propietarios,
`SECURITY DEFINER`, `search_path`, grants, RLS, Storage, cuotas y que todavía
esté instalada la lista blanca anterior.

### 3. Guardar respaldo

Ejecutar completo
`20261123_02_respaldo_previo_acceso_horario.sql` y descargar el resultado en
un lugar privado. Registra definiciones, políticas, grants implícitos en ACL,
buckets y conteos agregados de autorizaciones; no exporta UIDs ni datos
académicos.

Registrar por separado la hora UTC de aplicación y el conteo de filas de:

- `importaciones_horario`;
- `importacion_horario_asignaturas`;
- `horario_importacion_autorizaciones`.

No modificar ninguna fila.

### 4. Aplicar migración

Ejecutar completo
`202611230002_acceso_automatico_importacion_horario.sql`.

La transacción reemplaza exclusivamente
`uid_importacion_horario_autorizado()`, sus comentarios y grants. No modifica
horarios, autorizaciones existentes, OCR, cuotas ni políticas.

### 5. Validar estructura

Ejecutar completo
`20261123_03_validacion_posterior_acceso_automatico_horario.sql`. Debe terminar
con:

`Acceso automático productivo validado estructuralmente`

Comparar los conteos agregados con el respaldo. Deben ser idénticos.

### 6. Prueba real sin OCR

Crear una cuenta Firebase productiva descartable completamente nueva. No
utilizar cuentas existentes ni insertar autorizaciones.

Para mostrar temporalmente la herramienta P0 en Production Debug:

```powershell
flutter run -d emulator-5554 --flavor production `
  --dart-define-from-file=config/ocr_integrated_production.json `
  --dart-define=EDUFLOW_P0_HORARIO_DIAGNOSTIC_ENABLED=true
```

Comprobar primero “Solo autorización” y luego “Probar y limpiar”. La prueba
debe obtener el UID real, confirmar/listar una importación sintética y
eliminarla. Si la limpieza falla, detenerse y usar el ID informado.

La herramienta está protegida además por `kDebugMode`; no aparece en Release.
Después de la prueba, volver a ejecutar sin el último `--dart-define`.

### 7. Única prueba OCR integral

Solo después de aprobar la prueba sin OCR:

1. usar la misma cuenta productiva nueva;
2. importar un único horario real mediante el flujo normal;
3. confirmar revisión humana y guardado;
4. cerrar completamente y reabrir la aplicación;
5. comprobar Asignaturas, Horario y Calendario;
6. eliminar la importación mediante el flujo normal si la cuenta es
   descartable;
7. revisar cuota y errores sin modificar los registros de otras cuentas.

## Reversión

Si falla el postflight o la prueba real:

1. detener nuevas pruebas;
2. conservar evidencia y definición actual;
3. ejecutar completo
   `202611230002_acceso_automatico_importacion_horario_rollback.sql`;
4. comprobar que la definición vuelve a contener
   `importacion_horario_no_autorizada`;
5. confirmar que los conteos de datos permanecen iguales;
6. una cuenta sin fila debe volver a ser rechazada y una cuenta habilitada
   debe conservar acceso.

La reversión no elimina datos, pero restaura la lista blanca manual. Las filas
administrativas existentes permanecen intactas durante aplicación y reversión.

## Controles conservados y riesgos

Se conservan issuer/audience/rol/UID, RLS, aislamiento por UID, bloqueos
administrativos, límites de payload, idempotencia, cuota diaria por UID, cuota
mensual global y buckets privados.

Riesgos que la migración no corrige:

- App Check no se verifica en las Edge Functions locales auditadas;
- no hay rate limit SQL propio para confirmaciones;
- no hay cuota acumulada de documentos/importaciones por UID;
- la fuente local de `firebase-role` sigue siendo exclusiva de Testing y no
  debe desplegarse en Producción; cualquier cambio futuro debe compararse con
  la implementación productiva real antes de desplegarse.
