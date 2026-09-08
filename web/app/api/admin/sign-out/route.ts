import { NextResponse } from "next/server";
import { requireAdminSession, AdminSessionError } from "../../../lib/admin/auth";
import { assertAdminRequestOrigin, AdminRequestError, noStoreHeaders } from "../../../lib/admin/request";
import { createClient } from "../../../lib/supabase/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  try {
    assertAdminRequestOrigin(request);
    await requireAdminSession();
    const supabase = await createClient();
    const { error } = await supabase.auth.signOut({ scope: "local" });
    if (error) {
      return NextResponse.json({ error: "The session could not be cleared." }, { status: 502, headers: noStoreHeaders() });
    }
    return NextResponse.json({ ok: true }, { headers: noStoreHeaders() });
  } catch (error) {
    if (error instanceof AdminRequestError || error instanceof AdminSessionError) {
      return NextResponse.json({ error: error.message }, { status: error.status, headers: noStoreHeaders() });
    }
    return NextResponse.json({ error: "The session could not be cleared." }, { status: 502, headers: noStoreHeaders() });
  }
}
