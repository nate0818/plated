// POST /invite — tell somebody already on Plated that a seat is waiting.
//
// Body: { api_token, invitee_phone_e164, host_name, share_url, kind?, seat? }
// Returns: { ok } — always, whether or not the number belongs to anybody.
//
// `kind` is "table" (a seat at the host's Table, the default so an older
// build that never sends it keeps working) or "household" (a place in the
// host's household: the plan, the grocery list and the cookbook). The two
// are different rooms and the banner has to say which; the app opens a
// different sheet for each. `seat` is the household seat record name the
// link was minted for, carried through so the joiner does not have to pick
// their seat by hand. docs/household.md sections 6 and 7.
//
// The message with the link has already gone through Messages. This is the
// banner on the invitee's own phone saying who it is from, for the person
// who has the app and would otherwise find the text an hour later. The
// caller never learns whether the number matched: the answer is the
// directory's, the response is the same either way, and both lookups run
// on every call so the time taken says nothing either.
//
// The share URL is a bearer credential for a seat, so it is never stored and
// never logged: it goes from the request straight into the push, to that
// person's own phones, inside a link the app confirms before accepting. The
// same goes for the seat name, which means nothing without the share it
// belongs to. What the row keeps is the record that an invitation happened,
// which is what the daily limits count and what the privacy policy describes.
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

type Kind = "table" | "household";

// A CloudKit record name: "seat-<UUID>". Anything else is not a seat and
// is dropped rather than forwarded into a link the app will open.
const RECORD_NAME = /^[A-Za-z0-9_-]{1,80}$/;

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
  const kind: Kind = body?.kind === "household" ? "household" : "table";
  const rawSeat = String(body?.seat ?? "");
  // A malformed seat costs the joiner a seat picker, not the whole notice,
  // so it is dropped with a log line rather than refused.
  const seat = RECORD_NAME.test(rawSeat) ? rawSeat : "";
  if (rawSeat && !seat) console.log("invite: seat dropped, not a record name");
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
  // The insert's error is checked, and the check is load-bearing rather
  // than tidy. This row IS the rate limit: both counts above are queries
  // over this table, so an insert that fails silently does not lose a
  // record, it turns twenty-per-host and two-per-pair off with nothing on
  // any screen or in any log to say so. The way in is a migration applied
  // before this function is redeployed, dropping a column the live version
  // is still writing; see the banner in the 20260907 migration.
  const { error: recorded } = await db.from("invites").insert({
    inviter_id: host.id,
    invitee_phone_hash: hash,
    host_name: typedHost,
    kind,
    status: known ? "pushed" : "sent",
  });
  if (recorded) {
    // Refusing to send is the honest answer: a push nobody counted is a
    // push outside the limits that exist to stop this being a way to
    // message a stranger repeatedly.
    console.error("invite: the row would not record, so nothing was sent", recorded);
    return new Response("unavailable", { status: 503 });
  }
  if (!known || (pairToday ?? 0) >= PAIR_PER_DAY) return Response.json({ ok: true });

  const { data: devices } = await db
    .from("device_tokens").select("apns_token, sandbox").eq("user_id", invitee!.id);
  if (!devices?.length) return Response.json({ ok: true });

  // The name the directory holds beats the one the app typed: the push is
  // signed by the server, so the server says who it is from.
  const who = (host.display_name || typedHost || "Someone").trim();
  let link = `plated://invite?s=${encodeURIComponent(shareURL)}&from=${encodeURIComponent(who)}&k=${kind}`;
  if (kind === "household" && seat) link += `&seat=${encodeURIComponent(seat)}`;
  // Two rooms, two sentences. The household one says what it is and not what
  // is in it, because a banner has one line and "Open it to join" is the
  // true outcome of the tap: the app asks before it seats anybody.
  const push = kind === "household"
    ? { title: `${who} invited you to their household`, body: "Open it to join.", thread: "household" }
    : { title: `${who} kept you a seat at their table`, body: "Open it to see what they're cooking.", thread: "seat" };
  const delivery = await send(devices, { ...push, link });
  if (delivery.dead.length) {
    await db.from("device_tokens").delete().eq("user_id", invitee!.id).in("apns_token", delivery.dead);
  }
  return Response.json({ ok: true });
});
