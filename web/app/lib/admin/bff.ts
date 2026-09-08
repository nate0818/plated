import "server-only";

import { createHmac, randomUUID } from "node:crypto";
import type { AdminCommandRequest, AdminReadRequest } from "./contracts";
import { AdminSessionError, requireAdminSession } from "./auth";
import { getPublicSupabaseConfig } from "../supabase/config";

const MAX_EDGE_RESPONSE_BYTES = 512 * 1024;

export type AdminEdgeResult<T> =
  | { ok: true; status: number; data: T; requestId: string }
  | {
      ok: false;
      status: number;
      error: string;
      requestId: string;
      code?: "mfa_step_up_required";
    };

class AdminEdgeConfigurationError extends Error {}

function functionName(kind: "read" | "command"): string {
  return kind === "read" ? "admin-read" : "announce";
}

function functionUrl(kind: "read" | "command"): URL {
  const supabase = getPublicSupabaseConfig();
  if (!supabase) throw new AdminEdgeConfigurationError("Supabase public configuration is missing.");

  const override = kind === "read"
    ? process.env.ADMIN_READ_FUNCTION_URL
    : process.env.ADMIN_COMMAND_FUNCTION_URL;
  const fallbackName = functionName(kind);
  const url = new URL(override?.trim() || `/functions/v1/${fallbackName}`, supabase.url);
  const expectedPath = `/functions/v1/${fallbackName}`;

  // An administrator JWT must only ever be sent back to this Supabase project.
  const local = url.hostname === "127.0.0.1" || url.hostname === "localhost";
  if (url.origin !== new URL(supabase.url).origin || url.pathname !== expectedPath || (url.protocol !== "https:" && !local) || url.username || url.password || url.search || url.hash) {
    throw new AdminEdgeConfigurationError(`The ${kind} function URL is invalid.`);
  }
  return url;
}

function apiSecret(): string {
  const secret = process.env.ADMIN_API_SECRET ?? "";
  if (secret !== secret.trim()) {
    throw new AdminEdgeConfigurationError("ADMIN_API_SECRET must not begin or end with whitespace.");
  }
  if (Buffer.byteLength(secret, "utf8") < 32) {
    throw new AdminEdgeConfigurationError("ADMIN_API_SECRET is missing or too short.");
  }
  return secret;
}

async function cappedText(response: Response): Promise<string> {
  const declared = Number(response.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > MAX_EDGE_RESPONSE_BYTES) {
    throw new Error("response-too-large");
  }
  if (!response.body) return "";

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > MAX_EDGE_RESPONSE_BYTES) {
      await reader.cancel();
      throw new Error("response-too-large");
    }
    chunks.push(value);
  }
  const all = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    all.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(all);
}

function edgeMessage(value: unknown, fallback: string): string {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    const record = value as Record<string, unknown>;
    if (typeof record.error === "string" && record.error.length <= 240) return record.error;
    if (typeof record.message === "string" && record.message.length <= 240) return record.message;
  }
  return fallback;
}

export async function callAdminEdge<T>(
  kind: "read" | "command",
  payload: AdminReadRequest | AdminCommandRequest,
): Promise<AdminEdgeResult<T>> {
  const requestId = randomUUID();

  try {
    const [{ accessToken }, supabase] = await Promise.all([
      requireAdminSession({ recentTotp: kind === "command" }),
      Promise.resolve(getPublicSupabaseConfig()),
    ]);
    if (!supabase) throw new AdminEdgeConfigurationError("Supabase public configuration is missing.");

    const url = functionUrl(kind);
    const rawBody = JSON.stringify(payload);
    const timestamp = String(Math.floor(Date.now() / 1000));
    // The name, not the path: the function sees a different path than the one
    // called, so the two sides only agree on which endpoint this is.
    const signed = `v1:${timestamp}:POST:/${functionName(kind)}:${rawBody}`;
    const signature = createHmac("sha256", apiSecret()).update(signed).digest("hex");
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), kind === "read" ? 12_000 : 25_000);

    let response: Response;
    let rawResponse: string;
    try {
      response = await fetch(url, {
        method: "POST",
        headers: {
          Accept: "application/json",
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
          apikey: supabase.publishableKey,
          "x-plated-request-id": requestId,
          "x-plated-sig": signature,
          "x-plated-ts": timestamp,
        },
        body: rawBody,
        cache: "no-store",
        redirect: "error",
        signal: controller.signal,
      });
      rawResponse = await cappedText(response);
    } finally {
      clearTimeout(timeout);
    }

    let decoded: unknown = null;
    if (rawResponse) {
      try {
        decoded = JSON.parse(rawResponse);
      } catch {
        console.error("Founder admin response was unreadable. request_id=%s", requestId);
        return { ok: false, status: 502, error: "The admin service returned an unreadable response.", requestId };
      }
    }

    if (!response.ok) {
      return {
        ok: false,
        status: response.status,
        error: edgeMessage(decoded, "The admin service refused the request."),
        requestId,
      };
    }

    return { ok: true, status: response.status, data: decoded as T, requestId };
  } catch (error) {
    if (error instanceof AdminSessionError) {
      return {
        ok: false,
        status: error.status,
        error: error.message,
        requestId,
        ...(error.code ? { code: error.code } : {}),
      };
    }
    if (error instanceof AdminEdgeConfigurationError) {
      return { ok: false, status: 503, error: error.message, requestId };
    }
    if (error instanceof Error && error.name === "AbortError") {
      console.error("Founder admin request timed out. request_id=%s", requestId);
      return { ok: false, status: 504, error: "The admin service timed out.", requestId };
    }
    console.error("Founder admin request failed. request_id=%s", requestId);
    return { ok: false, status: 502, error: "The admin service is unavailable.", requestId };
  }
}

export function adminEdgeConfigured(): { read: boolean; command: boolean; secret: boolean } {
  let secret = false;
  let read = false;
  let command = false;
  try { functionUrl("read"); read = true; } catch { /* setup state */ }
  try { functionUrl("command"); command = true; } catch { /* setup state */ }
  try { apiSecret(); secret = true; } catch { /* setup state */ }
  return { read, command, secret };
}
