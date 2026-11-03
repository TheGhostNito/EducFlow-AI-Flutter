import handler from "./index.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function request(body: unknown): Request {
  return new Request("https://example.invalid/chat-crypto", {
    method: "POST",
    headers: { Authorization: "Bearer token-ficticio" },
    body: JSON.stringify(body),
  });
}

async function json(
  body: unknown,
): Promise<[number, Record<string, unknown>]> {
  const response = await handler.fetch(request(body));
  return [response.status, await response.json()];
}

Deno.test("chat-crypto v1: ida y vuelta, alteración y aislamiento", async () => {
  const oldFetch = globalThis.fetch;
  let uid = "usuarioA";
  globalThis.fetch =
    (() => Promise.resolve(Response.json(uid))) as typeof fetch;
  Deno.env.set(
    "CHAT_ENCRYPTION_KEY",
    btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32)))),
  );
  Deno.env.set("SUPABASE_URL", "https://example.invalid");
  Deno.env.set(
    "SUPABASE_PUBLISHABLE_KEYS",
    JSON.stringify({ default: "clave-publicable-ficticia" }),
  );
  try {
    const [encryptStatus, encrypted] = await json({
      action: "encrypt",
      purpose: "chat-message",
      chatId: "chatA",
      messageId: "mensajeA",
      role: "assistant",
      plaintext: "Texto ficticio",
    });
    assert(encryptStatus === 200, "Cifrado falló");
    assert(
      encrypted.algorithm === "aes-256-gcm" && encrypted.version === 1,
      "Formato v1",
    );
    assert(atob(encrypted.nonce as string).length === 12, "Nonce");
    assert(atob(encrypted.authTag as string).length === 16, "Etiqueta");
    const decryptBody = {
      action: "decrypt",
      purpose: "chat-message",
      chatId: "chatA",
      messageId: "mensajeA",
      role: "assistant",
      ciphertext: encrypted.ciphertext,
      nonce: encrypted.nonce,
      authTag: encrypted.authTag,
    };
    const [decryptStatus, decrypted] = await json(decryptBody);
    assert(
      decryptStatus === 200 && decrypted.plaintext === "Texto ficticio",
      "Descifrado",
    );
    const [titleStatus, encryptedTitle] = await json({
      action: "encrypt",
      purpose: "chat-title",
      chatId: "chatA",
      plaintext: "Título ficticio",
    });
    assert(titleStatus === 200, "Cifrado de título");
    const [titleDecryptStatus, decryptedTitle] = await json({
      action: "decrypt",
      purpose: "chat-title",
      chatId: "chatA",
      ciphertext: encryptedTitle.ciphertext,
      nonce: encryptedTitle.nonce,
      authTag: encryptedTitle.authTag,
    });
    assert(
      titleDecryptStatus === 200 &&
        decryptedTitle.plaintext === "Título ficticio",
      "Descifrado de título",
    );
    assert(
      (await json({ ...decryptBody, role: "user" }))[0] === 400,
      "AAD del rol no se verificó",
    );
    const changed = {
      ...decryptBody,
      ciphertext: btoa(
        String.fromCharCode(
          atob(encrypted.ciphertext as string).charCodeAt(0) ^ 1,
        ) +
          atob(encrypted.ciphertext as string).slice(1),
      ),
    };
    assert((await json(changed))[0] === 400, "Alteración aceptada");
    uid = "usuarioB";
    assert((await json(decryptBody))[0] === 400, "Otro UID pudo descifrar");
  } finally {
    globalThis.fetch = oldFetch;
    Deno.env.delete("CHAT_ENCRYPTION_KEY");
    Deno.env.delete("SUPABASE_URL");
    Deno.env.delete("SUPABASE_PUBLISHABLE_KEYS");
  }
});

Deno.test("chat-crypto v1: UID, IDs y rol ambiguos se rechazan", async () => {
  const oldFetch = globalThis.fetch;
  Deno.env.set("SUPABASE_URL", "https://example.invalid");
  Deno.env.set(
    "SUPABASE_PUBLISHABLE_KEYS",
    JSON.stringify({ default: "clave-publicable-ficticia" }),
  );
  globalThis.fetch =
    (() => Promise.resolve(Response.json("usuario|A"))) as typeof fetch;
  try {
    assert(
      (await json({
        action: "encrypt",
        purpose: "chat-title",
        chatId: "chatA",
        plaintext: "Ficticio",
      }))[0] === 401,
      "UID ambiguo",
    );
    globalThis.fetch = (() =>
      Promise.resolve(Response.json("usuarioA"))) as typeof fetch;
    const base = {
      action: "encrypt",
      purpose: "chat-message",
      chatId: "chatA",
      messageId: "mensajeA",
      role: "user",
      plaintext: "Ficticio",
    };
    assert(
      (await json({ ...base, chatId: "chat|A" }))[0] === 400,
      "Chat ID ambiguo",
    );
    assert(
      (await json({ ...base, messageId: "mensaje A" }))[0] === 400,
      "Message ID ambiguo",
    );
    assert(
      (await json({ ...base, role: "system" }))[0] === 400,
      "Rol inválido",
    );
    assert(
      (await json({ ...base, purpose: "chat-title" }))[0] === 400,
      "Título con datos de mensaje",
    );
  } finally {
    globalThis.fetch = oldFetch;
    Deno.env.delete("SUPABASE_URL");
    Deno.env.delete("SUPABASE_PUBLISHABLE_KEYS");
  }
});

Deno.test("chat-crypto rechaza JSON no objeto y ciphertext excesivo", async () => {
  const oldFetch = globalThis.fetch;
  globalThis.fetch =
    (() => Promise.resolve(Response.json("usuarioA"))) as typeof fetch;
  Deno.env.set("SUPABASE_URL", "https://example.invalid");
  Deno.env.set(
    "SUPABASE_PUBLISHABLE_KEYS",
    JSON.stringify({ default: "clave-publicable-ficticia" }),
  );
  Deno.env.set(
    "CHAT_ENCRYPTION_KEY",
    btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32)))),
  );
  try {
    for (const body of [null, [], "texto"]) {
      assert((await json(body))[0] === 400, "JSON no objeto aceptado");
    }
    assert(
      (await json({
        action: "decrypt",
        purpose: "chat-message",
        chatId: "chatA",
        messageId: "mensajeA",
        role: "user",
        ciphertext: "A".repeat(140_000),
        nonce: btoa(String.fromCharCode(...new Uint8Array(12))),
        authTag: btoa(String.fromCharCode(...new Uint8Array(16))),
      }))[0] === 413,
      "Ciphertext excesivo aceptado",
    );
  } finally {
    globalThis.fetch = oldFetch;
    Deno.env.delete("SUPABASE_URL");
    Deno.env.delete("SUPABASE_PUBLISHABLE_KEYS");
    Deno.env.delete("CHAT_ENCRYPTION_KEY");
  }
});
