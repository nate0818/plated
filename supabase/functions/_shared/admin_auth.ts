import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.115.0";

const encoder = new TextEncoder();
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const HEX_256 = /^[0-9a-f]{64}$/;
const MAX_CLOCK_SKEW_SECONDS = 300;
const RECENT_TOTP_MAX_AGE_SECONDS = 15 * 60;
const TOTP_FUTURE_SKEW_SECONDS = 30;

export type AdminDatabase = SupabaseClient;

export interface AdminContext {
  actorId: string;
  email: string | null;
  role: string;
  permissions: string[];
  requestId: string;
  db: AdminDatabase;
}

export interface JwtAuthClaims {
  aal: "aal1" | "aal2" | null;
  amr: unknown;
}

export interface AdminAuthenticationOptions {
  requireRecentTotp?: boolean;
  requestId?: string;
}

export class AdminHttpError extends Error {
  constructor(public status: number, message: string, public code?: string) {
    super(message);
  }
}

export function signaturePayload(timestamp: string, method: string, pathname: string, rawBody: string): string {
  return `v1:${timestamp}:${method.toUpperCase()}:${pathname}:${rawBody}`;
}

function bytesToHex(value: ArrayBuffer): string {
  return Array.from(new Uint8Array(value), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function hmacHex(secret: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return bytesToHex(await crypto.subtle.sign("HMAC", key, encoder.encode(value)));
}

export function constantTimeHexEquals(expected: string, actual: string): boolean {
  if (!HEX_256.test(expected) || !HEX_256.test(actual)) return false;
  let difference = 0;
  for (let index = 0; index < expected.length; index += 1) {
    difference |= expected.charCodeAt(index) ^ actual.charCodeAt(index);
  }
  return difference === 0;
}

function accessToken(req: Request): string {
  const authorization = req.headers.get("authorization") ?? "";
  const match = authorization.match(/^Bearer ([A-Za-z0-9._~-]+)$/);
  if (!match) throw new AdminHttpError(401, "A founder session is required.");
  return match[1];
}

// The caller may trust these decoded claims only after Auth getUser has
// validated this exact token. Keeping parsing pure makes the claim rules easy
// to exercise without weakening the authoritative verification step.
export function parseJwtAuthClaims(token: string): JwtAuthClaims | null {
  try {
    const encoded = token.split(".")[1];
    if (!encoded) return null;
    const base64 = encoded.replace(/-/g, "+").replace(/_/g, "/")
      .padEnd(Math.ceil(encoded.length / 4) * 4, "=");
    const payload = JSON.parse(atob(base64)) as unknown;
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) return null;
    const record = payload as { aal?: unknown; amr?: unknown };
    return {
      aal: record.aal === "aal2" ? "aal2" : record.aal === "aal1" ? "aal1" : null,
      amr: record.amr,
    };
  } catch {
    return null;
  }
}

export function jwtAssuranceLevel(token: string): "aal1" | "aal2" | null {
  return parseJwtAuthClaims(token)?.aal ?? null;
}

export function hasRecentTotp(
  claims: JwtAuthClaims | null,
  nowSeconds = Math.floor(Date.now() / 1000),
): boolean {
  if (!claims || !Number.isSafeInteger(nowSeconds) || !Array.isArray(claims.amr)) return false;
  let recent = false;
  for (const raw of claims.amr) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return false;
    const entry = raw as { method?: unknown; timestamp?: unknown };
    if (typeof entry.method !== "string" || entry.method.length < 1 || entry.method.length > 64
      || typeof entry.timestamp !== "number" || !Number.isSafeInteger(entry.timestamp)
      || entry.timestamp <= 0) {
      return false;
    }
    const timestamp = entry.timestamp;
    if (timestamp > nowSeconds + TOTP_FUTURE_SKEW_SECONDS) return false;
    if (entry.method === "totp" && timestamp >= nowSeconds - RECENT_TOTP_MAX_AGE_SECONDS) {
      recent = true;
    }
  }
  return recent;
}

export function adminSecretConfigurationError(secret: string): string | null {
  if (secret !== secret.trim()) {
    return "ADMIN_API_SECRET must not have leading or trailing whitespace.";
  }
  if (encoder.encode(secret).byteLength < 32) {
    return "ADMIN_API_SECRET must contain at least 32 bytes.";
  }
  return null;
}

function serviceClient(): AdminDatabase {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_SECRET_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !key) throw new AdminHttpError(503, "Founder services are not configured.");
  return createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

async function verifyHmac(req: Request, rawBody: string): Promise<void> {
  const secret = Deno.env.get("ADMIN_API_SECRET") ?? "";
  const configurationError = adminSecretConfigurationError(secret);
  if (configurationError) throw new AdminHttpError(503, configurationError);
  const timestamp = req.headers.get("x-plated-ts") ?? "";
  const signature = (req.headers.get("x-plated-sig") ?? "").toLowerCase();
  if (!/^\d{10}$/.test(timestamp) || !HEX_256.test(signature)) {
    throw new AdminHttpError(401, "The signed request is invalid.");
  }
  const sentAt = Number(timestamp);
  if (!Number.isSafeInteger(sentAt) || Math.abs(Math.floor(Date.now() / 1000) - sentAt) > MAX_CLOCK_SKEW_SECONDS) {
    console.error("founder signed request outside the accepted clock skew");
    throw new AdminHttpError(401, "The signed request has expired.");
  }
  // Sign over the function's own name, not the request path. The gateway
  // routes /functions/v1/<name> to a container that sees a different path
  // than the caller sent, so signing the full path made every request fail
  // verification with a correct secret on both sides. The name still binds a
  // signature to one endpoint: an admin-read signature cannot be replayed
  // against announce.
  const endpoint = functionEndpoint(req);
  const expected = await hmacHex(
    secret,
    signaturePayload(timestamp, req.method, endpoint, rawBody),
  );
  if (!constantTimeHexEquals(expected, signature)) {
    console.error(`founder signature mismatch endpoint=${endpoint}`);
    throw new AdminHttpError(401, "The signed request is invalid.");
  }
}

/// The last non-empty path segment, which is the function's name whether or
/// not the platform kept the /functions/v1 prefix.
export function functionEndpoint(req: Request): string {
  const segments = new URL(req.url).pathname.split("/").filter(Boolean);
  return `/${segments.at(-1) ?? ""}`;
}

export async function authenticateAdmin(
  req: Request,
  rawBody: string,
  permission: string,
  options: AdminAuthenticationOptions = {},
): Promise<AdminContext> {
  await verifyHmac(req, rawBody);
  const token = accessToken(req);
  const db = serviceClient();

  // getUser performs the authoritative Auth validation. Only after that
  // succeeds do we inspect the verified token's standard Supabase `aal` claim.
  const { data: userData, error: userError } = await db.auth.getUser(token);
  if (userError || !userData.user) {
    console.error("founder session rejected by the auth server");
    throw new AdminHttpError(401, "The founder session is no longer valid.");
  }
  const claims = parseJwtAuthClaims(token);
  if (claims?.aal !== "aal2") {
    throw new AdminHttpError(403, "Complete multi-factor authentication to continue.");
  }
  if (options.requireRecentTotp && !hasRecentTotp(claims)) {
    throw new AdminHttpError(
      403,
      "Verify a TOTP code again to continue.",
      "mfa_step_up_required",
    );
  }

  const { data: principal, error: principalError } = await db
    .from("admin_principals")
    .select("role, permissions, active")
    .eq("user_id", userData.user.id)
    .maybeSingle();
  if (principalError) throw new AdminHttpError(503, "Founder authorization is unavailable.");
  const permissions = Array.isArray(principal?.permissions)
    ? principal.permissions.filter((value): value is string => typeof value === "string")
    : [];
  if (!principal?.active || (!permissions.includes(permission) && !permissions.includes("*"))) {
    throw new AdminHttpError(403, "This founder account does not have that permission.");
  }

  return {
    actorId: userData.user.id,
    email: userData.user.email ?? null,
    role: String(principal.role ?? "operator"),
    permissions,
    requestId: options.requestId ?? adminRequestId(req),
    db,
  };
}

export async function audit(
  context: AdminContext,
  action: string,
  outcome: "allowed" | "denied" | "failed",
  targetType?: string,
  targetId?: string,
  metadata: Record<string, unknown> = {},
): Promise<void> {
  const { error } = await context.db.rpc("admin_record_audit_event", {
    p_actor_user_id: context.actorId,
    p_action: action,
    p_outcome: outcome,
    p_target_type: targetType ?? null,
    p_target_id: targetId ?? null,
    p_request_id: context.requestId,
    p_metadata: metadata,
  });
  if (error) throw new AdminHttpError(503, "The audit trail is unavailable.");
}

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store, max-age=0",
      "x-content-type-options": "nosniff",
    },
  });
}

export function adminRequestId(req: Request): string {
  const supplied = req.headers.get("x-plated-request-id") ?? "";
  return UUID.test(supplied) ? supplied.toLowerCase() : crypto.randomUUID();
}

export function adminErrorResponse(error: unknown, requestId?: string): Response {
  if (error instanceof AdminHttpError) {
    if (requestId && (error.status === 401 || error.status === 403)) {
      console.log(`founder request denied request_id=${requestId}`);
    } else if (requestId && error.status >= 500) {
      console.error(`founder request failed request_id=${requestId}`);
    }
    return jsonResponse(
      error.code ? { error: error.message, code: error.code } : { error: error.message },
      error.status,
    );
  }
  // Database/provider details can contain implementation or account data. They
  // stay out of both logs and responses; the request id is enough to correlate
  // a failure with the append-only audit trail.
  if (requestId) console.error(`founder request failed request_id=${requestId}`);
  return jsonResponse({ error: "Founder services could not complete the request." }, 500);
}

export async function readBoundedBody(req: Request, maxBytes = 32_768): Promise<string> {
  const reader = req.body?.getReader();
  if (!reader) return "";
  const decoder = new TextDecoder();
  let raw = "";
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > maxBytes) {
      await reader.cancel();
      throw new AdminHttpError(413, "The request is too large.");
    }
    raw += decoder.decode(value, { stream: true });
  }
  return raw + decoder.decode();
}
