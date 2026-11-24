# P0: acceso automático a la importación de horarios

## Resultado esperado

Una cuenta Firebase válida, con la preparación normal de sesión completada,
puede confirmar, listar y eliminar sus importaciones sin una fila previa en
`horario_importacion_autorizaciones`.

La identidad no se recibe como parámetro de las RPC. Se obtiene mediante
`is_educflow_firebase_user()` y `current_firebase_uid()` desde el JWT Firebase
validado. Las RPC y políticas RLS continúan comparando los datos con ese UID.

`horario_importacion_autorizaciones` queda como control de suspensión:

- ausencia de fila: acceso automático;
- `habilitado = true`: acceso permitido;
- `habilitado = false` sin expiración: bloqueo permanente;
- `habilitado = false` con `expira_en` futura: bloqueo temporal;
- `habilitado = false` con `expira_en` pasada: acceso permitido nuevamente.

Solo `service_role` conserva permisos de escritura sobre esta tabla. El
cliente no puede concederse acceso, retirar un bloqueo ni actuar por otro UID.

## Archivos preparados

- Migración: `supabase/migrations/202611230002_acceso_automatico_importacion_horario.sql`.
- Reversión: `supabase/rollbacks/202611230002_acceso_automatico_importacion_horario_rollback.sql`.
- Validación estructural: `supabase/tests/horario_importacion_acceso_automatico_validation.sql`.
- Preflight de Testing: `supabase/testing/20261123_08_preflight_acceso_automatico_horario.sql`.
- Prueba SQL reversible: `supabase/testing/20261123_09_prueba_acceso_automatico_horario.sql`.

Ninguno de estos archivos se ha ejecutado contra Supabase.

## Controles que se conservan

- validación del issuer/audience y UID Firebase mediante las funciones de
  identidad ya usadas por el resto del backend;
- rol `authenticated`; `anon` no puede ejecutar las RPC;
- RLS de lectura por `usuario_uid = current_firebase_uid()`;
- UID derivado del JWT dentro de las RPC `SECURITY DEFINER` con
  `search_path = ''`;
- claves compuestas y filtros por UID en importaciones, asignaturas, períodos,
  bloques y sesiones;
- idempotencia por `(usuario_uid, document_hash)`;
- bloqueo transaccional por UID y validación estricta del payload;
- límites de 100 asignaturas, 100 bloques/sesiones por asignatura y 1000
  bloques/sesiones totales;
- bucket privado, rutas cuyo primer segmento es el UID y documentos de hasta
  10 MiB;
- cuotas OCR diaria por UID y mensual global, reservadas exclusivamente por
  `service_role`.

## Control faltante detectado

Flutter activa Firebase App Check, pero la fuente local de las Edge Functions
`ocr-process` y `firebase-role` no recibe ni valida un token App Check. Por lo
tanto, App Check no está aplicado de extremo a extremo en esa fuente. El ID
token Firebase, la vinculación de ruta al UID y las cuotas sí se validan.

La migración P0 no reduce ni altera estos controles, pero tampoco corrige esa
carencia porque hacerlo requiere cambiar y desplegar Edge Functions. Debe
tratarse como bloqueo antes de abrir el servicio al público general, no como
un cambio de último minuto en el motor OCR antes de la demostración.

Además, la fuente local de `supabase/functions/firebase-role/index.ts` está
fijada al proyecto `eduflow-ai-testing`. La aplicación necesita esa función
para añadir el claim `role=authenticated` a una cuenta nueva antes de usar
Supabase. No es posible concluir solo desde el repositorio que la función
desplegada en Producción tenga un contrato equivalente para `educflow-ai`.
Antes de la APK oficial se debe inventariar en modo de solo lectura la función
productiva o probar el registro completo con una cuenta nueva; no debe
desplegarse esta fuente de Testing en Producción.

Las cuotas existentes limitan el consumo de Google Vision, pero las RPC SQL
de confirmación no tienen una cuota propia por cantidad de importaciones o por
ventana de tiempo. Sus límites actuales son de tamaño por payload,
idempotencia por hash y serialización por UID. Un cliente autenticado que
evitara el OCR podría intentar muchos hashes distintos directamente contra la
RPC. Esto no impide la demostración controlada, pero es otro control de abuso
que debe diseñarse antes de la apertura pública.

La protección efectiva actual frente a abuso queda así:

- `firebase-role` verifica el ID token con Firebase Admin, incluida revocación
  y cuenta deshabilitada, antes de asignar `role=authenticated`;
- `ocr-process` verifica firma RS256, `issuer`, `audience`, tiempos y UID, pero
  no consulta revocación ni estado deshabilitado en cada solicitud;
- el OCR limita archivos a 10 MiB, PDF a cinco páginas, tipos MIME conocidos y
  rutas bajo el UID autenticado;
- Google Vision está limitado a 10 unidades diarias por UID y 800 mensuales
  globales; los aciertos de caché no reservan cuota porque no consumen Vision;
- el límite global contiene el coste, pero crear muchas cuentas permite
  repartir el límite diario y App Check ausente facilita automatización;
- el guardado SQL y `horarios-originales` no tienen límite por frecuencia,
  número de importaciones ni almacenamiento acumulado por UID.

Para la demostración controlada estos límites contienen el coste OCR, pero no
son suficientes para apertura pública sin App Check verificado en servidor,
rate limiting por identidad/IP y cuotas de almacenamiento/importaciones.

## Procedimiento exacto para Supabase Testing

Requiere autorización explícita antes de ejecutar cualquier paso remoto.
Todos los archivos deben abrirse desde el repositorio y ejecutarse completos,
sin copiar fragmentos ni sustituir UIDs manualmente.

### 1. Confirmar el entorno

En el panel de Supabase comprobar visualmente que el proyecto seleccionado es
`oxrvksaljxcwdhkeapej`. No continuar si aparece
`ubjmdfwkjgblnjgmufpc`, que corresponde a Producción.

Ejecutar completo:

`supabase/testing/20261123_08_preflight_acceso_automatico_horario.sql`

El script usa una transacción de solo lectura y debe devolver
`Supabase Testing listo para 202611230002`. Entre otras cosas comprueba:

- issuer, audience, rol y `sub` de Firebase Testing;
- dependencias académicas y RPC de importación;
- `SECURITY DEFINER`, propietario `postgres` y `search_path` vacío;
- RLS por UID y ausencia de privilegios administrativos del cliente;
- bucket privado y política de ruta por UID;
- cuotas OCR accesibles solamente mediante `service_role`;
- presencia de la lista blanca anterior, para detectar una aplicación previa.

### 2. Guardar evidencia anterior

Antes de cambiar nada, ejecutar y guardar el resultado:

   ```sql
   select pg_catalog.pg_get_functiondef(
     'public.uid_importacion_horario_autorizado()'::pg_catalog.regprocedure
   );

   select usuario_uid, habilitado, expira_en, comentario,
          creada_en, actualizada_en
   from public.horario_importacion_autorizaciones
   order by usuario_uid;
   ```

No exportar ni compartir UIDs fuera del equipo autorizado.

### 3. Aplicar la migración

Ejecutar completo:

`supabase/migrations/202611230002_acceso_automatico_importacion_horario.sql`

La transacción solo reemplaza una función y sus comentarios/permisos. No
inserta autorizaciones, no modifica horarios y no altera el OCR.

### 4. Validar estructura y comportamiento SQL

Ejecutar, en este orden:

1. `supabase/tests/horario_importacion_acceso_automatico_validation.sql`.
2. `supabase/testing/20261123_09_prueba_acceso_automatico_horario.sql`.
3. `supabase/tests/ocr_backend_testing_validation.sql`.

Los tres deben finalizar sin excepciones. Los dos últimos realizan escrituras
sintéticas dentro de transacciones que terminan en `ROLLBACK`; no deben dejar
usuarios, horarios ni consumo reservado.

La segunda prueba crea dos UIDs sintéticos sin lista blanca, guarda y repite
una importación, comprueba cruce de cuentas, bloqueo/expiración, token de
Producción rechazado, falta de rol y acceso anónimo. Los claims son simulados:
esto no prueba firma JWT ni `firebase-role`.

### 5. Validar `firebase-role` con una cuenta real

Usar Android Testing, nunca la APK de Producción:

```powershell
flutter run --flavor validation `
  --dart-define-from-file=config/android_testing.local.json
```

1. Registrar desde la aplicación una cuenta Firebase Testing A con correo
   único y completar el inicio de sesión.
2. La preparación de sesión debe invocar `firebase-role`; esta función debe
   validar el token contra `eduflow-ai-testing`, comprobar revocación/estado,
   asignar `role=authenticated` y forzar la renovación del ID token.
3. Antes de importar, localizar administrativamente el UID por el correo y
   ejecutar:

   ```sql
   select u.uid, a.habilitado, a.expira_en
   from public.usuarios as u
   left join public.horario_importacion_autorizaciones as a
     on a.usuario_uid = u.uid
   where u.correo_principal = '<CORREO_TESTING_A>';
   ```

   Debe existir `usuarios`, pero `habilitado` y `expira_en` deben ser `NULL`.
   No insertar ninguna autorización.
4. Importar un horario de prueba no perteneciente a las cuentas de
   demostración y guardarlo. Cerrar completamente la aplicación, reabrir y
   comprobar Horario, Asignaturas y Calendario.
5. Reintentar el mismo documento. Debe reutilizar la importación y no duplicar
   período, asignaturas, bloques ni sesiones.

Si el registro no supera la preparación de sesión, detener la prueba: el
problema está en `firebase-role`/claims y no debe compensarse insertando una
autorización de horarios.

### 6. Cuenta B, bloqueo y cruce real

1. Crear una segunda cuenta Firebase Testing B, también sin fila
   administrativa.
2. Confirmar que B puede listar sus propias importaciones y no ve la de A.
3. Conservar el ID de la importación de A e intentar eliminarlo usando la
   sesión de B. Debe responder `importacion_horario_no_encontrada` y los datos
   de A deben permanecer.
4. Crear para B una fila administrativa con `habilitado=false` usando la
   consulta de bloqueo temporal documentada más abajo.
5. B debe recibir `importacion_horario_bloqueada` al listar, confirmar,
   asociar documento o eliminar.
6. Eliminar esa única fila de bloqueo. B debe recuperar acceso sin crear una
   fila `habilitado=true`.
7. Invocar `listar_importaciones_horario` sin bearer Firebase. Debe responder
   401/403; `anon` no debe ejecutar la RPC.

Las pruebas reales crean datos únicamente en las cuentas descartables A y B.
Al terminar, eliminarlos mediante los flujos normales o conservarlos como
evidencia de Testing; no tocar las cuentas de demostración.

### 7. Criterio de aprobación de Testing

Testing queda aprobado solamente si se cumplen todos estos puntos:

- cuenta A nueva recibe el claim y guarda sin fila administrativa;
- persistencia comprobada tras cierre total;
- reintento idempotente;
- cuenta B aislada y sin capacidad de eliminar A;
- bloqueo administrativo efectivo y reversible;
- anónimo, token de Producción y token sin rol rechazados;
- cuotas estructural y funcionalmente aprobadas;
- cero cambios en las cuentas/datos de demostración.

No debe editarse manualmente el SQL para insertar UIDs de demostración.

## Matriz de pruebas funcionales

Usar dos cuentas nuevas, A y B, sin filas en
`horario_importacion_autorizaciones`. Verificar previamente con una consulta
administrativa que no existan filas para esos UIDs.

| Escenario | Procedimiento | Resultado obligatorio |
| --- | --- | --- |
| Usuario nuevo | Registrar A, iniciar sesión, completar la preparación normal e importar un horario válido | Guarda el horario sin intervención administrativa; listar devuelve solo la importación de A |
| Usuario existente | Iniciar sesión con una cuenta existente y repetir/listar una importación | Continúa funcionando; el mismo hash devuelve `ya_existia = true` y no duplica datos |
| No autenticado | Invocar las RPC sin `Authorization` o con rol `anon` | HTTP 401/403; ninguna escritura |
| Token inválido | Invocar con token expirado, issuer/audience incorrectos o sin rol `authenticated` | Rechazo `usuario_firebase_no_valido` o rechazo de autenticación previo |
| Cuota diaria | En Testing, alcanzar el límite diario configurado del OCR con documentos no cacheados | OCR responde 429 con `daily_limit`; no se confirma una nueva importación |
| Cuota mensual | En un entorno de Testing controlado, alcanzar el límite mensual | OCR responde 429 con `monthly_limit`; no se confirma una nueva importación |
| Acceso entre cuentas | A crea una importación; B intenta leer sus tablas o eliminar el ID de A | B no obtiene filas y la eliminación devuelve no encontrada; los datos de A permanecen intactos |
| Bloqueo administrativo | Crear para A una fila `habilitado=false`; intentar importar/listar | Rechazo `importacion_horario_bloqueada`; al expirar/eliminar el bloqueo, A recupera acceso |
| Cambio de sesión | Cambiar de A a B mientras hay una operación del cliente pendiente | El cliente rechaza el resultado por cambio de sesión y el backend conserva el aislamiento del JWT usado |

Las pruebas SQL de cuota usan límites aislados dentro de una transacción y no
llaman a Google Vision. Una prueba HTTP real de `daily_limit` sí requiere
documentos no cacheados y consume cuota de Testing; no es necesaria para
aprobar la migración si `ocr_backend_testing_validation.sql` y una importación
OCR real normal pasan correctamente.

## Consultas administrativas de apoyo

Crear un bloqueo temporal de una hora (solo con credenciales administrativas):

```sql
insert into public.horario_importacion_autorizaciones (
  usuario_uid, habilitado, expira_en, comentario
) values (
  '<UID>', false, pg_catalog.now() + interval '1 hour',
  'Prueba de suspensión P0'
)
on conflict (usuario_uid) do update set
  habilitado = false,
  expira_en = excluded.expira_en,
  comentario = excluded.comentario,
  actualizada_en = pg_catalog.now();
```

Retirar el bloqueo:

```sql
delete from public.horario_importacion_autorizaciones
where usuario_uid = '<UID>';
```

Estas acciones nunca deben exponerse al cliente.

## Reversión

1. Detener las pruebas y no distribuir el build de Testing afectado.
2. Guardar la definición actual de la función y la evidencia del fallo.
3. Si alguna cuenta debe conservar acceso después de volver a la lista blanca,
   crear su autorización antes de revertir. Para una reversión inmediata de
   Testing puede aceptarse que todas vuelvan a quedar bloqueadas.
4. Ejecutar completo
   `supabase/rollbacks/202611230002_acceso_automatico_importacion_horario_rollback.sql`.
5. Ejecutar:

   ```sql
   select pg_catalog.pg_get_functiondef(
     'public.uid_importacion_horario_autorizado()'::pg_catalog.regprocedure
   );
   ```

   La definición debe contener `importacion_horario_no_autorizada` y exigir
   una fila `habilitado=true` vigente.
6. Con una cuenta descartable sin fila, confirmar que listar vuelve a ser
   rechazado. Con una fila habilitada, confirmar que vuelve a funcionar.

La reversión no elimina horarios ni documentos, pero sí vuelve a exigir
autorización manual. Por eso no debe ejecutarse durante la demostración sin
preparar primero la lista blanca.

## Diferencia entre Testing y Producción

La función local `firebase-role` es deliberadamente exclusiva de Testing:
acepta solo `eduflow-ai-testing` y su cuenta de servicio debe pertenecer a ese
proyecto. No debe desplegarse tal cual en Producción.

Antes de autorizar Producción se necesita, como mínimo:

1. inventario de solo lectura de la Edge Function productiva y sus secretos;
2. confirmar que valida `educflow-ai`, revocación, cuenta deshabilitada y
   coherencia `uid=sub`;
3. probar una cuenta Firebase productiva nueva que reciba
   `role=authenticated` sin intervención manual;
4. aplicar primero la migración SQL en Producción y repetir aislamiento/RLS;
5. decidir si la presentación puede aceptar el riesgo temporal de App Check
   no verificado o si debe añadirse y desplegarse antes de la APK oficial.
