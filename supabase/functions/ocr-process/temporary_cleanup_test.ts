import { runWithTemporaryCleanup } from "./temporary_cleanup.ts";

function assert(
  condition: unknown,
  message = "La condición no se cumplió",
): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(actual: unknown, expected: unknown) {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson !== expectedJson) {
    throw new Error(`Esperado ${expectedJson}, recibido ${actualJson}`);
  }
}

async function assertRejects(
  action: () => Promise<unknown>,
  expectedMessage: string,
) {
  try {
    await action();
  } catch (error) {
    assert(error instanceof Error, "Se esperaba una excepción Error");
    assert(
      error.message.includes(expectedMessage),
      `La excepción no contiene: ${expectedMessage}`,
    );
    return;
  }
  throw new Error("Se esperaba que la operación fallara");
}

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return Response.json(body, { status });
}

async function responseBody(response: Response) {
  return await response.json() as Record<string, unknown>;
}

for (
  const scenario of [
    { name: "OCR exitoso", status: 200, body: { ok: true, cacheHit: false } },
    {
      name: "respuesta desde caché",
      status: 200,
      body: { ok: true, cacheHit: true },
    },
  ]
) {
  Deno.test(`limpia el temporal después de ${scenario.name}`, async () => {
    let cleanupCalls = 0;
    const response = await runWithTemporaryCleanup({
      operation: async () =>
        jsonResponse(
          { ...scenario.body, temporaryFileDeleted: false },
          scenario.status,
        ),
      cleanup: async () => {
        cleanupCalls++;
        return true;
      },
    });

    assertEquals(cleanupCalls, 1);
    assertEquals(response.status, scenario.status);
    assertEquals((await responseBody(response)).temporaryFileDeleted, true);
  });
}

for (
  const scenario of [
    {
      name: "Google Vision",
      status: 502,
      body: { ok: false, error: "vision" },
    },
    { name: "PDF inválido", status: 400, body: { ok: false, error: "pdf" } },
    {
      name: "cuota agotada",
      status: 429,
      body: { ok: false, quotaBlocked: true },
    },
  ]
) {
  Deno.test(`limpia el temporal ante error de ${scenario.name}`, async () => {
    let cleanupCalls = 0;
    const response = await runWithTemporaryCleanup({
      operation: async () => jsonResponse(scenario.body, scenario.status),
      cleanup: async () => {
        cleanupCalls++;
        return true;
      },
    });

    assertEquals(cleanupCalls, 1);
    assertEquals(response.status, scenario.status);
    assertEquals(await responseBody(response), scenario.body);
  });
}

Deno.test("un fallo de eliminación no invalida el OCR exitoso", async () => {
  const response = await runWithTemporaryCleanup({
    operation: async () =>
      jsonResponse({
        ok: true,
        cacheHit: false,
        temporaryFileDeleted: true,
        courses: [{ id: "MAT101" }],
      }),
    cleanup: async () => false,
  });
  const body = await responseBody(response);

  assertEquals(response.status, 200);
  assertEquals(body.temporaryFileDeleted, false);
  assertEquals(body.courses, [{ id: "MAT101" }]);
});

Deno.test("una excepción de limpieza conserva el resultado OCR", async () => {
  let logged = false;
  const response = await runWithTemporaryCleanup({
    operation: async () =>
      jsonResponse({ ok: true, temporaryFileDeleted: true }),
    cleanup: async () => {
      throw new Error("detalle sensible no propagable");
    },
    onCleanupFailure: (_) => logged = true,
  });

  assert(logged);
  assertEquals((await responseBody(response)).temporaryFileDeleted, false);
});

Deno.test("una excepción principal conserva prioridad sobre la limpieza", async () => {
  const primaryError = new Error("fallo principal");
  let cleanupCalls = 0;

  await assertRejects(
    () =>
      runWithTemporaryCleanup({
        operation: async () => {
          throw primaryError;
        },
        cleanup: async () => {
          cleanupCalls++;
          throw new Error("fallo secundario");
        },
      }),
    "fallo principal",
  );
  assertEquals(cleanupCalls, 1);
});
