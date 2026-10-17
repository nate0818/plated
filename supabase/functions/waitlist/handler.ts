import { EARLY_ACCESS_SOURCE } from "./contracts.ts";

type Store = {
  insert: (entry: { email: string; source: string }) => Promise<{ error: { code: string } | null }>;
  upgrade: (email: string) => Promise<{ error: unknown }>;
};

export async function handleRequest(req: Request, store: Store): Promise<Response> {
  if (req.method !== "POST") return new Response("method", { status: 405 });
  const body = await req.json().catch(() => null);
  const email = typeof body?.email === "string" ? body.email.trim().toLowerCase() : "";
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return new Response("bad email", { status: 400 });
  const source = body?.source === EARLY_ACCESS_SOURCE ? EARLY_ACCESS_SOURCE : "plated.food";
  const { error } = await store.insert({ email, source });
  if (error?.code === "23505" && source === EARLY_ACCESS_SOURCE) {
    const result = await store.upgrade(email);
    if (result.error) return new Response("request not saved", { status: 500 });
  } else if (error && error.code !== "23505") {
    console.error("waitlist insert failed:", error.code);
    return new Response("request not saved", { status: 500 });
  }
  return Response.json({ ok: true });
}
