import type {
  AdminReadEnvelope,
  AdminReadOp,
  AnnouncementAudience,
  AnnouncementHistoryDTO,
  AnnouncementHistoryRow,
  AuditDTO,
  AuditEvent,
  OperationsDTO,
  OverviewDTO,
  PeopleDTO,
  PersonRow,
  ReleasesDTO,
  WaitlistDTO,
} from "./contracts";
import { ANNOUNCEMENT_AUDIENCES } from "./contracts";

export class AdminContractError extends Error {
  constructor() {
    super("The admin service returned data in an unexpected format.");
    this.name = "AdminContractError";
  }
}

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new AdminContractError();
  return value as Record<string, unknown>;
}

function text(value: unknown): string {
  if (typeof value !== "string") throw new AdminContractError();
  return value;
}

function nullableText(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  return text(value);
}

function count(value: unknown): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) throw new AdminContractError();
  return value;
}

function nullableCount(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  return count(value);
}

function flag(value: unknown): boolean {
  if (typeof value !== "boolean") throw new AdminContractError();
  return value;
}

function nullableFlag(value: unknown): boolean | null {
  if (value === null || value === undefined) return null;
  return flag(value);
}

function list(value: unknown): unknown[] {
  if (!Array.isArray(value)) throw new AdminContractError();
  return value;
}

function strings(value: unknown): string[] {
  return list(value).map(text);
}

function numberMap(value: unknown): Record<string, number> {
  return Object.fromEntries(Object.entries(record(value)).map(([key, item]) => [key, count(item)]));
}

function envelope<T>(value: unknown, expectedOp: AdminReadOp, decode: (data: Record<string, unknown>) => T): AdminReadEnvelope<T> {
  const outer = record(value);
  if (outer.op !== expectedOp) throw new AdminContractError();
  return { op: expectedOp, generatedAt: text(outer.generatedAt), data: decode(record(outer.data)) };
}

function audience(value: unknown): AnnouncementAudience {
  if (typeof value !== "string" || !(ANNOUNCEMENT_AUDIENCES as readonly string[]).includes(value)) throw new AdminContractError();
  return value as AnnouncementAudience;
}

function announcementStatus(value: unknown): AnnouncementHistoryRow["status"] {
  if (typeof value !== "string" || !["previewed", "queued", "sending", "sent", "partial", "failed", "retracted"].includes(value)) throw new AdminContractError();
  return value as AnnouncementHistoryRow["status"];
}

function announcementRow(value: unknown): AnnouncementHistoryRow {
  const row = record(value);
  if (row.acceptedLabel !== "Accepted by Apple") throw new AdminContractError();
  return {
    announcementId: text(row.announcementId),
    title: text(row.title),
    body: text(row.body),
    link: text(row.link),
    audience: audience(row.audience),
    belowBuild: nullableCount(row.belowBuild),
    replaces: nullableText(row.replaces),
    overrideCap: flag(row.overrideCap),
    status: announcementStatus(row.status),
    targetedCount: count(row.targetedCount),
    acceptedCount: count(row.acceptedCount),
    retryableCount: count(row.retryableCount),
    permanentFailureCount: count(row.permanentFailureCount),
    pendingCount: count(row.pendingCount),
    createdAt: text(row.createdAt),
    queuedAt: nullableText(row.queuedAt),
    startedAt: nullableText(row.startedAt),
    finishedAt: nullableText(row.finishedAt),
    retractedAt: nullableText(row.retractedAt),
    acceptedLabel: "Accepted by Apple",
  };
}

export function decodeOverview(value: unknown): AdminReadEnvelope<OverviewDTO> {
  return envelope(value, "overview", (root) => {
    const accounts = record(root.accounts);
    const waitlist = record(root.waitlist);
    const invitations = record(root.invitations);
    const devices = record(root.devices);
    const privacy = record(root.privacyBoundary);
    return {
      accounts: { directoryCount: count(accounts.directoryCount) },
      waitlist: { totalCount: count(waitlist.totalCount) },
      invitations: { last24HoursCount: count(invitations.last24HoursCount), retentionDays: count(invitations.retentionDays) },
      devices: {
        registeredCount: count(devices.registeredCount),
        eligibleForNewsCount: count(devices.eligibleForNewsCount),
        deniedNotificationCount: count(devices.deniedNotificationCount),
        unknownAuthorizationCount: count(devices.unknownAuthorizationCount),
        byReleaseChannel: numberMap(devices.byReleaseChannel),
        byGateway: numberMap(devices.byGateway),
      },
      announcements: list(root.announcements).map((value) => {
        const row = record(value);
        if (row.acceptedLabel !== "Accepted by Apple") throw new AdminContractError();
        return {
          announcementId: text(row.announcementId),
          status: announcementStatus(row.status),
          targetedCount: count(row.targetedCount),
          acceptedCount: count(row.acceptedCount),
          retryableCount: count(row.retryableCount),
          permanentFailureCount: count(row.permanentFailureCount),
          pendingCount: count(row.pendingCount),
          createdAt: text(row.createdAt),
          acceptedLabel: "Accepted by Apple" as const,
        };
      }),
      privacyBoundary: { centrallyReadable: strings(privacy.centrallyReadable), privateInCloudKit: strings(privacy.privateInCloudKit) },
    };
  });
}

function person(value: unknown): PersonRow {
  const row = record(value);
  return {
    personKey: text(row.personKey),
    displayName: text(row.displayName),
    phoneOnFile: flag(row.phoneOnFile),
    joinedAt: text(row.joinedAt),
    lastDirectoryRegistrationAt: text(row.lastDirectoryRegistrationAt),
    deviceCount: count(row.deviceCount),
    eligibleDeviceCount: count(row.eligibleDeviceCount),
    lastDeviceRegistrationAt: nullableText(row.lastDeviceRegistrationAt),
    latestBuild: nullableCount(row.latestBuild),
    latestVersion: nullableText(row.latestVersion),
    releaseChannel: nullableText(row.releaseChannel),
    notificationAuthorization: nullableText(row.notificationAuthorization),
    newsEnabled: nullableFlag(row.newsEnabled),
  };
}

export function decodePeople(value: unknown): AdminReadEnvelope<PeopleDTO> {
  return envelope(value, "people", (root) => ({
    rows: list(root.rows).map(person),
    totalCount: count(root.totalCount),
    nextCursor: nullableText(root.nextCursor),
  }));
}

export function decodeWaitlist(value: unknown): AdminReadEnvelope<WaitlistDTO> {
  return envelope(value, "waitlist", (root) => {
    if (root.revealAvailable !== false) throw new AdminContractError();
    return {
      rows: list(root.rows).map((value) => {
        const row = record(value);
        return { emailMasked: text(row.emailMasked), joinedAt: text(row.joinedAt) };
      }),
      totalCount: count(root.totalCount),
      nextCursor: nullableText(root.nextCursor),
      revealAvailable: false,
      retention: text(root.retention),
    };
  });
}

export function decodeAnnouncements(value: unknown): AdminReadEnvelope<AnnouncementHistoryDTO> {
  return envelope(value, "announcements", (root) => ({
    rows: list(root.rows).map(announcementRow),
    totalCount: count(root.totalCount),
    nextCursor: nullableText(root.nextCursor),
  }));
}

export function decodeOperations(value: unknown): AdminReadEnvelope<OperationsDTO> {
  return envelope(value, "operations", (root) => {
    const database = record(root.database);
    const adminAuth = record(root.adminAuth);
    const push = record(root.push);
    const deviceDirectory = record(root.deviceDirectory);
    const invitations = record(root.invitations);
    const adminRetention = record(root.adminRetention);
    const integrations = record(root.integrations);
    const instacart = record(integrations.instacart);
    const appStoreConnect = record(integrations.appStoreConnect);
    const phoneHashing = record(root.phoneHashing);
    if (database.status !== "available" || adminAuth.mfaRequired !== true || adminAuth.signedRequestsRequired !== true ||
        push.acceptedLabel !== "Accepted by Apple" || deviceDirectory.tokenOwnership !== "global" || invitations.shareUrlsStored !== false ||
        adminRetention.terminalDeliveryTokensCleared !== "immediately" || instacart.status !== "coverage_gap" ||
        appStoreConnect.status !== "coverage_gap" || appStoreConnect.configured !== false) {
      throw new AdminContractError();
    }
    return {
      database: { status: "available" },
      adminAuth: { activePrincipalCount: count(adminAuth.activePrincipalCount), mfaRequired: true, signedRequestsRequired: true },
      push: {
        configured: flag(push.configured),
        acceptedLabel: "Accepted by Apple",
        deliveryCounts: numberMap(push.deliveryCounts),
        exhaustedRetryCount: count(push.exhaustedRetryCount),
      },
      deviceDirectory: {
        lastRegistrationAt: nullableText(deviceDirectory.lastRegistrationAt),
        tokenOwnership: "global",
        signOutUnregisterSupported: flag(deviceDirectory.signOutUnregisterSupported),
      },
      invitations: { shareUrlsStored: false, metadataRetentionDays: count(invitations.metadataRetentionDays) },
      adminRetention: {
        previewIntentMinutes: count(adminRetention.previewIntentMinutes),
        expiredPreviewPurgeCadence: text(adminRetention.expiredPreviewPurgeCadence),
        resumableDeliveryHours: count(adminRetention.resumableDeliveryHours),
        terminalDeliveryTokensCleared: "immediately",
        maximumSnapshotTokenDays: count(adminRetention.maximumSnapshotTokenDays),
      },
      integrations: {
        instacart: { status: "coverage_gap", reason: text(instacart.reason) },
        appStoreConnect: { status: "coverage_gap", configured: false },
      },
      phoneHashing: { configured: flag(phoneHashing.configured) },
    };
  });
}

function auditEvent(value: unknown): AuditEvent {
  const row = record(value);
  if (!["you", "another_admin", "system"].includes(String(row.actor)) || !["allowed", "denied", "failed"].includes(String(row.outcome))) {
    throw new AdminContractError();
  }
  return {
    auditId: count(row.auditId),
    actor: row.actor as AuditEvent["actor"],
    action: text(row.action),
    outcome: row.outcome as AuditEvent["outcome"],
    targetType: nullableText(row.targetType),
    targetId: nullableText(row.targetId),
    requestId: nullableText(row.requestId),
    metadata: record(row.metadata),
    createdAt: text(row.createdAt),
  };
}

export function decodeAudit(value: unknown): AdminReadEnvelope<AuditDTO> {
  return envelope(value, "audit", (root) => {
    if (root.appendOnly !== true) throw new AdminContractError();
    return {
      rows: list(root.rows).map(auditEvent),
      totalCount: count(root.totalCount),
      nextCursor: nullableText(root.nextCursor),
      appendOnly: true,
    };
  });
}

export function decodeReleases(value: unknown): AdminReadEnvelope<ReleasesDTO> {
  return envelope(value, "releases", (root) => {
    const source = record(root.authoritativeSource);
    if (source.provider !== "App Store Connect") throw new AdminContractError();
    const reported = Object.fromEntries(Object.entries(record(root.deviceReported)).map(([channel, value]) => {
      const row = record(value);
      return [channel, { deviceCount: count(row.deviceCount), highestBuild: nullableCount(row.highestBuild), versions: strings(row.versions) }];
    }));
    return {
      authoritativeSource: {
        provider: "App Store Connect",
        connected: flag(source.connected),
        status: text(source.status),
        reason: text(source.reason),
      },
      deviceReported: reported,
      caveat: text(root.caveat),
    };
  });
}
