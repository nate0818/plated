// POST /invite — tell somebody already on Plated that a seat is waiting.
//
// Body: { api_token, invitee_phone_e164, host_name, share_url }
// Returns: { ok } — always, whether or not the number belongs to anybody.
//
// The message with the link has already gone through Messages. This is the
// banner on the invitee's own phone saying who it is from, for the person
// who has the app and would otherwise find the text an hour later. The
// caller never learns whether the number matched: the answer is the
// directory's, the response is the same either way, and both lookups run
// on every call so the time taken says nothing either.
//
// The share URL is a bearer credential for a seat, so it is stored only for
// a number that belongs to somebody (that is what the push needs), never
// logged, and only ever handed back to that person's own phones, inside a
// link the app confirms before accepting.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { send } from "./apns.ts";

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// A host can save a seat for many people, but not for a phone book: twenty
// a day is a household plus some slack. An invitee hears about a given
// host at most twice a day, so a resend is a resend and not a siren.
const HOST_PER_DAY = 20;
const PAIR_PER_DAY = 2;

let saltCache: string | null = null;
async function pepper(): Promise<string> {
  if (saltCache) return saltCache;
  const { data } = await db.from("server_config").select("value").eq("key", "phone_salt").single();
  // Never cache a miss. An empty pepper would hash unpeppered for the
  // life of the isolate, and those hashes would match nothing in the table.
  if (!data?.value) throw new Error("no pepper");
  saltCache = data.value;
  return saltCache;
}

async function phoneHash(e164: string): Promise<string> {
  const bytes = new TextEncoder().encode((await pepper()) + e164);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function isShareURL(raw: string): boolean {
  try {
    const url = new URL(raw);
    return url.protocol === "https:" &&
      (url.hostname === "www.icloud.com" || url.hostname === "icloud.com" ||
        url.hostname === "plated.food" || url.hostname === "www.plated.food");
  } catch {
    return false;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("method", { status: 405 });
  const body = await req.json().catch(() => null);
  const apiToken = String(body?.api_token ?? "");
  const phone = String(body?.invitee_phone_e164 ?? "");
  const shareURL = String(body?.share_url ?? "");
  const typedHost = String(body?.host_name ?? "").slice(0, 80);
  if (!/^[0-9a-f-]{36}$/.test(apiToken) || !/^\+\d{7,15}$/.test(phone) || !isShareURL(shareURL)) {
    return new Response("missing", { status: 400 });
  }

  const { data: host } = await db
    .from("directory_users").select("id, display_name").eq("api_token", apiToken).maybeSingle();
  if (!host) return new Response("unregistered", { status: 403 });

  const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  const { count: today } = await db
    .from("invites").select("id", { count: "exact", head: true })
    .eq("inviter_id", host.id).gte("created_at", since);
  if ((today ?? 0) >= HOST_PER_DAY) return Response.json({ ok: true });

  let hash: string;
  try {
    hash = await phoneHash(phone);
  } catch {
    return new Response("unavailable", { status: 503 });
  }

  // Both lookups, every time, before any early return below: the shape of
  // the work must not depend on whether the number is known.
  const [{ data: invitee }, { count: pairToday }] = await Promise.all([
    db.from("directory_users").select("id").eq("phone_hash", hash).maybeSingle(),
    db.from("invites").select("id", { count: "exact", head: true })
      .eq("inviter_id", host.id).eq("invitee_phone_hash", hash).gte("created_at", since),
  ]);

  const known = Boolean(invitee) && invitee!.id !== host.id;
  await db.from("invites").insert({
    inviter_id: host.id,
    invitee_phone_hash: hash,
    host_name: typedHost,
    // The credential is kept only where the push needs it.
    share_url: known ? shareURL : "",
    status: known ? "pushed" : "sent",
  });
  if (!known || (pairToday ?? 0) >= PAIR_PER_DAY) return Response.json({ ok: true });

  const { data: devices } = await db
    .from("device_tokens").select("apns_token, sandbox").eq("user_id", invitee!.id);
  if (!devices?.length) return Response.json({ ok: true });

  // The name the directory holds beats the one the app typed: the push is
  // signed by the server, so the server says who it is from.
  const who = (host.display_name || typedHost || "Someone").trim();
  const link = `plated://invite?s=${encodeURIComponent(shareURL)}&from=${encodeURIComponent(who)}`;
  const delivery = await send(devices, {
    title: `${who} saved you a seat`,
    body: "Open it to see what they're cooking.",
    link,
    thread: "seat",
  });
  if (delivery.dead.length) {
    await db.from("device_tokens").delete().eq("user_id", invitee!.id).in("apns_token", delivery.dead);
  }
  return Response.json({ ok: true });
});
