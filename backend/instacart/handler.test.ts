import assert from 'node:assert/strict';
import { test } from 'node:test';
import { handler, instacartBody, validLink, type Dependencies } from './handler.ts';
const payload = { title: 'Plated groceries', items: [{ name: 'Salmon', quantity: 1.5, unit: 'lb' }, { name: 'Garlic', quantity: 3, unit: 'clove' }] };
function setup(change: Partial<Dependencies> = {}) {
  let calls = 0; let saved = 0;
  const deps: Dependencies = { apiKey: 'test-only', production: false, authenticate: async () => 'test-user', cached: async () => null, save: async () => { saved++; }, allow: async () => true,
    fetch: (async (url, init) => { calls++; assert.match(String(url), /^https:\/\/connect.dev.instacart.tools/); assert.equal(init?.redirect, 'error'); return Response.json({ products_link_url: 'https://www.instacart.com/store/shopping_lists/test' }); }) as typeof fetch, ...change };
  return { run: handler(deps), calls: () => calls, saved: () => saved };
}
const request = (body: unknown = payload, token = 'a-valid-test-token-123456789') => new Request('https://plated.test/shopping', { method: 'POST', headers: { 'X-Plated-Session': token }, body: JSON.stringify(body) });
test('authenticates before creating or returning a link', async () => { const d = setup({ authenticate: async () => null }); assert.equal((await d.run(request())).status, 401); assert.equal(d.calls(), 0); });
test('missing session is refused', async () => { const d = setup(); assert.equal((await d.run(request(payload, ''))).status, 401); });
test('missing partner key fails honestly', async () => { const d = setup({ apiKey: undefined }); assert.equal((await d.run(request())).status, 503); assert.equal(d.calls(), 0); });
test('creates a real API handoff and caches it', async () => { const d = setup(); const r = await d.run(request()); assert.equal(r.status, 200); assert.match((await r.json()).products_link_url, /instacart.com/); assert.equal(d.calls(), 1); assert.equal(d.saved(), 1); });
test('cached lists do not make another partner request', async () => { const d = setup({ cached: async () => 'https://www.instacart.com/test' }); assert.equal((await d.run(request())).status, 200); assert.equal(d.calls(), 0); });
test('changed quantities affect the fingerprint', async () => { const keys: string[] = []; const d = setup({ cached: async (_, key) => { keys.push(key); return null; } }); await d.run(request()); await d.run(request({ ...payload, items: [{ name: 'Salmon', quantity: 3, unit: 'lb' }] })); assert.notEqual(keys[0], keys[1]); });
test('quantities and unsupported measures are handled without invented counts', () => { const body = instacartBody(payload); assert.deepEqual(body.line_items[0].line_item_measurements, [{ quantity: 1.5, unit: 'pound' }]); assert.equal(body.line_items[1].line_item_measurements, undefined); assert.match(body.line_items[1].display_text, /3 clove/); });
test('invalid, oversized and negative lists are rejected', async () => { for (const body of [{ ...payload, items: [] }, { ...payload, items: [{ name: 'A', quantity: -1, unit: 'lb' }] }, { ...payload, items: Array(101).fill(payload.items[0]) }]) { assert.equal((await setup().run(request(body))).status, 400); } assert.equal((await setup().run(request('a'.repeat(50001)))).status, 413); });
test('enforces durable quota before upstream request', async () => { const d = setup({ allow: async () => false }); assert.equal((await d.run(request())).status, 429); assert.equal(d.calls(), 0); });
test('upstream failures and unsafe URLs cannot become successes', async () => { for (const response of [new Response('', { status: 500 }), Response.json({ products_link_url: 'https://instacart.com.attacker.test/x' })]) { const d = setup({ fetch: (async () => response) as typeof fetch }); assert.equal((await d.run(request())).status, 502); assert.equal(d.saved(), 0); } assert.equal(validLink('javascript:alert(1)'), false); });
