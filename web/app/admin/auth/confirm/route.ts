import type { EmailOtpType } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import {
  assertCanonicalAdminRequest,
  canonicalAdminOrigin,
  AdminRequestError,
  noStoreHeaders,
} from "../../../lib/admin/request";
import { getPublicSupabaseConfig } from "../../../lib/supabase/config";
import { createClient } from "../../../lib/supabase/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const ACCEPTED_TYPES = new Set<EmailOtpType>(["invite", "recovery"]);

export async function GET(request: Request) {
  const url = new URL(request.url);
  let adminOrigin: string;
  try {
    adminOrigin = canonicalAdminOrigin(request.url);
    assertCanonicalAdminRequest(request);
  } catch (error) {
    if (error instanceof AdminRequestError && error.status === 403) {
      const canonical = canonicalAdminOrigin(request.url);
      return NextResponse.redirect(new URL("/admin/login?notice=link", canonical), {
        headers: noStoreHeaders(),
      });
    }
    const status = error instanceof AdminRequestError ? error.status : 503;
    return NextResponse.json(
      { error: "Founder authentication is not configured for this origin." },
      { status, headers: noStoreHeaders() },
    );
  }

  const tokenHash = url.searchParams.get("token_hash") ?? "";
  const rawType = url.searchParams.get("type") ?? "";
  const failure = new URL("/admin/login?notice=link", adminOrigin);

  if (!getPublicSupabaseConfig() || tokenHash.length < 20 || tokenHash.length > 2048 ||
      !/^[A-Za-z0-9._~-]+$/.test(tokenHash) || !ACCEPTED_TYPES.has(rawType as EmailOtpType)) {
    return NextResponse.redirect(failure, { headers: noStoreHeaders() });
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.verifyOtp({ token_hash: tokenHash, type: rawType as EmailOtpType });
  if (error) return NextResponse.redirect(failure, { headers: noStoreHeaders() });

  return NextResponse.redirect(new URL("/admin/password", adminOrigin), { headers: noStoreHeaders() });
}
