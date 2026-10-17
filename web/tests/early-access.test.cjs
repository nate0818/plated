/* eslint-disable @typescript-eslint/no-require-imports -- Node test harness uses CommonJS. */
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const ts = require("typescript");

function load(file, overrides = {}) {
  const loaded = { exports: {} };
  const source = ts.transpileModule(fs.readFileSync(path.join(__dirname, "..", file), "utf8"), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  vm.runInNewContext(source, { exports: loaded.exports, module: loaded, require, Request, Response, AbortSignal, console: { error() {} }, ...overrides });
  return loaded.exports;
}
function request(value) {
  return new Request("https://plated.food/api/waitlist", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(value) });
}

test("access request keeps its purpose through the public BFF", async () => {
  let submitted;
  const { POST } = load("app/api/waitlist/route.ts", { fetch: async (url, init) => { submitted = { url, body: JSON.parse(init.body) }; return Response.json({ ok: true }); } });
  assert.equal((await POST(request({ email: "test@example.invalid", intent: "early-access" }))).status, 200);
  assert.equal(submitted.body.source, "plated.food/early-access");
  assert.equal(submitted.body.email, "test@example.invalid");
  assert.equal(submitted.url, "https://dyvrksooelbkzkprqlhk.supabase.co/functions/v1/waitlist");
});
test("legacy launch requests retain their original purpose", async () => {
  let source;
  const { POST } = load("app/api/waitlist/route.ts", { fetch: async (_url, init) => { source = JSON.parse(init.body).source; return Response.json({ ok: true }); } });
  assert.equal((await POST(request({ email: "test@example.invalid" }))).status, 200);
  assert.equal(source, "plated.food");
});
test("invalid email never reaches persistence and failed persistence never confirms success", async () => {
  let called = false;
  const { POST } = load("app/api/waitlist/route.ts", { fetch: async () => { called = true; return new Response("unavailable", { status: 503 }); } });
  assert.equal((await POST(request({ email: "invalid" }))).status, 400);
  assert.equal(called, false);
  assert.equal((await POST(request({ email: "test@example.invalid", intent: "early-access" }))).status, 502);
});
test("CSV download preserves quoting and neutralises spreadsheet formulas", () => {
  const { csvCell } = load("app/lib/admin/csv.ts");
  assert.equal(csvCell('a"b@example.invalid'), '"a""b@example.invalid"');
  assert.equal(csvCell("=test@example.invalid"), '"\'=test@example.invalid"');
  assert.equal(csvCell("normal@example.invalid"), '"normal@example.invalid"');
});
