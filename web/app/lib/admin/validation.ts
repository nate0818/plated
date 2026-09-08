import type { AdminCommandRequest, AdminReadRequest, AnnouncementAudience, AppLink } from "./contracts";
import { ANNOUNCEMENT_AUDIENCES, APP_LINKS, READ_OPS } from "./contracts";

export class AdminValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AdminValidationError";
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function rejectUnknownKeys(value: Record<string, unknown>, allowed: readonly string[]) {
  const allowedKeys = new Set(allowed);
  if (Object.keys(value).some((key) => !allowedKeys.has(key))) {
    throw new AdminValidationError("The request contains fields this operation does not accept.");
  }
}

function optionalString(value: unknown, name: string, max: number): string | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== "string" || value.length === 0 || value.length > max) {
    throw new AdminValidationError(`${name} is invalid.`);
  }
  return value;
}

function requiredString(value: unknown, name: string, max: number): string {
  const result = optionalString(value, name, max)?.trim();
  if (!result) throw new AdminValidationError(`${name} is required.`);
  return result;
}

function optionalLimit(value: unknown): number | undefined {
  if (value === undefined) return undefined;
  if (!Number.isInteger(value) || Number(value) < 1 || Number(value) > 100) {
    throw new AdminValidationError("limit must be an integer from 1 through 100.");
  }
  return Number(value);
}

function requiredUuid(value: unknown, name: string): string {
  const id = requiredString(value, name, 64);
  if (!UUID.test(id)) throw new AdminValidationError(`${name} is invalid.`);
  return id.toLowerCase();
}

export function normalizeReadRequest(value: Record<string, unknown>): AdminReadRequest {
  const op = typeof value.op === "string" ? value.op : "";
  if (!(READ_OPS as readonly string[]).includes(op)) {
    throw new AdminValidationError("Unknown read operation.");
  }

  if (op === "overview" || op === "operations" || op === "releases") {
    rejectUnknownKeys(value, ["op"]);
    return { op };
  }

  if (op === "people" || op === "waitlist" || op === "audit" || op === "announcements") {
    rejectUnknownKeys(value, ["op", "cursor", "limit"]);
    const cursor = optionalString(value.cursor, "cursor", 100);
    if (cursor && !/^[A-Za-z0-9+/=]+$/.test(cursor)) {
      throw new AdminValidationError("cursor is invalid.");
    }
    const limit = optionalLimit(value.limit);
    return { op, ...(cursor ? { cursor } : {}), ...(limit ? { limit } : {}) };
  }

  throw new AdminValidationError("Unknown read operation.");
}

export function normalizeCommandRequest(value: Record<string, unknown>): AdminCommandRequest {
  const op = typeof value.op === "string" ? value.op : "";

  if (op === "preview") {
    rejectUnknownKeys(value, ["op", "title", "body", "link", "audience", "belowBuild", "replaces", "overrideCap"]);
    const title = requiredString(value.title, "title", 32);
    const body = requiredString(value.body, "body", 140);
    if (/[–—]/.test(`${title}${body}`)) {
      throw new AdminValidationError("Use a comma, colon, or full stop instead of a long dash.");
    }
    if (/^plated\b/i.test(title)) {
      throw new AdminValidationError("The title should describe the news rather than repeat the app name.");
    }
    const link = String(value.link ?? "");
    if (!(APP_LINKS as readonly string[]).includes(link)) {
      throw new AdminValidationError("link is invalid.");
    }
    const audience = String(value.audience ?? "");
    if (!(ANNOUNCEMENT_AUDIENCES as readonly string[]).includes(audience)) {
      throw new AdminValidationError("audience is invalid.");
    }
    const belowBuild = value.belowBuild;
    if (belowBuild !== null && (!Number.isInteger(belowBuild) || Number(belowBuild) < 1 || Number(belowBuild) > 1_000_000)) {
      throw new AdminValidationError("belowBuild must be a positive build number no greater than 1,000,000.");
    }
    if (link === "plated://update" && belowBuild === null) {
      throw new AdminValidationError("An update notice requires a build ceiling.");
    }
    const replaces = value.replaces === null ? null : requiredUuid(value.replaces, "replaces");
    if (typeof value.overrideCap !== "boolean") {
      throw new AdminValidationError("overrideCap must be true or false.");
    }
    return {
      op,
      title,
      body,
      link: link as AppLink,
      audience: audience as AnnouncementAudience,
      belowBuild: belowBuild === null ? null : Number(belowBuild),
      replaces,
      overrideCap: value.overrideCap,
    };
  }

  if (op === "send") {
    rejectUnknownKeys(value, ["op", "intentId", "typedTitle"]);
    return {
      op,
      intentId: requiredUuid(value.intentId, "intentId"),
      typedTitle: requiredString(value.typedTitle, "typedTitle", 32),
    };
  }

  if (op === "retry" || op === "retract") {
    rejectUnknownKeys(value, ["op", "announcementId"]);
    return { op, announcementId: requiredUuid(value.announcementId, "announcementId") };
  }

  throw new AdminValidationError("Unknown command operation.");
}
