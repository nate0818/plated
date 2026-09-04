// One APNs sender for every function that needs to reach a phone.
//
// Auth is a provider token: an ES256 JWT signed with the .p8 key from the
// Apple Developer portal, good for an hour, cached for fifty minutes. The
// three secrets have to be set on the project before this does anything:
//
//   supabase secrets set APNS_TEAM_ID=… APNS_KEY_ID=… APNS_KEY_P8="$(cat AuthKey.p8)"
//
// and until they are, `send` returns { configured: false } and the caller
// carries on. A missing push is a missing nicety; it is never an error a
// person should see.
import { importPKCS8, SignJWT } from "https://deno.land/x/jose@v5.9.6/index.ts";

const TOPIC = "com.natemeadows.plated";
const SANDBOX = "https://api.sandbox.push.apple.com";
const PRODUCTION = "https://api.push.apple.com";

let cached: { token: string; at: number } | null = null;

async function providerToken(): Promise<string | null> {
  const teamID = Deno.env.get("APNS_TEAM_ID");
  const keyID = Deno.env.get("APNS_KEY_ID");
  const p8 = Deno.env.get("APNS_KEY_P8");
  if (!teamID || !keyID || !p8) return null;
  if (cached && Date.now() - cached.at < 50 * 60 * 1000) return cached.token;
  const key = await importPKCS8(p8.replace(/\\n/g, "\n"), "ES256");
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyID })
    .setIssuer(teamID)
    .setIssuedAt()
    .sign(key);
  cached = { token, at: Date.now() };
  return token;
}

export interface Push {
  title: string;
  body: string;
  /// A plated:// link the app opens on tap.
  link: string;
  /// Groups on the lock screen.
  thread?: string;
  sound?: boolean;
}

export interface Delivery {
  configured: boolean;
  sent: number;
  /// Tokens APNs said are dead for this app. The caller deletes them.
  dead: string[];
  /// Deliveries APNs asked us to try again later. Not dead, not sent.
  retry: number;
}

// Reasons APNs gives for a token that will never work again. Everything
// else (rate limits, server trouble, a bad provider token) is our problem
// or Apple's, never the phone's, and must not cost anybody their token.
const DEAD = new Set(["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"]);

export async function send(
  devices: { apns_token: string; sandbox: boolean }[],
  push: Push,
): Promise<Delivery> {
  const token = await providerToken();
  if (!token) return { configured: false, sent: 0, dead: [], retry: 0 };

  const payload = JSON.stringify({
    aps: {
      alert: { title: push.title, body: push.body },
      sound: push.sound === false ? undefined : "default",
      "thread-id": push.thread ?? "table",
    },
    link: push.link,
  });

  let sent = 0;
  let retry = 0;
  const dead: string[] = [];
  for (const device of devices) {
    const host = device.sandbox ? SANDBOX : PRODUCTION;
    let res: Response;
    try {
      res = await fetch(`${host}/3/device/${device.apns_token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${token}`,
          "apns-topic": TOPIC,
          "apns-push-type": "alert",
          "apns-priority": "10",
        },
        body: payload,
      });
    } catch (error) {
      console.log(`apns unreachable: ${error}`);
      retry += 1;
      continue;
    }
    if (res.ok) {
      sent += 1;
      continue;
    }
    const reason = (await res.json().catch(() => ({})))?.reason ?? String(res.status);
    console.log(`apns ${res.status} ${reason}`);
    if (DEAD.has(reason)) {
      dead.push(device.apns_token);
    } else if (reason === "ExpiredProviderToken" || reason === "InvalidProviderToken" || res.status === 403) {
      // The cached JWT is the problem, not the phone. Forget it so the
      // next call mints a fresh one instead of failing for fifty minutes.
      cached = null;
      retry += 1;
    } else {
      retry += 1;
    }
  }
  return { configured: true, sent, dead, retry };
}
