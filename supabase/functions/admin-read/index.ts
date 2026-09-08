import {
  adminErrorResponse,
  AdminHttpError,
  adminRequestId,
  audit,
  authenticateAdmin,
  hmacHex,
  jsonResponse,
  readBoundedBody,
  type AdminContext,
} from "../_shared/admin_auth.ts";
import { apnsConfigured } from "../_shared/apns.ts";
import {
  decodeOffset,
  encodeOffset,
  maskEmail,
  parseAdminReadCommand,
  type AdminReadCommand,
} from "./contracts.ts";

function failIf(error: unknown): void {
  if (error) throw new AdminHttpError(503, "Founder data is temporarily unavailable.");
}

function nextCursor(offset: number, returned: number, total: number): string | null {
  return offset + returned < total ? encodeOffset(offset + returned) : null;
}

async function metrics(context: AdminContext, operation: "overview" | "operations" | "releases") {
  const { data, error } = await context.db.rpc("admin_read_metrics", {
    p_actor_user_id: context.actorId,
    p_operation: operation,
  });
  failIf(error);
  return (data ?? {}) as Record<string, unknown>;
}

async function overview(context: AdminContext) {
  const [aggregate, announcements] = await Promise.all([
    metrics(context, "overview"),
    context.db.from("announcements").select(
      "id, status, targeted_count, accepted_count, retryable_count, permanent_failure_count, pending_count, created_at",
    ).order("created_at", { ascending: false }).limit(10),
  ]);
  failIf(announcements.error);
  return {
    ...aggregate,
    announcements: (announcements.data ?? []).map((row) => ({
      announcementId: row.id,
      status: row.status,
      targetedCount: row.targeted_count,
      acceptedCount: row.accepted_count,
      retryableCount: row.retryable_count,
      permanentFailureCount: row.permanent_failure_count,
      pendingCount: row.pending_count,
      createdAt: row.created_at,
      acceptedLabel: "Accepted by Apple",
    })),
    privacyBoundary: {
      centrallyReadable: ["directory registration", "push eligibility", "waitlist", "invitation abuse metadata"],
      privateInCloudKit: ["recipes", "meal plans", "households", "posts", "photos", "cooking history"],
    },
  };
}

async function people(context: AdminContext, command: AdminReadCommand) {
  const offset = decodeOffset(command.cursor);
  const page = await context.db.from("directory_users")
    .select("id, display_name, phone_hash, created_at, updated_at", { count: "exact" })
    .order("created_at", { ascending: false }).order("id", { ascending: false })
    .range(offset, offset + command.limit - 1);
  failIf(page.error);
  const rows = page.data ?? [];
  const ids = rows.map((row) => row.id);
  const [devices, sessions] = ids.length
    ? await Promise.all([
      context.db.from("device_tokens").select(
        "user_id, installation_id, directory_session_id, release_channel, apns_environment, notification_authorization, news, app_build, app_version, updated_at",
      ).in("user_id", ids),
      context.db.from("directory_sessions").select("id, user_id, installation_id")
        .in("user_id", ids).is("revoked_at", null).gt("expires_at", new Date().toISOString()),
    ])
    : [{ data: [], error: null }, { data: [], error: null }];
  failIf(devices.error);
  failIf(sessions.error);
  const activeBindings = new Set((sessions.data ?? []).map((session) =>
    `${session.id}:${session.user_id}:${session.installation_id}`
  ));
  const byPerson = new Map<string, Array<Record<string, unknown>>>();
  for (const device of (devices.data ?? []) as Array<Record<string, unknown>>) {
    // Same rule as admin_read_metrics: a registration made before the
    // directory cutover carries no session and is still a real phone. Once
    // the cutover lands the column is not null and only the binding counts.
    const preCutover = device.directory_session_id === null;
    if (!preCutover && !activeBindings.has(
      `${device.directory_session_id}:${device.user_id}:${device.installation_id}`,
    )) continue;
    const id = String(device.user_id);
    byPerson.set(id, [...(byPerson.get(id) ?? []), device]);
  }
  const redactedRows = await Promise.all(rows.map(async (person) => {
      const personDevices = byPerson.get(person.id) ?? [];
      const lastDevice = [...personDevices].sort((a, b) =>
        String(b.updated_at).localeCompare(String(a.updated_at))
      )[0];
      return {
        personKey: (await hmacHex(
          Deno.env.get("ADMIN_API_SECRET")!,
          `person:${context.actorId}:${person.id}`,
        )).slice(0, 24),
        displayName: person.display_name || "Unnamed person",
        phoneOnFile: Boolean(person.phone_hash),
        joinedAt: person.created_at,
        lastDirectoryRegistrationAt: person.updated_at,
        deviceCount: personDevices.length,
        eligibleDeviceCount: personDevices.filter((device) =>
          device.news === true && ["authorized", "provisional", "ephemeral"].includes(
            String(device.notification_authorization),
          )
        ).length,
        lastDeviceRegistrationAt: lastDevice?.updated_at ?? null,
        latestBuild: lastDevice?.app_build ?? null,
        latestVersion: lastDevice?.app_version ?? null,
        releaseChannel: lastDevice?.release_channel ?? null,
        notificationAuthorization: lastDevice?.notification_authorization ?? null,
        newsEnabled: lastDevice?.news ?? null,
      };
    }));
  return {
    rows: redactedRows,
    totalCount: page.count ?? 0,
    nextCursor: nextCursor(offset, rows.length, page.count ?? 0),
  };
}

async function waitlist(context: AdminContext, command: AdminReadCommand) {
  const offset = decodeOffset(command.cursor);
  const page = await context.db.from("waitlist")
    .select("email, created_at", { count: "exact" })
    .order("created_at", { ascending: false })
    .range(offset, offset + command.limit - 1);
  failIf(page.error);
  const rows = page.data ?? [];
  return {
    rows: rows.map((row) => ({ emailMasked: maskEmail(row.email), joinedAt: row.created_at })),
    totalCount: page.count ?? 0,
    nextCursor: nextCursor(offset, rows.length, page.count ?? 0),
    revealAvailable: false,
    retention: "Waitlist emails remain until the person asks Plated to delete them.",
  };
}

async function announcements(context: AdminContext, command: AdminReadCommand) {
  const offset = decodeOffset(command.cursor);
  const page = await context.db.from("announcements").select(
    "id, title, body, link, audience, below_build, replaces, override_cap, status, targeted_count, accepted_count, retryable_count, permanent_failure_count, pending_count, created_at, queued_at, started_at, finished_at, retracted_at",
    { count: "exact" },
  ).order("created_at", { ascending: false }).order("id", { ascending: false })
    .range(offset, offset + command.limit - 1);
  failIf(page.error);
  const rows = page.data ?? [];
  return {
    rows: rows.map((row) => ({
      announcementId: row.id,
      title: row.title,
      body: row.body,
      link: row.link,
      audience: row.audience,
      belowBuild: row.below_build,
      replaces: row.replaces,
      overrideCap: row.override_cap,
      status: row.status,
      targetedCount: row.targeted_count,
      acceptedCount: row.accepted_count,
      retryableCount: row.retryable_count,
      permanentFailureCount: row.permanent_failure_count,
      pendingCount: row.pending_count,
      createdAt: row.created_at,
      queuedAt: row.queued_at,
      startedAt: row.started_at,
      finishedAt: row.finished_at,
      retractedAt: row.retracted_at,
      acceptedLabel: "Accepted by Apple",
    })),
    totalCount: page.count ?? 0,
    nextCursor: nextCursor(offset, rows.length, page.count ?? 0),
  };
}

async function operations(context: AdminContext) {
  const aggregate = await metrics(context, "operations") as {
    activePrincipalCount?: number;
    deliveryCounts?: Record<string, number>;
    exhaustedRetryCount?: number;
    lastDeviceRegistrationAt?: string | null;
    phonePepperConfigured?: boolean;
  };
  return {
    database: { status: "available" },
    adminAuth: {
      activePrincipalCount: aggregate.activePrincipalCount ?? 0,
      mfaRequired: true,
      signedRequestsRequired: true,
    },
    push: {
      configured: apnsConfigured(),
      acceptedLabel: "Accepted by Apple",
      deliveryCounts: aggregate.deliveryCounts ?? {},
      exhaustedRetryCount: aggregate.exhaustedRetryCount ?? 0,
    },
    deviceDirectory: {
      lastRegistrationAt: aggregate.lastDeviceRegistrationAt ?? null,
      tokenOwnership: "global",
      signOutUnregisterSupported: true,
    },
    invitations: {
      shareUrlsStored: false,
      metadataRetentionDays: 30,
    },
    adminRetention: {
      previewIntentMinutes: 10,
      expiredPreviewPurgeCadence: "hourly",
      resumableDeliveryHours: 72,
      terminalDeliveryTokensCleared: "immediately",
      maximumSnapshotTokenDays: 30,
    },
    integrations: {
      instacart: {
        status: "coverage_gap",
        reason: "Instacart configuration belongs to a separate function and is not authoritative here.",
      },
      appStoreConnect: { status: "coverage_gap", configured: false },
    },
    phoneHashing: { configured: aggregate.phonePepperConfigured ?? false },
  };
}

async function auditRows(context: AdminContext, command: AdminReadCommand) {
  const offset = decodeOffset(command.cursor);
  const page = await context.db.from("admin_audit_events").select(
    "id, actor_user_id, action, outcome, target_type, target_id, request_id, metadata, created_at",
    { count: "exact" },
  ).order("created_at", { ascending: false }).order("id", { ascending: false })
    .range(offset, offset + command.limit - 1);
  failIf(page.error);
  const rows = page.data ?? [];
  return {
    rows: rows.map((row) => ({
      auditId: row.id,
      actor: row.actor_user_id === context.actorId ? "you" : row.actor_user_id ? "another_admin" : "system",
      action: row.action,
      outcome: row.outcome,
      targetType: row.target_type,
      targetId: row.target_id,
      requestId: row.request_id,
      metadata: row.metadata,
      createdAt: row.created_at,
    })),
    totalCount: page.count ?? 0,
    nextCursor: nextCursor(offset, rows.length, page.count ?? 0),
    appendOnly: true,
  };
}

async function releases(context: AdminContext) {
  const aggregate = await metrics(context, "releases") as {
    deviceReported?: Record<string, { deviceCount: number; highestBuild: number | null; versions: string[] }>;
  };
  return {
    authoritativeSource: {
      provider: "App Store Connect",
      connected: false,
      status: "coverage_gap",
      reason: "No App Store Connect integration is configured for the founder console.",
    },
    deviceReported: aggregate.deviceReported ?? {},
    caveat: "Device registrations show installed builds. They do not establish TestFlight or App Store release status.",
  };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);
  const requestId = adminRequestId(req);
  try {
    const raw = await readBoundedBody(req, 8_192);
    let command: AdminReadCommand;
    try { command = parseAdminReadCommand(JSON.parse(raw)); } catch (error) {
      throw new AdminHttpError(400, error instanceof Error ? error.message : "The read command is invalid.");
    }
    const context = await authenticateAdmin(req, raw, "admin.read", { requestId });
    const { error: purgeError } = await context.db.rpc("purge_admin_ephemera");
    failIf(purgeError);
    const data = command.op === "overview" ? await overview(context)
      : command.op === "people" ? await people(context, command)
      : command.op === "waitlist" ? await waitlist(context, command)
      : command.op === "operations" ? await operations(context)
      : command.op === "audit" ? await auditRows(context, command)
      : command.op === "announcements" ? await announcements(context, command)
      : await releases(context);
    await audit(context, `admin.read.${command.op}`, "allowed", "admin_view", command.op, {
      pageSize: command.limit,
      hasCursor: Boolean(command.cursor),
    });
    return jsonResponse({ op: command.op, generatedAt: new Date().toISOString(), data });
  } catch (error) {
    return adminErrorResponse(error, requestId);
  }
});
