import "server-only";

import { getPublicSupabaseConfig } from "../supabase/config";
import { createClient } from "../supabase/server";

export type AdminIdentity = { id: string; email: string | null };

export const ADMIN_TOTP_STEP_UP_SECONDS = 15 * 60;

export type AdminAuthState =
  | { kind: "setup" }
  | { kind: "signed-out" }
  | { kind: "mfa-required"; user: AdminIdentity }
  | {
      kind: "ready";
      user: AdminIdentity;
      accessToken: string;
      totpVerifiedAt: number | null;
      recentTotp: boolean;
    };

export class AdminSessionError extends Error {
  constructor(
    public readonly status: 401 | 403 | 503,
    message: string,
    public readonly code?: "mfa_step_up_required",
  ) {
    super(message);
    this.name = "AdminSessionError";
  }
}

function authenticationMethod(entry: unknown): string | null {
  if (typeof entry === "string") return entry;
  if (!entry || typeof entry !== "object" || Array.isArray(entry)) return null;
  const method = (entry as { method?: unknown }).method;
  return typeof method === "string" ? method : null;
}

function totpVerificationTimestamp(methods: unknown): number | null {
  if (!Array.isArray(methods)) return null;
  let latest: number | null = null;
  for (const entry of methods) {
    // A string-only AMR can establish the session's AAL, but cannot prove when
    // the TOTP occurred. Any non-detailed or malformed entry fails step-up
    // closed so the BFF and Edge verifier make the same decision.
    if (typeof entry === "string") return null;
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) return null;
    const method = (entry as { method?: unknown }).method;
    const timestamp = (entry as { timestamp?: unknown }).timestamp;
    if (typeof method !== "string" || method.length < 1 || method.length > 64 ||
        typeof timestamp !== "number" || !Number.isSafeInteger(timestamp) || timestamp <= 0) {
      return null;
    }
    if (method !== "totp") continue;
    latest = latest === null ? timestamp : Math.max(latest, timestamp);
  }
  return latest;
}

function isRecentTotp(timestamp: number | null, nowSeconds = Math.floor(Date.now() / 1000)): boolean {
  if (timestamp === null) return false;
  const age = nowSeconds - timestamp;
  return age >= -30 && age <= ADMIN_TOTP_STEP_UP_SECONDS;
}

/**
 * Verify the signed JWT with Supabase on every protected server entry point.
 * getSession alone only reads the cookie, so it is deliberately never used as
 * the authorization check. The access token is read only after getClaims and AAL
 * verification, then forwarded to the Edge Function for principal checks.
 */
export async function getAdminAuthState(): Promise<AdminAuthState> {
  if (!getPublicSupabaseConfig()) return { kind: "setup" };

  const supabase = await createClient();
  const { data: claimsData, error: claimsError } = await supabase.auth.getClaims();
  const claims = claimsData?.claims;

  if (claimsError || !claims || typeof claims.sub !== "string" || !claims.sub) {
    return { kind: "signed-out" };
  }
  const user = {
    id: claims.sub,
    email: typeof claims.email === "string" ? claims.email : null,
  };

  const { data: assurance, error: assuranceError } =
    await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  const methods: unknown = assurance?.currentAuthenticationMethods ?? [];
  const totpVerifiedThisSession = Array.isArray(methods) && methods.some((entry) => {
    const method = authenticationMethod(entry);
    return method === "totp";
  });

  if (assuranceError || !assurance || assurance.currentLevel !== "aal2" || !totpVerifiedThisSession) {
    return { kind: "mfa-required", user };
  }

  const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
  const accessToken = sessionData.session?.access_token;

  if (sessionError || !accessToken) return { kind: "signed-out" };
  const totpVerifiedAt = totpVerificationTimestamp(methods);
  return {
    kind: "ready",
    user,
    accessToken,
    totpVerifiedAt,
    recentTotp: isRecentTotp(totpVerifiedAt),
  };
}

export async function requireAdminSession(
  options: { recentTotp?: boolean } = {},
): Promise<Extract<AdminAuthState, { kind: "ready" }>> {
  const state = await getAdminAuthState();
  if (state.kind === "setup") {
    throw new AdminSessionError(503, "The founder console has not been configured.");
  }
  if (state.kind === "signed-out") {
    throw new AdminSessionError(401, "Your session has ended. Sign in again.");
  }
  if (state.kind === "mfa-required") {
    throw new AdminSessionError(403, "Authenticator verification is required.");
  }
  if (options.recentTotp && !state.recentTotp) {
    throw new AdminSessionError(
      403,
      "Confirm with your authenticator before using founder controls.",
      "mfa_step_up_required",
    );
  }
  return state;
}

const ADMIN_NEXT_PATHS = new Set([
  "/admin",
  "/admin/announcements",
  "/admin/audit",
  "/admin/operations",
  "/admin/people",
  "/admin/releases",
  "/admin/waitlist",
]);

export function safeAdminNextPath(value: unknown, fallback = "/admin"): string {
  return typeof value === "string" && ADMIN_NEXT_PATHS.has(value) ? value : fallback;
}

export function adminUserLabel(user: AdminIdentity): string {
  return user.email ?? "Founder account";
}
