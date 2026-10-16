export type AccountDeleteDependencies = {
  deleteAccount: (credential: string, requestID: string) => Promise<boolean>;
};

const jsonHeaders = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};

const answer = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: jsonHeaders });

// The shipping directory protocol mints a v4 UUID bearer. Accepting a broader
// shape here would only turn malformed credentials into database errors; the
// future per-installation session cutover must update this boundary and the RPC
// together.
const credentialPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const requestIDPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/// HTTP boundary for account deletion. The database RPC authenticates the
/// bearer and performs the entire mutation in one transaction; this layer
/// deliberately never logs or echoes the credential.
export function accountDeleteHandler(dependencies: AccountDeleteDependencies) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return answer(405, { error: "Method not allowed" });
    }

    const credential = request.headers.get("X-Plated-Session")?.trim() ?? "";
    const requestID = request.headers.get("Idempotency-Key")?.trim() ?? "";
    if (!credentialPattern.test(credential) || !requestIDPattern.test(requestID)) {
      return answer(401, { error: "Sign in required" });
    }

    try {
      const deleted = await dependencies.deleteAccount(credential, requestID);
      if (!deleted) return answer(401, { error: "Sign in required" });
      return answer(200, { deleted: true });
    } catch {
      return answer(503, { error: "Account deletion is temporarily unavailable" });
    }
  };
}
