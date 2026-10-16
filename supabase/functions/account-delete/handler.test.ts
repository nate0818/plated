import assert from "node:assert/strict";
import { test } from "node:test";
import {
  accountDeleteHandler,
  type AccountDeleteDependencies,
} from "./handler.ts";

const credential = "c673a7e9-326a-4d67-9ef8-3d95e1ea5f7f";
const requestID = "85533739-96dc-4a12-bb22-3d276457cc69";

function setup(change: Partial<AccountDeleteDependencies> = {}) {
  let received: [string, string] | undefined;
  const dependencies: AccountDeleteDependencies = {
    deleteAccount: async (token, id) => {
      received = [token, id];
      return true;
    },
    ...change,
  };
  return {
    run: accountDeleteHandler(dependencies),
    received: () => received,
  };
}

function request(headers: Record<string, string> = {}) {
  return new Request("https://plated.test/account-delete", {
    method: "POST",
    headers: {
      "X-Plated-Session": credential,
      "Idempotency-Key": requestID,
      ...headers,
    },
  });
}

test("passes the private bearer and idempotency key only to the database boundary", async () => {
  const fixture = setup();
  const response = await fixture.run(request());
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { deleted: true });
  assert.deepEqual(fixture.received(), [credential, requestID]);
  assert.equal(response.headers.get("Cache-Control"), "no-store");
});

test("refuses a missing or malformed credential before touching the database", async () => {
  for (const token of ["", "short", "contains a space"]) {
    const fixture = setup();
    const response = await fixture.run(request({ "X-Plated-Session": token }));
    assert.equal(response.status, 401);
    assert.equal(fixture.received(), undefined);
  }
});

test("refuses a missing or malformed idempotency key", async () => {
  for (const id of ["", "not-a-uuid", "00000000-0000-0000-0000-000000000000"]) {
    const fixture = setup();
    const response = await fixture.run(request({ "Idempotency-Key": id }));
    assert.equal(response.status, 401);
    assert.equal(fixture.received(), undefined);
  }
});

test("does not disclose whether an invalid bearer ever named an account", async () => {
  const response = await setup({ deleteAccount: async () => false }).run(request());
  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { error: "Sign in required" });
});

test("turns database failures into a retryable service response", async () => {
  const response = await setup({
    deleteAccount: async () => {
      throw new Error("database detail that must not escape");
    },
  }).run(request());
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), {
    error: "Account deletion is temporarily unavailable",
  });
});

test("accepts POST only", async () => {
  const response = await setup().run(new Request("https://plated.test/account-delete"));
  assert.equal(response.status, 405);
});
