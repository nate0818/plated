import type {
  AccessFilter,
  AccessRequestsDTO,
  AccessStatus,
  TestFlightRequest,
} from "./contracts";
const filters = ["active", "invited", "archived", "all"];
const statuses = [
  "new",
  "archived",
  "sending",
  "invited",
  "accepted",
  "installed",
  "failed",
  "uncertain",
  "revoked",
];
export function normalizeTestFlightRequest(
  r: Record<string, unknown>,
): TestFlightRequest {
  if (r.op === "connection") return { op: "connection" };
  if (r.op === "list") {
    if (
      !filters.includes(String(r.filter)) || !Number.isSafeInteger(r.offset) ||
      Number(r.offset) < 0 || Number(r.offset) > 10_000_000
    ) throw new Error("Invalid request page.");
    return {
      op: "list",
      filter: r.filter as AccessFilter,
      offset: Number(r.offset),
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
export function decodeAccessRequests(input: unknown): AccessRequestsDTO {
  if (!input || typeof input !== "object") {
    throw new Error("Access requests are unavailable.");
  }
  const r = input as AccessRequestsDTO;
  const text = (v: unknown) => typeof v === "string";
  const nullable = (v: unknown) => v === null || text(v);
  const count = (v: unknown) =>
    typeof v === "number" && Number.isSafeInteger(v) && v >= 0;
  if (
    !Array.isArray(r.rows) || r.rows.length > 50 || !count(r.totalCount) ||
    !r.counts || !Object.values(r.counts).every(count) || !r.connection ||
    typeof r.connection.ready !== "boolean" ||
    !nullable(r.connection.groupName) || !nullable(r.connection.build) ||
    !text(r.connection.message)
  ) throw new Error("Access requests are unavailable.");
  for (const row of r.rows) {
    if (
      !row || !text(row.id) || !text(row.email) || !text(row.requestedAt) ||
      !statuses.includes(row.status) ||
      ![row.appleState, row.invitedAt, row.checkedAt, row.errorCode].every(
        nullable,
      )
    ) throw new Error("Access requests are unavailable.");
  }
  return r;
}
export const accessStatusLabel: Record<AccessStatus, string> = {
  new: "New request",
  archived: "Archived",
  sending: "Checking",
  invited: "Invited",
  accepted: "Accepted",
  installed: "Installed",
  failed: "Try again",
  uncertain: "Needs checking",
  revoked: "Stopped testing",
};
