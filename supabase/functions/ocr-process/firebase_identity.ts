export const PRODUCTION_FIREBASE_PROJECT_ID = "educflow-ai";
export const TESTING_FIREBASE_PROJECT_ID = "eduflow-ai-testing";
export const PRODUCTION_SUPABASE_PROJECT_REF = "ubjmdfwkjgblnjgmufpc";
export const TESTING_SUPABASE_PROJECT_REF = "oxrvksaljxcwdhkeapej";

export const FIREBASE_PROJECT_ID_ENV = "EDUFLOW_FIREBASE_PROJECT_ID";

const ALLOWED_FIREBASE_PROJECT_IDS = new Set([
  PRODUCTION_FIREBASE_PROJECT_ID,
  TESTING_FIREBASE_PROJECT_ID,
]);

export type FirebaseIdentity = Readonly<{
  projectId: string;
  issuer: string;
}>;

/**
 * Resuelve una sola identidad Firebase por despliegue.
 *
 * La ausencia de la variable conserva el contrato productivo histórico. Un
 * valor vacío, múltiple o desconocido falla de forma cerrada para impedir que
 * un despliegue acepte accidentalmente tokens de más de un proyecto.
 */
export function resolveFirebaseIdentity(
  configuredProjectId: string | undefined,
): FirebaseIdentity {
  const projectId = configuredProjectId === undefined
    ? PRODUCTION_FIREBASE_PROJECT_ID
    : configuredProjectId.trim();

  if (!ALLOWED_FIREBASE_PROJECT_IDS.has(projectId)) {
    throw new Error(
      `${FIREBASE_PROJECT_ID_ENV} no contiene un proyecto Firebase permitido.`,
    );
  }

  return Object.freeze({
    projectId,
    issuer: `https://securetoken.google.com/${projectId}`,
  });
}

export function assertFirebaseClaimsIdentity(
  payload: Readonly<Record<string, unknown>>,
  identity: FirebaseIdentity,
): void {
  if (payload.iss !== identity.issuer || payload.aud !== identity.projectId) {
    throw new Error("El token Firebase pertenece a otro proyecto.");
  }
}

/** Impide cruzar la identidad Firebase de un entorno con el Supabase del otro. */
export function assertDeploymentIdentity(
  identity: FirebaseIdentity,
  supabaseUrl: string | undefined,
): void {
  // Permite importar el módulo en pruebas puras. En Edge Runtime SUPABASE_URL
  // siempre debe existir y también se valida antes de acceder a Storage/REST.
  if (supabaseUrl === undefined) return;

  let projectRef: string;
  try {
    projectRef = new URL(supabaseUrl).hostname.split(".")[0];
  } catch (_) {
    throw new Error("SUPABASE_URL no es válida.");
  }

  const expectedProjectId = projectRef === PRODUCTION_SUPABASE_PROJECT_REF
    ? PRODUCTION_FIREBASE_PROJECT_ID
    : projectRef === TESTING_SUPABASE_PROJECT_REF
    ? TESTING_FIREBASE_PROJECT_ID
    : null;

  if (expectedProjectId === null || identity.projectId !== expectedProjectId) {
    throw new Error(
      "La identidad Firebase no coincide con el entorno Supabase.",
    );
  }
}
