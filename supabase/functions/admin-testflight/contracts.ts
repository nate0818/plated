export const FILTERS = ["active", "all", "invited", "archived"] as const;
export type RequestFilter = typeof FILTERS[number];
export type TestFlightCommand =
  | { op: "list"; filter: RequestFilter; offset: number }
  | { op: "connection" }
  | { op: "invite" | "sync" | "archive" | "restore"; id: string };
export function parseCommand(input: unknown): TestFlightCommand {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new Error("Send a request action.");
  }
  const r = input as Record<string, unknown>;
  if (r.op === "connection") return { op: "connection" };
  if (r.op === "list") {
    const filter = r.filter ?? "active";
    const offset = r.offset ?? 0;
    if (
      !FILTERS.includes(filter as RequestFilter) ||
      !Number.isSafeInteger(offset) || Number(offset) < 0 ||
      Number(offset) > 10_000_000
    ) throw new Error("Invalid request page.");
    return {
      op: "list",
      filter: filter as RequestFilter,
      offset: Number(offset),
    };
  }
  if (
    !["invite", "sync", "archive", "restore"].includes(String(r.op)) ||
    typeof r.id !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(r.id)
  ) throw new Error("Choose a valid access request.");
  return { op: r.op as "invite" | "sync" | "archive" | "restore", id: r.id };
}
export function assertFounder(role: string): void {
  if (role !== "founder") {
    throw new Error("Only the founder can manage access requests.");
  }
}
export function stateStatus(
  state: string | undefined,
): "invited" | "accepted" | "installed" | "revoked" | null {
  return state === "INVITED"
    ? "invited"
    : state === "ACCEPTED"
    ? "accepted"
    : state === "INSTALLED"
    ? "installed"
    : state === "REVOKED"
    ? "revoked"
    : null;
}
