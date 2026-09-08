import { NextResponse } from "next/server";
import { AdminSessionError } from "../../../lib/admin/auth";
import { callAdminEdge } from "../../../lib/admin/bff";
import { assertAdminRequestOrigin, AdminRequestError, noStoreHeaders, readJsonObject } from "../../../lib/admin/request";
import { AdminValidationError, normalizeReadRequest } from "../../../lib/admin/validation";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  try {
    assertAdminRequestOrigin(request);
    const payload = normalizeReadRequest(await readJsonObject(request));
    const result = await callAdminEdge<unknown>("read", payload);
    if (!result.ok) {
      return NextResponse.json(
        { error: result.error, request_id: result.requestId },
        { status: result.status, headers: noStoreHeaders() },
      );
    }
    return NextResponse.json(result.data, { status: result.status, headers: noStoreHeaders() });
  } catch (error) {
    if (error instanceof AdminRequestError || error instanceof AdminValidationError) {
      const status = error instanceof AdminRequestError ? error.status : 400;
      return NextResponse.json({ error: error.message }, { status, headers: noStoreHeaders() });
    }
    if (error instanceof AdminSessionError) {
      return NextResponse.json({ error: error.message }, { status: error.status, headers: noStoreHeaders() });
    }
    console.error("Founder read request failed without a response.");
    return NextResponse.json({ error: "The founder data service is unavailable." }, { status: 502, headers: noStoreHeaders() });
  }
}
