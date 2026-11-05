# Historial IA en Supabase

La aplicación principal utiliza `SupabaseAiChatHistoryRepository` como repositorio predeterminado en el chat y en Historial. Ambas pantallas comparten la misma instancia. Firebase Authentication y Firebase AI Logic permanecen en uso. Las conversaciones antiguas de Firestore no se importan y el flujo principal ya no escribe historial nuevo allí.

## Contrato de almacenamiento

- `chats` y `mensajes_chat` almacenan títulos y mensajes cifrados con AES-256-GCM v1. La Edge Function `chat-crypto` conserva el AAD y la derivación HKDF por UID validados para ese formato.
- El cliente envía el ID token de Firebase a la función y utiliza las RPC de chat para escrituras atómicas. Los IDs de chat y mensaje se mantienen estables durante los reintentos.
- El historial muestra un marcador para los títulos o mensajes con cifrado permanentemente incompatible y no sobrescribe esas filas. Esos mensajes quedan fuera del contexto de Gemini. Los errores de almacenamiento se distinguen de los errores de Gemini.
- Las lecturas y cambios de estado respetan el UID actual. El contexto de Gemini se reconstruye desde los mensajes recuperados al iniciar una sesión nueva.

## Validación local

El 3 de noviembre de 2026, `flutter test --no-pub` pasó 360 pruebas y `flutter analyze --no-pub` terminó sin problemas. `flutter build web --release --no-pub` completó. La marca Web de depuración de App Check solo se activa en `localhost` y `127.0.0.1`; el artefacto release no la activa en los dominios públicos comprobados. No se incorpora ningún token de depuración.

En las aplicaciones principales locales Android y PWA se comprobó, con mensajes ficticios, recuperación del mismo chat tras reingreso, respuesta real de Gemini con contexto, actualización desde Historial sin recargar la página y reintento tras una desconexión limitada al emulador sin duplicados visibles. El token de depuración Web usado durante esa prueba fue revocado. La comprobación de ausencia de escrituras Firestore proviene del flujo de código; no se efectuó un recuento remoto independiente en esta ronda.

## Operación

El SQL productivo y `chat-crypto` se aplicaron y validaron en intervenciones anteriores; este commit conserva su fuente, sin ejecutarlos de nuevo. La publicación del APK o la PWA requiere autorización separada y una comprobación breve en las versiones distribuidas. El informe Word completo y las capturas de operación permanecen fuera de este commit porque contienen detalles internos del entorno.
