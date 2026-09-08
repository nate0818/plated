import { decodeOffset, encodeOffset, maskEmail, parseAdminReadCommand } from "./contracts.ts";

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}
function assertThrows(run: () => unknown): void {
  try { run(); } catch { return; }
  throw new Error("Expected rejection");
}

Deno.test("read contracts allow only named operations and bounded pages", () => {
  assertEquals(parseAdminReadCommand({ op: "people" }), { op: "people", cursor: null, limit: 50 });
  assertThrows(() => parseAdminReadCommand({ op: "sql", query: "select *" }));
  assertThrows(() => parseAdminReadCommand({ op: "people", limit: 1000 }));
});

Deno.test("pagination cursor is opaque and bounded", () => {
  assertEquals(decodeOffset(encodeOffset(125)), 125);
  assertThrows(() => decodeOffset(btoa("-1")));
  assertThrows(() => decodeOffset(btoa("not-a-number")));
});

Deno.test("waitlist emails are masked before leaving the function", () => {
  assertEquals(maskEmail("Founder@example.com"), "f•••@e••.com");
  assertEquals(maskEmail("bad"), "hidden");
});
