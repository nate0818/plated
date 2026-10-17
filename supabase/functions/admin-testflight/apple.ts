export interface AppleConfig {
  keyId: string;
  issuerId: string;
  privateKey: string;
  appId: string;
  groupId: string;
}
export interface Resource {
  id: string;
  type: string;
  attributes?: Record<string, unknown>;
  relationships?: Record<
    string,
    { data?: { id: string } | Array<{ id: string }>; links?: { next?: string } }
  >;
}
interface AppleResponse {
  data: Resource | Resource[];
  included?: Resource[];
  links?: { next?: string };
}
export class AppleError extends Error {
  constructor(public status: number, public uncertain: boolean) {
    super(
      status === 401 || status === 403
        ? "Apple connection needs attention."
        : status === 429
        ? "Apple is busy. Try again shortly."
        : "Apple could not complete this action.",
    );
  }
}
function b64(bytes: Uint8Array) {
  return btoa(String.fromCharCode(...bytes)).replace(/=/g, "").replace(
    /\+/g,
    "-",
  ).replace(/\//g, "_");
}
export async function appleToken(config: AppleConfig): Promise<string> {
  const encode = (v: unknown) =>
    b64(new TextEncoder().encode(JSON.stringify(v)));
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${
    encode({ alg: "ES256", kid: config.keyId, typ: "JWT" })
  }.${
    encode({
      iss: config.issuerId,
      iat: now - 30,
      exp: now + 300,
      aud: "appstoreconnect-v1",
    })
  }`;
  const keyBytes = Uint8Array.from(
    atob(config.privateKey.replace(/-----[^-]+-----/g, "").replace(/\s/g, "")),
    (c) => c.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(unsigned),
  );
  return `${unsigned}.${b64(new Uint8Array(signature))}`;
}
export class AppleClient {
  private token: Promise<string> | null = null;
  constructor(
    readonly config: AppleConfig,
    private transport: typeof fetch = fetch,
  ) {}
  async call(
    method: "GET" | "POST",
    path: string,
    body?: unknown,
  ): Promise<AppleResponse> {
    // Only relative paths assembled here; Apple-provided links never become fetch targets.
    if (!path.startsWith("/") || path.startsWith("//")) {
      throw new Error("Invalid Apple path.");
    }
    let response: Response;
    try {
      response = await this.transport(
        `https://api.appstoreconnect.apple.com/v1${path}`,
        {
          method,
          headers: {
            Authorization:
              `Bearer ${await (this.token ??= appleToken(this.config))}`,
            "Content-Type": "application/json",
          },
          ...(body ? { body: JSON.stringify(body) } : {}),
          signal: AbortSignal.timeout(8_000),
          redirect: "error",
        },
      );
    } catch {
      throw new AppleError(0, method === "POST");
    }
    if (!response.ok) {
      await response.body?.cancel();
      throw new AppleError(
        response.status,
        method === "POST" && response.status >= 500,
      );
    }
    if (response.status === 204) return { data: [] };
    try {
      return await response.json();
    } catch {
      throw new AppleError(502, method === "POST");
    }
  }
  async connection() {
    const group = (await this.call(
      "GET",
      `/betaGroups/${this.config.groupId}?include=app&fields[apps]=name`,
    )).data as Resource;
    const app = group.relationships?.app?.data;
    if (
      group.attributes?.isInternalGroup !== false || !app ||
      Array.isArray(app) || app.id !== this.config.appId
    ) throw new Error("The configured group must be an external Plated group.");
    const result = await this.call(
      "GET",
      `/betaGroups/${this.config.groupId}/builds?fields[builds]=version,expired,expirationDate&limit=200`,
    );
    const builds = (result.data as Resource[]).filter((b) =>
      b.attributes?.expired === false &&
      Date.parse(String(b.attributes.expirationDate)) > Date.now()
    ).sort((a, b) =>
      String(b.attributes?.version).localeCompare(
        String(a.attributes?.version),
        undefined,
        { numeric: true },
      )
    );
    // Fail closed if Apple ever paginates beyond our bounded read.
    if (result.links?.next) {
      throw new Error("Review the testing group in App Store Connect.");
    }
    for (const build of builds.slice(0, 3)) {
      const detail =
        (await this.call("GET", `/builds/${build.id}/buildBetaDetail`))
          .data as Resource;
      if (detail.attributes?.externalBuildState === "IN_BETA_TESTING") {
        return {
          ready: true,
          groupName: String(group.attributes?.name),
          build: String(build.attributes?.version),
          message: "Apple sends the invitation email.",
        };
      }
    }
    throw new Error(
      "This group needs an active build approved for external testing.",
    );
  }
  async find(email: string, groupOnly = false): Promise<Resource | null> {
    const params = new URLSearchParams({
      "filter[email]": email,
      ...(groupOnly ? { "filter[betaGroups]": this.config.groupId } : {}),
      "fields[betaTesters]": "email,state",
      "limit": "200",
    });
    const result = await this.call("GET", `/betaTesters?${params}`);
    if (result.links?.next) {
      throw new Error("Apple tester lookup needs review.");
    }
    // Do not trust partial/case-insensitive API filters for address matching.
    return (result.data as Resource[]).find((t) =>
      String(t.attributes?.email).toLowerCase() === email.toLowerCase()
    ) ?? null;
  }
  async create(email: string): Promise<Resource> {
    return (await this.call("POST", "/betaTesters", {
      data: {
        type: "betaTesters",
        attributes: { email },
        relationships: {
          betaGroups: {
            data: [{ type: "betaGroups", id: this.config.groupId }],
          },
        },
      },
    })).data as Resource;
  }
  async add(testerId: string) {
    await this.call(
      "POST",
      `/betaGroups/${this.config.groupId}/relationships/betaTesters`,
      { data: [{ type: "betaTesters", id: testerId }] },
    );
  }
  async invite(testerId: string) {
    await this.call("POST", "/betaTesterInvitations", {
      data: {
        type: "betaTesterInvitations",
        relationships: {
          app: { data: { type: "apps", id: this.config.appId } },
          betaTester: { data: { type: "betaTesters", id: testerId } },
        },
      },
    });
  }
}
export function appleConfig(): AppleConfig | null {
  const get = (n: string) => Deno.env.get(n)?.trim() ?? "";
  let privateKey: string;
  try {
    privateKey = get("ASC_PRIVATE_KEY_B64")
      ? atob(get("ASC_PRIVATE_KEY_B64"))
      : "";
  } catch {
    return null;
  }
  const config = {
    keyId: get("ASC_KEY_ID"),
    issuerId: get("ASC_ISSUER_ID"),
    privateKey,
    appId: get("ASC_APP_ID"),
    groupId: get("ASC_BETA_GROUP_ID"),
  };
  return Object.values(config).every(Boolean) ? config : null;
}
