# EducFlow AI

Aplicación Flutter de gestión académica personal para Android y web/PWA. Firebase Authentication mantiene las sesiones; Firebase AI Logic, Firestore, Supabase y las Edge Functions cubren partes distintas del funcionamiento actual.

## Requisitos e instalación

- Flutter con Dart compatible con `^3.13.1` (véase `pubspec.yaml`).
- Android Studio y Android SDK para Android; Java 17 para la configuración Gradle actual.
- Firebase CLI para publicar Hosting y acceso autorizado a los proyectos externos.
- Configuración de Firebase, Supabase y secretos de backend existentes. Las credenciales administrativas no forman parte del repositorio.

Desde la raíz del repositorio:

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d <device-id>
```

`pubspec.lock` fija las versiones resueltas. Las pruebas de `test/` se conservan localmente durante la preparación Git, pero no forman parte del conjunto previsto para GitHub; en un clon sin ellas, `flutter test` no valida la suite histórica.

## Configuración de servicios

`lib/firebase_options.dart`, `firebase.json`, `.firebaserc` y `android/app/google-services.json` contienen la configuración cliente del proyecto principal Firebase `educflow-ai`. `lib/main.dart` inicializa el proyecto principal de Supabase y utiliza tokens de Firebase Authentication para el cliente Supabase. Las claves cliente son publicables; nunca se debe añadir una clave de servicio ni un secreto de firma.

El código actual no exige variables de entorno para iniciar Flutter: los identificadores y claves publicables están en la configuración cliente. El backend depende de configuración externa: Firebase Authentication, App Check, políticas de Storage para `ocr-temp`, funciones `ocr-process` y `chat-crypto`, secretos de cifrado de chat, y esquema/RLS de Supabase. No se documentan aquí valores secretos. La importación OCR usa el bucket `ocr-temp`.

El cliente productivo invoca `ocr-process`, pero el código fuente de esa Edge Function v2.2 y su configuración de Google Cloud Vision no están versionados en este repositorio. Por ello, un clon puede compilar el cliente, pero no reconstruir ni desplegar el procesamiento OCR del backend solo desde GitHub. La función desplegada y sus dependencias deben recuperarse y verificarse por separado antes de preparar un entorno nuevo.

La entrada `lib/testing/` y el proyecto `testing_runner/` son laboratorios locales separados de `lib/main.dart` y se excluyen del conjunto productivo.

## Android y web

`android/app/build.gradle.kts` carga `android/key.properties` para la firma Android. Prepare ese archivo localmente con `keyAlias`, `keyPassword`, `storeFile` y `storePassword`, apuntando a un keystore autorizado. El archivo y el keystore están ignorados por Git. La configuración Gradle actual también lee esos valores al configurar builds de desarrollo; obtenga los valores de desarrollo apropiados antes de compilar. No copie secretos de producción al repositorio.

```sh
flutter build apk --release
flutter build web --release
```

Firebase Hosting publica `build/web` y redirige las rutas a `index.html` según `firebase.json`. La publicación requiere autorización y destino explícito:

```sh
firebase deploy --only hosting --project educflow-ai
```

Ese comando no despliega Supabase ni las Edge Functions.

## Estado del backend reproducible

`supabase/migrations/` conserva las migraciones SQL productivas disponibles. `202611040001_malla_curricular.sql` y `202611050001_editar_ramo_malla.sql` corresponden al módulo aplicado y validado en Supabase principal. Los archivos anteriores de notas, asignaturas, evaluaciones, tareas y cálculo de notas forman parte del historial local.

`202610280001_chat_ia_rpc_preparada.sql` es un borrador no verificado ubicado en `supabase/proposals/`, fuera de la cadena oficial. `20261101_chat_produccion_candidata.sql` tampoco se ha contrastado aquí con las definiciones desplegadas. Flutter utiliza las RPC de chat, pero su correspondencia exacta con producción requiere inspección autorizada del esquema remoto. No aplique estas propuestas como migraciones.

El repositorio no contiene una reconstrucción completa verificada del backend desde una base vacía: faltan por documentar dependencias previas de identidad Firebase, tablas y políticas históricas, configuración de Storage, Edge Functions desplegadas y secretos administrados fuera de Git. Antes de desplegar en otro proyecto, compare el esquema y los permisos en un entorno de ensayo y obtenga la configuración externa autorizada. No ejecute migraciones en producción por seguir esta guía.
