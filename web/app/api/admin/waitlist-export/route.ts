import { NextResponse } from "next/server";
import { callAdminEdge } from "../../../lib/admin/bff";
import { assertAdminRequestOrigin, AdminRequestError, noStoreHeaders, readJsonObject } from "../../../lib/admin/request";
import { normalizeReadRequest } from "../../../lib/admin/validation";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  try {
    assertAdminRequestOrigin(request);
    const body = await readJsonObject(request);
    const payload = normalizeReadRequest({ op: "waitlist-export", limit: 100, ...(body.cursor ? { cursor: body.cursor } : {}) });
    const result = await callAdminEdge<unknown>("read", payload);
    return NextResponse.json(result.ok ? result.data : { error: result.error, code: result.code }, { status: result.status, headers: noStoreHeaders() });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "The list could not be downloaded." }, { status: error instanceof AdminRequestError ? error.status : 400, headers: noStoreHeaders() });
  }
}
