import { handleRequest } from "./handler.ts";
import { EARLY_ACCESS_SOURCE, emailPattern } from "./contracts.ts";

function equal(a: unknown, b: unknown) { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`Mismatch: ${JSON.stringify(a)} != ${JSON.stringify(b)}`); }
function request(body: unknown) { return new Request("https://example.invalid/waitlist", { method: "POST", body: JSON.stringify(body) }); }

Deno.test("failed persistence never confirms a saved request", async () => {
  const response = await handleRequest(request({ email: "test@example.invalid", source: EARLY_ACCESS_SOURCE }), { insert: async () => ({ error: { code: "08006" } }), upgrade: async () => ({ error: null }) });
  equal(response.status, 500);
});
Deno.test("existing launch signup upgrades only after an explicit access request", async () => {
  let upgraded: string | null = null;
  const store = { insert: async () => ({ error: { code: "23505" } }), upgrade: async (email: string) => { upgraded = email; return { error: null }; } };
  equal((await handleRequest(request({ email: " TEST@example.invalid ", source: "plated.food" }), store)).status, 200);
  equal(upgraded, null);
  equal((await handleRequest(request({ email: " TEST@example.invalid ", source: EARLY_ACCESS_SOURCE }), store)).status, 200);
  equal(upgraded, "test@example.invalid");
});
Deno.test("failed consent upgrade is retryable rather than a false success", async () => {
  equal((await handleRequest(request({ email: "test@example.invalid", source: EARLY_ACCESS_SOURCE }), { insert: async () => ({ error: { code: "23505" } }), upgrade: async () => ({ error: new Error("unavailable") }) })).status, 500);
});
Deno.test("email lookup cannot treat valid wildcard characters as other addresses", () => {
  equal(emailPattern("a_b%test@example.invalid"), "a\\_b\\%test@example.invalid");
});
Deno.test("invalid addresses never reach persistence", async () => {
  let touched = false;
  const response = await handleRequest(request({ email: "invalid" }), { insert: async () => { touched = true; return { error: null }; }, upgrade: async () => ({ error: null }) });
  equal(response.status, 400); equal(touched, false);
});
