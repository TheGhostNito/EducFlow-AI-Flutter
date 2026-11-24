export type TemporaryCleanupOptions = {
  operation: () => Promise<Response>;
  cleanup: () => Promise<boolean>;
  onCleanupFailure?: (error: unknown) => void;
};

export async function runWithTemporaryCleanup({
  operation,
  cleanup,
  onCleanupFailure,
}: TemporaryCleanupOptions): Promise<Response> {
  let response: Response | null = null;
  let operationError: unknown;
  let operationFailed = false;

  try {
    response = await operation();
  } catch (error) {
    operationFailed = true;
    operationError = error;
  }

  let temporaryFileDeleted = false;
  try {
    temporaryFileDeleted = await cleanup();
  } catch (error) {
    onCleanupFailure?.(error);
  }

  if (operationFailed) throw operationError;
  if (response == null) {
    throw new Error("La operación OCR no entregó una respuesta.");
  }

  return attachCleanupResult(response, temporaryFileDeleted);
}

async function attachCleanupResult(
  response: Response,
  temporaryFileDeleted: boolean,
): Promise<Response> {
  const contentType = response.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().includes("application/json")) return response;

  let body: unknown;
  try {
    body = await response.clone().json();
  } catch (_) {
    return response;
  }

  if (
    body == null ||
    typeof body !== "object" ||
    (body as Record<string, unknown>).ok !== true ||
    !("temporaryFileDeleted" in body)
  ) {
    return response;
  }

  const headers = new Headers(response.headers);
  headers.delete("content-length");
  return Response.json(
    {
      ...(body as Record<string, unknown>),
      temporaryFileDeleted,
    },
    { status: response.status, statusText: response.statusText, headers },
  );
}
