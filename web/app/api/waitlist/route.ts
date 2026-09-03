import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

export const runtime = "nodejs";

// Deliberately loose: the only address that matters is one a person can
// receive mail at, and the strict grammar rejects real ones. Shape plus a
// length cap is enough to keep garbage out of the table.
const looksLikeEmail = (s: string) => s.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s);

export async function POST(req: Request) {
  let email = "";
  try {
    const body = (await req.json()) as { email?: unknown };
    email = typeof body.email === "string" ? body.email.trim() : "";
  } catch {
    return NextResponse.json({ error: "That didn't look like an email address." }, { status: 400 });
  }

  if (!looksLikeEmail(email)) {
    return NextResponse.json({ error: "That didn't look like an email address." }, { status: 400 });
  }

  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

  // Honesty over optimism: if the site cannot store the address, it says so
  // rather than showing a confirmation for a write that never happened.
  if (!url || !key) {
    console.error("waitlist: SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is not set");
    return NextResponse.json({ error: "The waitlist isn't open yet. Try again later." }, { status: 503 });
  }

  const supabase = createClient(url, key, { auth: { persistSession: false } });
  const { error } = await supabase.from("waitlist").insert({ email, source: "plated.food" });

  // 23505 is the unique index on lower(email): the address is already kept,
  // which is exactly what the person asked for. Same answer as a fresh save.
  if (error && error.code !== "23505") {
    console.error("waitlist insert failed:", error.code, error.message);
    return NextResponse.json({ error: "That didn't save. Try again." }, { status: 502 });
  }

  return NextResponse.json({ ok: true });
}
