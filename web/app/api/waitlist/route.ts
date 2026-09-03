import { NextResponse } from "next/server";

export const runtime = "nodejs";

// The write happens inside a Supabase edge function, which holds the service
// role key on Supabase's side. Nothing secret lives in Vercel: the website
// only carries the publishable key, the same one that ships in the app and
// can read nothing on its own.
const FUNCTION_URL = "https://dyvrksooelbkzkprqlhk.supabase.co/functions/v1/waitlist";
const PUBLISHABLE_KEY = "sb_publishable_E8Jx1GJNYSDAAT-KDfvLqw_WjjGy9GL";

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

  // Honesty over optimism: if the address could not be stored, say so rather
  // than showing a confirmation for a write that never happened.
  try {
    const res = await fetch(FUNCTION_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: PUBLISHABLE_KEY,
        Authorization: `Bearer ${PUBLISHABLE_KEY}`,
      },
      body: JSON.stringify({ email, source: "plated.food" }),
    });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      console.error("waitlist function failed:", res.status, text.slice(0, 200));
      return NextResponse.json({ error: "That didn't save. Try again." }, { status: 502 });
    }
  } catch (err) {
    console.error("waitlist function unreachable:", err);
    return NextResponse.json({ error: "Couldn't reach the server. Try again." }, { status: 502 });
  }

  return NextResponse.json({ ok: true });
}
