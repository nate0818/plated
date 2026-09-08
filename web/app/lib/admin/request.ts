import "server-only";

import { ADMIN_CSRF_HEADER, ADMIN_CSRF_VALUE } from "./contracts";

export const MAX_ADMIN_REQUEST_BYTES = 16 * 1024;

export class AdminRequestError extends Error {
  constructor(
    public readonly status: 400 | 403 | 413 | 415 | 503,
    message: string,
  ) {
    super(message);
    this.name = "AdminRequestError";
  }
}

const LOCAL_ADMIN_HOSTS = new Set(["localhost", "127.0.0.1", "[::1]"]);

function parseAdminOrigin(value: string): URL | null {
  try {
    const url = new URL(value);
    if (url.username || url.password || url.search || url.hash ||
        (url.pathname !== "" && url.pathname !== "/")) return null;
    if (url.protocol === "https:") return url;
    if (process.env.NODE_ENV !== "production" &&
        url.protocol === "http:" &&
        LOCAL_ADMIN_HOSTS.has(url.hostname)) return url;
    return null;
  } catch {
    return null;
  }
}

/**
 * Resolve the one origin that is allowed to host founder authentication and
 * admin mutations. Production must declare it explicitly so preview aliases
 * and a forged Host header cannot become trusted redirect or CSRF origins.
 */
export function canonicalAdminOrigin(requestUrl: string): string {
  const configured = process.env.ADMIN_ORIGIN;
  if (configured !== undefined) {
    if (!configured || configured !== configured.trim()) {
      throw new AdminRequestError(503, "ADMIN_ORIGIN is invalid.");
    }
    const parsed = parseAdminOrigin(configured);
    if (!parsed) throw new AdminRequestError(503, "ADMIN_ORIGIN is invalid.");
    return parsed.origin;
  }

  const requestOrigin = parseAdminOrigin(new URL(requestUrl).origin);
  if (process.env.NODE_ENV !== "production" &&
      requestOrigin &&
      LOCAL_ADMIN_HOSTS.has(requestOrigin.hostname)) {
    return requestOrigin.origin;
  }
  throw new AdminRequestError(503, "ADMIN_ORIGIN is required for the founder console.");
}

export function assertCanonicalAdminRequest(request: Request): string {
  const expectedOrigin = canonicalAdminOrigin(request.url);
  if (new URL(request.url).origin !== expectedOrigin) {
    throw new AdminRequestError(403, "This request did not come from the canonical founder console.");
  }
  return expectedOrigin;
}

export function assertAdminRequestOrigin(request: Request) {
  const origin = request.headers.get("origin");
  const expectedOrigin = assertCanonicalAdminRequest(request);
  const fetchSite = request.headers.get("sec-fetch-site");

  if (origin !== expectedOrigin || (fetchSite && fetchSite !== "same-origin")) {
    throw new AdminRequestError(403, "This request did not come from the founder console.");
  }
  if (request.headers.get(ADMIN_CSRF_HEADER) !== ADMIN_CSRF_VALUE) {
    throw new AdminRequestError(403, "The founder console request token is missing.");
  }
}

export async function readJsonObject(request: Request): Promise<Record<string, unknown>> {
  const contentType = request.headers.get("content-type")?.split(";", 1)[0].trim().toLowerCase();
  if (contentType !== "application/json") {
    throw new AdminRequestError(415, "Send JSON with the application/json content type.");
  }

  const declaredLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > MAX_ADMIN_REQUEST_BYTES) {
    throw new AdminRequestError(413, "The request is too large.");
  }

  const bytes = await request.arrayBuffer();
  if (bytes.byteLength > MAX_ADMIN_REQUEST_BYTES) {
    throw new AdminRequestError(413, "The request is too large.");
  }

  let value: unknown;
  try {
    const raw = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    value = JSON.parse(raw);
  } catch {
    throw new AdminRequestError(400, "The request body is not valid JSON.");
  }

  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new AdminRequestError(400, "The request body must be a JSON object.");
  }
  return value as Record<string, unknown>;
}

export function noStoreHeaders(): HeadersInit {
  return {
    "Cache-Control": "private, no-store, max-age=0, must-revalidate",
    Pragma: "no-cache",
    Vary: "Cookie",
  };
}
