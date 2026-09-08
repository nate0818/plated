import "server-only";

import type { AdminReadRequest } from "./contracts";
import { callAdminEdge, type AdminEdgeResult } from "./bff";
import { AdminContractError } from "./decode";

export async function loadAdminPageData<T>(
  request: AdminReadRequest,
  decode: (value: unknown) => T,
): Promise<AdminEdgeResult<T>> {
  const result = await callAdminEdge<unknown>("read", request);
  if (!result.ok) return result;

  try {
    return { ...result, data: decode(result.data) };
  } catch (error) {
    return {
      ok: false,
      status: 502,
      error: error instanceof AdminContractError ? error.message : "The founder data could not be read.",
      requestId: result.requestId,
    };
  }
}
