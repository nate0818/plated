import type { Push } from "../_shared/apns.ts";
import type { VerifiedEvent, VerifiedNotice } from "./cloudkit.ts";
export interface Preferences {
  enabled: boolean; authorized: boolean; timeZone: string;
  categories: Record<string, boolean>; muted: string[]; blocked: string[];
}
export function preferences(value: unknown): Preferences {
  const v = value as Partial<Preferences> | null;
  const list = (x: unknown) => Array.isArray(x) ? x.filter((s): s is string => typeof s === "string" && s.length <= 255).slice(0, 1000) : [];
  const zone = typeof v?.timeZone === "string" ? v.timeZone : "UTC";
  try { new Intl.DateTimeFormat("en", {timeZone: zone}).format(); } catch { throw new Error("invalid_time_zone"); }
  return { enabled: v?.enabled === true, authorized: v?.authorized === true, timeZone: zone,
    categories: Object.fromEntries(["dishes", "comments", "replies", "plates", "seats"].map(k => [k, v?.categories?.[k] !== false])),
    muted: list(v?.muted), blocked: list(v?.blocked) };
}
export function pushFor(event: VerifiedEvent, notice: VerifiedNotice, prefs: Preferences, now = new Date()): Push | null {
  if (event.cancelled || notice.recipient === event.actor || !event.members.includes(notice.recipient)
    || !prefs.enabled || !prefs.authorized || prefs.categories[notice.category] === false
    || prefs.blocked.includes(event.actor) || (notice.category !== "replies" && prefs.muted.includes(notice.post))) return null;
  const hour = Number(new Intl.DateTimeFormat("en", {timeZone: prefs.timeZone, hour: "2-digit", hourCycle: "h23"}).format(now));
  const passive = notice.category === "plates" || (!notice.direct && (hour < 8 || hour >= 22));
  const link = notice.post ? `plated://post?id=${encodeURIComponent(notice.post)}`
    : notice.kind === "householdSeat" ? "plated://home" : "plated://table";
  return {
    title: notice.title, body: notice.body, link, thread: notice.post || (notice.kind === "householdSeat" ? "household" : "table"),
    contentAvailable: true,
    sound: !passive && (notice.direct || notice.category === "seats"), level: passive ? "passive" : "active", priority: 10,
    category: notice.kind === "dish" ? "plated.category.dish" : notice.kind === "ask" ? "plated.category.ask" : notice.kind === "comment" ? "plated.category.comment" : notice.kind === "householdSeat" ? "plated.category.household.seat" : "plated.category.plates",
    expiresAt: Math.floor((event.occurredAt + 86400000) / 1000),
    extra: {post: notice.post, kind: notice.kind, actor: event.actorName, actorID: event.actor, source: "social-v1", noticeKey: notice.key, comment: notice.kind === "comment" ? notice.key.replace(/^note:/, "") : ""},
  };
}
export function retryDelay(attempt: number): number {
  return Math.min(1800, 15 * 2 ** Math.max(0, Math.min(10, attempt - 1)));
}
export async function digest(value: string): Promise<string> {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)))].map(b => b.toString(16).padStart(2,"0")).join("");
}
