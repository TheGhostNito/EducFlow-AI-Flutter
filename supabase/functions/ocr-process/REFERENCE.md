# Procedencia de la fuente OCR

- Referencia recibida: `ocr_process_produccion_referencia_20261118.ts`.
- Origen declarado: copia manual desde el Dashboard de Supabase Producción.
- Fecha del archivo: 2026-11-18 15:03:28 (America/Santiago).
- SHA-256 del archivo recibido:
  `440B7E9128090A4A495AF8ECD78EBB7B5BDFD926B1CE3A479D1331071969F215`.

La copia permite preparar y probar cambios locales, pero no certifica por sí
sola que sea idéntica a la versión actualmente desplegada. Antes de desplegar se
debe volver a comparar con el Dashboard o con metadatos de la versión remota.
`index.ts` conserva la lógica recuperada y solo añade la orquestación de
limpieza temporal, puntos de prueba y tres aserciones de tipo sin efecto en
tiempo de ejecución necesarias para que la fuente recuperada supere
`deno check`.

## Identidad Firebase por entorno

`ocr-process` acepta exactamente un proyecto Firebase por despliegue mediante
`EDUFLOW_FIREBASE_PROJECT_ID`:

- Producción: `educflow-ai`. Si la variable no existe se conserva este valor
  histórico, por compatibilidad y para que Producción nunca admita Testing por
  omisión.
- Testing: `eduflow-ai-testing`. Debe configurarse explícitamente antes del
  despliegue de la función en el proyecto Supabase Testing.

La lista es cerrada. Los valores vacíos, múltiples o desconocidos impiden que
la función se inicie. Además, la función cruza esa identidad con el project ref
de `SUPABASE_URL`: Testing y Producción no pueden intercambiar sus identidades
aunque el secreto se configure incorrectamente. La variable no cambia el contrato HTTP, el parser de
mallas, la propiedad por UID, las cuotas ni la limpieza temporal.

## Configuración requerida en Supabase Testing

Antes de desplegar o consumir Vision se debe confirmar, sin exponer valores:

- secretos automáticos `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY`;
- `EDUFLOW_FIREBASE_PROJECT_ID=eduflow-ai-testing`;
- `GOOGLE_CLOUD_PROJECT_ID`, `GOOGLE_CLOUD_CLIENT_EMAIL` y
  `GOOGLE_CLOUD_PRIVATE_KEY` correspondientes a una cuenta con el permiso
  mínimo necesario para Vision;
- bucket privado `ocr-temp` y políticas de carga/borrado que limiten la primera
  carpeta al UID Firebase autenticado;
- tablas `ocr_cache`, `ocr_usage`, `ocr_monthly_usage`,
  `ocr_daily_user_usage` y RPC `reserve_ocr_vision_usage` con los permisos
  validados por `supabase/tests/ocr_backend_testing_validation.sql`.

Los secretos de una Edge Function no pueden certificarse mediante una consulta
SQL y nunca deben imprimirse. Su presencia debe revisarse en el inventario de
secretos del proyecto Testing; la autenticación real se valida después con un
ID token emitido por Firebase Testing. Las pruebas unitarias solo validan la
selección estricta de issuer/audience y no sustituyen esa comprobación.
