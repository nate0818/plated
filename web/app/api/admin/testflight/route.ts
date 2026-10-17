import { NextResponse } from "next/server";
import { callAdminEdge } from "../../../lib/admin/bff";
import {
  AdminRequestError,
  assertAdminRequestOrigin,
  noStoreHeaders,
  readJsonObject,
} from "../../../lib/admin/request";
import { normalizeTestFlightRequest } from "../../../lib/admin/testflight";
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export async function POST(request: Request) {
  try {
    assertAdminRequestOrigin(request);
    const payload = normalizeTestFlightRequest(await readJsonObject(request));
    const result = await callAdminEdge<unknown>("testflight", payload);
    return NextResponse.json(
      result.ok ? result.data : {
        error: result.error,
        code: result.code,
        request_id: result.requestId,
      },
      { status: result.status, headers: noStoreHeaders() },
    );
  } catch (error) {
    return NextResponse.json({
      error: error instanceof Error
        ? error.message
        : "The request could not be updated.",
    }, {
      status: error instanceof AdminRequestError ? error.status : 400,
      headers: noStoreHeaders(),
    });
  }
}
