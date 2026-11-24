import { handleOcrRequest, validateStoragePath } from "./index.ts";

function assert(condition: unknown, message = "La condición no se cumplió") {
  if (!condition) throw new Error(message);
}

function assertEquals(actual: unknown, expected: unknown) {
  if (actual !== expected) {
    throw new Error(`Esperado ${expected}, recibido ${actual}`);
  }
}

function assertThrows(action: () => void) {
  try {
    action();
  } catch (_) {
    return;
  }
  throw new Error("Se esperaba que la operación fallara");
}

Deno.test("acepta únicamente la ruta temporal del UID verificado", () => {
  validateStoragePath("firebase-user/123456.pdf", "firebase-user");
  assertThrows(() =>
    validateStoragePath("otro-usuario/123456.pdf", "firebase-user")
  );
  assertThrows(() =>
    validateStoragePath("firebase-user/../otro.pdf", "firebase-user")
  );
});

Deno.test("OPTIONS conserva el contrato CORS sin autenticar", async () => {
  const response = await handleOcrRequest(
    new Request("https://testing.invalid/ocr-process", { method: "OPTIONS" }),
  );
  assertEquals(response.status, 200);
  assert(response.headers.has("access-control-allow-origin"));
});

Deno.test("rechaza métodos distintos de POST", async () => {
  const response = await handleOcrRequest(
    new Request("https://testing.invalid/ocr-process", { method: "GET" }),
  );
  assertEquals(response.status, 405);
  const body = await response.json();
  assertEquals(body.ok, false);
});

Deno.test("rechaza POST sin Firebase ID token", async () => {
  const response = await handleOcrRequest(
    new Request("https://testing.invalid/ocr-process", { method: "POST" }),
  );
  assertEquals(response.status, 401);
  const body = await response.json();
  assertEquals(body.ok, false);
});
