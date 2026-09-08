export const ADMIN_CSRF_HEADER = "X-Plated-CSRF";
export const ADMIN_CSRF_VALUE = "founder-console-v1";

export const READ_OPS = ["overview", "people", "waitlist", "operations", "audit", "announcements", "releases"] as const;
export type AdminReadOp = (typeof READ_OPS)[number];

export type AdminReadRequest =
  | { op: "overview" | "operations" | "releases" }
  | { op: "people" | "waitlist" | "audit" | "announcements"; cursor?: string; limit?: number };

export const ANNOUNCEMENT_AUDIENCES = ["me", "development", "testflight", "app_store", "all"] as const;
export type AnnouncementAudience = (typeof ANNOUNCEMENT_AUDIENCES)[number];

export const APP_LINKS = [
  "plated://home",
  "plated://table",
  "plated://plan",
  "plated://cookbook",
  "plated://grocery",
  "plated://activity",
  "plated://update",
] as const;
export type AppLink = (typeof APP_LINKS)[number];

/** Browser-to-BFF contract. The BFF strips every field outside this union. */
export type AdminCommandRequest =
  | {
      op: "preview";
      title: string;
      body: string;
      link: AppLink;
      audience: AnnouncementAudience;
      belowBuild: number | null;
      replaces: string | null;
      overrideCap: boolean;
    }
  | { op: "send"; intentId: string; typedTitle: string }
  | { op: "retry"; announcementId: string }
  | { op: "retract"; announcementId: string };

export type AdminReadEnvelope<T> = { op: AdminReadOp; generatedAt: string; data: T };

export type AnnouncementHistoryRow = {
  announcementId: string;
  title: string;
  body: string;
  link: string;
  audience: AnnouncementAudience;
  belowBuild: number | null;
  replaces: string | null;
  overrideCap: boolean;
  status: "previewed" | "queued" | "sending" | "sent" | "partial" | "failed" | "retracted";
  targetedCount: number;
  acceptedCount: number;
  retryableCount: number;
  permanentFailureCount: number;
  pendingCount: number;
  createdAt: string;
  queuedAt: string | null;
  startedAt: string | null;
  finishedAt: string | null;
  retractedAt: string | null;
  acceptedLabel: "Accepted by Apple";
};

export type OverviewDTO = {
  accounts: { directoryCount: number };
  waitlist: { totalCount: number };
  invitations: { last24HoursCount: number; retentionDays: number };
  devices: {
    registeredCount: number;
    eligibleForNewsCount: number;
    deniedNotificationCount: number;
    unknownAuthorizationCount: number;
    byReleaseChannel: Record<string, number>;
    byGateway: Record<string, number>;
  };
  announcements: Array<Pick<AnnouncementHistoryRow,
    "announcementId" | "status" | "targetedCount" | "acceptedCount" | "retryableCount" |
    "permanentFailureCount" | "pendingCount" | "createdAt" | "acceptedLabel">>;
  privacyBoundary: { centrallyReadable: string[]; privateInCloudKit: string[] };
};

export type PersonRow = {
  /** Stable only for this administrator; never a database or Auth identifier. */
  personKey: string;
  displayName: string;
  phoneOnFile: boolean;
  joinedAt: string;
  lastDirectoryRegistrationAt: string;
  deviceCount: number;
  eligibleDeviceCount: number;
  lastDeviceRegistrationAt: string | null;
  latestBuild: number | null;
  latestVersion: string | null;
  releaseChannel: string | null;
  notificationAuthorization: string | null;
  newsEnabled: boolean | null;
};

export type PeopleDTO = { rows: PersonRow[]; totalCount: number; nextCursor: string | null };

export type WaitlistDTO = {
  rows: Array<{ emailMasked: string; joinedAt: string }>;
  totalCount: number;
  nextCursor: string | null;
  revealAvailable: false;
  retention: string;
};

export type AnnouncementHistoryDTO = { rows: AnnouncementHistoryRow[]; totalCount: number; nextCursor: string | null };

export type OperationsDTO = {
  database: { status: "available" };
  adminAuth: { activePrincipalCount: number; mfaRequired: true; signedRequestsRequired: true };
  push: {
    configured: boolean;
    acceptedLabel: "Accepted by Apple";
    deliveryCounts: Record<string, number>;
    exhaustedRetryCount: number;
  };
  deviceDirectory: { lastRegistrationAt: string | null; tokenOwnership: "global"; signOutUnregisterSupported: boolean };
  invitations: { shareUrlsStored: false; metadataRetentionDays: number };
  adminRetention: {
    previewIntentMinutes: number;
    expiredPreviewPurgeCadence: string;
    resumableDeliveryHours: number;
    terminalDeliveryTokensCleared: "immediately";
    maximumSnapshotTokenDays: number;
  };
  integrations: {
    instacart: { status: "coverage_gap"; reason: string };
    appStoreConnect: { status: "coverage_gap"; configured: false };
  };
  phoneHashing: { configured: boolean };
};

export type AuditEvent = {
  auditId: number;
  actor: "you" | "another_admin" | "system";
  action: string;
  outcome: "allowed" | "denied" | "failed";
  targetType: string | null;
  targetId: string | null;
  requestId: string | null;
  metadata: Record<string, unknown>;
  createdAt: string;
};

export type AuditDTO = { rows: AuditEvent[]; totalCount: number; nextCursor: string | null; appendOnly: true };

export type ReleasesDTO = {
  authoritativeSource: { provider: "App Store Connect"; connected: boolean; status: "coverage_gap" | string; reason: string };
  deviceReported: Record<string, { deviceCount: number; highestBuild: number | null; versions: string[] }>;
  caveat: string;
};

export type AnnouncementPreviewDTO = {
  announcementId: string;
  intentId: string;
  expiresAt: string;
  payloadHash: string;
  recipientCount: number;
  skippedUnknownBuild: number;
  byReleaseChannel: Record<string, number>;
  byGateway: Record<string, number>;
  byBuild: Record<string, number>;
  capWarning: string | null;
  overrideCap: boolean;
  apnsConfigured: boolean;
};

export type AnnouncementReceiptDTO = {
  announcementId: string;
  status: string;
  targetedCount: number;
  acceptedCount: number;
  retryableCount: number;
  permanentFailureCount: number;
  pendingCount: number;
  batch: { claimedCount: number; acceptedByAppleCount: number; retryableCount: number; permanentFailureCount: number };
  nextRetryAt: string | null;
  acceptedLabel: "Accepted by Apple";
};

export type AdminApiError = {
  error: string;
  request_id?: string;
  code?: "mfa_step_up_required";
};
