// POST /device — where to reach this phone.
//
// Body: { api_token, apns_token, sandbox }
// Returns: { ok }
//
// The api_token is the session minted by /register; a caller without one is
// nobody to the directory and gets nothing. One row per (user, token): a
// person with two phones has two rows, and a reinstalled phone that minted
// a new token simply adds one. A person keeps at most eight tokens, oldest
// dropped first, so a token minted on every reinstall cannot grow a row
// per launch. Dead tokens are pruned by whoever sends, for that user only.
import { createClient } from "jsr:@supabase/supabase-js@2";

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const KEEP = 8;

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("method", { status: 405 });
  const body = await req.json().catch(() => null);
  const apiToken = String(body?.api_token ?? "");
  const apnsToken = String(body?.apns_token ?? "").toLowerCase();
  // An APNs token is 32 bytes today, hex-encoded by the app. Anything
  // else is not a token, whatever it is.
  if (!/^[0-9a-f]{64}$/.test(apnsToken) || !/^[0-9a-f-]{36}$/.test(apiToken)) {
    return new Response("missing", { status: 400 });
  }

  const { data: user } = await db
    .from("directory_users").select("id").eq("api_token", apiToken).maybeSingle();
  if (!user) return new Response("unregistered", { status: 403 });

  const { error } = await db.from("device_tokens").upsert(
    {
      user_id: user.id,
      apns_token: apnsToken,
      sandbox: Boolean(body?.sandbox),
      updated_at: new Date().toISOString(),
    },
    { onConflict: "user_id,apns_token" },
  );
  if (error) return new Response(error.message, { status: 500 });

  const { data: rows } = await db
    .from("device_tokens").select("apns_token, updated_at")
    .eq("user_id", user.id).order("updated_at", { ascending: false });
  const stale = (rows ?? []).slice(KEEP).map((r) => r.apns_token);
  if (stale.length) {
    await db.from("device_tokens").delete().eq("user_id", user.id).in("apns_token", stale);
  }
  return Response.json({ ok: true });
});
