// Native CKFetchWebAuthTokenOperation proves the iCloud identity. Never persist
// or log its bearer token; rotate it after EVERY successful Apple round-trip.
export type Environment = "development" | "production";
export interface CKRecord {
  recordName: string; recordType: string;
  fields?: Record<string, { value: unknown }>;
  created?: { userRecordName?: string; timestamp?: number };
  modified?: { userRecordName?: string; timestamp?: number };
  parent?: { recordName: string }; share?: { recordName: string };
  owner?: Participant; participants?: Participant[];
  deleted?: boolean; serverErrorCode?: string;
}
export interface Participant {
  userIdentity?: { userRecordName?: string };
  type?: string; acceptanceStatus?: string; permission?: string;
}
export class Rejected extends Error {
  constructor(public status: number, public code: string) { super(code); }
}
export const field = (r: CKRecord, key: string): unknown => r.fields?.[key]?.value;
export const string = (r: CKRecord, key: string): string => {
  const v = field(r, key); return typeof v === "string" ? v : "";
};
export const strings = (r: CKRecord, key: string): string[] => {
  const v = field(r, key); return Array.isArray(v) ? v.filter(x => typeof x === "string") : [];
};
export function identifier(value: unknown): string {
  if (typeof value !== "string" || !value.length || value.length > 255 || /[\x00-\x1f\x7f/]/.test(value)) {
    throw new Rejected(400, "invalid_identifier");
  }
  return value;
}
export class CloudKit {
  private token: string;
  constructor(private apiToken: string, token: string, readonly environment: Environment,
    private fetcher: typeof fetch = fetch) {
    if (typeof token !== "string" || token.length < 16 || token.length > 16384) throw new Rejected(401, "cloud_auth_required");
    this.token = token;
  }
  private async call(scope: "public" | "private" | "shared", path: string, body?: unknown): Promise<Record<string, unknown>> {
    const url = new URL(`https://api.apple-cloudkit.com/database/1/iCloud.com.natemeadows.plated/${this.environment}/${scope}/${path}`);
    url.searchParams.set("ckAPIToken", this.apiToken);
    url.searchParams.set("ckWebAuthToken", this.token);
    let response: Response;
    try {
      response = await this.fetcher(url, {
        method: body ? "POST" : "GET", redirect: "error",
        headers: { "Content-Type": "application/json", Origin: "https://dyvrksooelbkzkprqlhk.supabase.co" },
        body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(10000),
      });
    } catch { throw new Rejected(503, "cloud_unavailable"); }
    const data = await response.json().catch(() => ({}));
    if (!response.ok || data.serverErrorCode) {
      const terminal = ["ACCESS_DENIED", "NOT_FOUND", "UNKNOWN_ITEM"].includes(data.serverErrorCode);
      throw new Rejected(terminal ? 403 : 503, terminal ? "cloud_access_denied" : "cloud_retry");
    }
    // Apple's refreshed token is mandatory before another request. Some
    // record responses omit it: don't silently replay an expired token.
    this.token = typeof data.ckWebAuthToken === "string" ? data.ckWebAuthToken : "";
    return data;
  }
  async identity(): Promise<string> {
    // Apple exposes the current authenticated identity at public/users/caller.
    // The prior private/users/current route is not the documented caller
    // identity endpoint, so registration could not verify the user there.
    const data = await this.call("public", "users/caller");
    const users = data.users;
    if (!Array.isArray(users) || users.length !== 1 || !users[0] || typeof users[0] !== "object") {
      throw new Rejected(403, "cloud_identity_unavailable");
    }
    return identifier((users[0] as Record<string, unknown>).userRecordName);
  }
  async record(name: string, zone: string, owner: string, me: string): Promise<CKRecord> {
    if (!this.token) throw new Rejected(503, "cloud_token_refresh_required");
    const data = await this.call(owner === me ? "private" : "shared", "records/lookup", {
      zoneID: { zoneName: zone, ...(owner === me ? {} : { ownerRecordName: owner }) },
      records: [{ recordName: identifier(name) }],
      desiredKeys: ["authorID", "authorName", "text", "dishTitle", "kind", "postRecordName", "parentCommentID",
        "deletedAt", "active", "choice", "userRecordName", "seat", "joinedAt", "removedIDs", "name", "inviteID"],
    });
    const record = (data.records as CKRecord[] | undefined)?.find(r => r.recordName === name);
    if (!record || record.serverErrorCode || record.deleted) throw new Rejected(409, "record_unavailable");
    return record;
  }
}
export interface VerifiedNotice {
  key: string; recipient: string; kind: "comment" | "plates" | "votes" | "commentLikes" | "seat" | "householdSeat";
  category: "replies" | "comments" | "plates" | "seats";
  post: string; title: string; body: string; direct: boolean;
}
export interface VerifiedEvent {
  key: string; actor: string; actorName: string; room: string; members: string[];
  notices: VerifiedNotice[]; occurredAt: number; cancelled: boolean;
}
export async function verifyRoom(cloud: Pick<CloudKit, "record" | "environment">, me: string, owner: string, zone: string, grantSeat?: string) {
  if (!["PlatedTable", "PlatedHousehold"].includes(zone)) throw new Rejected(400, "invalid_zone");
  owner = owner || me;
  identifier(owner);
  const household = zone === "PlatedHousehold";
  const rootName = household ? "household-root" : "table-root";
  const root = await cloud.record(rootName, zone, owner, me);
  if (root.recordType !== (household ? "PlatedHousehold" : "Table")) throw new Rejected(403, "invalid_root");
  if (!root.share?.recordName) throw new Rejected(409, "share_unavailable");
  const share = await cloud.record(root.share.recordName, zone, owner, me);
  const shareOwner = share.owner?.userIdentity?.userRecordName;
  if (!["cloudKit.share", "cloudkit.share"].includes(share.recordType) || (shareOwner !== owner && !(owner === me && shareOwner === "__defaultOwner__"))) {
    throw new Rejected(403, "invalid_share");
  }
  const removed = new Set(strings(root, "removedIDs").filter(id => !id.startsWith("plated-reinvite-")));
  if (household && grantSeat && removed.has(me)) {
    const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(grantSeat)));
    const hash = [...bytes].map(b=>b.toString(16).padStart(2,"0")).join("");
    if (strings(root,"removedIDs").includes(`plated-reinvite-v1:${btoa(me)}:${hash}`)) removed.delete(me);
  }
  const members = new Set([owner, ...(share.participants ?? []).filter(p =>
    p.acceptanceStatus === "ACCEPTED" && ["READ_ONLY", "READ_WRITE"].includes(p.permission ?? "")
  ).map(p => p.userIdentity?.userRecordName ?? "")].filter(id => id && !removed.has(id)));
  if (!members.has(me)) throw new Rejected(403, "not_a_member");
  return {owner,household,rootName,share,members,room:`${cloud.environment}|${owner}|${zone}|${share.recordName}`};
}
export async function verifyEvent(
  cloud: Pick<CloudKit, "record" | "environment">, me: string, owner: string,
  zone: string, name: string, actorName: string, now = Date.now(),
): Promise<VerifiedEvent> {
  const {owner: verifiedOwner, household, rootName, share, members} = await verifyRoom(cloud,me,owner,zone,zone === "PlatedHousehold" ? name : undefined);
  owner = verifiedOwner;
  const record = await cloud.record(name, zone, owner, me);
  if (record.parent?.recordName !== rootName || ![me,"__defaultOwner__"].includes(record.modified?.userRecordName ?? "")) throw new Rejected(403, "not_your_event");
  const age = now - (record.modified?.timestamp ?? 0);
  if (age < -300000 || age > 86400000) throw new Rejected(410, "event_expired");
  const event: VerifiedEvent = {
    key: `${cloud.environment}|${owner}|${zone}|${share.recordName}|${name}`,
    actor: me, actorName: (string(record,"authorName") || actorName).replace(/[\x00-\x1f\x7f]/g, "").trim().slice(0, 80) || "Someone",
    room: `${cloud.environment}|${owner}|${zone}|${share.recordName}`, members: [...members],
    notices: [], occurredAt: record.modified!.timestamp!, cancelled: false,
  };
  const add = (recipient: string, kind: VerifiedNotice["kind"], category: VerifiedNotice["category"], post: string, title: string, body: string) => {
    if (recipient === me || !members.has(recipient) || event.notices.some(n => n.recipient === recipient)) return;
    event.notices.push({key: record.recordType === "PlatedDishNote" ? `note:${name}` : household ? `household:${me}:${name}` : record.recordType === "PlatedDishClaim" ? `seat:${me}` : `${kind === "commentLikes" ? "commentLike" : kind === "votes" ? "ballot" : "plate"}:${string(record,"postRecordName")}:${me}`, recipient, kind, category, post, title, body, direct: category === "replies" || category === "comments"});
  };
  const clean = (value: string, max: number) => value.replace(/[\x00-\x1f\x7f]/g, " ").trim().slice(0, max);
  if (record.recordType === "PlatedDishClaim" || record.recordType === "PlatedHouseholdSeat") {
    if (string(record, "userRecordName") !== me || (household && string(record, "seat") !== "joined")) throw new Rejected(403, "invalid_join");
    if (household && typeof field(record, "joinedAt") !== "number") throw new Rejected(403, "invalid_join");
    if (household && now - Number(field(record, "joinedAt")) > 86400000) throw new Rejected(410, "event_expired");
    add(owner, household ? "householdSeat" : "seat", "seats", "", `${event.actorName} joined`, household ? "Your household is ready to plan together." : "They’re now at your Table.");
    return event;
  }
  if (household || !["PlatedDishNote", "PlatedDishPlate", "PlatedDishBallot"].includes(record.recordType) || string(record, "authorID") !== me) {
    throw new Rejected(403, "invalid_event");
  }
  const target = await cloud.record(identifier(string(record, "postRecordName")), zone, owner, me);
  if (target.parent?.recordName !== rootName) throw new Rejected(403, "invalid_target");
  let post = target;
  if (target.recordType === "PlatedDishNote") {
    post = await cloud.record(identifier(string(target, "postRecordName")), zone, owner, me);
  }
  if (!["PlatedDish", "TablePost"].includes(post.recordType) || post.parent?.recordName !== rootName) throw new Rejected(403, "invalid_post");
  const label = clean(string(post, "dishTitle"), 100) || "your post";
  const targetAuthor = string(target, "authorID");
  if (record.recordType === "PlatedDishNote") {
    if (target !== post) throw new Rejected(403, "invalid_comment_target");
    event.cancelled = field(record, "deletedAt") != null;
    if (now - (record.created?.timestamp ?? 0) > 86400000 && !event.cancelled) throw new Rejected(410, "event_expired");
    const parentID = string(record, "parentCommentID");
    if (parentID) {
      const parent = await cloud.record(parentID, zone, owner, me);
      if (parent.recordType !== "PlatedDishNote" || string(parent, "postRecordName") !== post.recordName || parent.parent?.recordName !== rootName) throw new Rejected(403, "invalid_reply");
      add(string(parent, "authorID"), "comment", "replies", post.recordName, `${event.actorName} replied to you`, clean(string(record, "text"), 180) || `On ${label}`);
    }
    add(targetAuthor, "comment", "comments", post.recordName, `${event.actorName} commented`, clean(string(record, "text"), 180) || `On ${label}`);
  } else {
    const ballot = record.recordType === "PlatedDishBallot";
    event.cancelled = ballot ? Number(field(record, "choice")) < 0 : field(record, "active") !== 1;
    event.cancelled ||= field(target, "deletedAt") != null;
    add(targetAuthor, target === post ? (ballot ? "votes" : "plates") : "commentLikes", "plates", post.recordName,
      `${event.actorName} ${ballot ? "voted on your question" : target === post ? "liked your post" : "liked your comment"}`, label);
  }
  return event;
}
