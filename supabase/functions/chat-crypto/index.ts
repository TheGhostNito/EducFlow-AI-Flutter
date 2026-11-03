const ALGORITHM = "aes-256-gcm";
const VERSION = 1;

const IV_BYTES = 12;
const TAG_BYTES = 16;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const encoder = new TextEncoder();
const decoder = new TextDecoder();

type Purpose =
  | "chat-title"
  | "chat-message";

// ======================================================
// RESPUESTAS HTTP
// ======================================================

function jsonResponse(
  body: unknown,
  status = 200,
): Response {
  return Response.json(
    body,
    {
      status,
      headers: {
        ...CORS_HEADERS,
        "Cache-Control": "no-store",
      },
    },
  );
}

// ======================================================
// SUPABASE
// ======================================================

function getSupabaseUrl(): string {
  const url = Deno.env.get("SUPABASE_URL");

  if (!url) {
    throw new Error(
      "SUPABASE_URL no configurada.",
    );
  }

  return url;
}

function getPublishableKey(): string {
  const keysJson = Deno.env.get(
    "SUPABASE_PUBLISHABLE_KEYS",
  );

  if (keysJson) {
    try {
      const keys = JSON.parse(
        keysJson,
      ) as Record<
        string,
        unknown
      >;

      const defaultKey = keys.default;

      if (
        typeof defaultKey ===
          "string" &&
        defaultKey.length > 0
      ) {
        return defaultKey;
      }

      const firstKey = Object.values(
        keys,
      ).find(
        (value) =>
          typeof value ===
            "string" &&
          value.length > 0,
      );

      if (
        typeof firstKey ===
          "string"
      ) {
        return firstKey;
      }
    } catch {
      throw new Error(
        "SUPABASE_PUBLISHABLE_KEYS inválida.",
      );
    }
  }

  // Compatibilidad local.
  const fallback = Deno.env.get(
    "SUPABASE_PUBLISHABLE_KEY",
  );

  if (fallback) {
    return fallback;
  }

  throw new Error(
    "No existe una publishable key de Supabase.",
  );
}

// ======================================================
// AUTENTICACIÓN FIREBASE
// ======================================================

async function authenticateFirebaseUser(
  req: Request,
): Promise<string | null> {
  const authorization = req.headers.get(
    "Authorization",
  );

  if (
    !authorization ||
    !authorization.startsWith(
      "Bearer ",
    )
  ) {
    return null;
  }

  const token = authorization
    .slice(7)
    .trim();

  if (!token) {
    return null;
  }

  /*
   * Enviamos el Firebase ID Token
   * al Data API de Supabase.
   *
   * Supabase valida el token mediante
   * la integración Third-Party Auth
   * configurada para Firebase.
   *
   * Solo si PostgreSQL reconoce al
   * usuario devolvemos su UID.
   */
  const response = await fetch(
    `${getSupabaseUrl()}/rest/v1/rpc/current_educflow_firebase_uid`,
    {
      method: "POST",

      headers: {
        apikey: getPublishableKey(),

        Authorization: `Bearer ${token}`,

        "Content-Type": "application/json",

        Accept: "application/json",
      },

      body: "{}",
    },
  );

  if (!response.ok) {
    return null;
  }

  const uid = await response.json();

  if (
    typeof uid !== "string" ||
    !isValidUid(uid)
  ) {
    return null;
  }

  return uid;
}

// ======================================================
// CONVERSIÓN DE BYTES
// ======================================================

function bytesToBase64(
  bytes: Uint8Array,
): string {
  let binary = "";

  const chunkSize = 0x8000;

  for (
    let i = 0;
    i < bytes.length;
    i += chunkSize
  ) {
    const chunk = bytes.subarray(
      i,
      Math.min(
        i + chunkSize,
        bytes.length,
      ),
    );

    binary += String.fromCharCode(
      ...chunk,
    );
  }

  return btoa(binary);
}

function base64ToBytes(
  value: string,
): Uint8Array {
  const binary = atob(value);

  const bytes = new Uint8Array(
    binary.length,
  );

  for (
    let i = 0;
    i < binary.length;
    i++
  ) {
    bytes[i] = binary.charCodeAt(i);
  }

  return bytes;
}

function concatBytes(
  first: Uint8Array,
  second: Uint8Array,
): Uint8Array {
  const result = new Uint8Array(
    first.length +
      second.length,
  );

  result.set(
    first,
    0,
  );

  result.set(
    second,
    first.length,
  );

  return result;
}

function toArrayBuffer(
  bytes: Uint8Array,
): ArrayBuffer {
  const copy = new Uint8Array(
    bytes.byteLength,
  );

  copy.set(bytes);

  return copy.buffer;
}

// ======================================================
// CLAVE MAESTRA
// ======================================================

function getMasterKey(): Uint8Array {
  const encoded = Deno.env.get(
    "CHAT_ENCRYPTION_KEY",
  );

  if (!encoded) {
    throw new Error(
      "CHAT_ENCRYPTION_KEY no configurada.",
    );
  }

  const key = base64ToBytes(
    encoded,
  );

  if (key.length !== 32) {
    throw new Error(
      "CHAT_ENCRYPTION_KEY debe contener exactamente 32 bytes.",
    );
  }

  return key;
}

// ======================================================
// CLAVE DERIVADA POR USUARIO
// ======================================================

async function deriveUserKey(
  uid: string,
): Promise<CryptoKey> {
  const master = getMasterKey();

  const keyMaterial = await crypto.subtle.importKey(
    "raw",
    toArrayBuffer(
      master,
    ),
    "HKDF",
    false,
    ["deriveKey"],
  );

  const salt = encoder.encode(
    "educflow-ai-chat-salt-v1",
  );

  const info = encoder.encode(
    `educflow-ai/chat/${uid}/v1`,
  );

  return crypto.subtle.deriveKey(
    {
      name: "HKDF",
      hash: "SHA-256",

      salt: toArrayBuffer(
        salt,
      ),

      info: toArrayBuffer(
        info,
      ),
    },
    keyMaterial,
    {
      name: "AES-GCM",
      length: 256,
    },
    false,
    [
      "encrypt",
      "decrypt",
    ],
  );
}

// ======================================================
// AAD
// ======================================================

function buildAdditionalData(
  uid: string,
  purpose: Purpose,
  chatId: string,
  messageId?: string,
  role?: string,
): Uint8Array {
  if (
    purpose ===
      "chat-title"
  ) {
    return encoder.encode(
      `educflow-ai|v${VERSION}|${uid}|chat-title|${chatId}`,
    );
  }

  return encoder.encode(
    `educflow-ai|v${VERSION}|${uid}|chat-message|${chatId}|${messageId}|${role}`,
  );
}

// ======================================================
// VALIDACIONES
// ======================================================

function isPurpose(
  value: unknown,
): value is Purpose {
  return (
    value ===
      "chat-title" ||
    value ===
      "chat-message"
  );
}

// El AAD v1 usa '|' como separador: conservarlo y rechazar IDs ambiguos.
function isValidUid(value: string): boolean {
  return /^[A-Za-z0-9._:@-]{1,128}$/.test(value);
}

function isValidRecordId(value: string): boolean {
  return /^[A-Za-z0-9_-]{1,128}$/.test(value);
}

function maxBytesForPurpose(
  purpose: Purpose,
): number {
  if (
    purpose ===
      "chat-title"
  ) {
    return 2_000;
  }

  return 100_000;
}

// ======================================================
// EDGE FUNCTION
// ======================================================

export default {
  async fetch(
    req: Request,
  ): Promise<Response> {
    try {
      // --------------------------------
      // CORS
      // --------------------------------

      if (
        req.method ===
          "OPTIONS"
      ) {
        return new Response(
          null,
          {
            status: 204,
            headers: CORS_HEADERS,
          },
        );
      }

      // --------------------------------
      // MÉTODO
      // --------------------------------

      if (
        req.method !==
          "POST"
      ) {
        return jsonResponse(
          {
            error: "Método no permitido.",
          },
          405,
        );
      }

      // --------------------------------
      // AUTENTICACIÓN
      // --------------------------------

      const uid = await authenticateFirebaseUser(
        req,
      );

      if (!uid) {
        return jsonResponse(
          {
            error: "Usuario Firebase no autorizado.",
          },
          401,
        );
      }

      // --------------------------------
      // BODY
      // --------------------------------

      let parsedBody: unknown;

      try {
        parsedBody = await req.json();
      } catch {
        return jsonResponse(
          {
            error: "JSON inválido.",
          },
          400,
        );
      }

      if (
        parsedBody === null ||
        typeof parsedBody !== "object" ||
        Array.isArray(parsedBody)
      ) {
        return jsonResponse(
          { error: "El cuerpo JSON debe ser un objeto." },
          400,
        );
      }
      const body = parsedBody as Record<string, unknown>;

      const action = body.action;

      const purpose = body.purpose;

      if (
        !isPurpose(
          purpose,
        )
      ) {
        return jsonResponse(
          {
            error: "Purpose no válido.",
          },
          400,
        );
      }

      // --------------------------------
      // CHAT ID
      // --------------------------------

      const chatId = typeof body.chatId ===
          "string"
        ? body.chatId
        : "";

      if (!isValidRecordId(chatId)) {
        return jsonResponse(
          {
            error: "chatId es obligatorio.",
          },
          400,
        );
      }

      // --------------------------------
      // DATOS DEL MENSAJE
      // --------------------------------

      let messageId:
        | string
        | undefined;

      let messageRole:
        | string
        | undefined;

      if (
        purpose ===
          "chat-message"
      ) {
        messageId = typeof body.messageId ===
            "string"
          ? body.messageId
          : "";

        messageRole = typeof body.role ===
            "string"
          ? body.role
          : "";

        if (
          !isValidRecordId(messageId) ||
          (
            messageRole !==
              "user" &&
            messageRole !==
              "assistant"
          )
        ) {
          return jsonResponse(
            {
              error: "messageId y role válidos son obligatorios para mensajes.",
            },
            400,
          );
        }
      } else if (body.messageId != null || body.role != null) {
        return jsonResponse(
          { error: "Los títulos no aceptan messageId ni role." },
          400,
        );
      }

      // --------------------------------
      // CLAVE DEL USUARIO
      // --------------------------------

      const key = await deriveUserKey(
        uid,
      );

      const additionalData = buildAdditionalData(
        uid,
        purpose,
        chatId,
        messageId,
        messageRole,
      );

      // ==================================================
      // CIFRAR
      // ==================================================

      if (
        action ===
          "encrypt"
      ) {
        if (
          typeof body.plaintext !==
            "string"
        ) {
          return jsonResponse(
            {
              error: "plaintext debe ser texto.",
            },
            400,
          );
        }

        const plaintext = encoder.encode(
          body.plaintext,
        );

        if (
          plaintext.length >
            maxBytesForPurpose(
              purpose,
            )
        ) {
          return jsonResponse(
            {
              error: "Contenido demasiado grande.",
            },
            413,
          );
        }

        const nonce = crypto.getRandomValues(
          new Uint8Array(
            IV_BYTES,
          ),
        );

        const encryptedCombined = new Uint8Array(
          await crypto.subtle.encrypt(
            {
              name: "AES-GCM",

              iv: toArrayBuffer(
                nonce,
              ),

              additionalData: toArrayBuffer(
                additionalData,
              ),

              tagLength: 128,
            },
            key,
            toArrayBuffer(
              plaintext,
            ),
          ),
        );

        if (
          encryptedCombined.length <
            TAG_BYTES
        ) {
          throw new Error(
            "Resultado criptográfico inválido.",
          );
        }

        const splitIndex = encryptedCombined.length -
          TAG_BYTES;

        const ciphertext = encryptedCombined.slice(
          0,
          splitIndex,
        );

        const authTag = encryptedCombined.slice(
          splitIndex,
        );

        return jsonResponse({
          ciphertext: bytesToBase64(
            ciphertext,
          ),

          nonce: bytesToBase64(
            nonce,
          ),

          authTag: bytesToBase64(
            authTag,
          ),

          algorithm: ALGORITHM,

          version: VERSION,
        });
      }

      // ==================================================
      // DESCIFRAR
      // ==================================================

      if (
        action ===
          "decrypt"
      ) {
        if (
          typeof body.ciphertext !==
            "string" ||
          typeof body.nonce !==
            "string" ||
          typeof body.authTag !==
            "string"
        ) {
          return jsonResponse(
            {
              error: "Payload cifrado incompleto.",
            },
            400,
          );
        }

        const maxCipherBytes = maxBytesForPurpose(purpose);
        const maxCipherBase64Length = 4 * Math.ceil(maxCipherBytes / 3);
        if (body.ciphertext.length > maxCipherBase64Length) {
          return jsonResponse({ error: "Contenido demasiado grande." }, 413);
        }
        if (body.nonce.length > 16 || body.authTag.length > 24) {
          return jsonResponse(
            { error: "Parámetros criptográficos inválidos." },
            400,
          );
        }

        let ciphertext: Uint8Array;

        let nonce: Uint8Array;

        let authTag: Uint8Array;

        try {
          ciphertext = base64ToBytes(
            body.ciphertext,
          );

          nonce = base64ToBytes(
            body.nonce,
          );

          authTag = base64ToBytes(
            body.authTag,
          );
        } catch {
          return jsonResponse(
            {
              error: "Base64 inválido.",
            },
            400,
          );
        }

        if (ciphertext.length > maxCipherBytes) {
          return jsonResponse({ error: "Contenido demasiado grande." }, 413);
        }

        if (
          nonce.length !==
            IV_BYTES ||
          authTag.length !==
            TAG_BYTES
        ) {
          return jsonResponse(
            {
              error: "Parámetros criptográficos inválidos.",
            },
            400,
          );
        }

        const combined = concatBytes(
          ciphertext,
          authTag,
        );

        try {
          const decrypted = await crypto.subtle.decrypt(
            {
              name: "AES-GCM",

              iv: toArrayBuffer(
                nonce,
              ),

              additionalData: toArrayBuffer(
                additionalData,
              ),

              tagLength: 128,
            },
            key,
            toArrayBuffer(
              combined,
            ),
          );

          return jsonResponse({
            plaintext: decoder.decode(
              decrypted,
            ),

            algorithm: ALGORITHM,

            version: VERSION,
          });
        } catch {
          return jsonResponse(
            {
              error: "No fue posible descifrar el contenido.",
            },
            400,
          );
        }
      }

      // --------------------------------
      // ACCIÓN DESCONOCIDA
      // --------------------------------

      return jsonResponse(
        {
          error: "Acción no válida.",
        },
        400,
      );
    } catch (error) {
      console.error(
        "chat-crypto:",
        error instanceof Error ? error.message : "Error desconocido",
      );

      return jsonResponse(
        {
          error: "Error interno de cifrado.",
        },
        500,
      );
    }
  },
};
