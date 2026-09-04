import { handler } from "./handler.ts";
const base = Deno.env.get("SUPABASE_URL")!;
const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
async function database(path: string, init: RequestInit = {}) {
  const r = await fetch(base + "/rest/v1/" + path, { ...init, headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json", ...init.headers }, signal: AbortSignal.timeout(8000) });
  if (!r.ok) throw new Error("Database unavailable");
  const text = await r.text(); return text ? JSON.parse(text) : null;
}
// Custom authentication matches Plated's existing Apple-verified directory
// sessions. verify_jwt=false never implies anonymous access to this handler.
Deno.serve(handler({
  apiKey: Deno.env.get("INSTACART_API_KEY"), production: Deno.env.get("INSTACART_ENV") === "production", fetch,
  authenticate: async token => {
    const rows = await database("directory_users?select=id&api_token=eq." + encodeURIComponent(token) + "&limit=1");
    return rows?.[0]?.id ?? null;
  },
  cached: async (user, fingerprint) => {
    const rows = await database("instacart_links?select=products_link_url&user_id=eq." + encodeURIComponent(user) + "&fingerprint=eq." + fingerprint + "&expires_at=gt." + encodeURIComponent(new Date().toISOString()));
    return rows?.[0]?.products_link_url ?? null;
  },
  allow: user => database("rpc/claim_instacart_request", { method: "POST", body: JSON.stringify({ caller: user }) }),
  save: async (user, fingerprint, url) => {
    await database("instacart_links", { method: "POST", headers: { Prefer: "resolution=merge-duplicates" }, body: JSON.stringify({ user_id: user, fingerprint, products_link_url: url, expires_at: new Date(Date.now() + 6 * 86400000).toISOString() }) });
  },
}));
