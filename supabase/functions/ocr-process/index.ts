import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { PDFDocument } from "npm:pdf-lib@1.17.1";

import { decodeProtectedHeader, importX509, jwtVerify } from "npm:jose@6.1.0";

import { runWithTemporaryCleanup } from "./temporary_cleanup.ts";

import {
  assertDeploymentIdentity,
  assertFirebaseClaimsIdentity,
  FIREBASE_PROJECT_ID_ENV,
  resolveFirebaseIdentity,
} from "./firebase_identity.ts";

const FIREBASE_IDENTITY = resolveFirebaseIdentity(
  Deno.env.get(FIREBASE_PROJECT_ID_ENV),
);

assertDeploymentIdentity(FIREBASE_IDENTITY, Deno.env.get("SUPABASE_URL"));

const FIREBASE_CERTS_URL =
  "https://www.googleapis.com/robot/v1/metadata/x509/" +
  "securetoken@system.gserviceaccount.com";

const OCR_BUCKET = "ocr-temp";

const ALLOWED_MIME_TYPES = new Set([
  "image/jpeg",

  "image/png",

  "image/webp",

  "application/pdf",
]);

const MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024;

const MONTHLY_VISION_LIMIT = 800;

const DAILY_USER_VISION_LIMIT = 10;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",

  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

let cachedCertificates: Record<string, string> | null = null;

let certificatesExpireAt = 0;

function base64UrlEncode(data: Uint8Array | string): string {
  const bytes = typeof data === "string"
    ? new TextEncoder().encode(data)
    : data;

  let binary = "";

  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const normalizedPem = pem.replace(/\\n/g, "\n");

  const base64 = normalizedPem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");

  const binary = atob(base64);

  const bytes = new Uint8Array(binary.length);

  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }

  return bytes.buffer;
}

async function getGoogleAccessToken(
  clientEmail: string,
  privateKey: string,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  const header = {
    alg: "RS256",

    typ: "JWT",
  };

  const payload = {
    iss: clientEmail,

    scope: "https://www.googleapis.com/auth/cloud-platform",

    aud: "https://oauth2.googleapis.com/token",

    iat: now,

    exp: now + 3600,
  };

  const unsignedToken = `${base64UrlEncode(JSON.stringify(header))}.${
    base64UrlEncode(JSON.stringify(payload))
  }`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKey),
    {
      name: "RSASSA-PKCS1-v1_5",

      hash: "SHA-256",
    },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsignedToken),
  );

  const jwt = `${unsignedToken}.${base64UrlEncode(new Uint8Array(signature))}`;

  const response = await fetch(
    "https://oauth2.googleapis.com/token",
    {
      method: "POST",

      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },

      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",

        assertion: jwt,
      }),
    },
  );

  if (!response.ok) {
    throw new Error(
      `Google OAuth respondió ${response.status}: ${await response.text()}`,
    );
  }

  const data = await response.json();

  if (
    typeof data?.access_token !== "string" || data.access_token.length === 0
  ) {
    throw new Error("Google OAuth no devolvió un access_token válido.");
  }

  return data.access_token;
}

function getMaxAgeSeconds(cacheControl: string | null): number {
  if (!cacheControl) return 300;

  const match = cacheControl.match(/max-age=(\d+)/i);

  return match ? Number(match[1]) : 300;
}

async function getFirebaseCertificate(kid: string): Promise<string> {
  const now = Date.now();

  if (
    cachedCertificates &&
    now < certificatesExpireAt &&
    cachedCertificates[kid]
  ) {
    return cachedCertificates[kid];
  }

  const response = await fetch(FIREBASE_CERTS_URL);

  if (!response.ok) {
    throw new Error(
      `No se pudieron obtener las claves públicas de Firebase: ${response.status}`,
    );
  }

  const certificates = await response.json() as Record<string, string>;

  const maxAge = getMaxAgeSeconds(response.headers.get("cache-control"));

  cachedCertificates = certificates;

  certificatesExpireAt = Date.now() + maxAge * 1000;

  const certificate = certificates[kid];

  if (!certificate) {
    throw new Error(
      "El token Firebase utiliza una clave pública desconocida.",
    );
  }

  return certificate;
}

async function verifyFirebaseIdToken(token: string) {
  const header = decodeProtectedHeader(token);

  if (header.alg !== "RS256") {
    throw new Error("Algoritmo de firma Firebase no permitido.");
  }

  if (typeof header.kid !== "string" || header.kid.length === 0) {
    throw new Error("El token Firebase no contiene un kid válido.");
  }

  const certificate = await getFirebaseCertificate(header.kid);

  const publicKey = await importX509(certificate, "RS256");

  const { payload } = await jwtVerify(token, publicKey, {
    algorithms: ["RS256"],

    issuer: FIREBASE_IDENTITY.issuer,

    audience: FIREBASE_IDENTITY.projectId,
  });

  assertFirebaseClaimsIdentity(payload, FIREBASE_IDENTITY);

  const now = Math.floor(Date.now() / 1000);

  if (
    typeof payload.sub !== "string" ||
    payload.sub.length === 0 ||
    payload.sub.length > 128
  ) {
    throw new Error("El token Firebase no contiene un UID válido.");
  }

  if (typeof payload.iat !== "number" || payload.iat > now) {
    throw new Error("El token Firebase tiene un iat inválido.");
  }

  const authTime = payload.auth_time;

  if (typeof authTime !== "number" || authTime > now) {
    throw new Error("El token Firebase tiene un auth_time inválido.");
  }

  return { uid: payload.sub, payload };
}

export function validateStoragePath(path: string, firebaseUid: string) {
  if (!path) {
    throw new Error("Falta la ruta del archivo.");
  }

  if (path.startsWith("/") || path.includes("\\\\")) {
    throw new Error("Ruta de archivo no válida.");
  }

  const segments = path.split("/");

  if (
    segments.length < 2 ||
    segments.some(
      (segment) => segment.length === 0 || segment === "." || segment === "..",
    )
  ) {
    throw new Error("Ruta de archivo no válida.");
  }

  if (segments[0] !== firebaseUid) {
    throw new Error("El archivo no pertenece al usuario autenticado.");
  }
}

function encodeStoragePath(path: string) {
  return path
    .split("/")
    .map((segment) => encodeURIComponent(segment))
    .join("/");
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const hashBuffer = await crypto.subtle.digest(
    "SHA-256",
    bytes as unknown as BufferSource,
  );

  const hashArray = Array.from(new Uint8Array(hashBuffer));

  return hashArray
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function bytesToBase64(bytes: Uint8Array): string {
  const chunkSize = 0x8000;

  let binary = "";

  for (let i = 0; i < bytes.length; i += chunkSize) {
    const chunk = bytes.subarray(
      i,
      Math.min(i + chunkSize, bytes.length),
    );

    binary += String.fromCharCode(...chunk);
  }

  return btoa(binary);
}

function getBoundingMetrics(block: any) {
  const boundingBox = block?.boundingBox ?? null;

  if (!boundingBox) {
    return {
      xMin: null,
      xMax: null,
      yMin: null,
      yMax: null,
      centerX: null,
      centerY: null,
      width: null,
      height: null,
    };
  }

  const pixelVertices = Array.isArray(boundingBox.vertices)
    ? boundingBox.vertices
    : [];

  const normalizedVertices = Array.isArray(boundingBox.normalizedVertices)
    ? boundingBox.normalizedVertices
    : [];

  // Mantiene el comportamiento antiguo cuando Vision entrega coordenadas
  // absolutas. Para PDFs, donde suele entregar normalizedVertices (0..1),
  // las proyectamos a un espacio virtual 0..1000 para que el parser pueda
  // seguir trabajando con distancias comparables.
  const usesNormalizedVertices = pixelVertices.length === 0 &&
    normalizedVertices.length > 0;

  const sourceVertices = usesNormalizedVertices
    ? normalizedVertices
    : pixelVertices;

  const scale = usesNormalizedVertices ? 1000 : 1;

  const xs = sourceVertices
    .map((vertex: any) =>
      typeof vertex?.x === "number" ? vertex.x * scale : null
    )
    .filter((x: any) => typeof x === "number");

  const ys = sourceVertices
    .map((vertex: any) =>
      typeof vertex?.y === "number" ? vertex.y * scale : null
    )
    .filter((y: any) => typeof y === "number");

  if (xs.length === 0 || ys.length === 0) {
    return {
      xMin: null,
      xMax: null,
      yMin: null,
      yMax: null,
      centerX: null,
      centerY: null,
      width: null,
      height: null,
    };
  }

  const xMin = Math.min(...xs);
  const xMax = Math.max(...xs);
  const yMin = Math.min(...ys);
  const yMax = Math.max(...ys);

  return {
    xMin,
    xMax,
    yMin,
    yMax,
    centerX: (xMin + xMax) / 2,
    centerY: (yMin + yMax) / 2,
    width: xMax - xMin,
    height: yMax - yMin,
  };
}

function normalizeAcademicCode(text: string): string {
  return text
    .toUpperCase()
    .replace(/\s+/g, "")
    .trim();
}

function detectBlockType(text: string): string {
  const clean = text.trim().toUpperCase();

  const punctuationClean = clean
    .replace(/^[^A-Z0-9]+/g, "")
    .replace(/[^A-Z0-9]+$/g, "")
    .replace(/\s+/g, " ")
    .trim();

  const punctuationCompact = punctuationClean.replace(/\s+/g, "");

  if (/^[A-Z]{2,4}\d{4,5}$/.test(punctuationCompact)) {
    return "course_code";
  }

  if (/^[A-Z]{2,4}\d{4,5}\s+\d{1,2}$/.test(punctuationClean)) {
    return "course_code_credits";
  }

  if (/^\d{1,2}$/.test(clean)) {
    return "number";
  }

  if (/^(I|II|III|IV|V|VI|VII|VIII|IX|X)$/.test(clean)) {
    return "semester";
  }

  if (clean.includes("CERTIFICADO EN")) {
    return "certificate";
  }

  if (clean.includes("CRÉDITOS")) {
    return "credits_label";
  }

  if (clean.length >= 3) {
    return "text";
  }

  return "unknown";
}

async function getCachedOcrResult(documentHash: string) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error(
      "Faltan variables internas de Supabase para consultar ocr_cache.",
    );
  }

  const response = await fetch(
    `${supabaseUrl}/rest/v1/ocr_cache` +
      `?document_hash=eq.${encodeURIComponent(documentHash)}` +
      `&select=result,created_at,page_count,course_count`,
    {
      headers: {
        apikey: serviceRoleKey,

        Authorization: `Bearer ${serviceRoleKey}`,
      },
    },
  );

  if (!response.ok) {
    throw new Error(
      `Error consultando ocr_cache: ${response.status} ${await response
        .text()}`,
    );
  }

  const rows = await response.json();

  if (!Array.isArray(rows) || rows.length === 0) return null;

  return rows[0];
}

async function saveOcrResultToCache({
  documentHash,

  mimeType,

  result,

  pageCount,

  courseCount,

  visionUnits = 1,
}: {
  documentHash: string;

  mimeType: string;

  result: any;

  pageCount: number;

  courseCount: number;

  visionUnits?: number;
}) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error(
      "Faltan variables internas de Supabase para guardar ocr_cache.",
    );
  }

  const response = await fetch(
    `${supabaseUrl}/rest/v1/ocr_cache`,
    {
      method: "POST",

      headers: {
        apikey: serviceRoleKey,

        Authorization: `Bearer ${serviceRoleKey}`,

        "Content-Type": "application/json",

        Prefer: "resolution=ignore-duplicates,return=minimal",
      },

      body: JSON.stringify({
        document_hash: documentHash,

        mime_type: mimeType,

        result,

        page_count: pageCount,

        course_count: courseCount,

        vision_units: visionUnits,
      }),
    },
  );

  if (!response.ok) {
    throw new Error(
      `Error guardando ocr_cache: ${response.status} ${await response.text()}`,
    );
  }
}

function parseCourseCodeAndCredits(text: string) {
  const clean = text.toUpperCase().replace(/\s+/g, " ").trim();

  const punctuationClean = clean
    .replace(/^[^A-Z0-9]+/g, "")
    .replace(/[^A-Z0-9]+$/g, "")
    .trim();

  // Ej.: "PGY3121 12".
  const codeCredits = punctuationClean.match(
    /^([A-Z\s]{2,6}\d{4})\s+(\d{1,2})$/,
  );

  if (codeCredits) {
    const code = codeCredits[1].replace(/\s+/g, "");

    if (/^[A-Z]{2,4}\d{4,5}$/.test(code)) {
      return { code, credits: Number(codeCredits[2]) };
    }
  }

  const code = punctuationClean.replace(/\s+/g, "");

  if (/^[A-Z]{2,4}\d{4,5}$/.test(code)) {
    return { code, credits: null };
  }

  // Ej.: OCR "TTS1101 ." o un código dentro de un bloque pequeño.
  const embeddedCode = punctuationClean.match(
    /\b([A-Z]{2,4}\s*\d{4})\b/,
  );

  if (embeddedCode) {
    return {
      code: embeddedCode[1].replace(/\s+/g, ""),
      credits: null,
    };
  }

  return { code: null, credits: null };
}

function parseFlexibleCourseData(text: string) {
  const direct = parseCourseCodeAndCredits(text);

  if (direct.code) return direct;

  const clean = text.toUpperCase().replace(/\s+/g, " ").trim();

  const codeMatch = clean.match(/\b([A-Z]{2,4}\s*\d{4})\b/);

  if (!codeMatch) {
    return { code: null, credits: null };
  }

  const code = codeMatch[1].replace(/\s+/g, "");

  const creditsMatch = clean.match(/\b(\d{1,2})\s*CRÉDITOS?\b/);

  return {
    code,

    credits: creditsMatch ? Number(creditsMatch[1]) : null,
  };
}

function cleanCourseName(name: string | null): string | null {
  if (!name) return null;

  const cleaned = name
    .replace(/[→←↔⇢⇠⇄⇆]+/g, " ")
    .replace(/^[•●▪■◆◇·\-–—\s]+/g, "")
    .replace(/[•●▪■◆◇·\-–—\s]+$/g, "")
    .replace(/\s+/g, " ")
    .trim();

  return cleaned.length > 0 ? cleaned : null;
}

const NON_COURSE_NAME_LABELS = new Set([
  "ESPECIALIDADES",
  "ESPECIALIDAD",
  "FORMACIÓN GENERAL",
  "FORMACION GENERAL",
  "FORMACIÓN SELLO",
  "FORMACION SELLO",
  "FORMACIÓN COMPLEMENTARIA",
  "FORMACION COMPLEMENTARIA",
  "BÁSICAS Y DE EMPLEABILIDAD",
  "BASICAS Y DE EMPLEABILIDAD",
  "BÁSICAS FORMACIÓN VALÓRICA",
  "BASICAS FORMACION VALORICA",
]);

function normalizeLabelText(text: string): string {
  return text
    .toUpperCase()
    .replace(/[•●▪■◆◇·]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function isNonCourseNameLabel(text: string): boolean {
  return NON_COURSE_NAME_LABELS.has(normalizeLabelText(text));
}

function documentAppearsToUseCourseCredits(blocks: any[]): boolean {
  let creditSignals = 0;

  for (const block of blocks) {
    const text = typeof block?.text === "string" ? block.text : "";

    if (block?.type === "course_code_credits") {
      creditSignals += 1;
      continue;
    }

    if (/^\s*\d{1,2}\s*CRÉDITOS?\s*$/i.test(text)) {
      creditSignals += 1;
      continue;
    }

    // Numbers close to common course-credit ranges are useful only when
    // they appear repeatedly in the document.
    if (block?.type === "number") {
      const value = Number(text.trim());

      if (
        Number.isFinite(value) &&
        value >= 1 &&
        value <= 30
      ) {
        creditSignals += 1;
      }
    }
  }

  return creditSignals >= 3;
}

// v2.1: ordinal-semester detection. Keep the legacy one-row parser unchanged
// unless a real two-band curricular grid is supported by multiple headings.
const ORDINAL_SEMESTERS: Record<string, number> = {
  PRIMER: 1,
  PRIMERO: 1,
  SEGUNDO: 2,
  TERCER: 3,
  TERCERO: 3,
  CUARTO: 4,
  QUINTO: 5,
  SEXTO: 6,
  SEPTIMO: 7,
  SÉPTIMO: 7,
  OCTAVO: 8,
  NOVENO: 9,
  DECIMO: 10,
  DÉCIMO: 10,
  UNDECIMO: 11,
  UNDÉCIMO: 11,
  DUODECIMO: 12,
  DUODÉCIMO: 12,
};

function detectOrdinalSemesterGrid(blocks: any[]): any[] {
  const candidates: any[] = [];
  for (const block of blocks) {
    const page = block?.page;
    const words = Array.isArray(block?.words) ? block.words : [];
    if (typeof page !== "number") continue;
    // Prefer word geometry so a header coalesced with the first subject is
    // reconstructed without absorbing that subject.
    for (let i = 0; i < words.length - 1; i++) {
      const a = words[i], b = words[i + 1];
      const first = String(a?.text ?? "").trim().toUpperCase();
      const second = String(b?.text ?? "").trim().toUpperCase();
      const semester = ORDINAL_SEMESTERS[first];
      if (!semester || second !== "SEMESTRE") continue;
      const p = a?.position, q = b?.position;
      if (
        !p || !q || typeof p.centerY !== "number" ||
        typeof q.centerY !== "number" ||
        Math.abs(p.centerY - q.centerY) > 10 ||
        typeof p.xMin !== "number" || typeof q.xMax !== "number"
      ) continue;
      candidates.push({
        semester,
        page,
        centerX: (p.xMin + q.xMax) / 2,
        centerY: (p.centerY + q.centerY) / 2,
        sourceBlock: block.block,
        source: "words",
      });
    }
    // Old/normalized cached results can lack word-level coordinates.
    if (
      words.length < 2 && typeof block?.text === "string" &&
      typeof block?.position?.centerX === "number"
    ) {
      const match = block.text.trim().toUpperCase().match(
        /^(PRIMER|PRIMERO|SEGUNDO|TERCER|TERCERO|CUARTO|QUINTO|SEXTO|SÉPTIMO|SEPTIMO|OCTAVO|NOVENO|DÉCIMO|DECIMO)\s+SEMESTRE$/,
      );
      if (match) {
        candidates.push({
          semester: ORDINAL_SEMESTERS[match[1]],
          page,
          centerX: block.position.centerX,
          centerY: block.position.centerY,
          sourceBlock: block.block,
          source: "block",
        });
      }
    }
  }
  const pages = new Map<number, any[]>();
  for (const candidate of candidates) {
    const group = pages.get(candidate.page) ?? [];
    group.push(candidate);
    pages.set(candidate.page, group);
  }
  let best: any[] = [];
  for (const group of pages.values()) {
    const bySemester = new Map<number, any>();
    for (const entry of group) {
      if (!bySemester.has(entry.semester)) {
        bySemester.set(entry.semester, entry);
      }
    }
    const distinct = [...bySemester.values()];
    if (distinct.length > best.length) best = distinct;
  }
  if (best.length < 6) return [];
  const ys = best.map((x) => x.centerY).sort((a, b) => a - b);
  let largestGap = 0, division = 0;
  for (let i = 1; i < ys.length; i++) {
    const gap = ys[i] - ys[i - 1];
    if (gap > largestGap) {
      largestGap = gap;
      division = (ys[i] + ys[i - 1]) / 2;
    }
  }
  // Two independently headed rows; never interpret course roman numerals as headers.
  if (
    largestGap < 100 || best.filter((x) => x.centerY < division).length < 3 ||
    best.filter((x) => x.centerY >= division).length < 3
  ) return [];
  return best.map((entry) => ({
    ...entry,
    layoutBand: entry.centerY < division ? "upper" : "lower",
    gridDividerY: division,
  }))
    .sort((a, b) => a.semester - b.semester);
}

function splitGridBlockByVisualRows(block: any): any[] {
  if (!Array.isArray(block?.words) || block.words.length === 0) return [];
  const sorted = block.words.filter((w: any) =>
    typeof w?.position?.centerY === "number" &&
    typeof w?.position?.centerX === "number" && typeof w?.text === "string"
  )
    .sort((a: any, b: any) =>
      a.position.centerY - b.position.centerY ||
      a.position.centerX - b.position.centerX
    );
  const lines: any[][] = [];
  for (const word of sorted) {
    let line = lines.find((line) =>
      Math.abs(
        line.reduce((sum: any, w: any) => sum + w.position.centerY, 0) /
            line.length - word.position.centerY,
      ) <= 8
    );
    if (!line) {
      line = [];
      lines.push(line);
    }
    line.push(word);
  }
  lines.sort((a, b) =>
    Math.min(...a.map((w: any) => w.position.centerY)) -
    Math.min(...b.map((w: any) => w.position.centerY))
  );
  const rows: any[][] = [];
  for (const line of lines) {
    line.sort((a, b) => a.position.centerX - b.position.centerX);
    const current = rows[rows.length - 1];
    const prev = current?.[current.length - 1];
    const prevY = prev
      ? prev.reduce((s: number, w: any) => s + w.position.centerY, 0) /
        prev.length
      : null;
    const lineY = line.reduce((s: number, w: any) =>
      s + w.position.centerY, 0) / line.length;
    if (!current || prevY === null || lineY - prevY > 23) {
      rows.push([line]);
    } else current.push(line);
  }
  return rows.map((row) => {
    const words = row.flat();
    const bounds = (p: string) =>
      words.map((w: any) => w.position[p]).filter((v: any) =>
        typeof v === "number"
      );
    const xMin = Math.min(...bounds("xMin")),
      xMax = Math.max(...bounds("xMax"));
    const yMin = Math.min(...bounds("yMin")),
      yMax = Math.max(...bounds("yMax"));
    return {
      page: block.page,
      block: block.block,
      text: row.map((line) => line.map((w: any) => w.text).join(" ")).join(" ")
        .replace(/\s+/g, " ").trim(),
      confidence: typeof block.confidence === "number"
        ? block.confidence
        : null,
      words,
      position: {
        xMin,
        xMax,
        yMin,
        yMax,
        centerX: (xMin + xMax) / 2,
        centerY: (yMin + yMax) / 2,
        width: xMax - xMin,
        height: yMax - yMin,
      },
    };
  });
}

function detectTwoBandGridCourseCandidates(
  blocks: any[],
  headers: any[],
): any[] {
  const page = headers[0]?.page;
  if (typeof page !== "number") return [];
  const upper = headers.filter((c) => c.layoutBand === "upper");
  const lower = headers.filter((c) => c.layoutBand === "lower");
  const upperY = Math.min(...upper.map((h) => h.centerY));
  const lowerY = Math.min(...lower.map((h) => h.centerY));
  const dividerY = headers[0].gridDividerY;
  const xColumns = [...upper].sort((a, b) => a.centerX - b.centerX);
  const columnBounds = xColumns.map((col, i) => ({
    left: i === 0
      ? col.centerX - (xColumns[1].centerX - col.centerX) / 2
      : (xColumns[i - 1].centerX + col.centerX) / 2,
    right: i === xColumns.length - 1
      ? col.centerX + (col.centerX - xColumns[i - 1].centerX) / 2
      : (col.centerX + xColumns[i + 1].centerX) / 2,
    centerX: col.centerX,
  }));
  const entries: any[] = [];
  for (const block of blocks) {
    if (block?.page !== page) continue;
    for (const frag of splitGridBlockByVisualRows(block)) {
      const x = frag.position.centerX, y = frag.position.centerY;
      if (y <= upperY + 12 || (y >= lowerY - 14 && y <= lowerY + 14)) continue;
      if (
        /^(?:\*?\s*MALLA\s+SUJETA\s+A\s+CAMBIOS|MALLA\s+CURRICULAR)\b/i.test(
          frag.text,
        )
      ) continue;
      if (
        /^(?:PRIMER|PRIMERO|SEGUNDO|TERCER|TERCERO|CUARTO|QUINTO|SEXTO|SÉPTIMO|SEPTIMO|OCTAVO|NOVENO|DÉCIMO|DECIMO)\s+SEMESTRE\b/i
          .test(frag.text)
      ) continue;
      const col = columnBounds.find((c) => x >= c.left && x < c.right);
      if (!col || Math.abs(x - col.centerX) > 65) continue;
      const band = y < lowerY ? upper : lower;
      const anchor = band.reduce(
        (best: any, h: any) =>
          Math.abs(h.centerX - x) < Math.abs(best.centerX - x) ? h : best,
        band[0],
      );
      if (!anchor || Math.abs(x - anchor.centerX) > 65) continue;
      if (y <= anchor.centerY + 12) continue;
      // Catch detached fragments that belong to a longer title, but never
      // include ornamental image glyphs outside semester columns.
      const text = frag.text.replace(/\s+/g, " ").trim();
      if (text.length < 3 || /^\d+$/.test(text)) continue;
      entries.push({
        text,
        page,
        block: frag.block,
        confidence: frag.confidence,
        centerX: x,
        centerY: y,
        yMin: frag.position.yMin,
        yMax: frag.position.yMax,
        semester: anchor.semester,
        distanceX: Math.abs(x - anchor.centerX),
      });
    }
  }
  // Fragment joining is confined to one semester and tight visual line spacing.
  // A large gap is necessarily another curricular box, even if Vision grouped it.
  const result: any[] = [];
  for (const header of headers) {
    const sorted = entries.filter((c) => c.semester === header.semester)
      .sort((a, b) => a.yMin - b.yMin || a.centerX - b.centerX);
    let current: any = null;
    for (const item of sorted) {
      const gap = current ? item.yMin - current.yMax : Infinity;
      const xGap = current
        ? Math.abs(item.centerX - current.centerX)
        : Infinity;
      const isContinuation = current && gap >= -4 && gap <= 10 && xGap <= 33 &&
        (item.centerY - current.centerY) <= 24;
      if (isContinuation) {
        current.text += ` ${item.text}`;
        current.blocks.push(item.block);
        current.centerX = (current.centerX + item.centerX) / 2;
        current.centerY = item.centerY;
        current.yMin = Math.min(current.yMin, item.yMin);
        current.yMax = Math.max(current.yMax, item.yMax);
        if (typeof item.confidence === "number") {
          current.confidence = typeof current.confidence === "number"
            ? Math.min(current.confidence, item.confidence)
            : item.confidence;
        }
      } else {
        if (current) result.push(current);
        current = {
          semester: header.semester,
          page,
          text: item.text,
          blocks: [item.block],
          centerX: item.centerX,
          centerY: item.centerY,
          yMin: item.yMin,
          yMax: item.yMax,
          confidence: item.confidence,
        };
      }
    }
    if (current) result.push(current);
  }
  return result.sort((a, b) => a.semester - b.semester || a.yMin - b.yMin)
    .map((candidate) => ({
      ...candidate,
      text: candidate.text.replace(/\s+([,;:])/g, "$1")
        .replace(/\bFund\s+\.\s+/gi, "Fund. ")
        .replace(/\s*-\s*/g, "-"),
      gridFinalized: true,
    }));
}

// v2.2: a strong *number above SEMESTRE* pattern activates its own parser.
// Unlike ordinary 01/02 labels or roman numerals in course names, a real
// header is verified by two independent geometrically aligned OCR blocks,
// a consistent header row, and a consecutively numbered grid on one page.
function detectSplitNumericSemesterGrid(blocks: any[]): any[] {
  if (!Array.isArray(blocks) || blocks.length === 0) return [];
  const groups = new Map<number, any[]>();
  for (const block of blocks) {
    const page = block?.page;
    const text = String(block?.text ?? "").trim().toUpperCase();
    const x = block?.position?.centerX;
    const y = block?.position?.centerY;
    if (
      typeof page !== "number" || typeof x !== "number" || typeof y !== "number"
    ) continue;
    const group = groups.get(page) ?? [];
    const num = text.match(/^(0?[1-9]|1[0-2])(?:[º°])?$/);
    if (num) {
      group.push({
        kind: "number",
        semester: Number(num[1]),
        page,
        x,
        y,
        block: block.block,
      });
    } else if (text === "SEMESTRE") {
      group.push({ kind: "label", page, x, y, block: block.block });
    }
    groups.set(page, group);
  }
  let best: any[] = [];
  for (const items of groups.values()) {
    const labels = items.filter((x) => x.kind === "label");
    const numbers = items.filter((x) => x.kind === "number");
    const pairs: any[] = [];
    for (const num of numbers) {
      const nearby = labels.filter((label) =>
        label.y - num.y >= 12 && label.y - num.y <= 53 &&
        Math.abs(label.x - num.x) <= 28
      )
        .sort((a, b) =>
          Math.abs(a.x - num.x) - Math.abs(b.x - num.x) ||
          Math.abs(a.y - num.y - 28) - Math.abs(b.y - num.y - 28)
        );
      if (!nearby.length) continue;
      const label = nearby[0];
      pairs.push({
        semester: num.semester,
        page: num.page,
        centerX: label.x,
        centerY: label.y,
        headerNumberY: num.y,
        numericSplitGrid: true,
        sourceBlock: num.block,
        labelBlock: label.block,
      });
    }
    // Numeric-only headings and unrelated labels are not evidence of a grid.
    const unique = new Map<number, any>();
    for (const pair of pairs) {
      if (!unique.has(pair.semester)) unique.set(pair.semester, pair);
    }
    const ordered = [...unique.values()].sort((a, b) => a.centerX - b.centerX);
    if (ordered.length < 5) continue;
    const headerYs = ordered.map((x) => x.centerY);
    if (Math.max(...headerYs) - Math.min(...headerYs) > 15) continue;
    const minSem = Math.min(...ordered.map((x) => x.semester));
    const maxSem = Math.max(...ordered.map((x) => x.semester));
    if (minSem !== 1 || ordered.length !== maxSem) continue;
    if (ordered.some((x, i) => x.semester !== i + 1)) continue;
    const widths = ordered.slice(1).map((x, i) =>
      x.centerX - ordered[i].centerX
    );
    if (widths.some((w) => w < 34 || w > 180)) continue;
    if (ordered.length > best.length) best = ordered;
  }
  return best.sort((a, b) => a.semester - b.semester);
}

function detectSplitNumericGridCourseCandidates(
  blocks: any[],
  columns: any[],
): any[] {
  const page = columns[0]?.page;
  if (typeof page !== "number" || columns.length < 5) return [];
  const sorted = [...columns].sort((a, b) => a.centerX - b.centerX);
  const spacings = sorted.slice(1).map((c, i) => c.centerX - sorted[i].centerX)
    .sort((a, b) => a - b);
  const spacing = spacings[Math.floor(spacings.length / 2)] ?? 85;
  const headerY = Math.max(...columns.map((c) => c.centerY));
  const pageBlocks = blocks.filter((b) =>
    b?.page === page &&
    typeof b?.position?.centerX === "number" &&
    typeof b?.position?.centerY === "number"
  );
  // A documentary footer often follows the actual grid. The marker must be
  // a lower-page section heading, not a legitimate "Pasantía Laboral I" tile.
  const footerMarker =
    /^(?:PASANT[IÍ]AS? LABORALES|MALLA SUJETA A CAMBIOS|INFORMACI[OÓ]N ACTUALIZADA|REVIS[AE] AQU[IÍ]|UBICACI[OÓ]N|CONOCE M[AÁ]S)\b/i;
  const footerY = pageBlocks.filter((b) =>
    b.position.centerY > 800 &&
    footerMarker.test(String(b.text ?? "").trim()) &&
    typeof b.position.yMin === "number"
  )
    .map((b) => b.position.yMin)
    .reduce((min: number, y: number) => Math.min(min, y), 1000);
  const endY = Math.min(980, footerY);
  const ignoredExact = new Set([
    "SEMESTRE",
    "ACI",
    "PROFUNDIZACIÓN ELECTIVA",
    "LICENCIADO/A EN CIENCIAS DE LA INGENIERÍA",
    "EGRESO Y TITULACIÓN",
    "CICLO INICIAL",
    "CICLO LICENCIATURA",
    "CICLO DE PROFUNDIZACIÓN",
  ]);
  const fragments: any[] = [];
  for (const b of pageBlocks) {
    const p = b.position,
      text = String(b.text ?? "").replace(/\s+/g, " ").trim();
    if (!text || text.length < 3 || p.yMin < headerY + 20 || p.yMin >= endY) {
      continue;
    }
    const norm = normalizeLabelText(text);
    if (ignoredExact.has(norm)) continue;
    if (
      /^(?:MALLA CURRICULAR|PLAN COM[UÚ]N|C[OÓ]DIGO (?:DEMRE|SIES)|CICLO\b|LAS PASANT[IÍ]AS|LOS ESTUDIANTES|\*|ENTRE LOS SEMESTRES|UNIVERSIDAD\b)/i
        .test(norm)
    ) continue;
    if (/\b(?:https?:|www\.|\.cl|@)\b/i.test(text)) continue;
    // The program's degree-award tile can be vertically typeset. Keep that
    // course, but exclude long narrow decorative labels and side captions.
    const tallTitle = /^ACTIVIDAD DE TITULACI[OÓ]N\b/i.test(norm);
    if (typeof p.height !== "number" || p.height > (tallTitle ? 205 : 110)) {
      continue;
    }
    if (
      typeof p.width !== "number" || p.width > Math.max(105, spacing * 1.25)
    ) continue;
    const column = sorted.reduce((best, c) =>
      Math.abs(p.centerX - c.centerX) <
          Math.abs(p.centerX - best.centerX)
        ? c
        : best, sorted[0]);
    const dist = Math.abs(p.centerX - column.centerX);
    if (dist > Math.min(48, spacing * 0.57)) continue;
    // Prevent paragraph/legend text from entering the first row of subjects.
    if (p.centerY < headerY + 30) continue;
    fragments.push({
      semester: column.semester,
      page,
      block: b.block,
      text,
      confidence: typeof b.confidence === "number" ? b.confidence : null,
      centerX: p.centerX,
      centerY: p.centerY,
      yMin: p.yMin,
      yMax: p.yMax,
      gridSourceBlock: b.block,
    });
  }
  const results: any[] = [];
  for (const column of sorted) {
    const items = fragments.filter((f) => f.semester === column.semester)
      .sort((a, b) => a.yMin - b.yMin || a.centerX - b.centerX);
    let current: any = null;
    for (const item of items) {
      if (!current) {
        current = { ...item, blocks: [item.block] };
        continue;
      }
      const gap = item.yMin - current.yMax;
      // The vertical gap inside a wrapped title is much smaller than the
      // gap between adjacent boxes (e.g. 6 vs. 50+ normalized px).
      const joined = gap >= -5 && gap <= 10 &&
        item.centerY - current.centerY <= 37 &&
        Math.abs(item.centerX - current.centerX) <= 37 &&
        !/^ACTIVIDAD DE TITULACI[OÓ]N\b/i.test(current.text);
      if (joined) {
        const hyphen = /[-‐‑]\s*$/.test(current.text);
        current.text = (hyphen
          ? current.text.replace(/[-‐‑]\s*$/g, "") + item.text
          : current.text + " " + item.text).replace(/\s+/g, " ").trim();
        current.yMax = Math.max(current.yMax, item.yMax);
        current.centerY = item.centerY;
        current.centerX = (current.centerX + item.centerX) / 2;
        current.blocks.push(item.block);
        if (typeof item.confidence === "number") {
          current.confidence = typeof current.confidence === "number"
            ? Math.min(current.confidence, item.confidence)
            : item.confidence;
        }
      } else {
        results.push(current);
        current = { ...item, blocks: [item.block] };
      }
    }
    if (current) results.push(current);
  }
  return results.sort((a, b) => a.semester - b.semester || a.yMin - b.yMin)
    .map((item) => ({
      semester: item.semester,
      page: item.page,
      text: item.text,
      blocks: item.blocks,
      centerX: item.centerX,
      centerY: item.centerY,
      yMin: item.yMin,
      yMax: item.yMax,
      confidence: item.confidence,
      gridFinalized: true,
      numericSplitGrid: true,
      ...(/^(?:ELECTIVO PROFESIONAL|CURSO DE FORMACI[OÓ]N GENERAL)$/i.test(
          item.text,
        )
        ? { curricularSlotType: "elective_slot" }
        : {}),
    }));
}

function detectCurriculumParsingMode(
  blocks: any[],
): "code_based" | "layout_based" {
  const codeAnchors = blocks.filter(
    (block) =>
      block?.type === "course_code" ||
      block?.type === "course_code_credits",
  );

  // Si existen varios códigos académicos reales,
  // mantenemos el parser tradicional basado en códigos.
  if (codeAnchors.length >= 3) {
    return "code_based";
  }

  // v2.1: only opt into two-band layout after finding multiple real ordinal headers.
  if (
    detectOrdinalSemesterGrid(blocks).length >= 6 ||
    detectSplitNumericSemesterGrid(blocks).length >= 5
  ) return "layout_based";

  // Reutilizamos el mismo detector de columnas para aceptar
  // semestres arábigos y romanos sin duplicar heurísticas.
  const semesterColumns = detectSemesterColumns(blocks);

  if (semesterColumns.length < 4) {
    return "code_based";
  }

  const curriculumPage = semesterColumns[0]?.page;

  if (typeof curriculumPage !== "number") {
    return "code_based";
  }

  const curriculumTextBlocks = blocks.filter((block) => {
    if (block?.page !== curriculumPage) return false;
    if (block?.type !== "text") return false;
    if (typeof block?.text !== "string") return false;

    const text = block.text.trim();

    if (text.length < 4) return false;

    const normalized = normalizeLabelText(text);

    const excludedLabels = [
      "SEMESTRE",
      "CICLO INICIAL",
      "CICLO INTERMEDIO",
      "CICLO AVANZADO",
      "MALLA CURRICULAR",
      "ÁREA",
      "DE FORMACIÓN",
      "BÁSICA",
      "PROFESIONAL",
      "GENERAL",
    ];

    return !excludedLabels.includes(normalized);
  });

  // Pocos o ningún código + varias columnas de semestre +
  // suficiente contenido curricular => parser por layout.
  if (
    codeAnchors.length <= 2 &&
    semesterColumns.length >= 4 &&
    curriculumTextBlocks.length >= 10
  ) {
    return "layout_based";
  }

  return "code_based";
}

function parseSemesterNumber(
  text: string,
): number | null {
  const normalized = text
    .toUpperCase()
    .replace(/\s+/g, " ")
    .trim();

  const ordinalHeader = normalized.match(
    /^(PRIMER|PRIMERO|SEGUNDO|TERCER|TERCERO|CUARTO|QUINTO|SEXTO|SÉPTIMO|SEPTIMO|OCTAVO|NOVENO|DÉCIMO|DECIMO)\s+SEMESTRE$/,
  );
  if (ordinalHeader) return ORDINAL_SEMESTERS[ordinalHeader[1]] ?? null;

  // Formatos:
  // 1
  // 1º
  // 1 SEMESTRE
  const arabicSuffixMatch = normalized.match(
    /^(\d{1,2})(?:º|°)?(?:\s+SEMESTRE)?$/,
  );

  if (arabicSuffixMatch) {
    const value = Number(
      arabicSuffixMatch[1],
    );

    if (
      Number.isInteger(value) &&
      value >= 1 &&
      value <= 12
    ) {
      return value;
    }
  }

  // Formatos:
  // SEMESTRE 1
  // SEMESTRE 10
  const arabicPrefixMatch = normalized.match(
    /^SEMESTRE\s+(\d{1,2})(?:º|°)?$/,
  );

  if (arabicPrefixMatch) {
    const value = Number(
      arabicPrefixMatch[1],
    );

    if (
      Number.isInteger(value) &&
      value >= 1 &&
      value <= 12
    ) {
      return value;
    }
  }

  const romanValues: Record<string, number> = {
    I: 1,
    II: 2,
    III: 3,
    IV: 4,
    V: 5,
    VI: 6,
    VII: 7,
    VIII: 8,
    IX: 9,
    X: 10,
    XI: 11,
    XII: 12,
  };

  // I
  // I SEMESTRE
  const romanSuffixMatch = normalized.match(
    /^(I|II|III|IV|V|VI|VII|VIII|IX|X|XI|XII)(?:\s+SEMESTRE)?$/,
  );

  if (romanSuffixMatch) {
    return (
      romanValues[
        romanSuffixMatch[1]
      ] ?? null
    );
  }

  // SEMESTRE I
  const romanPrefixMatch = normalized.match(
    /^SEMESTRE\s+(I|II|III|IV|V|VI|VII|VIII|IX|X|XI|XII)$/,
  );

  if (romanPrefixMatch) {
    return (
      romanValues[
        romanPrefixMatch[1]
      ] ?? null
    );
  }

  return null;
}

function detectSemesterColumns(
  blocks: any[],
) {
  const ordinalGrid = detectOrdinalSemesterGrid(blocks);
  if (ordinalGrid.length >= 6) return ordinalGrid;
  const numericGrid = detectSplitNumericSemesterGrid(blocks);
  if (numericGrid.length >= 5) return numericGrid;
  if (
    !Array.isArray(blocks) ||
    blocks.length === 0
  ) {
    return [];
  }

  const candidates: any[] = [];

  for (const block of blocks) {
    const page = typeof block?.page === "number" ? block.page : null;

    const blockCenterY = block?.position?.centerY;

    if (
      page === null ||
      typeof blockCenterY !== "number"
    ) {
      continue;
    }

    /*
     * Los encabezados de semestre normalmente
     * están en la zona superior de la página.
     *
     * Conservamos este filtro para evitar que
     * números romanos dentro de asignaturas sean
     * interpretados como encabezados.
     */
    if (blockCenterY > 180) {
      continue;
    }

    /*
     * CASO 1:
     * El bloque completo ya representa un semestre.
     *
     * Ejemplos:
     * "1º Semestre"
     * "Semestre 1"
     * "I"
     * "I Semestre"
     */
    if (typeof block?.text === "string") {
      const directSemester = parseSemesterNumber(
        block.text,
      );

      if (
        directSemester !== null &&
        typeof block?.position?.centerX ===
          "number"
      ) {
        candidates.push({
          semester: directSemester,
          page,
          centerX: block.position.centerX,
          centerY: block.position.centerY,
          sourceBlock: block.block ?? null,
          source: "block",
        });
      }
    }

    /*
     * CASO 2:
     * Vision agrupó varios encabezados dentro
     * de un mismo bloque.
     *
     * Ejemplos:
     *
     * "Semestre 4 Semestre 5"
     *
     * "Semestre 7 Semestre 8 Semestre 9"
     *
     * Analizamos las palabras individualmente
     * y reconstruimos pares válidos.
     */
    if (
      !Array.isArray(block?.words) ||
      block.words.length < 2
    ) {
      continue;
    }

    const words = [...block.words]
      .filter(
        (word) =>
          typeof word?.text === "string" &&
          typeof word?.position?.centerX ===
            "number" &&
          typeof word?.position?.centerY ===
            "number",
      )
      .sort((a, b) => {
        const yDifference = a.position.centerY -
          b.position.centerY;

        if (
          Math.abs(yDifference) > 6
        ) {
          return yDifference;
        }

        return (
          a.position.centerX -
          b.position.centerX
        );
      });

    for (
      let index = 0;
      index < words.length - 1;
      index++
    ) {
      const first = words[index];

      const second = words[index + 1];

      const firstText = first.text
        .replace(/\s+/g, " ")
        .trim();

      const secondText = second.text
        .replace(/\s+/g, " ")
        .trim();

      if (
        !firstText ||
        !secondText
      ) {
        continue;
      }

      /*
       * Solo aceptamos pares donde exista
       * explícitamente la palabra SEMESTRE.
       *
       * Esto evita confundir números o romanos
       * pertenecientes a nombres de asignaturas.
       */
      const firstNormalized = normalizeLabelText(
        firstText,
      );

      const secondNormalized = normalizeLabelText(
        secondText,
      );

      if (
        firstNormalized !== "SEMESTRE" &&
        secondNormalized !== "SEMESTRE"
      ) {
        continue;
      }

      const combinedText = `${firstText} ${secondText}`;

      const semester = parseSemesterNumber(
        combinedText,
      );

      if (semester === null) {
        continue;
      }

      const xValues = [
        first?.position?.xMin,
        first?.position?.xMax,
        second?.position?.xMin,
        second?.position?.xMax,
      ].filter(
        (value) => typeof value === "number",
      );

      const yValues = [
        first?.position?.yMin,
        first?.position?.yMax,
        second?.position?.yMin,
        second?.position?.yMax,
      ].filter(
        (value) => typeof value === "number",
      );

      if (
        xValues.length === 0 ||
        yValues.length === 0
      ) {
        continue;
      }

      const xMin = Math.min(...xValues);

      const xMax = Math.max(...xValues);

      const yMin = Math.min(...yValues);

      const yMax = Math.max(...yValues);

      candidates.push({
        semester,
        page,
        centerX: (xMin + xMax) / 2,
        centerY: (yMin + yMax) / 2,
        sourceBlock: block.block ?? null,
        source: "words",
      });
    }
  }

  if (candidates.length === 0) {
    return [];
  }

  /*
   * Agrupamos candidatos por página.
   * La página curricular será aquella que
   * contenga más semestres distintos.
   */
  const byPage = new Map<number, any[]>();

  for (const candidate of candidates) {
    const items = byPage.get(
      candidate.page,
    ) ?? [];

    items.push(candidate);

    byPage.set(
      candidate.page,
      items,
    );
  }

  let bestPage: number | null = null;

  let bestUniqueSemesterCount = 0;

  for (
    const [page, items] of byPage.entries()
  ) {
    const uniqueSemesters = new Set(
      items.map(
        (item) => item.semester,
      ),
    );

    if (
      uniqueSemesters.size >
        bestUniqueSemesterCount
    ) {
      bestPage = page;

      bestUniqueSemesterCount = uniqueSemesters.size;
    }
  }

  /*
   * Exigimos mínimo 4 semestres para considerar
   * que realmente encontramos una estructura
   * curricular por columnas.
   */
  if (
    bestPage === null ||
    bestUniqueSemesterCount < 4
  ) {
    return [];
  }

  const pageCandidates = candidates.filter(
    (candidate) =>
      candidate.page ===
        bestPage,
  );

  /*
   * Puede ocurrir que el mismo semestre haya
   * sido detectado tanto por bloque completo
   * como por palabras.
   *
   * Conservamos un único candidato.
   *
   * Si existe detección por palabras,
   * la preferimos porque su posición horizontal
   * es más precisa.
   */
  const bestBySemester = new Map<number, any>();

  for (
    const candidate of pageCandidates
  ) {
    const existing = bestBySemester.get(
      candidate.semester,
    );

    if (!existing) {
      bestBySemester.set(
        candidate.semester,
        candidate,
      );

      continue;
    }

    if (
      candidate.source === "words" &&
      existing.source !== "words"
    ) {
      bestBySemester.set(
        candidate.semester,
        candidate,
      );
    }
  }

  return Array
    .from(
      bestBySemester.values(),
    )
    .sort(
      (a, b) =>
        a.semester -
        b.semester,
    )
    .map((candidate) => ({
      semester: candidate.semester,

      page: candidate.page,

      centerX: candidate.centerX,

      centerY: candidate.centerY,
    }));
}

function assignSemesterByColumn(
  block: any,
  semesterColumns: any[],
) {
  if (
    Array.isArray(semesterColumns) &&
    semesterColumns.some((column) => column?.layoutBand)
  ) {
    const x = block?.position?.centerX, y = block?.position?.centerY;
    if (typeof x !== "number" || typeof y !== "number") return null;
    const lowerHeaderY = Math.min(
      ...semesterColumns.filter((c) => c.layoutBand === "lower").map((c) =>
        c.centerY
      ),
    );
    const relevant = semesterColumns.filter((column) =>
      column.page === block.page &&
      (y < lowerHeaderY
        ? column.layoutBand === "upper"
        : column.layoutBand === "lower")
    );
    if (!relevant.length) return null;
    const closest = relevant.reduce(
      (best, c) =>
        Math.abs(c.centerX - x) < Math.abs(best.centerX - x) ? c : best,
      relevant[0],
    );
    return {
      semester: closest.semester,
      semesterColumnX: closest.centerX,
      distanceX: Math.abs(closest.centerX - x),
    };
  }
  const centerX = block?.position?.centerX;

  if (typeof centerX !== "number") {
    return null;
  }

  if (!Array.isArray(semesterColumns) || semesterColumns.length === 0) {
    return null;
  }

  let bestMatch: any = null;
  let bestDistance = Number.POSITIVE_INFINITY;

  for (const column of semesterColumns) {
    if (typeof column?.centerX !== "number") continue;

    const distance = Math.abs(centerX - column.centerX);

    if (distance < bestDistance) {
      bestDistance = distance;
      bestMatch = column;
    }
  }

  if (!bestMatch) {
    return null;
  }

  return {
    semester: bestMatch.semester,
    semesterColumnX: bestMatch.centerX,
    distanceX: bestDistance,
  };
}

function splitBlockBySemesterColumns(
  block: any,
  semesterColumns: any[],
) {
  if (
    !Array.isArray(block?.words) ||
    block.words.length === 0 ||
    !Array.isArray(semesterColumns) ||
    semesterColumns.length === 0
  ) {
    return [block];
  }

  const pageColumns = semesterColumns
    .filter(
      (column) =>
        column?.page === block?.page &&
        typeof column?.centerX === "number",
    )
    .sort(
      (a, b) => a.centerX - b.centerX,
    );

  if (pageColumns.length === 0) {
    return [block];
  }

  /*
   * Construimos los límites horizontales reales
   * de cada semestre.
   *
   * Entre dos columnas, el límite es exactamente
   * el punto medio entre sus centros.
   *
   * Para la primera y última columna extrapolamos
   * medio espacio de columna hacia afuera.
   */
  const columnBands = pageColumns.map(
    (column, index) => {
      let left: number;
      let right: number;

      if (pageColumns.length === 1) {
        left = column.centerX - 45;
        right = column.centerX + 45;
      } else {
        if (index === 0) {
          const next = pageColumns[index + 1];

          const spacing = next.centerX -
            column.centerX;

          left = column.centerX -
            spacing / 2;
        } else {
          const previous = pageColumns[index - 1];

          left = (
            previous.centerX +
            column.centerX
          ) / 2;
        }

        if (
          index ===
            pageColumns.length - 1
        ) {
          const previous = pageColumns[index - 1];

          const spacing = column.centerX -
            previous.centerX;

          right = column.centerX +
            spacing / 2;
        } else {
          const next = pageColumns[index + 1];

          right = (
            column.centerX +
            next.centerX
          ) / 2;
        }
      }

      return {
        ...column,
        left,
        right,
      };
    },
  );

  const groups = new Map<number, any[]>();

  for (const word of block.words) {
    const wordCenterX = word?.position?.centerX;

    if (
      typeof wordCenterX !== "number"
    ) {
      continue;
    }

    /*
     * Ya no asignamos simplemente a la columna
     * más cercana.
     *
     * La palabra debe encontrarse físicamente
     * dentro de la banda horizontal del semestre.
     *
     * Esto evita que etiquetas laterales como
     * "Bases Científicas de la Odontología"
     * terminen convertidas en cursos del
     * semestre 1.
     */
    const matchingColumn = columnBands.find(
      (column) =>
        wordCenterX >= column.left &&
        wordCenterX < column.right,
    );

    if (!matchingColumn) {
      continue;
    }

    const items = groups.get(
      matchingColumn.semester,
    ) ?? [];

    items.push(word);

    groups.set(
      matchingColumn.semester,
      items,
    );
  }

  /*
   * Si el bloque tenía palabras pero ninguna
   * quedó dentro de una columna académica,
   * entonces es texto externo a la malla.
   */
  if (groups.size === 0) {
    return [];
  }

  const fragments: any[] = [];

  for (
    const [semester, words] of groups.entries()
  ) {
    if (words.length === 0) {
      continue;
    }

    const sortedWords = [...words].sort(
      (a, b) => {
        const ay = a?.position?.centerY ?? 0;

        const by = b?.position?.centerY ?? 0;

        if (
          Math.abs(ay - by) > 6
        ) {
          return ay - by;
        }

        return (
          (a?.position?.centerX ?? 0) -
          (b?.position?.centerX ?? 0)
        );
      },
    );

    const text = sortedWords
      .map(
        (word) => word.text,
      )
      .join(" ")
      .replace(/\s+/g, " ")
      .trim();

    if (!text) {
      continue;
    }

    const xValues = sortedWords.flatMap(
      (word) => [
        word.position.xMin,
        word.position.xMax,
      ],
    );

    const yValues = sortedWords.flatMap(
      (word) => [
        word.position.yMin,
        word.position.yMax,
      ],
    );

    const xMin = Math.min(...xValues);

    const xMax = Math.max(...xValues);

    const yMin = Math.min(...yValues);

    const yMax = Math.max(...yValues);

    fragments.push({
      ...block,

      text,

      normalizedText: normalizeAcademicCode(
        text,
      ),

      type: detectBlockType(
        text,
      ),

      words: sortedWords,

      position: {
        xMin,
        xMax,
        yMin,
        yMax,

        centerX: (xMin + xMax) / 2,

        centerY: (yMin + yMax) / 2,

        width: xMax - xMin,

        height: yMax - yMin,
      },

      detectedSemester: semester,

      splitFromBlock: block.block,
    });
  }

  return fragments;
}

function detectLayoutCourseCandidates(
  blocks: any[],
  semesterColumns: any[],
) {
  if (semesterColumns.some((column) => column?.numericSplitGrid)) {
    return detectSplitNumericGridCourseCandidates(blocks, semesterColumns);
  }
  if (semesterColumns.some((column) => column?.layoutBand)) {
    return detectTwoBandGridCourseCandidates(blocks, semesterColumns);
  }
  if (
    !Array.isArray(semesterColumns) ||
    semesterColumns.length === 0
  ) {
    return [];
  }

  const curriculumPage = semesterColumns[0]?.page;

  const semesterHeaderYs = semesterColumns
    .map((column) => column?.centerY)
    .filter(
      (value) => typeof value === "number",
    );

  const maxSemesterHeaderY = semesterHeaderYs.length > 0
    ? Math.max(...semesterHeaderYs)
    : 0;

  const contentStartY = maxSemesterHeaderY + 25;

  const pageBlocks = blocks.filter(
    (block) =>
      block?.page === curriculumPage &&
      typeof block?.position?.centerY === "number",
  );

  const pageMaxY = pageBlocks.length > 0
    ? Math.max(
      ...pageBlocks.map(
        (block) => block.position.centerY,
      ),
    )
    : 1000;

  // Upper scanning bound: do not silently omit courses near page bottom.
  const contentEndY = pageMaxY * 0.98;

  if (typeof curriculumPage !== "number") {
    return [];
  }

  const sortedSemesterXs = semesterColumns
    .map((column) => column?.centerX)
    .filter(
      (value) => typeof value === "number",
    )
    .sort((a, b) => a - b);

  const semesterSpacings: number[] = [];

  for (
    let index = 1;
    index < sortedSemesterXs.length;
    index++
  ) {
    semesterSpacings.push(
      sortedSemesterXs[index] -
        sortedSemesterXs[index - 1],
    );
  }

  const sortedSpacings = [...semesterSpacings].sort(
    (a, b) => a - b,
  );

  const medianSemesterSpacing = sortedSpacings.length > 0
    ? sortedSpacings[
      Math.floor(
        sortedSpacings.length / 2,
      )
    ]
    : 80;

  /*
   * Detecta franjas transversales:
   *
   * - muy anchas respecto de una columna,
   * - prácticamente de una sola línea,
   * - ubicadas en la parte inferior de la
   *   zona curricular.
   *
   * Ejemplo real:
   * "Bienestar, Inteligencia Artificial y
   * Transformación Digital"
   *
   * No depende del nombre ni de la universidad.
   */
  const transverseBlockIds = new Set<number>();

  const transverseBlocks: any[] = [];

  for (const block of blocks) {
    if (block?.page !== curriculumPage) {
      continue;
    }

    const width = block?.position?.width;

    const height = block?.position?.height;

    const centerY = block?.position?.centerY;

    if (
      typeof width !== "number" ||
      typeof height !== "number" ||
      typeof centerY !== "number"
    ) {
      continue;
    }

    const isWide = width >=
      medianSemesterSpacing * 2;

    const isSingleLine = height <= 16;

    // Preserve the prior detection zone independently of the broader
    // content scan (78% was the previous page boundary).
    const lowerZoneStart = contentStartY +
      (
          (pageMaxY * 0.78) -
          contentStartY
        ) * 0.75;

    const isLowerZone = centerY >= lowerZoneStart;

    if (
      isWide &&
      isSingleLine &&
      isLowerZone &&
      typeof block?.block === "number"
    ) {
      transverseBlockIds.add(
        block.block,
      );
      transverseBlocks.push(block);
    }
  }

  // A wide label by itself is not sufficient to end a curriculum.
  // Confirm a footer using independent textual evidence and the
  // spatial collapse of normal semester-column content below it.
  // No university-specific strings, course counts or fixed 78% cutoff.
  const footerSignals = [
    /\b(?:CONTACTO|RRSS|TEL[EÉ]FONOS?|ADMISI[OÓ]N|DIRECCI[OÓ]N|CAMPUS|REDES SOCIALES|S[IÍ]GUENOS)\b/i,
    /(?:https?:\/\/|www\.|@[a-z0-9._-]+|[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,})/i,
  ];

  const isFooterSignal = (text: unknown): boolean =>
    typeof text === "string" &&
    footerSignals.some((pattern) => pattern.test(text));

  let dynamicContentEndY = contentEndY;

  const possibleFooterBands = [...transverseBlocks]
    .filter((block) =>
      block.position.centerY > contentStartY &&
      block.position.centerY < contentEndY
    )
    .sort((a, b) => a.position.centerY - b.position.centerY);

  for (const band of possibleFooterBands) {
    const bandY = band.position.centerY;

    const below = pageBlocks.filter((block) =>
      block.position.centerY > bandY &&
      block.position.centerY < contentEndY
    );

    const footerEvidence = below.filter((block) => isFooterSignal(block.text));

    // One coincidental footer word must not hide real courses.
    if (footerEvidence.length < 2) {
      continue;
    }

    const occupiedSemesters = new Set<number>();

    for (const block of below) {
      const width = block?.position?.width;

      if (
        block?.type !== "text" ||
        typeof width !== "number" ||
        width > medianSemesterSpacing * 1.35 ||
        isFooterSignal(block.text)
      ) {
        continue;
      }

      const assignment = assignSemesterByColumn(
        block,
        semesterColumns,
      );

      if (
        assignment &&
        typeof assignment.semester === "number" &&
        assignment.distanceX <= Math.min(45, medianSemesterSpacing * 0.55)
      ) {
        occupiedSemesters.add(assignment.semester);
      }
    }

    // A continuing broad semester grid contradicts a terminal footer.
    const maximumFooterColumns = Math.max(
      2,
      Math.floor(semesterColumns.length * 0.45),
    );

    if (occupiedSemesters.size > maximumFooterColumns) {
      continue;
    }

    dynamicContentEndY = Math.min(
      dynamicContentEndY,
      typeof band.position.yMin === "number" ? band.position.yMin : bandY,
    );
    break;
  }

  const excludedExact = new Set([
    "SEMESTRE",
    "MALLA",
    "CURRICULAR",
    "MALLA CURRICULAR",

    "ÁREA",
    "DE FORMACIÓN",
    "BÁSICA",
    "PROFESIONAL",
    "GENERAL",

    "ÁREA ESPECIALIZADA",
    "ÁREA ESPECILIZADA",

    "CICLO INICIAL",
    "CICLO INTERMEDIO",
    "CICLO AVANZADO",

    "ASIGNATURA DESGLOSE",
    "TIPO DE COMPETENCIA GENÉRICA",
    "COMPETENCIAS GENÉRICAS",

    "HC",
    "TE",
    "CE",
    "PC",
    "RS",

    "HC TE",
    "HC CE",
    "HC PC",
    "HC RS",
    "TE CE",
    "TE PC",
    "TE RS",
    "CE PC",
    "CE RS",
    "PC RS",

    "HC TE CE",
    "HC TE PC",
    "HC TE RS",
    "HC CE PC",
    "HC CE RS",
    "HC PC RS",
    "TE CE PC",
    "TE CE RS",
    "TE PC RS",
    "CE PC RS",
    "HC TE CE PC",
    "HC TE CE RS",
    "HC TE PC RS",
    "HC CE PC RS",
    "TE CE PC RS",
    "HC TE CE PC RS",
  ]);

  const excludedStartsWith = [
    "HABILIDADES DE COMUNICACIÓN",
    "TRABAJO EN EQUIPO",
    "COMPORTAMIENTO ÉTICO",
    "PENSAMIENTO CRÍTICO",
    "RESPONSABILIDAD SOCIAL",
    "LA INFORMACIÓN CONTENIDA",
    "GRADO ACADÉMICO",
    "TÍTULO PROFESIONAL",

    "UNIVERSIDAD DE CHILE",
    "FACULTAD DE DERECHO",
    "ESCUELA DE PREGRADO",
    "PLAN DE ESTUDIO",
    "CÓDIGO DE POSTULACIÓN",
  ];

  const expandedBlocks = blocks.flatMap((block) =>
    splitBlockBySemesterColumns(
      block,
      semesterColumns,
    )
  );

  return expandedBlocks
    .filter((block) => {
      if (
        typeof block?.block === "number" &&
        transverseBlockIds.has(
          block.block,
        )
      ) {
        return false;
      }
      if (block?.page !== curriculumPage) return false;
      if (block?.type !== "text") return false;
      if (typeof block?.text !== "string") return false;

      const text = block.text
        .replace(/\s+/g, " ")
        .trim();

      if (text.length < 3) return false;

      const normalized = normalizeLabelText(text);

      // Excluye encabezados de semestre:
      // 1, 2, 3... / I, II, III... / "I SEMESTRE", etc.
      if (parseSemesterNumber(text) !== null) {
        return false;
      }

      // Excluye encabezados de año académico.
      if (
        /^(PRIMER|PRIMERO|SEGUNDO|TERCER|TERCERO|CUARTO|QUINTO|SEXTO|SÉPTIMO|SEPTIMO|OCTAVO|NOVENO|DÉCIMO|DECIMO)\s+AÑO$/i
          .test(
            normalized,
          )
      ) {
        return false;
      }

      // Excluye bloques que contienen únicamente créditos.
      // Ej.: "5 SCT", "4 SCT", "2 SCT".
      if (/^\d{1,2}\s*SCT$/i.test(normalized)) {
        return false;
      }

      if (excludedExact.has(normalized)) {
        return false;
      }

      if (
        excludedStartsWith.some((prefix) => normalized.startsWith(prefix))
      ) {
        return false;
      }

      const centerX = block?.position?.centerX;
      const centerY = block?.position?.centerY;

      if (
        typeof centerX !== "number" ||
        typeof centerY !== "number"
      ) {
        return false;
      }

      // Los cursos deben estar bajo la fila de encabezados.
      if (centerY <= contentStartY) {
        return false;
      }

      if (centerY >= dynamicContentEndY) {
        return false;
      }

      const assignment = assignSemesterByColumn(
        block,
        semesterColumns,
      );

      if (!assignment) return false;

      // Evita textos alejados horizontalmente de una columna real.
      if (assignment.distanceX > 45) {
        return false;
      }

      return true;
    })
    .map((block) => {
      const assignment = assignSemesterByColumn(
        block,
        semesterColumns,
      );

      return {
        text: block.text,
        page: block.page,
        block: block.block,

        confidence: typeof block.confidence === "number"
          ? block.confidence
          : null,

        centerX: block.position.centerX,
        centerY: block.position.centerY,

        // Bordes reales del bloque.
        // Se utilizan para evitar unir cursos distintos
        // que tienen centros relativamente cercanos.
        yMin: typeof block?.position?.yMin === "number"
          ? block.position.yMin
          : null,

        yMax: typeof block?.position?.yMax === "number"
          ? block.position.yMax
          : null,

        semester: assignment?.semester ?? null,

        distanceX: assignment?.distanceX ?? null,
      };
    });
}

function mergeLayoutCourseCandidateFragments(
  candidates: any[],
) {
  if (candidates.some((candidate) => candidate?.gridFinalized === true)) {
    return candidates;
  }
  if (
    !Array.isArray(candidates) ||
    candidates.length === 0
  ) {
    return [];
  }

  const groupedBySemester = new Map<number, any[]>();

  for (const candidate of candidates) {
    if (
      typeof candidate?.semester !== "number"
    ) {
      continue;
    }

    const items = groupedBySemester.get(
      candidate.semester,
    ) ?? [];

    items.push(candidate);

    groupedBySemester.set(
      candidate.semester,
      items,
    );
  }

  const merged: any[] = [];

  for (
    const [semester, items] of groupedBySemester.entries()
  ) {
    const sorted = [...items].sort(
      (a, b) =>
        (a.yMin ?? a.centerY) -
        (b.yMin ?? b.centerY),
    );

    let current: any = null;

    for (const item of sorted) {
      const cleanText = typeof item?.text === "string"
        ? item.text
          .replace(/\s+/g, " ")
          .trim()
        : "";

      if (!cleanText) {
        continue;
      }

      if (!current) {
        current = {
          semester,
          page: item.page,
          text: cleanText,
          blocks: [item.block],

          centerX: item.centerX,
          centerY: item.centerY,

          yMin: typeof item.yMin === "number" ? item.yMin : null,

          yMax: typeof item.yMax === "number" ? item.yMax : null,

          confidence: item.confidence,
        };

        continue;
      }

      const horizontalGap = Math.abs(
        item.centerX -
          current.centerX,
      );

      /*
       * Distancia real entre el borde inferior
       * del fragmento actual y el borde superior
       * del siguiente.
       *
       * Esto evita falsos merges como:
       *
       * "Probabilidad y Estadística Computacional"
       * + "Cálculo III"
       *
       * donde los centros estaban a menos de 48,
       * pero las cajas visuales pertenecen a
       * tarjetas distintas.
       */
      let edgeGap: number | null = null;

      if (
        typeof current.yMax === "number" &&
        typeof item.yMin === "number"
      ) {
        edgeGap = item.yMin - current.yMax;
      }

      /*
       * Si por alguna razón un OCR antiguo no
       * tiene yMin/yMax, usamos una condición
       * mucho más conservadora basada en centros.
       */
      const centerGap = item.centerY -
        current.centerY;

      const verticalCompatible = edgeGap !== null
        ? (
          edgeGap >= 0 &&
          edgeGap <= 10
        )
        : (
          centerGap > 0 &&
          centerGap <= 20
        );

      const shouldMerge = verticalCompatible &&
        horizontalGap <= 20;

      if (shouldMerge) {
        current.text = `${current.text} ${cleanText}`;

        current.blocks.push(
          item.block,
        );

        current.centerX = (
          current.centerX +
          item.centerX
        ) / 2;

        /*
         * El centerY sigue al último fragmento
         * para mantener compatibilidad con el
         * resto del parser.
         */
        current.centerY = item.centerY;

        /*
         * Extendemos la caja vertical acumulada.
         */
        if (
          typeof current.yMin !== "number" &&
          typeof item.yMin === "number"
        ) {
          current.yMin = item.yMin;
        } else if (
          typeof current.yMin === "number" &&
          typeof item.yMin === "number"
        ) {
          current.yMin = Math.min(
            current.yMin,
            item.yMin,
          );
        }

        if (
          typeof item.yMax === "number"
        ) {
          if (
            typeof current.yMax === "number"
          ) {
            current.yMax = Math.max(
              current.yMax,
              item.yMax,
            );
          } else {
            current.yMax = item.yMax;
          }
        }

        if (
          typeof current.confidence ===
            "number" &&
          typeof item.confidence ===
            "number"
        ) {
          current.confidence = Math.min(
            current.confidence,
            item.confidence,
          );
        } else if (
          typeof current.confidence !==
            "number" &&
          typeof item.confidence ===
            "number"
        ) {
          current.confidence = item.confidence;
        }

        continue;
      }

      merged.push(current);

      current = {
        semester,
        page: item.page,
        text: cleanText,
        blocks: [item.block],

        centerX: item.centerX,
        centerY: item.centerY,

        yMin: typeof item.yMin === "number" ? item.yMin : null,

        yMax: typeof item.yMax === "number" ? item.yMax : null,

        confidence: item.confidence,
      };
    }

    if (current) {
      merged.push(current);
    }
  }

  return merged.sort((a, b) => {
    if (
      a.semester !== b.semester
    ) {
      return (
        a.semester -
        b.semester
      );
    }

    return (
      a.centerY -
      b.centerY
    );
  });
}

function findLayoutCourseCredits(
  candidate: any,
  blocks: any[],
  semesterColumns: any[],
): number | null {
  if (
    !candidate ||
    !Array.isArray(blocks) ||
    !Array.isArray(semesterColumns)
  ) {
    return null;
  }

  const semester = candidate?.semester;
  const candidateX = candidate?.centerX;
  const candidateY = candidate?.centerY;

  if (
    typeof semester !== "number" ||
    typeof candidateX !== "number" ||
    typeof candidateY !== "number"
  ) {
    return null;
  }

  const creditCandidates = blocks
    .filter((block) => {
      if (typeof block?.text !== "string") {
        return false;
      }

      const match = block.text
        .replace(/\s+/g, " ")
        .trim()
        .match(/^(\d{1,2})\s*SCT$/i);

      if (!match) {
        return false;
      }

      const assignment = assignSemesterByColumn(
        block,
        semesterColumns,
      );

      if (!assignment) {
        return false;
      }

      if (assignment.semester !== semester) {
        return false;
      }

      const blockX = block?.position?.centerX;
      const blockY = block?.position?.centerY;

      if (
        typeof blockX !== "number" ||
        typeof blockY !== "number"
      ) {
        return false;
      }

      const verticalGap = blockY - candidateY;
      const horizontalGap = Math.abs(
        blockX - candidateX,
      );

      // El crédito debe estar debajo del curso,
      // dentro de la misma tarjeta visual.
      if (
        verticalGap < 8 ||
        verticalGap > 70
      ) {
        return false;
      }

      if (horizontalGap > 35) {
        return false;
      }

      return true;
    })
    .map((block) => {
      const match = block.text
        .replace(/\s+/g, " ")
        .trim()
        .match(/^(\d{1,2})\s*SCT$/i);

      return {
        credits: match ? Number(match[1]) : null,
        verticalGap: block.position.centerY - candidateY,
        horizontalGap: Math.abs(
          block.position.centerX - candidateX,
        ),
      };
    })
    .filter(
      (item) => typeof item.credits === "number",
    )
    .sort((a, b) => {
      if (a.verticalGap !== b.verticalGap) {
        return a.verticalGap - b.verticalGap;
      }

      return a.horizontalGap - b.horizontalGap;
    });

  if (creditCandidates.length === 0) {
    return null;
  }

  return creditCandidates[0].credits;
}

// Detached roman numerals can be misclassified as semester labels by OCR.
// Recover only glyphs located directly below the same course title.
function recoverLayoutRomanSuffix(
  name: string,
  rawText: string,
  candidate: any,
  blocks: any[],
) {
  if (/\b(?:I|II|III|IV|V|VI|VII|VIII|IX|X)$/.test(name)) {
    return {
      name,
      romanSuffixEvidence: null,
      romanSuffixReviewSuggested: false,
    };
  }
  const x = candidate?.centerX, y = candidate?.centerY;
  let marker: string | null = null;
  let source: "detached_roman" | "ocr_strokes" | null = null;
  if (typeof x === "number" && typeof y === "number") {
    const nearby = blocks.filter((b) => {
      const bx = b.position?.centerX, by = b.position?.centerY;
      return b.page === candidate.page && typeof bx === "number" &&
        typeof by === "number" && Math.abs(bx - x) <= 18 &&
        by - y >= 7 && by - y <= 28 &&
        /^\s*(?:I|II|III|IV|V|VI|VII|VIII|IX|X|\|{1,3})\s*$/.test(
          b.text ?? "",
        ) &&
        !(candidate.blocks ?? []).includes(b.block);
    }).sort((a, b) =>
      Math.abs(a.position.centerY - y) - Math.abs(b.position.centerY - y)
    );
    if (nearby.length) {
      marker = nearby[0].text.trim();
      source = /^\|+$/.test(marker as string)
        ? "ocr_strokes"
        : "detached_roman";
    }
  }
  if (!marker) {
    const trailing = rawText.match(/\s+(\|{1,3})\s*$/);
    if (trailing) {
      marker = trailing[1];
      source = "ocr_strokes";
    }
  }
  if (!marker) {
    return {
      name,
      romanSuffixEvidence: null,
      romanSuffixReviewSuggested: false,
    };
  }
  const numeral = /^\|{1,3}$/.test(marker) ? "I".repeat(marker.length) : marker;
  return {
    name: `${name} ${numeral}`,
    romanSuffixEvidence: source,
    romanSuffixReviewSuggested: source === "ocr_strokes",
  };
}

function buildLayoutCourses(
  mergedCandidates: any[],
  semesterColumns: any[],
  blocks: any[],
) {
  if (
    !Array.isArray(mergedCandidates) ||
    mergedCandidates.length === 0
  ) {
    return [];
  }

  const cleanedCourses = mergedCandidates
    .map((candidate) => {
      const semesterColumn = semesterColumns.find(
        (column) => column?.semester === candidate?.semester,
      ) ?? null;

      const detectedCredits = findLayoutCourseCredits(
        candidate,
        blocks,
        semesterColumns,
      );

      const rawText = typeof candidate?.text === "string"
        ? candidate.text
          .replace(/\s+/g, " ")
          .trim()
        : "";

      if (!rawText) {
        return null;
      }

      let name = rawText;

      // Quita símbolos OCR aislados en los extremos.
      name = name
        .replace(/^[|:;,.\s]+/g, "")
        .replace(/[|:;,.\s]+$/g, "")
        .trim();

      // Excluye códigos de postulación o fragmentos equivalentes.
      if (/^\d{4,8}$/.test(name)) {
        return null;
      }

      if (
        /^CÓDIGO DE POSTULACIÓN\b/i.test(name) ||
        /^CODIGO DE POSTULACION\b/i.test(name)
      ) {
        return null;
      }

      // Ejemplo residual después del split:
      // ": 11055"
      if (/^[:\s]*\d{4,8}$/.test(rawText)) {
        return null;
      }

      // Las etiquetas de área no son asignaturas.
      if (
        /^ÁREA\s+ESPEC(?:IALIZADA|ILIZADA)\b/i.test(name) ||
        /^AREA\s+ESPEC(?:IALIZADA|ILIZADA)\b/i.test(name)
      ) {
        return null;
      }

      // Extrae créditos SCT cuando Vision los pegó
      // al mismo bloque del nombre.
      //
      // Ejemplo:
      // "DERECHO ECONÓMICO I 4 SCT"
      // -> name: "DERECHO ECONÓMICO I"
      // -> credits: 4
      let credits: number | null = null;

      const sctMatch = name.match(
        /\b(\d{1,2})\s*SCT\s*$/i,
      );

      if (sctMatch) {
        credits = Number(sctMatch[1]);

        name = name
          .slice(0, sctMatch.index)
          .replace(/[|:;,.\s]+$/g, "")
          .trim();
      }

      // Segunda limpieza de símbolos OCR después
      // de retirar los créditos.
      name = name
        .replace(/^[|:;,.\s]+/g, "")
        .replace(/[|:;,.\s]+$/g, "")
        .replace(/\s+/g, " ")
        .trim();

      if (!name) {
        return null;
      }

      const romanRecovery = recoverLayoutRomanSuffix(
        name,
        rawText,
        candidate,
        blocks,
      );
      name = romanRecovery.name;
      const gridRomanUncertain = candidate.gridFinalized === true &&
        romanRecovery.romanSuffixReviewSuggested === true;

      return {
        code: null,
        name,
        ...(candidate?.curricularSlotType
          ? { curricularSlotType: candidate.curricularSlotType }
          : {}),
        ...(romanRecovery.romanSuffixEvidence
          ? {
            romanSuffixEvidence: romanRecovery.romanSuffixEvidence,
            romanSuffixReviewSuggested:
              romanRecovery.romanSuffixReviewSuggested,
          }
          : {}),
        ...(gridRomanUncertain ? { nameAssociationUncertain: true } : {}),
        credits: credits !== null ? credits : detectedCredits,
        confidence: typeof candidate?.confidence === "number"
          ? candidate.confidence
          : null,
        semester: typeof candidate?.semester === "number"
          ? candidate.semester
          : null,
        semesterColumnX: typeof semesterColumn?.centerX === "number"
          ? semesterColumn.centerX
          : null,
        position: {
          centerX: typeof candidate?.centerX === "number"
            ? candidate.centerX
            : null,
          centerY: typeof candidate?.centerY === "number"
            ? candidate.centerY
            : null,
        },
        sourceBlocks: Array.isArray(candidate?.blocks) ? candidate.blocks : [],
      };
    })
    .filter((course) => course !== null);

  return cleanedCourses;
}

function buildSemesterAssignmentSamples(
  blocks: any[],
  semesterColumns: any[],
) {
  const sampleNames = new Set([
    "ÁLGEBRA LINEAL",
    "DESARROLLO DE APLICACIONES WEB",
    "CONSULTORÍA INFORMÁTICA",
  ]);

  return blocks
    .filter((block) => {
      if (block?.page !== 2) return false;
      if (typeof block?.text !== "string") return false;

      const normalized = block.text
        .replace(/\s+/g, " ")
        .trim()
        .toUpperCase();

      return sampleNames.has(normalized);
    })
    .map((block) => ({
      text: block.text,
      centerX: block?.position?.centerX ?? null,
      assignment: assignSemesterByColumn(
        block,
        semesterColumns,
      ),
    }));
}

// Code-based layouts may put titles above the code (one design) or below it
// (another design). Infer this from the page itself, never from its university.
function collectCodeCourseAnchors(blocks: any[]): any[] {
  return blocks.filter((block) => {
    if (
      block?.type === "course_code" ||
      block?.type === "course_code_credits"
    ) return true;
    return block?.type === "credits_label" &&
      parseFlexibleCourseData(block.text ?? "").code !== null;
  }).filter((block) => parseFlexibleCourseData(block.text ?? "").code !== null);
}

function isPotentialCourseTitle(block: any): boolean {
  if (block?.type !== "text" || typeof block.text !== "string") return false;
  const text = normalizeLabelText(block.text);
  if (!text || text.length < 3 || isNonCourseNameLabel(text)) return false;
  if (parseFlexibleCourseData(text).code) return false;
  if (
    /^\d{1,2}\s*[°ºª.]?\s*SEMESTRE\b/.test(text) ||
    /^(?:I|II|III|IV|V|VI|VII|VIII|IX|X)\s*SEMESTRE\b/.test(text) ||
    /^(?:OPTATIVO|CUPO ELECTIVO)$/.test(text) ||
    /^(?:CERTIFICADO\b|MALLA CURRICULAR\b|ESCUELA DE\b|DUOC\s*UC\b)/.test(
      text,
    ) ||
    /^(?:HAZ CLICK\b|LOS COLORES\b|VICERRECTORÍA\b|DIRECCIÓN DE DOCENCIA\b)/
      .test(text) ||
    /\b(?:HIVEL APROBADO|NIVEL APROBADO)\b/.test(text) ||
    text === "APROBADO"
  ) return false;
  return true;
}

function codeColumnCenters(anchors: any[]): number[] {
  const xs = anchors.map((block) => block?.position?.centerX)
    .filter((x): x is number => typeof x === "number" && Number.isFinite(x))
    .sort((a, b) => a - b);
  const groups: number[][] = [];
  for (const x of xs) {
    const last = groups[groups.length - 1];
    if (
      !last || Math.abs(x - last.reduce((s, n) => s + n, 0) / last.length) > 60
    ) {
      groups.push([x]);
    } else last.push(x);
  }
  return groups.map((g) => g.reduce((s, n) => s + n, 0) / g.length);
}

function closestCodeColumn(x: number, centers: number[]): number {
  let result = 0;
  for (let i = 1; i < centers.length; i++) {
    if (Math.abs(centers[i] - x) < Math.abs(centers[result] - x)) result = i;
  }
  return result;
}

function buildCourses(blocks: any[]) {
  const courseAnchors = collectCodeCourseAnchors(blocks);
  const pageMap = new Map<number, any[]>();
  for (const anchor of courseAnchors) {
    const page = anchor.page ?? 1;
    if (!pageMap.has(page)) pageMap.set(page, []);
    pageMap.get(page)!.push(anchor);
  }
  const inferredPages = new Map<number, {
    columns: number[];
    direction: "above" | "below";
    titles: any[];
    anchors: any[];
  }>();
  for (const [page, anchors] of pageMap) {
    const columns = codeColumnCenters(anchors);
    const titles = blocks.filter((b) =>
      b.page === page && isPotentialCourseTitle(b) &&
      typeof b.position?.centerX === "number" &&
      typeof b.position?.centerY === "number"
    );
    const votes = { above: 0, below: 0 };
    for (const anchor of anchors) {
      const x = anchor.position?.centerX, y = anchor.position?.centerY;
      if (typeof x !== "number" || typeof y !== "number") continue;
      const col = closestCodeColumn(x, columns);
      const relevant = titles.filter((b) =>
        closestCodeColumn(b.position.centerX, columns) === col
      );
      for (const dir of ["above", "below"] as const) {
        const closest = relevant.map((b) => b.position.centerY - y)
          .filter((d) => dir === "above" ? d < -5 && d > -52 : d > 5 && d < 52)
          .sort((a, b) => Math.abs(a) - Math.abs(b))[0];
        if (closest !== undefined) votes[dir] += 1;
      }
    }
    // Clear majority determines reading order. A tie is conservatively
    // resolved per course and marked as uncertain when equally plausible.
    const direction = votes.below > votes.above ? "below" : "above";
    inferredPages.set(page, { columns, direction, titles, anchors });
  }

  return courseAnchors.map((anchor) => {
    const parsed = parseFlexibleCourseData(anchor.text);
    const x = anchor.position?.centerX, y = anchor.position?.centerY;
    if (typeof x !== "number" || typeof y !== "number") {
      return {
        code: parsed.code,
        name: null,
        credits: parsed.credits,
        confidence: anchor.confidence,
      };
    }
    const page = inferredPages.get(anchor.page ?? 1)!;
    const col = closestCodeColumn(x, page.columns);
    const sameColumnAnchors = page.anchors
      .filter((a) =>
        closestCodeColumn(a.position.centerX, page.columns) === col
      )
      .sort((a, b) => a.position.centerY - b.position.centerY);
    const previous = sameColumnAnchors.filter((a) => a.position.centerY < y - 3)
      .at(-1);
    const next = sameColumnAnchors.find((a) => a.position.centerY > y + 3);

    const gather = (direction: "above" | "below") => {
      const minY = direction === "below"
        ? y + 5
        : Math.max(y - 88, (previous?.position.centerY ?? -Infinity) + 5);
      const maxY = direction === "below"
        ? Math.min(y + 88, (next?.position.centerY ?? Infinity) - 5)
        : y - 5;
      const choices = page.titles.filter((b) => {
        const bx = b.position.centerX, by = b.position.centerY;
        if (
          closestCodeColumn(bx, page.columns) !== col || by < minY || by > maxY
        ) return false;
        return true;
      }).map((block) => {
        const dy = Math.abs(block.position.centerY - y);
        const dx = Math.abs(block.position.centerX - x);
        return { block, score: dy + dx * .12, dy };
      }).sort((a, b) => a.score - b.score);
      // An isolated nearby line defines a candidate, adjacent lines in the
      // same course tile are joined without swallowing the next tile.
      const seed = choices[0];
      if (!seed || seed.dy > 70) return null;
      const pieces = [seed.block];
      for (
        const candidate of [...choices].sort((a, b) =>
          a.block.position.centerY - b.block.position.centerY
        )
      ) {
        if (candidate.block === seed.block) continue;
        if (pieces.length >= 4) break;
        const ys = pieces.map((b) => b.position.centerY);
        const nearLine = ys.some((v) =>
          Math.abs(v - candidate.block.position.centerY) <= 24
        );
        if (nearLine && Math.abs(candidate.block.position.centerY - y) <= 85) {
          pieces.push(candidate.block);
        }
      }
      pieces.sort((a, b) => a.position.centerY - b.position.centerY);
      return { blocks: pieces, score: seed.score, dy: seed.dy };
    };
    let chosen = gather(page.direction);
    let associationUncertain = false;
    if (!chosen) {
      const opposite = gather(page.direction === "above" ? "below" : "above");
      if (opposite && opposite.dy <= 45) {
        chosen = opposite;
        associationUncertain = true;
      }
    }
    const rawName = chosen?.blocks.map((b: any) => b.text.replace(/\n/g, " "))
      .join(" ").replace(/\s+/g, " ").trim() ?? null;
    const name = cleanCourseName(rawName);
    if (chosen && chosen.blocks.some((b: any) => b.confidence < .80)) {
      associationUncertain = true;
    }
    let credits = parsed.credits;
    if (credits === null) {
      const credit = blocks.filter((b) => {
        if (b.page !== anchor.page) return false;
        const cx = b.position?.centerX, cy = b.position?.centerY;
        if (typeof cx !== "number" || typeof cy !== "number") return false;
        if (closestCodeColumn(cx, page.columns) !== col) return false;
        if (cy <= y || cy - y > 32) return false;
        return b.type === "number" && /^\d{1,2}$/.test(b.text.trim()) ||
          b.type === "credits_label" &&
            /^\d{1,2}\s*CRÉDITOS?$/i.test(b.text.trim());
      }).sort((a, b) => a.position.centerY - b.position.centerY)[0];
      if (credit) {
        credits = Number(credit.text.trim().match(/^\d{1,2}/)?.[0] ?? 0) ||
          null;
      }
    }
    return {
      code: parsed.code,
      name,
      credits,
      confidence: anchor.confidence,
      position: { centerX: x, centerY: y },
      ...(associationUncertain ? { nameAssociationUncertain: true } : {}),
    };
  });
}

// Preserve no-code course slots as separate, explicitly reviewable metadata.
// They are not silently inserted into the counted coded-course collection.
function buildSpecialCurricularElements(blocks: any[], courses: any[]) {
  const codedColumns = [
    ...new Set(
      courses.map((c) => c.semesterColumnX)
        .filter((x): x is number => typeof x === "number"),
    ),
  ].sort((a, b) => a - b);
  if (!codedColumns.length) return [];
  const place = (x: number) => {
    const idx = closestCodeColumn(x, codedColumns);
    const near = courses.find((c) => c.semesterColumnX === codedColumns[idx]);
    return {
      semester: near?.semester ?? idx + 1,
      semesterColumnX: codedColumns[idx],
    };
  };
  const result: any[] = [];
  const labelBlocks = blocks.filter((b) =>
    b.type === "text" &&
    /^(?:CUPO ELECTIVO|OPTATIVO)$/i.test(normalizeLabelText(b.text ?? ""))
  );
  for (const label of labelBlocks) {
    const x = label.position?.centerX, y = label.position?.centerY;
    if (typeof x !== "number" || typeof y !== "number") continue;
    const col = closestCodeColumn(x, codedColumns);
    const texts = blocks.filter((b) =>
      b.page === label.page &&
      isPotentialCourseTitle(b) && b !== label &&
      typeof b.position?.centerX === "number" &&
      typeof b.position?.centerY === "number" &&
      closestCodeColumn(b.position.centerX, codedColumns) === col &&
      b.position.centerY > y + 5 && b.position.centerY <= y + 60 &&
      !/^(?:FORMACI[OÓ]N SELLO|ESPECIALIDADES|FORMACI[OÓ]N GENERAL)/i.test(
        b.text,
      )
    );
    texts.sort((a, b) => a.position.centerY - b.position.centerY);
    const first = texts[0];
    if (!first) continue;
    const fragments = [first];
    for (const b of texts.slice(1)) {
      if (fragments.length >= 3) break;
      if (
        b.position.centerY - fragments[fragments.length - 1].position.centerY <=
          25
      ) {
        fragments.push(b);
      } else break;
    }
    const name = cleanCourseName(
      fragments.map((b) => b.text.replace(/\n/g, " ")).join(" "),
    );
    if (!name) continue;
    result.push({
      kind: "elective_slot",
      name,
      code: null,
      credits: null,
      ...place(x),
      position: { centerX: x, centerY: y },
      quality: "review",
      needsReview: true,
      reviewReasons: ["code_missing", "elective_slot"],
    });
  }
  const creditLabels = blocks.filter((b) =>
    b.type === "credits_label" &&
    /^\d{1,2}\s*CRÉDITOS?$/i.test((b.text ?? "").trim())
  );
  for (const label of creditLabels) {
    const x = label.position?.centerX, y = label.position?.centerY;
    if (typeof x !== "number" || typeof y !== "number") continue;
    const col = closestCodeColumn(x, codedColumns);
    const parts = blocks.filter((b) =>
      b.page === label.page && isPotentialCourseTitle(b) &&
      typeof b.position?.centerX === "number" &&
      typeof b.position?.centerY === "number" &&
      closestCodeColumn(b.position.centerX, codedColumns) === col &&
      b.position.centerY < y - 5 && b.position.centerY >= y - 45
    )
      .sort((a, b) => a.position.centerY - b.position.centerY);
    if (!parts.length) continue;
    const name = cleanCourseName(
      parts.map((b) => b.text.replace(/\n/g, " ")).join(" "),
    );
    if (
      !name ||
      result.some((r) => r.semester === place(x).semester && r.name === name)
    ) continue;
    // Do not confuse a normal coded course with this no-code entry.
    if (
      courses.some((c) =>
        c.semester === place(x).semester &&
        normalizeLabelText(c.name ?? "") === normalizeLabelText(name)
      )
    ) continue;
    result.push({
      kind: "uncoded_course",
      name,
      code: null,
      credits: Number(label.text.match(/^\d{1,2}/)?.[0]),
      ...place(x),
      position: { centerX: x, centerY: y },
      quality: "review",
      needsReview: true,
      reviewReasons: ["code_missing"],
    });
  }
  return result;
}

function assignSemesters(courses: any[]) {
  const validCourses = courses.filter(
    (course) => typeof course.position?.centerX === "number",
  );

  const sortedX = validCourses
    .map((course) => course.position.centerX)
    .sort((a, b) => a - b);

  const columns: number[][] = [];

  for (const x of sortedX) {
    const lastColumn = columns[columns.length - 1];

    if (!lastColumn) {
      columns.push([x]);

      continue;
    }

    const average = lastColumn.reduce((sum, value) => sum + value, 0) /
      lastColumn.length;

    if (Math.abs(x - average) <= 60) {
      lastColumn.push(x);
    } else {
      columns.push([x]);
    }
  }

  const columnCenters = columns.map(
    (column) => column.reduce((sum, value) => sum + value, 0) / column.length,
  );

  return courses.map((course) => {
    const x = course.position?.centerX;

    if (typeof x !== "number") {
      return { ...course, semester: null };
    }

    let closestIndex = 0;

    let closestDistance = Infinity;

    columnCenters.forEach((center, index) => {
      const distance = Math.abs(x - center);

      if (distance < closestDistance) {
        closestDistance = distance;

        closestIndex = index;
      }
    });

    return {
      ...course,

      semester: closestIndex + 1,

      semesterColumnX: columnCenters[closestIndex],
    };
  });
}

function evaluateCourseQuality(
  course: any,
  requireCredits: boolean,
  requireCode = true,
) {
  const reasons: string[] = [];

  const confidence = typeof course.confidence === "number"
    ? course.confidence
    : null;

  if (requireCode && !course.code) {
    reasons.push("code_missing");
  }

  if (course.curricularSlotType === "elective_slot") {
    reasons.push("elective_slot");
  }

  if (!course.name) {
    reasons.push("name_missing");
  }

  if (course.nameAssociationUncertain === true) {
    reasons.push("name_association_uncertain");
  }

  if (
    requireCredits &&
    (course.credits === null ||
      course.credits === undefined)
  ) {
    reasons.push("credits_missing");
  }

  if (confidence !== null && confidence < 0.9) {
    reasons.push("low_ocr_confidence");
  }

  let quality: "high" | "medium" | "review" = "high";

  if (
    reasons.includes("elective_slot") ||
    reasons.includes("code_missing") ||
    reasons.includes("name_missing") ||
    reasons.includes("name_association_uncertain") ||
    reasons.includes("low_ocr_confidence")
  ) {
    quality = "review";
  } else if (reasons.includes("credits_missing")) {
    quality = "medium";
  }

  return {
    ...course,
    quality,
    needsReview: quality !== "high",
    reviewReasons: reasons,
  };
}

function evaluateCoursesQuality(
  courses: any[],
  requireCredits = true,
  requireCode = true,
) {
  return courses.map((course) =>
    evaluateCourseQuality(
      course,
      requireCredits,
      requireCode,
    )
  );
}

function buildQualitySummary(courses: any[]) {
  const summary = {
    high: 0,

    medium: 0,

    review: 0,
  };

  const reviewCourseCodes: string[] = [];
  let reviewCourseCount = 0;

  for (const course of courses) {
    const quality = course.quality;

    if (
      quality === "high" ||
      quality === "medium" ||
      quality === "review"
    ) {
      summary[quality as keyof typeof summary] += 1;
    }

    if (course.needsReview === true) {
      reviewCourseCount += 1;
      if (course.code) reviewCourseCodes.push(course.code);
    }
  }

  return {
    qualitySummary: summary,

    reviewCourseCodes,

    reviewCourseCount,
  };
}

async function reserveOcrVisionUsage(
  userId: string,
  units = 1,
) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error(
      "Faltan variables internas de Supabase para reservar cuota OCR.",
    );
  }

  const response = await fetch(
    `${supabaseUrl}/rest/v1/rpc/reserve_ocr_vision_usage`,
    {
      method: "POST",

      headers: {
        apikey: serviceRoleKey,

        Authorization: `Bearer ${serviceRoleKey}`,

        "Content-Type": "application/json",
      },

      body: JSON.stringify({
        p_user_id: userId,

        p_units: units,

        p_monthly_limit: MONTHLY_VISION_LIMIT,

        p_daily_limit: DAILY_USER_VISION_LIMIT,
      }),
    },
  );

  if (!response.ok) {
    throw new Error(
      `Error reservando cuota OCR: ${response.status} ${await response.text()}`,
    );
  }

  const rows = await response.json();

  const row = Array.isArray(rows) ? rows[0] : null;

  if (
    !row ||
    typeof row.allowed !== "boolean" ||
    typeof row.monthly_used !== "number" ||
    typeof row.monthly_remaining !== "number" ||
    typeof row.daily_used !== "number" ||
    typeof row.daily_remaining !== "number"
  ) {
    throw new Error("Respuesta inválida de reserve_ocr_vision_usage.");
  }

  return {
    allowed: row.allowed,

    reason: typeof row.reason === "string" ? row.reason : null,

    monthly: {
      usedUnits: row.monthly_used,

      remainingUnits: row.monthly_remaining,

      limit: MONTHLY_VISION_LIMIT,
    },

    daily: {
      usedUnits: row.daily_used,

      remainingUnits: row.daily_remaining,

      limit: DAILY_USER_VISION_LIMIT,
    },
  };
}

async function createOcrUsage({
  userId,

  documentHash,

  pages = 1,

  visionUnits = 1,
}: {
  userId: string;

  documentHash: string;

  pages?: number;

  visionUnits?: number;
}) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error(
      "Faltan variables internas de Supabase para registrar uso OCR.",
    );
  }

  const response = await fetch(
    `${supabaseUrl}/rest/v1/ocr_usage`,
    {
      method: "POST",

      headers: {
        apikey: serviceRoleKey,

        Authorization: `Bearer ${serviceRoleKey}`,

        "Content-Type": "application/json",

        Prefer: "return=representation",
      },

      body: JSON.stringify({
        user_id: userId,

        document_hash: documentHash,

        provider: "google_vision",

        pages,

        vision_units: visionUnits,

        status: "started",
      }),
    },
  );

  if (!response.ok) {
    throw new Error(
      `Error registrando uso OCR: ${response.status} ${await response.text()}`,
    );
  }

  const rows = await response.json();

  if (
    !Array.isArray(rows) ||
    rows.length === 0 ||
    typeof rows[0]?.id !== "number"
  ) {
    throw new Error("No se pudo obtener el ID del registro OCR.");
  }

  return rows[0].id as number;
}

async function updateOcrUsageStatus(
  usageId: number,
  status: "success" | "failed",
) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error(
      "Faltan variables internas de Supabase para actualizar uso OCR.",
    );
  }

  const response = await fetch(
    `${supabaseUrl}/rest/v1/ocr_usage?id=eq.${usageId}`,
    {
      method: "PATCH",

      headers: {
        apikey: serviceRoleKey,

        Authorization: `Bearer ${serviceRoleKey}`,

        "Content-Type": "application/json",

        Prefer: "return=minimal",
      },

      body: JSON.stringify({ status }),
    },
  );

  if (!response.ok) {
    throw new Error(
      `Error actualizando uso OCR: ${response.status} ${await response.text()}`,
    );
  }
}

async function deleteTemporaryOcrFile(
  bucket: string,
  path: string,
  firebaseUid: string,
): Promise<boolean> {
  if (bucket !== OCR_BUCKET) {
    console.error("OCR cleanup: category=invalid_bucket");
    return false;
  }

  try {
    validateStoragePath(path, firebaseUid);
  } catch (_) {
    console.error("OCR cleanup: category=ownership_validation_failed");
    return false;
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !serviceRoleKey) {
    console.error("OCR cleanup: category=server_configuration");

    return false;
  }

  try {
    const response = await fetch(
      `${supabaseUrl}/storage/v1/object/${encodeURIComponent(bucket)}/${
        path
          .split("/")
          .map(encodeURIComponent)
          .join("/")
      }`,
      {
        method: "DELETE",

        headers: {
          apikey: serviceRoleKey,

          Authorization: `Bearer ${serviceRoleKey}`,
        },
      },
    );

    if (!response.ok) {
      console.error(
        `OCR cleanup: category=storage_rejected; status=${response.status}`,
      );

      return false;
    }

    return true;
  } catch (error) {
    console.error(
      `OCR cleanup: category=exception; type=${
        error instanceof Error ? error.name : "unknown"
      }`,
    );

    return false;
  }
}

async function getPdfPageCount(
  bytes: Uint8Array,
): Promise<number> {
  const pdf = await PDFDocument.load(bytes, {
    ignoreEncryption: true,
  });

  return pdf.getPageCount();
}

export async function handleOcrRequest(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return Response.json(
        { ok: false, error: "Método no permitido." },
        { status: 405, headers: corsHeaders },
      );
    }

    const authorization = req.headers.get("Authorization");

    if (!authorization?.startsWith("Bearer ")) {
      return Response.json(
        { ok: false, error: "Falta autenticación." },
        { status: 401, headers: corsHeaders },
      );
    }

    const token = authorization.substring(7);

    let firebaseUid: string;

    try {
      const verified = await verifyFirebaseIdToken(token);

      firebaseUid = verified.uid;
    } catch (error) {
      console.error("Firebase JWT inválido:", error);

      return Response.json(
        { ok: false, error: "Token Firebase inválido o expirado." },
        { status: 401, headers: corsHeaders },
      );
    }

    const body = await req.json();

    const bucket = typeof body.bucket === "string" ? body.bucket : "";

    const path = typeof body.path === "string" ? body.path : "";

    const mimeType = typeof body.mimeType === "string" ? body.mimeType : "";

    if (bucket !== OCR_BUCKET) {
      return Response.json(
        { ok: false, error: "Bucket OCR no permitido." },
        { status: 400, headers: corsHeaders },
      );
    }

    try {
      validateStoragePath(path, firebaseUid);
    } catch (error) {
      return Response.json(
        {
          ok: false,

          error: error instanceof Error ? error.message : String(error),
        },
        { status: 403, headers: corsHeaders },
      );
    }

    return await runWithTemporaryCleanup({
      operation: async () => {
        if (!ALLOWED_MIME_TYPES.has(mimeType)) {
          return Response.json(
            { ok: false, error: "Tipo de archivo OCR no permitido." },
            { status: 400, headers: corsHeaders },
          );
        }

        const supabaseUrl = Deno.env.get("SUPABASE_URL");

        const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

        if (!supabaseUrl || !serviceRoleKey) {
          throw new Error("Faltan variables internas de Supabase.");
        }

        const encodedPath = encodeStoragePath(path);

        const storageResponse = await fetch(
          `${supabaseUrl}/storage/v1/object/${bucket}/${encodedPath}`,
          {
            headers: {
              apikey: serviceRoleKey,

              Authorization: `Bearer ${serviceRoleKey}`,
            },
          },
        );

        if (!storageResponse.ok) {
          const errorText = await storageResponse.text();

          return Response.json(
            {
              ok: false,

              error: "No se pudo descargar el archivo desde Storage.",

              storageStatus: storageResponse.status,

              storageError: errorText,
            },
            { status: 404, headers: corsHeaders },
          );
        }

        const storageContentType = storageResponse.headers
          .get("content-type")
          ?.split(";")[0]
          .trim()
          .toLowerCase() ?? null;

        if (
          storageContentType &&
          !ALLOWED_MIME_TYPES.has(storageContentType)
        ) {
          return Response.json(
            {
              ok: false,

              error: "Storage devolvió un tipo de archivo no permitido.",
            },
            { status: 400, headers: corsHeaders },
          );
        }

        const bytes = new Uint8Array(await storageResponse.arrayBuffer());

        if (bytes.length > MAX_FILE_SIZE_BYTES) {
          return Response.json(
            {
              ok: false,
              error: "El archivo supera el límite máximo de 10 MB.",
            },
            { status: 413, headers: corsHeaders },
          );
        }

        if (bytes.length === 0) {
          return Response.json(
            { ok: false, error: "El archivo descargado está vacío." },
            { status: 400, headers: corsHeaders },
          );
        }

        let visionUnits = 1;

        let pdfPageCount: number | null = null;

        if (mimeType === "application/pdf") {
          try {
            pdfPageCount = await getPdfPageCount(bytes);
          } catch (pdfError) {
            console.error("No se pudo leer el PDF:", pdfError);

            return Response.json(
              {
                ok: false,

                error:
                  "No se pudo leer el PDF. Puede estar dañado, cifrado o tener un formato no compatible.",
              },
              { status: 400, headers: corsHeaders },
            );
          }

          if (pdfPageCount < 1) {
            return Response.json(
              {
                ok: false,

                error: "El PDF no contiene páginas válidas.",
              },
              { status: 400, headers: corsHeaders },
            );
          }

          if (pdfPageCount > 5) {
            return Response.json(
              {
                ok: false,

                error: "El PDF supera el máximo permitido de 5 páginas.",

                pageCount: pdfPageCount,

                maxPdfPages: 5,
              },
              { status: 400, headers: corsHeaders },
            );
          }

          visionUnits = pdfPageCount;
        }

        const documentHash = await sha256Hex(bytes);

        const cached = await getCachedOcrResult(documentHash);

        if (cached) {
          const cachedBlocks = Array.isArray(cached.result?.blocks)
            ? cached.result.blocks
            : [];

          // Recalcula la clasificación al leer desde caché para que
          // mejoras nuevas del parser también afecten OCR antiguos.
          const reparsedBlocks = cachedBlocks.map((block: any) => {
            const blockText = typeof block?.text === "string" ? block.text : "";

            return {
              ...block,
              normalizedText: normalizeAcademicCode(blockText),
              type: detectBlockType(blockText),
              position: getBoundingMetrics(block),
            };
          });

          const cachedRequiresCredits = documentAppearsToUseCourseCredits(
            reparsedBlocks,
          );

          const cachedParsingMode = detectCurriculumParsingMode(reparsedBlocks);

          const cachedSemesterColumns = cachedParsingMode === "layout_based"
            ? detectSemesterColumns(reparsedBlocks)
            : [];

          const cachedLayoutCourseCandidates =
            cachedParsingMode === "layout_based"
              ? detectLayoutCourseCandidates(
                reparsedBlocks,
                cachedSemesterColumns,
              )
              : [];

          const cachedMergedLayoutCourseCandidates =
            cachedParsingMode === "layout_based"
              ? mergeLayoutCourseCandidateFragments(
                cachedLayoutCourseCandidates,
              )
              : [];

          const cachedLayoutCourses = cachedParsingMode === "layout_based"
            ? buildLayoutCourses(
              cachedMergedLayoutCourseCandidates,
              cachedSemesterColumns,
              reparsedBlocks,
            )
            : [];

          const cachedSemesterAssignmentSamples =
            cachedParsingMode === "layout_based"
              ? buildSemesterAssignmentSamples(
                reparsedBlocks,
                cachedSemesterColumns,
              )
              : [];

          const cachedRequireCredits = cachedParsingMode === "layout_based"
            ? false
            : documentAppearsToUseCourseCredits(
              reparsedBlocks,
            );

          const reparsedCourses = cachedParsingMode === "layout_based"
            ? evaluateCoursesQuality(
              cachedLayoutCourses,
              false,
              false,
            )
            : evaluateCoursesQuality(
              assignSemesters(
                buildCourses(reparsedBlocks),
              ),
              cachedRequireCredits,
              true,
            );

          const cachedSpecialCurricularElements =
            cachedParsingMode === "code_based"
              ? buildSpecialCurricularElements(reparsedBlocks, reparsedCourses)
              : [];

          const qualityData = buildQualitySummary(reparsedCourses);

          const temporaryFileDeleted = false;

          return Response.json(
            {
              ok: true,

              cacheHit: true,

              documentHash,

              cachedAt: cached.created_at,

              temporaryFileDeleted,

              ...cached.result,

              blocks: reparsedBlocks,

              courseCount: reparsedCourses.length,
              extractionStatus: reparsedCourses.length > 0
                ? "courses_extracted"
                : "no_courses_extracted",

              courses: reparsedCourses,
              specialCurricularElements: cachedSpecialCurricularElements,

              parsingMode: cachedParsingMode,

              semesterColumns: cachedSemesterColumns,

              semesterAssignmentSamples: cachedSemesterAssignmentSamples,

              layoutCourseCandidates: cachedLayoutCourseCandidates,

              mergedLayoutCourseCandidates: cachedMergedLayoutCourseCandidates,

              courseCreditsExpected: cachedParsingMode === "layout_based"
                ? false
                : cachedRequireCredits,

              ...qualityData,
            },
            { headers: corsHeaders },
          );
        }

        const reservation = await reserveOcrVisionUsage(
          firebaseUid,
          visionUnits,
        );

        if (!reservation.allowed) {
          const message = reservation.reason === "daily_limit"
            ? "OCR temporalmente bloqueado porque este usuario alcanzó el límite diario interno."
            : "OCR temporalmente bloqueado porque se alcanzó el límite interno mensual de Google Vision.";

          return Response.json(
            {
              ok: false,

              cacheHit: false,

              quotaBlocked: true,

              quotaReason: reservation.reason,

              message,

              documentHash,

              monthlyUsage: reservation.monthly,

              dailyUsage: reservation.daily,
            },
            { status: 429, headers: corsHeaders },
          );
        }

        const usageId = await createOcrUsage({
          userId: firebaseUid,

          documentHash,

          pages: visionUnits,

          visionUnits,
        });

        const projectId = Deno.env.get("GOOGLE_CLOUD_PROJECT_ID");

        const clientEmail = Deno.env.get("GOOGLE_CLOUD_CLIENT_EMAIL");

        const privateKey = Deno.env.get("GOOGLE_CLOUD_PRIVATE_KEY");

        if (!projectId || !clientEmail || !privateKey) {
          try {
            await updateOcrUsageStatus(usageId, "failed");
          } catch (statusError) {
            console.error(
              "No se pudo marcar ocr_usage como failed:",
              statusError,
            );
          }

          throw new Error("Faltan secretos de Google Cloud.");
        }

        try {
          const accessToken = await getGoogleAccessToken(
            clientEmail,
            privateKey,
          );

          const cleanBase64 = bytesToBase64(bytes);

          let pageResponses: any[] = [];

          if (mimeType === "application/pdf") {
            if (pdfPageCount === null) {
              throw new Error(
                "No se pudo determinar la cantidad de páginas del PDF.",
              );
            }

            const requestedPages = Array.from(
              { length: pdfPageCount },
              (_, index) => index + 1,
            );

            const visionResponse = await fetch(
              "https://vision.googleapis.com/v1/files:annotate",
              {
                method: "POST",

                headers: {
                  Authorization: `Bearer ${accessToken}`,

                  "Content-Type": "application/json",

                  "x-goog-user-project": projectId,
                },

                body: JSON.stringify({
                  requests: [
                    {
                      inputConfig: {
                        content: cleanBase64,

                        mimeType: "application/pdf",
                      },

                      features: [
                        { type: "DOCUMENT_TEXT_DETECTION" },
                      ],

                      pages: requestedPages,
                    },
                  ],
                }),
              },
            );

            const visionData = await visionResponse.json();

            if (!visionResponse.ok) {
              throw new Error(
                `Google Cloud Vision rechazó el PDF (${visionResponse.status}): ${
                  JSON.stringify(visionData)
                }`,
              );
            }

            const fileResult = visionData.responses?.[0];

            if (fileResult?.error) {
              throw new Error(
                `Cloud Vision devolvió un error procesando el PDF: ${
                  JSON.stringify(fileResult.error)
                }`,
              );
            }

            pageResponses = Array.isArray(fileResult?.responses)
              ? fileResult.responses
              : [];

            if (pageResponses.length === 0) {
              throw new Error(
                "Cloud Vision no devolvió respuestas de páginas para el PDF.",
              );
            }
          } else {
            const visionResponse = await fetch(
              "https://vision.googleapis.com/v1/images:annotate",
              {
                method: "POST",

                headers: {
                  Authorization: `Bearer ${accessToken}`,

                  "Content-Type": "application/json",

                  "x-goog-user-project": projectId,
                },

                body: JSON.stringify({
                  requests: [
                    {
                      image: { content: cleanBase64 },

                      features: [
                        { type: "DOCUMENT_TEXT_DETECTION" },
                      ],

                      imageContext: {
                        languageHints: ["es"],
                      },
                    },
                  ],
                }),
              },
            );

            const visionData = await visionResponse.json();

            if (!visionResponse.ok) {
              throw new Error(
                `Google Cloud Vision rechazó la solicitud (${visionResponse.status}): ${
                  JSON.stringify(visionData)
                }`,
              );
            }

            const imageResult = visionData.responses?.[0];

            if (imageResult?.error) {
              throw new Error(
                `Cloud Vision devolvió un error: ${
                  JSON.stringify(imageResult.error)
                }`,
              );
            }

            pageResponses = [imageResult];
          }

          const textParts: string[] = [];

          const blocks: any[] = [];

          let detectedPageCount = 0;

          pageResponses.forEach((pageResponse: any, responseIndex: number) => {
            if (pageResponse?.error) {
              throw new Error(
                `Cloud Vision devolvió un error en una página: ${
                  JSON.stringify(pageResponse.error)
                }`,
              );
            }

            const pageText = pageResponse?.fullTextAnnotation?.text ??
              pageResponse?.textAnnotations?.[0]?.description ??
              "";

            if (pageText.length > 0) {
              textParts.push(pageText);
            }

            const responsePages = pageResponse?.fullTextAnnotation?.pages ?? [];

            responsePages.forEach((page: any) => {
              detectedPageCount += 1;

              const contextPageNumber = pageResponse?.context?.pageNumber;

              const logicalPageNumber = typeof contextPageNumber === "number"
                ? contextPageNumber
                : mimeType === "application/pdf"
                ? responseIndex + 1
                : detectedPageCount;

              (page.blocks ?? []).forEach(
                (block: any, blockIndex: number) => {
                  const wordItems: any[] = [];

                  const blockText = (block.paragraphs ?? [])
                    .flatMap((paragraph: any) =>
                      (paragraph.words ?? []).map((word: any) => {
                        const wordText = (word.symbols ?? [])
                          .map((symbol: any) => symbol.text ?? "")
                          .join("");

                        const lastSymbol = word.symbols
                          ?.[word.symbols.length - 1];

                        const breakType = lastSymbol?.property?.detectedBreak
                          ?.type;

                        const separator = breakType === "LINE_BREAK" ||
                            breakType === "EOL_SURE"
                          ? "\n"
                          : " ";

                        const wordMetrics = getBoundingMetrics(word);

                        wordItems.push({
                          text: wordText,
                          confidence: typeof word.confidence === "number"
                            ? word.confidence
                            : null,
                          position: wordMetrics,
                        });

                        return `${wordText}${separator}`;
                      })
                    )
                    .join("")
                    .trim();

                  const metrics = getBoundingMetrics(block);

                  blocks.push({
                    page: logicalPageNumber,

                    block: blockIndex + 1,

                    text: blockText,

                    normalizedText: normalizeAcademicCode(blockText),

                    type: detectBlockType(blockText),

                    confidence: block.confidence ?? null,

                    boundingBox: block.boundingBox ?? null,

                    words: wordItems,

                    position: metrics,
                  });
                },
              );
            });
          });

          const text = textParts.join("\n\n").trim();

          const parsingMode = detectCurriculumParsingMode(blocks);

          const semesterColumns = parsingMode === "layout_based"
            ? detectSemesterColumns(blocks)
            : [];

          const layoutCourseCandidates = parsingMode === "layout_based"
            ? detectLayoutCourseCandidates(
              blocks,
              semesterColumns,
            )
            : [];

          const mergedLayoutCourseCandidates = parsingMode === "layout_based"
            ? mergeLayoutCourseCandidateFragments(
              layoutCourseCandidates,
            )
            : [];

          const layoutCourses = parsingMode === "layout_based"
            ? buildLayoutCourses(
              mergedLayoutCourseCandidates,
              semesterColumns,
              blocks,
            )
            : [];

          const semesterAssignmentSamples = parsingMode === "layout_based"
            ? buildSemesterAssignmentSamples(
              blocks,
              semesterColumns,
            )
            : [];

          const requireCredits = parsingMode === "layout_based"
            ? false
            : documentAppearsToUseCourseCredits(blocks);

          const courses = parsingMode === "layout_based"
            ? evaluateCoursesQuality(
              layoutCourses,
              false,
              false,
            )
            : evaluateCoursesQuality(
              assignSemesters(
                buildCourses(blocks),
              ),
              requireCredits,
              true,
            );

          const specialCurricularElements = parsingMode === "code_based"
            ? buildSpecialCurricularElements(blocks, courses)
            : [];

          const qualityData = buildQualitySummary(courses);

          const processedPageCount = mimeType === "application/pdf"
            ? (pdfPageCount ?? detectedPageCount)
            : detectedPageCount;

          const result = {
            textDetected: text.length > 0,

            text,

            pageCount: processedPageCount,

            blockCount: blocks.length,

            blocks,

            courseCount: courses.length,
            extractionStatus: courses.length > 0
              ? "courses_extracted"
              : "no_courses_extracted",

            courses,

            specialCurricularElements,

            mimeType,

            parsingMode,

            semesterColumns,

            semesterAssignmentSamples,

            layoutCourseCandidates,

            mergedLayoutCourseCandidates,

            courseCreditsExpected: requireCredits,

            ...qualityData,
          };

          let usageStatusSaved = true;

          try {
            await updateOcrUsageStatus(usageId, "success");
          } catch (statusError) {
            usageStatusSaved = false;

            console.error(
              "No se pudo marcar ocr_usage como success:",
              statusError,
            );
          }

          let cacheSaved = true;

          try {
            await saveOcrResultToCache({
              documentHash,

              mimeType,

              result,

              pageCount: result.pageCount,

              courseCount: courses.length,

              visionUnits,
            });
          } catch (cacheError) {
            cacheSaved = false;

            console.error(
              "Vision funcionó, pero no se pudo guardar caché:",
              cacheError,
            );
          }

          const temporaryFileDeleted = false;

          return Response.json(
            {
              ok: true,

              cacheHit: false,

              quotaBlocked: false,

              documentHash,

              monthlyUsage: reservation.monthly,

              dailyUsage: reservation.daily,

              usageStatusSaved,

              cacheSaved,

              temporaryFileDeleted,

              ...result,
            },
            { headers: corsHeaders },
          );
        } catch (visionError) {
          try {
            await updateOcrUsageStatus(usageId, "failed");
          } catch (statusError) {
            console.error(
              "No se pudo marcar ocr_usage como failed:",
              statusError,
            );
          }

          console.error("Error procesando con Google Vision:", visionError);

          return Response.json(
            {
              ok: false,

              cacheHit: false,

              quotaBlocked: false,

              documentHash,

              monthlyUsage: reservation.monthly,

              dailyUsage: reservation.daily,

              error: visionError instanceof Error
                ? visionError.message
                : "Error desconocido procesando con Google Vision.",
            },
            { status: 502, headers: corsHeaders },
          );
        }
      },
      cleanup: () => deleteTemporaryOcrFile(bucket, path, firebaseUid),
      onCleanupFailure: (error) => {
        console.error(
          `OCR cleanup: category=unexpected_exception; type=${
            error instanceof Error ? error.name : "unknown"
          }`,
        );
      },
    });
  } catch (error) {
    console.error(error);

    return Response.json(
      {
        ok: false,

        error: error instanceof Error ? error.message : String(error),
      },
      { status: 500, headers: corsHeaders },
    );
  }
}

if (import.meta.main) Deno.serve(handleOcrRequest);
