type Item = { name: string; quantity: number; unit: string };
type Payload = { title: string; items: Item[] };
export type Dependencies = {
  authenticate: (token: string) => Promise<string | null>;
  cached: (user: string, fingerprint: string) => Promise<string | null>;
  save: (user: string, fingerprint: string, url: string) => Promise<void>;
  allow: (user: string) => Promise<boolean>;
  apiKey: string | undefined;
  production: boolean;
  fetch: typeof fetch;
};
const headers = { "Content-Type": "application/json", "Cache-Control": "no-store" };
const answer = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers });
const aliases: Record<string, string> = { "": "each", "lb": "pound", "oz": "ounce", "fl oz": "fl oz ounce", "tbsp": "tablespoon", "tsp": "teaspoon", "clove": "each", "piece": "each", "slice": "each" };
const units = new Set(["each", "pound", "ounce", "fl oz ounce", "tablespoon", "teaspoon", "cup", "can", "bunch", "head", "package", "packet", "pint", "quart", "gallon", "g", "kg", "ml", "l"]);
export function validate(value: unknown): Payload | null {
  if (!value || typeof value !== "object") return null;
  const p = value as Payload;
  if (typeof p.title !== "string" || !p.title.trim() || p.title.length > 100 || !Array.isArray(p.items) || p.items.length < 1 || p.items.length > 100) return null;
  if (p.items.some(i => !i || typeof i.name !== "string" || !i.name.trim() || i.name.length > 150 || !Number.isFinite(i.quantity) || i.quantity < 0 || i.quantity > 10000 || typeof i.unit !== "string" || i.unit.length > 30)) return null;
  return { title: p.title.trim(), items: p.items.map(i => ({ name: i.name.trim(), quantity: i.quantity, unit: i.unit.trim().toLowerCase() })) };
}
export function instacartBody(p: Payload) {
  return {
    title: p.title, link_type: "shopping_list", expires_in: 7,
    line_items: p.items.map(i => {
      const unit = aliases[i.unit] ?? i.unit;
      // Unsupported measures stay in the label. Never claim a "clove" is
      // an entire garlic bulb, or invent a store's package size.
      const measured = units.has(unit) && !["clove", "slice", "piece"].includes(i.unit) && i.quantity > 0;
      return { name: i.name, display_text: [i.quantity || "", i.unit, i.name].filter(Boolean).join(" "),
        ...(measured ? { line_item_measurements: [{ quantity: i.quantity, unit }] } : {}) };
    }),
    landing_page_configuration: { partner_linkback_url: "https://www.plated.food" },
  };
}
export function validLink(raw: unknown): raw is string {
  try { const u = new URL(String(raw)); return u.protocol === "https:" && ["instacart.com", "instacart.tools"].some(h => u.hostname === h || u.hostname.endsWith("." + h)); } catch { return false; }
}
export function handler(deps: Dependencies) {
  return async (req: Request): Promise<Response> => {
    if (req.method !== "POST") return answer(405, { error: "Method not allowed" });
    const token = req.headers.get("X-Plated-Session") ?? "";
    if (!/^[A-Za-z0-9._~+\/-]{20,256}$/.test(token)) return answer(401, { error: "Sign in required" });
    try {
      // Cap streamed input too: Content-Length may be absent or incorrect.
      const reader = req.body?.getReader(); if (!reader) return answer(400, { error: "List required" });
      let raw = ""; let length = 0; const decoder = new TextDecoder();
      while (true) { const { done, value } = await reader.read(); if (done) break; length += value.length; if (length > 50000) { await reader.cancel(); return answer(413, { error: "List is too large" }); } raw += decoder.decode(value, { stream: true }); }
      raw += decoder.decode();
      const payload = validate(JSON.parse(raw));
      if (!payload) return answer(400, { error: "Check the shopping list" });
      const user = await deps.authenticate(token);
      if (!user) return answer(401, { error: "Sign in required" });
      if (!deps.apiKey) return answer(503, { error: "Shopping is not configured" });
      const body = instacartBody(payload);
      const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify(body)));
      const fingerprint = Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, "0")).join("");
      const cached = await deps.cached(user, fingerprint);
      if (validLink(cached)) return answer(200, { products_link_url: cached });
      if (!(await deps.allow(user))) return answer(429, { error: "Try again later" });
      const base = deps.production ? "https://connect.instacart.com" : "https://connect.dev.instacart.tools";
      const response = await deps.fetch(base + "/idp/v1/products/products_link", {
        method: "POST", headers: { Authorization: `Bearer ${deps.apiKey}`, "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify(body), signal: AbortSignal.timeout(20000), redirect: "error",
      });
      if (!response.ok) return answer(response.status === 429 ? 429 : 502, { error: "Couldn't prepare the shopping list" });
      const result = await response.json();
      if (!validLink(result.products_link_url)) return answer(502, { error: "Invalid shopping link" });
      await deps.save(user, fingerprint, result.products_link_url);
      return answer(200, { products_link_url: result.products_link_url });
    } catch (error) {
      return answer(error instanceof SyntaxError ? 400 : 502, { error: "Couldn't prepare the shopping list" });
    }
  };
}
