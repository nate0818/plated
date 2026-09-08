import { importPKCS8, SignJWT } from "https://deno.land/x/jose@v5.9.6/index.ts";

const TOPIC = "com.natemeadows.plated";
const HOSTS = {
  sandbox: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
} as const;

export type APNSEnvironment = keyof typeof HOSTS;
export type DeliveryState = "accepted" | "retryable" | "permanent_failure";

export interface APNsDevice {
  apns_token: string;
  apns_environment?: APNSEnvironment;
  // When this exact token binding was last attached. APNs 410 timestamps
  // older than this generation cannot invalidate it.
  token_registered_at?: string;
  // Transitional compatibility for invite rows written before the migration.
  sandbox?: boolean;
}

export interface Push {
  title: string;
  body: string;
  link: string;
  thread?: string;
  sound?: boolean;
  category?: string;
  level?: "passive" | "active";
  priority?: 5 | 10;
  collapseID?: string;
  expiresAt?: number;
  extra?: Record<string, string>;
}

export interface AttemptClassification {
  kind: "accepted" | "token_invalid" | "retryable" | "permanent";
  invalidateProviderToken: boolean;
}

export interface PushResult {
  configured: boolean;
  state: DeliveryState;
  status: number;
  reason: string;
  apnsID: string | null;
  timestamp: number | null;
  acceptedEnvironment: APNSEnvironment | null;
  invalidateToken: boolean;
}

export interface Delivery {
  configured: boolean;
  sent: number;
  dead: string[];
  retry: number;
  permanentFailure: number;
  flipped: string[];
}

const TOKEN_INVALID_REASONS = new Set([
  "BadDeviceToken",
  "Unregistered",
  "DeviceTokenNotForTopic",
]);
const RETRY_REASONS = new Set([
  "ExpiredProviderToken",
  "InvalidProviderToken",
  "MissingProviderToken",
  "TooManyProviderTokenUpdates",
  "TooManyRequests",
  "InternalServerError",
  "ServiceUnavailable",
  "Shutdown",
]);

export function classifyAPNsResponse(status: number, reason: string): AttemptClassification {
  if (status >= 200 && status < 300) return { kind: "accepted", invalidateProviderToken: false };
  if (TOKEN_INVALID_REASONS.has(reason)) return { kind: "token_invalid", invalidateProviderToken: false };
  if (status === 0 || status === 429 || status >= 500 || RETRY_REASONS.has(reason)) {
    return {
      kind: "retryable",
      invalidateProviderToken: reason === "ExpiredProviderToken" || reason === "InvalidProviderToken",
    };
  }
  return { kind: "permanent", invalidateProviderToken: false };
}

let cachedProviderToken: { token: string; at: number } | null = null;
let providerTokenInFlight: Promise<string> | null = null;

export function apnsConfigured(): boolean {
  return Boolean(
    Deno.env.get("APNS_TEAM_ID") && Deno.env.get("APNS_KEY_ID") && Deno.env.get("APNS_KEY_P8"),
  );
}

async function providerToken(): Promise<string | null> {
  const teamID = Deno.env.get("APNS_TEAM_ID");
  const keyID = Deno.env.get("APNS_KEY_ID");
  const p8 = Deno.env.get("APNS_KEY_P8");
  if (!teamID || !keyID || !p8) return null;
  if (cachedProviderToken && Date.now() - cachedProviderToken.at < 50 * 60 * 1000) {
    return cachedProviderToken.token;
  }
  if (providerTokenInFlight) return await providerTokenInFlight;

  const mint = (async () => {
    const key = await importPKCS8(p8.replace(/\\n/g, "\n"), "ES256");
    const token = await new SignJWT({})
      .setProtectedHeader({ alg: "ES256", kid: keyID })
      .setIssuer(teamID)
      .setIssuedAt()
      .sign(key);
    cachedProviderToken = { token, at: Date.now() };
    return token;
  })();
  providerTokenInFlight = mint;
  try {
    return await mint;
  } finally {
    if (providerTokenInFlight === mint) providerTokenInFlight = null;
  }
}

interface Attempt {
  status: number;
  reason: string;
  apnsID: string | null;
  timestamp: number | null;
}

export function authoritativeTokenInvalidation(
  status: number,
  reason: string,
  timestamp: number | null,
  tokenRegisteredAt?: string,
): boolean {
  if ((reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic") && status === 400) {
    return true;
  }
  if (reason !== "Unregistered" || status !== 410 || !Number.isSafeInteger(timestamp)
    || timestamp === null || timestamp <= 0 || !tokenRegisteredAt) return false;
  const registeredAt = Date.parse(tokenRegisteredAt);
  return Number.isFinite(registeredAt) && timestamp >= registeredAt;
}

function safeReason(value: unknown, fallback: string): string {
  const reason = typeof value === "string" ? value : fallback;
  return reason.replace(/[^A-Za-z0-9_.-]/g, "").slice(0, 80) || fallback;
}

async function post(
  environment: APNSEnvironment,
  token: string,
  providerJWT: string,
  push: Push,
  payload: string,
): Promise<Attempt> {
  const headers: Record<string, string> = {
    authorization: `bearer ${providerJWT}`,
    "apns-topic": TOPIC,
    "apns-push-type": "alert",
    "apns-priority": String(push.priority ?? 10),
  };
  if (push.collapseID) headers["apns-collapse-id"] = push.collapseID.slice(0, 64);
  if (push.expiresAt !== undefined) headers["apns-expiration"] = String(push.expiresAt);
  try {
    const response = await fetch(`${HOSTS[environment]}/3/device/${token}`, {
      method: "POST",
      headers,
      body: payload,
      signal: AbortSignal.timeout(10_000),
    });
    const apnsID = response.headers.get("apns-id");
    if (response.ok) return { status: response.status, reason: "", apnsID, timestamp: null };
    const responseBody = await response.json().catch(() => ({}));
    const rawTimestamp = (responseBody as { timestamp?: unknown }).timestamp;
    return {
      status: response.status,
      reason: safeReason((responseBody as { reason?: unknown }).reason, `HTTP${response.status}`),
      apnsID,
      timestamp: typeof rawTimestamp === "number" && Number.isSafeInteger(rawTimestamp)
          && rawTimestamp > 0 && rawTimestamp <= 32_503_680_000_000
        ? rawTimestamp
        : null,
    };
  } catch {
    // Network exception text can include host or runtime details. Persist only a
    // stable class that is safe to show in the founder console.
    return { status: 0, reason: "NetworkUnavailable", apnsID: null, timestamp: null };
  }
}

async function tokenDiagnostic(token: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  return Array.from(new Uint8Array(digest).slice(0, 6), (byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

function payload(push: Push): string {
  const aps: Record<string, unknown> = {
    alert: { title: push.title, body: push.body },
    "thread-id": push.thread ?? "table",
  };
  if (push.sound !== false) aps.sound = "default";
  if (push.level) aps["interruption-level"] = push.level;
  if (push.category) aps.category = push.category;
  return JSON.stringify({ aps, link: push.link, ...(push.extra ?? {}) });
}

function alternate(environment: APNSEnvironment): APNSEnvironment {
  return environment === "sandbox" ? "production" : "sandbox";
}

export async function sendOne(device: APNsDevice, push: Push): Promise<PushResult> {
  const providerJWT = await providerToken();
  if (!providerJWT) {
    return {
      configured: false,
      state: "retryable",
      status: 0,
      reason: "APNsNotConfigured",
      apnsID: null,
      timestamp: null,
      acceptedEnvironment: null,
      invalidateToken: false,
    };
  }
  const home: APNSEnvironment = device.apns_environment ?? (device.sandbox ? "sandbox" : "production");
  const diagnostic = await tokenDiagnostic(device.apns_token);
  const first = await post(home, device.apns_token, providerJWT, push, payload(push));
  const firstClass = classifyAPNsResponse(first.status, first.reason);
  if (firstClass.invalidateProviderToken) cachedProviderToken = null;
  if (firstClass.kind === "accepted") {
    return { configured: true, state: "accepted", ...first, acceptedEnvironment: home, invalidateToken: false };
  }
  console.log(`apns ${first.status} ${first.reason} token_hash=${diagnostic}`);
  if (firstClass.kind === "retryable") {
    return { configured: true, state: "retryable", ...first, acceptedEnvironment: null, invalidateToken: false };
  }
  if (firstClass.kind === "permanent") {
    return { configured: true, state: "permanent_failure", ...first, acceptedEnvironment: null, invalidateToken: false };
  }

  // A token-invalid response can mean only that the recorded APNs gateway is
  // stale. The other gateway gets one attempt. A transient second response can
  // never delete the token.
  const other = alternate(home);
  const second = await post(other, device.apns_token, providerJWT, push, payload(push));
  const secondClass = classifyAPNsResponse(second.status, second.reason);
  if (secondClass.invalidateProviderToken) cachedProviderToken = null;
  if (secondClass.kind === "accepted") {
    console.log(`apns gateway_repaired token_hash=${diagnostic}`);
    return { configured: true, state: "accepted", ...second, acceptedEnvironment: other, invalidateToken: false };
  }
  console.log(`apns ${second.status} ${second.reason} alternate token_hash=${diagnostic}`);
  if (secondClass.kind === "retryable") {
    return { configured: true, state: "retryable", ...second, acceptedEnvironment: null, invalidateToken: false };
  }
  return {
    configured: true,
    state: "permanent_failure",
    ...second,
    acceptedEnvironment: null,
    invalidateToken: secondClass.kind === "token_invalid" && authoritativeTokenInvalidation(
      second.status,
      second.reason,
      second.timestamp,
      device.token_registered_at,
    ),
  };
}

// Small-recipient convenience for invite. Fleet announcements use sendOne and
// persist each result before claiming another batch.
export async function send(devices: APNsDevice[], push: Push): Promise<Delivery> {
  let configured = true;
  let sent = 0;
  let retry = 0;
  let permanentFailure = 0;
  const dead: string[] = [];
  const flipped: string[] = [];
  for (const device of devices) {
    const original = device.apns_environment ?? (device.sandbox ? "sandbox" : "production");
    const result = await sendOne(device, push);
    configured &&= result.configured;
    if (result.state === "accepted") {
      sent += 1;
      if (result.acceptedEnvironment && result.acceptedEnvironment !== original) flipped.push(device.apns_token);
    } else if (result.state === "retryable") {
      retry += 1;
    } else {
      permanentFailure += 1;
      if (result.invalidateToken) dead.push(device.apns_token);
    }
  }
  return { configured, sent, dead, retry, permanentFailure, flipped };
}
