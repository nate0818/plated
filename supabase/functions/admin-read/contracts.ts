const OPS = new Set([
  "overview", "people", "waitlist", "operations", "audit", "announcements", "releases",
]);

export type AdminReadOp =
  | "overview" | "people" | "waitlist" | "operations" | "audit"
  | "announcements" | "releases";

export interface AdminReadCommand {
  op: AdminReadOp;
  cursor: string | null;
  limit: number;
}

export function parseAdminReadCommand(value: unknown): AdminReadCommand {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("The read command is invalid.");
  const input = value as Record<string, unknown>;
  if (typeof input.op !== "string" || !OPS.has(input.op)) throw new Error("The read operation is invalid.");
  const cursor = input.cursor === undefined || input.cursor === null ? null : String(input.cursor);
  if (cursor && (cursor.length > 100 || !/^[A-Za-z0-9+/=]+$/.test(cursor))) {
    throw new Error("The page cursor is invalid.");
  }
  const requested = input.limit === undefined ? 50 : Number(input.limit);
  if (!Number.isInteger(requested) || requested < 1 || requested > 100) throw new Error("The page size is invalid.");
  return { op: input.op as AdminReadOp, cursor, limit: requested };
}

export function encodeOffset(offset: number): string {
  return btoa(String(Math.max(0, Math.floor(offset))));
}

export function decodeOffset(cursor: string | null): number {
  if (!cursor) return 0;
  try {
    const value = Number(atob(cursor));
    if (!Number.isSafeInteger(value) || value < 0 || value > 10_000_000) throw new Error();
    return value;
  } catch {
    throw new Error("The page cursor is invalid.");
  }
}

export function maskEmail(raw: unknown): string {
  const email = typeof raw === "string" ? raw.trim().toLowerCase() : "";
  const at = email.lastIndexOf("@");
  if (at < 1) return "hidden";
  const local = email.slice(0, at);
  const domain = email.slice(at + 1);
  const dot = domain.lastIndexOf(".");
  const domainName = dot > 0 ? domain.slice(0, dot) : domain;
  const suffix = dot > 0 ? domain.slice(dot) : "";
  return `${local[0]}${"•".repeat(Math.min(3, Math.max(1, local.length - 1)))}@${domainName[0] ?? "•"}••${suffix}`;
}
