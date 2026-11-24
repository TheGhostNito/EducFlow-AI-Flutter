import {
  assertDeploymentIdentity,
  assertFirebaseClaimsIdentity,
  PRODUCTION_FIREBASE_PROJECT_ID,
  PRODUCTION_SUPABASE_PROJECT_REF,
  resolveFirebaseIdentity,
  TESTING_FIREBASE_PROJECT_ID,
  TESTING_SUPABASE_PROJECT_REF,
} from "./firebase_identity.ts";

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

Deno.test("sin configuración conserva exclusivamente la identidad productiva", () => {
  const identity = resolveFirebaseIdentity(undefined);
  assertEquals(identity.projectId, PRODUCTION_FIREBASE_PROJECT_ID);
  assertEquals(
    identity.issuer,
    "https://securetoken.google.com/educflow-ai",
  );
  assertThrows(() =>
    assertFirebaseClaimsIdentity(
      {
        iss: "https://securetoken.google.com/eduflow-ai-testing",
        aud: TESTING_FIREBASE_PROJECT_ID,
      },
      identity,
    )
  );
});

Deno.test("Testing acepta únicamente issuer y audience de su proyecto", () => {
  const identity = resolveFirebaseIdentity(TESTING_FIREBASE_PROJECT_ID);
  assertFirebaseClaimsIdentity(
    {
      iss: "https://securetoken.google.com/eduflow-ai-testing",
      aud: TESTING_FIREBASE_PROJECT_ID,
    },
    identity,
  );
  assertThrows(() =>
    assertFirebaseClaimsIdentity(
      {
        iss: "https://securetoken.google.com/educflow-ai",
        aud: PRODUCTION_FIREBASE_PROJECT_ID,
      },
      identity,
    )
  );
  assertThrows(() =>
    assertFirebaseClaimsIdentity(
      {
        iss: identity.issuer,
        aud: PRODUCTION_FIREBASE_PROJECT_ID,
      },
      identity,
    )
  );
});

Deno.test("rechaza configuraciones vacías, múltiples o desconocidas", () => {
  assertThrows(() => resolveFirebaseIdentity(""));
  assertThrows(() => resolveFirebaseIdentity("educflow-ai,eduflow-ai-testing"));
  assertThrows(() => resolveFirebaseIdentity("otro-proyecto"));
});

Deno.test("impide cruzar identidades entre Supabase Testing y Producción", () => {
  const production = resolveFirebaseIdentity(PRODUCTION_FIREBASE_PROJECT_ID);
  const testing = resolveFirebaseIdentity(TESTING_FIREBASE_PROJECT_ID);
  assertDeploymentIdentity(
    production,
    `https://${PRODUCTION_SUPABASE_PROJECT_REF}.supabase.co`,
  );
  assertDeploymentIdentity(
    testing,
    `https://${TESTING_SUPABASE_PROJECT_REF}.supabase.co`,
  );
  assertThrows(() =>
    assertDeploymentIdentity(
      production,
      `https://${TESTING_SUPABASE_PROJECT_REF}.supabase.co`,
    )
  );
  assertThrows(() =>
    assertDeploymentIdentity(
      testing,
      `https://${PRODUCTION_SUPABASE_PROJECT_REF}.supabase.co`,
    )
  );
  assertThrows(() =>
    assertDeploymentIdentity(testing, "https://otro.supabase.co")
  );
});
