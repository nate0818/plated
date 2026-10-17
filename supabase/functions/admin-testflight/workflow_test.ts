import { deepEqual, equal, rejects } from "node:assert/strict";
import {
  AppleClient,
  type AppleConfig,
  AppleError,
  appleToken,
  type Resource,
} from "./apple.ts";
import { assertFounder, parseCommand } from "./contracts.ts";
import {
  AttemptError,
  type Claim,
  processRequest,
  type TesterProvider,
} from "./workflow.ts";
const claim: Claim = {
  leaseId: "lease",
  email: "person@example.invalid",
  previousStatus: "new",
  maySend: true,
  testerId: null,
};
const tester = (state: string, id = "tester"): Resource => ({
  id,
  type: "betaTesters",
  attributes: { email: claim.email, state },
});
function provider(
  find: TesterProvider["find"],
): TesterProvider & { writes: string[] } {
  const writes: string[] = [];
  return {
    writes,
    find,
    create: async () => {
      writes.push("create");
      return tester("INVITED");
    },
    add: async () => {
      writes.push("add");
    },
    invite: async () => {
      writes.push("invite");
    },
  };
}
Deno.test("new tester creation uses group and does not send a second invitation", async () => {
  const p = provider(async () => null);
  equal((await processRequest(p, claim)).status, "invited");
  deepEqual(p.writes, ["create"]);
});
Deno.test("already invited, accepted, installed and revoked testers never receive another email", async () => {
  for (const state of ["INVITED", "ACCEPTED", "INSTALLED", "REVOKED"]) {
    const p = provider(async () => tester(state));
    await processRequest(p, claim);
    deepEqual(p.writes, []);
  }
});
Deno.test("a not-invited group member receives one explicit invitation", async () => {
  const p = provider(async () => tester("NOT_INVITED"));
  equal((await processRequest(p, claim)).status, "invited");
  deepEqual(p.writes, ["invite"]);
});
Deno.test("an existing tester is added to the selected group and read before sending", async () => {
  let reads = 0;
  const p = provider(async () =>
    ++reads === 1 ? null : tester(reads === 2 ? "NOT_INVITED" : "INVITED")
  );
  equal((await processRequest(p, claim)).status, "invited");
  deepEqual(p.writes, ["add"]);
  equal(reads, 3);
});
Deno.test("sync and uncertain retries never mutate Apple", async () => {
  for (const value of [null, tester("NOT_INVITED"), tester("INVITED")]) {
    const p = provider(async () => value);
    const result = await processRequest(p, {
      ...claim,
      maySend: false,
      previousStatus: "uncertain",
    });
    deepEqual(p.writes, []);
    equal(
      result.status,
      value?.attributes?.state === "INVITED" ? "invited" : "uncertain",
    );
  }
});
Deno.test("network loss during a send is uncertain while a definite refusal is retryable", async () => {
  for (
    const error of [
      new AppleError(0, true),
      new AppleError(503, true),
      new AppleError(403, false),
    ]
  ) {
    const p = provider(async () => tester("NOT_INVITED"));
    p.invite = async () => {
      throw error;
    };
    await rejects(
      () => processRequest(p, claim),
      (e: unknown) =>
        e instanceof AttemptError && e.uncertain === error.uncertain,
    );
  }
});
Deno.test("successful group assignment followed by a failed read is uncertain", async () => {
  let reads = 0;
  const p = provider(async () => {
    reads++;
    if (reads === 3) throw new AppleError(503, false);
    return reads === 1 ? null : tester("NOT_INVITED");
  });
  await rejects(
    () => processRequest(p, claim),
    (e: unknown) => e instanceof AttemptError && e.uncertain,
  );
  deepEqual(p.writes, ["add"]);
});
Deno.test("unknown Apple state cannot trigger an invitation", async () => {
  const p = provider(async () => tester("FUTURE_STATE"));
  await rejects(() => processRequest(p, claim));
  deepEqual(p.writes, []);
});
Deno.test("provider lookup failure before writes is safe to retry", async () => {
  const p = provider(async () => {
    throw new AppleError(503, false);
  });
  await rejects(
    () => processRequest(p, claim),
    (e: unknown) => e instanceof AttemptError && !e.uncertain,
  );
});
Deno.test("only founder and valid stored request IDs reach management operations", () => {
  for (const role of ["operator", "read_only", ""]) {
    let denied = false;
    try {
      assertFounder(role);
    } catch {
      denied = true;
    }
    equal(denied, true);
  }
  assertFounder("founder");
  deepEqual(
    parseCommand({
      op: "invite",
      id: "68043320-6433-4064-8676-243382064000",
      email: "ignored@example.invalid",
      groupId: "ignored",
    }),
    { op: "invite", id: "68043320-6433-4064-8676-243382064000" },
  );
  for (
    const value of [
      { op: "invite", id: "invalid" },
      { op: "list", offset: -1 },
      { op: "list", filter: "launch" },
      { op: "resend", id: "invalid" },
    ]
  ) {
    let denied = false;
    try {
      parseCommand(value);
    } catch {
      denied = true;
    }
    equal(denied, true);
  }
});
async function config(): Promise<AppleConfig> {
  const keys = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const bytes = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", keys.privateKey),
  );
  return {
    keyId: "test",
    issuerId: "issuer",
    appId: "app",
    groupId: "group",
    privateKey: `-----BEGIN PRIVATE KEY-----\n${
      btoa(String.fromCharCode(...bytes))
    }\n-----END PRIVATE KEY-----`,
  };
}
Deno.test("JWT uses a short lifetime and a valid ES256 signature", async () => {
  const c = await config();
  const token = await appleToken(c);
  const [header, body, signature] = token.split(".");
  const decode = (s: string) =>
    Uint8Array.from(
      atob(s.replace(/-/g, "+").replace(/_/g, "/")),
      (c) => c.charCodeAt(0),
    );
  equal(JSON.parse(new TextDecoder().decode(decode(header))).alg, "ES256");
  const payload = JSON.parse(new TextDecoder().decode(decode(body)));
  equal(payload.exp - payload.iat, 330);
  equal(payload.aud, "appstoreconnect-v1");
  equal(decode(signature).length, 64);
  const bytes = Uint8Array.from(
    atob(c.privateKey.replace(/-----[^-]+-----/g, "").replace(/\s/g, "")),
    (c) => c.charCodeAt(0),
  );
  const imported = await crypto.subtle.importKey(
    "pkcs8",
    bytes,
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign"],
  );
  const jwk = await crypto.subtle.exportKey("jwk", imported);
  delete jwk.d;
  jwk.key_ops = ["verify"];
  const publicKey = await crypto.subtle.importKey(
    "jwk",
    jwk,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  equal(
    await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      publicKey,
      decode(signature),
      new TextEncoder().encode(`${header}.${body}`),
    ),
    true,
  );
});
Deno.test("connection fails closed for internal groups and wrong apps", async () => {
  for (
    const attributes of [{ isInternalGroup: true }, { isInternalGroup: false }]
  ) {
    let calls = 0;
    const client = new AppleClient(await config(), async () => {
      calls++;
      return Response.json({
        data: {
          id: "group",
          attributes,
          relationships: { app: { data: { id: "other-app" } } },
        },
      });
    });
    await rejects(() => client.connection());
    equal(calls, 1);
  }
});
Deno.test("lookup checks exact email and refuses incomplete pagination", async () => {
  const client = new AppleClient(
    await config(),
    async () => Response.json({ data: [tester("INVITED")] }),
  );
  equal(await client.find("different@example.invalid"), null);
  const paged = new AppleClient(
    await config(),
    async () =>
      Response.json({ data: [], links: { next: "https://example.invalid" } }),
  );
  await rejects(() => paged.find(claim.email));
});
Deno.test("connection requires an unexpired build in external testing", async () => {
  for (const expired of [false, true]) {
    let calls = 0;
    const c = await config();
    const client = new AppleClient(c, async () => {
      calls++;
      return Response.json(
        calls === 1
          ? {
            data: {
              id: "group",
              attributes: { isInternalGroup: false, name: "External" },
              relationships: { app: { data: { id: c.appId } } },
            },
          }
          : calls === 2
          ? {
            data: [{
              id: "build",
              attributes: {
                version: "33",
                expired,
                expirationDate: "2099-01-01T00:00:00Z",
              },
            }],
          }
          : {
            data: {
              id: "detail",
              attributes: { externalBuildState: "IN_BETA_TESTING" },
            },
          },
      );
    });
    if (expired) await rejects(() => client.connection());
    else equal((await client.connection()).ready, true);
  }
});
Deno.test("Apple create and invitation requests use the configured group and app", async () => {
  const c = await config();
  const calls: Array<{ url: string; body: unknown }> = [];
  const client = new AppleClient(c, async (url, init) => {
    calls.push({
      url: String(url),
      body: JSON.parse(String((init as { body?: string })?.body)),
    });
    return Response.json({ data: tester("INVITED") }, { status: 201 });
  });
  await client.create(claim.email);
  await client.invite("tester");
  deepEqual(calls[0].body, {
    data: {
      type: "betaTesters",
      attributes: { email: claim.email },
      relationships: {
        betaGroups: { data: [{ type: "betaGroups", id: c.groupId }] },
      },
    },
  });
  deepEqual(calls[1].body, {
    data: {
      type: "betaTesterInvitations",
      relationships: {
        app: { data: { type: "apps", id: c.appId } },
        betaTester: { data: { type: "betaTesters", id: "tester" } },
      },
    },
  });
});
