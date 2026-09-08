import { NextResponse } from "next/server";
import { AdminSessionError } from "../../../lib/admin/auth";
import { callAdminEdge } from "../../../lib/admin/bff";
import { assertAdminRequestOrigin, AdminRequestError, noStoreHeaders, readJsonObject } from "../../../lib/admin/request";
import { AdminValidationError, normalizeCommandRequest } from "../../../lib/admin/validation";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  try {
    assertAdminRequestOrigin(request);
    const payload = normalizeCommandRequest(await readJsonObject(request));
    const result = await callAdminEdge<unknown>("command", payload);
    if (!result.ok) {
      return NextResponse.json(
        {
          error: result.error,
          request_id: result.requestId,
          ...(result.code ? { code: result.code } : {}),
        },
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
    console.error("Founder command failed without a response.");
    return NextResponse.json({ error: "The founder command service is unavailable." }, { status: 502, headers: noStoreHeaders() });
  }
}
