"use client";

import { useRouter } from "next/navigation";
import Link from "next/link";
import { useRef, useState } from "react";
import {
  ADMIN_CSRF_HEADER,
  ADMIN_CSRF_VALUE,
  ANNOUNCEMENT_AUDIENCES,
  APP_LINKS,
  type AdminApiError,
  type AnnouncementAudience,
  type AnnouncementPreviewDTO,
  type AnnouncementReceiptDTO,
  type AnnouncementHistoryRow,
  type AppLink,
} from "../../lib/admin/contracts";
import { formatWhen, StatusPill } from "./UI";
import styles from "../admin.module.css";

const AUDIENCE_COPY: Record<AnnouncementAudience, { label: string; detail: string }> = {
  me: { label: "My devices", detail: "A private end-to-end test for the signed-in founder." },
  development: { label: "Development", detail: "Development-signed installations using Apple's sandbox gateway." },
  testflight: { label: "TestFlight", detail: "Installations positively identified as TestFlight." },
  app_store: { label: "App Store", detail: "Public App Store installations. Keep this audience exceptional." },
  all: { label: "Every channel", detail: "All eligible installations across development, TestFlight and App Store." },
};

type Draft = {
  title: string;
  body: string;
  link: AppLink;
  audience: AnnouncementAudience;
  belowBuild: string;
  replaces: string;
  overrideCap: boolean;
};

type Message = { tone: "good" | "bad" | "plain"; text: string };

class AdminCommandError extends Error {
  constructor(
    message: string,
    public readonly code?: AdminApiError["code"],
  ) {
    super(message);
    this.name = "AdminCommandError";
  }
}

const EMPTY_DRAFT: Draft = {
  title: "",
  body: "",
  link: "plated://home",
  audience: "me",
  belowBuild: "",
  replaces: "",
  overrideCap: false,
};

function object(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
}

function responsePayload(value: unknown): Record<string, unknown> | null {
  const outer = object(value);
  if (!outer) return null;
  return object(outer.data) ?? outer;
}

function asNonnegative(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 ? value : null;
}

function previewFrom(value: unknown): AnnouncementPreviewDTO | null {
  const root = responsePayload(value);
  if (!root || typeof root.announcementId !== "string" || typeof root.intentId !== "string" ||
      typeof root.expiresAt !== "string" || typeof root.payloadHash !== "string" ||
      typeof root.apnsConfigured !== "boolean" || typeof root.overrideCap !== "boolean") return null;
  const recipientCount = asNonnegative(root.recipientCount);
  const skippedUnknownBuild = asNonnegative(root.skippedUnknownBuild);
  const releaseChannels = object(root.byReleaseChannel);
  const gateways = object(root.byGateway);
  const builds = object(root.byBuild);
  if (recipientCount === null || skippedUnknownBuild === null || !releaseChannels || !gateways || !builds ||
      (root.capWarning !== null && typeof root.capWarning !== "string")) return null;
  const numericRecord = (source: Record<string, unknown>): Record<string, number> | null => {
    const entries = Object.entries(source);
    if (entries.some(([, value]) => asNonnegative(value) === null)) return null;
    return Object.fromEntries(entries) as Record<string, number>;
  };
  const byReleaseChannel = numericRecord(releaseChannels);
  const byGateway = numericRecord(gateways);
  const byBuild = numericRecord(builds);
  if (!byReleaseChannel || !byGateway || !byBuild) return null;
  return {
    announcementId: root.announcementId,
    intentId: root.intentId,
    expiresAt: root.expiresAt,
    payloadHash: root.payloadHash,
    recipientCount,
    skippedUnknownBuild,
    byReleaseChannel,
    byGateway,
    byBuild,
    capWarning: root.capWarning,
    overrideCap: root.overrideCap,
    apnsConfigured: root.apnsConfigured,
  };
}

function receiptFrom(value: unknown): AnnouncementReceiptDTO | null {
  const root = responsePayload(value);
  if (!root || typeof root.status !== "string" || root.acceptedLabel !== "Accepted by Apple" ||
      (root.nextRetryAt !== null && typeof root.nextRetryAt !== "string")) return null;
  const id = typeof root.announcementId === "string" ? root.announcementId : null;
  const targetedCount = asNonnegative(root.targetedCount);
  const acceptedCount = asNonnegative(root.acceptedCount);
  const retryableCount = asNonnegative(root.retryableCount);
  const permanentFailureCount = asNonnegative(root.permanentFailureCount);
  const pendingCount = asNonnegative(root.pendingCount);
  const batch = object(root.batch);
  const claimedCount = asNonnegative(batch?.claimedCount);
  const acceptedByAppleCount = asNonnegative(batch?.acceptedByAppleCount);
  const batchRetryableCount = asNonnegative(batch?.retryableCount);
  const batchPermanentFailureCount = asNonnegative(batch?.permanentFailureCount);
  if (!id || targetedCount === null || acceptedCount === null || retryableCount === null ||
      permanentFailureCount === null || pendingCount === null || !batch || claimedCount === null ||
      acceptedByAppleCount === null || batchRetryableCount === null || batchPermanentFailureCount === null) return null;
  return {
    announcementId: id,
    status: root.status,
    targetedCount,
    acceptedCount,
    retryableCount,
    permanentFailureCount,
    pendingCount,
    batch: { claimedCount, acceptedByAppleCount, retryableCount: batchRetryableCount, permanentFailureCount: batchPermanentFailureCount },
    nextRetryAt: root.nextRetryAt,
    acceptedLabel: "Accepted by Apple",
  };
}

function receiptMessage(receipt: AnnouncementReceiptDTO): string {
  const details = [
    receipt.acceptedCount + " of " + receipt.targetedCount + " requests accepted by Apple.",
  ];
  if (receipt.pendingCount > 0) {
    details.push(
      receipt.pendingCount + " remain pending" +
      (receipt.retryableCount > 0 ? ", including " + receipt.retryableCount + " marked for retry." : "."),
    );
  } else {
    details.push("No requests remain pending.");
  }
  if (receipt.permanentFailureCount > 0) {
    details.push(receipt.permanentFailureCount + " permanently failed.");
  }
  return details.join(" ");
}

async function command<T>(payload: Record<string, unknown>): Promise<T> {
  const response = await fetch("/api/admin/command", {
    method: "POST",
    headers: { "Content-Type": "application/json", [ADMIN_CSRF_HEADER]: ADMIN_CSRF_VALUE },
    body: JSON.stringify(payload),
    cache: "no-store",
  });
  const data = await response.json().catch(() => null) as T | AdminApiError | null;
  if (!response.ok) {
    const record = object(data);
    const error = record?.error;
    const code = record?.code === "mfa_step_up_required" ? record.code : undefined;
    throw new AdminCommandError(
      typeof error === "string" ? error : "The command was not accepted.",
      code,
    );
  }
  if (data === null) throw new Error("The command returned an empty response.");
  return data as T;
}

function draftError(draft: Draft): string | null {
  const title = draft.title.trim();
  const body = draft.body.trim();
  if (!title) return "Write a title.";
  if (!body) return "Write the one fact people need.";
  if (title.length > 32) return "Keep the title to 32 characters.";
  if (body.length > 140) return "Keep the body to 140 characters.";
  if (!/[.!?]$/.test(body)) return "End the body with a full stop, question mark or exclamation mark.";
  if (/[–—]/.test(`${title}${body}`)) return "Use a comma, colon or full stop instead of a long dash.";
  if (/^plated\b/i.test(title)) return "The banner already identifies Plated. Name the news instead.";
  if (draft.link === "plated://update" && !draft.belowBuild) return "A build notice needs a build ceiling so current installations are left alone.";
  if (draft.belowBuild && Number(draft.belowBuild) > 1_000_000) return "The build ceiling cannot exceed 1,000,000.";
  if (draft.replaces && !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(draft.replaces)) return "The correction ID is not valid.";
  return null;
}

export default function AnnouncementConsole({
  history,
  commandReady,
  stepUpRequired,
  nextCursor,
  totalCount,
}: {
  history: AnnouncementHistoryRow[];
  commandReady: boolean;
  stepUpRequired: boolean;
  nextCursor: string | null;
  totalCount: number;
}) {
  const router = useRouter();
  const draftRevision = useRef(0);
  const [draft, setDraft] = useState<Draft>(EMPTY_DRAFT);
  const [preview, setPreview] = useState<AnnouncementPreviewDTO | null>(null);
  const [confirmation, setConfirmation] = useState("");
  const [busy, setBusy] = useState<"" | "preview" | "send" | string>("");
  const [message, setMessage] = useState<Message | null>(null);
  const [needsStepUp, setNeedsStepUp] = useState(stepUpRequired);
  const localError = draftError(draft);

  function change<K extends keyof Draft>(key: K, value: Draft[K]) {
    draftRevision.current += 1;
    setDraft((current) => ({ ...current, [key]: value }));
    setPreview(null);
    setConfirmation("");
    setMessage(null);
  }

  function showCommandError(error: unknown, fallback: string) {
    if (error instanceof AdminCommandError && error.code === "mfa_step_up_required") {
      setNeedsStepUp(true);
    }
    setMessage({ tone: "bad", text: error instanceof Error ? error.message : fallback });
  }

  async function createPreview() {
    if (busy || localError || !commandReady || needsStepUp) return;
    const revision = draftRevision.current;
    const snapshot = draft;
    setBusy("preview");
    setMessage(null);
    try {
      const response = await command<unknown>({
        op: "preview",
        title: snapshot.title.trim(),
        body: snapshot.body.trim(),
        link: snapshot.link,
        audience: snapshot.audience,
        belowBuild: snapshot.belowBuild ? Number(snapshot.belowBuild) : null,
        replaces: snapshot.replaces ? snapshot.replaces.toLowerCase() : null,
        overrideCap: snapshot.overrideCap,
      });
      const decoded = previewFrom(response);
      if (!decoded) throw new Error("The preview response was incomplete.");
      if (revision !== draftRevision.current) {
        setMessage({ tone: "plain", text: "The draft changed while reach was calculated. Preview it again." });
        return;
      }
      setPreview(decoded);
    } catch (error) {
      showCommandError(error, "The preview failed.");
    } finally {
      setBusy("");
    }
  }

  async function send() {
    if (busy || needsStepUp || !preview || (preview.capWarning && !preview.overrideCap) || !preview.apnsConfigured || confirmation !== draft.title.trim()) return;
    setBusy("send");
    setMessage(null);
    try {
      const response = await command<unknown>({ op: "send", intentId: preview.intentId, typedTitle: confirmation });
      const receipt = receiptFrom(response);
      if (!receipt) throw new Error("The delivery receipt was incomplete.");
      setMessage({
        tone: receipt.pendingCount > 0 || receipt.permanentFailureCount > 0 ? "plain" : "good",
        text: receiptMessage(receipt),
      });
      draftRevision.current += 1;
      setDraft(EMPTY_DRAFT);
      setPreview(null);
      setConfirmation("");
      router.refresh();
    } catch (error) {
      showCommandError(error, "The send failed.");
    } finally {
      setBusy("");
    }
  }

  async function historyCommand(op: "retry" | "retract", announcementId: string) {
    if (busy || needsStepUp) return;
    if (op === "retract" && !window.confirm("Mark this announcement retracted? Notifications already seen cannot be recalled.")) return;
    setBusy(`${op}:${announcementId}`);
    setMessage(null);
    try {
      const response = await command<unknown>({ op, announcementId });
      if (op === "retry") {
        const receipt = receiptFrom(response);
        if (!receipt) throw new Error("The retry receipt was incomplete.");
        setMessage({
          tone: receipt.pendingCount > 0 || receipt.permanentFailureCount > 0 ? "plain" : "good",
          text: "Retry processed. " + receiptMessage(receipt),
        });
      } else {
        setMessage({ tone: "good", text: "The announcement was marked retracted." });
      }
      router.refresh();
    } catch (error) {
      showCommandError(error, "The command failed.");
    } finally {
      setBusy("");
    }
  }

  function prepareCorrection(item: AnnouncementHistoryRow) {
    draftRevision.current += 1;
    setDraft({
      ...EMPTY_DRAFT,
      link: APP_LINKS.includes(item.link as AppLink) ? item.link as AppLink : "plated://home",
      audience: item.audience,
      belowBuild: item.belowBuild ? String(item.belowBuild) : "",
      replaces: item.announcementId,
    });
    setPreview(null);
    setConfirmation("");
    setMessage(null);
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    window.scrollTo({ top: 0, behavior: reducedMotion ? "auto" : "smooth" });
  }

  return (
    <div className={styles.announcementGrid}>
      <section className={styles.composer} aria-labelledby="compose-title">
        <div className={styles.composerIntro}>
          <div><p className={styles.eyebrow}>Compose</p><h2 id="compose-title" className={styles.sectionTitle}>A rare note from Plated</h2></div>
          <p>Use a founder announcement only for service or release news that the people at a Table cannot say themselves.</p>
        </div>
        {!commandReady ? <div className={styles.callout}><p className={styles.calloutTitle}>Sending is not configured</p><p className={styles.smallMuted}>Set ADMIN_API_SECRET and the command function URL on Vercel. The APNs credentials remain in Supabase.</p></div> : null}
        {commandReady && needsStepUp ? (
          <div className={styles.callout} role="status">
            <p className={styles.calloutTitle}>Authenticator confirmation required</p>
            <p className={styles.smallMuted}>Founder controls require a current authenticator code. Reading the console remains available.</p>
            <Link className={styles.panelLink} href="/admin/mfa?stepup=1&next=%2Fadmin%2Fannouncements">Confirm with authenticator</Link>
          </div>
        ) : null}

        <fieldset className={styles.fieldset} disabled={Boolean(busy)}>
          <legend className={styles.label}>Audience</legend>
          <div className={styles.audienceGrid}>
            {ANNOUNCEMENT_AUDIENCES.map((audience) => (
              <label
                key={audience}
                className={`${styles.audienceButton} ${draft.audience === audience ? styles.audienceCurrent : ""}`}
              >
                <input
                  className={styles.visuallyHidden}
                  type="radio"
                  name="announcement-audience"
                  value={audience}
                  checked={draft.audience === audience}
                  onChange={() => change("audience", audience)}
                />
                <strong>{AUDIENCE_COPY[audience].label}</strong>
                <span>{AUDIENCE_COPY[audience].detail}</span>
              </label>
            ))}
          </div>
        </fieldset>

        <div className={styles.formGrid}>
          <label className={styles.field}><span className={styles.label}>Title</span><input className={styles.input} value={draft.title} maxLength={32} onChange={(event) => change("title", event.target.value)} placeholder="A new build to test" disabled={Boolean(busy)} /><span className={styles.counter}>{draft.title.trim().length}/32</span></label>
          <label className={`${styles.field} ${styles.fieldWide}`}><span className={styles.label}>Body</span><textarea className={styles.textarea} value={draft.body} maxLength={140} rows={4} onChange={(event) => change("body", event.target.value)} placeholder="Photos at the Table load more reliably in build 24. Update in TestFlight when it appears." disabled={Boolean(busy)} /><span className={styles.counter}>{draft.body.trim().length}/140</span></label>
          <label className={styles.field}><span className={styles.label}>Opens</span><select className={styles.input} value={draft.link} onChange={(event) => change("link", event.target.value as AppLink)} disabled={Boolean(busy)}>{APP_LINKS.map((link) => <option key={link} value={link}>{link.replace("plated://", "")}</option>)}</select></label>
          <label className={styles.field}><span className={styles.label}>Only below build</span><input className={styles.input} inputMode="numeric" value={draft.belowBuild} onChange={(event) => change("belowBuild", event.target.value.replace(/\D/g, "").slice(0, 10))} placeholder="Required for update notices" disabled={Boolean(busy)} /></label>
          <label className={`${styles.field} ${styles.fieldWide}`}><span className={styles.label}>Corrects announcement ID</span><input className={styles.input} value={draft.replaces} onChange={(event) => change("replaces", event.target.value.trim())} placeholder="Optional UUID from the audit history" autoComplete="off" disabled={Boolean(busy)} /><span className={styles.fieldHelp}>A correction keeps the original audience and collapse behavior. The server verifies the relationship.</span></label>
        </div>
        {localError ? <p className={styles.formError} role="alert">{localError}</p> : null}
        <div className={styles.composerActions}>
          <button className={styles.secondaryButton} type="button" onClick={createPreview} disabled={Boolean(busy) || Boolean(localError) || !commandReady || needsStepUp}>{busy === "preview" ? "Calculating…" : "Lock preview and reach"}</button>
        </div>

        {preview ? (
          <div className={styles.previewCard}>
            <div className={styles.notificationPreview} aria-label="Notification copy preview">
              <span className={styles.appTile} aria-hidden="true">plated</span>
              <div><p className={styles.notificationTitle}>{draft.title.trim()}</p><p>{draft.body.trim()}</p></div>
            </div>
            <div className={styles.previewFacts}>
              <div><strong>{preview.recipientCount}</strong><span>eligible devices</span></div>
              <div><strong>{preview.skippedUnknownBuild}</strong><span>unknown builds excluded</span></div>
              <div><strong>{formatWhen(preview.expiresAt)}</strong><span>intent expires</span></div>
            </div>
            <p className={styles.smallMuted}>Eligible means News is on, iOS authorization is known to allow delivery, and the release channel matches. Apple acceptance is reported after send; viewing is not measurable.</p>
            {Object.keys(preview.byReleaseChannel).length ? <dl className={styles.channelList}>{Object.entries(preview.byReleaseChannel).map(([channel, count]) => <div key={channel}><dt>{channel.replaceAll("_", " ")}</dt><dd>{count}</dd></div>)}</dl> : null}
            {!preview.apnsConfigured ? <p className={styles.formError}>APNs is not configured. The server will refuse to send.</p> : null}
            {preview.capWarning && !preview.overrideCap ? (
              <div className={styles.dangerCallout}>
                <p><strong>Rate cap:</strong> {preview.capWarning}</p>
                {!draft.overrideCap ? <button className={styles.textButton} type="button" onClick={() => change("overrideCap", true)} disabled={Boolean(busy)}>Override deliberately, then preview again</button> : null}
              </div>
            ) : preview.recipientCount === 0 ? <p className={styles.formError}>There are no eligible devices. Nothing can be sent.</p> : (
              <label className={styles.field}><span className={styles.label}>Type the title to authorize this exact intent</span><input className={styles.input} value={confirmation} onChange={(event) => setConfirmation(event.target.value)} autoComplete="off" disabled={Boolean(busy) || needsStepUp} /></label>
            )}
            <button className={styles.primaryButton} type="button" onClick={send} disabled={Boolean(busy) || needsStepUp || Boolean(preview.capWarning && !preview.overrideCap) || !preview.apnsConfigured || preview.recipientCount === 0 || confirmation !== draft.title.trim()}>{busy === "send" ? "Sending…" : `Send to ${preview.recipientCount}`}</button>
          </div>
        ) : null}
        {message ? <p className={`${styles.resultMessage} ${styles[`result_${message.tone}`]}`} role={message.tone === "bad" ? "alert" : "status"}>{message.text}</p> : null}
      </section>

      <section className={styles.historyPanel} aria-labelledby="announcement-history">
        <div><p className={styles.eyebrow}>History · {totalCount}</p><h2 id="announcement-history" className={styles.sectionTitle}>Announcements</h2></div>
        {history.length === 0 ? <p className={styles.bodyMuted}>No announcement actions have been recorded.</p> : (
          <ol className={styles.historyList}>
            {history.map((item) => (
              <li key={item.announcementId} className={styles.historyRow}>
                <div className={styles.historyTop}><strong>{item.title}</strong><StatusPill status={item.status} /></div>
                <p>{item.body}</p>
                <p className={styles.tableSubtext}>{formatWhen(item.createdAt)} · {item.audience.replaceAll("_", " ")}{item.belowBuild ? ` · below build ${item.belowBuild}` : ""}</p>
                <p className={styles.tableSubtext}>{item.acceptedCount} of {item.targetedCount} accepted by Apple · {item.pendingCount} pending · {item.permanentFailureCount} failed</p>
                <code className={styles.historyId}>{item.announcementId}</code>
                <div className={styles.historyActions}>
                  {(item.status === "queued" || item.status === "sending") && (item.pendingCount > 0 || item.retryableCount > 0) ? <button className={styles.smallButton} type="button" onClick={() => historyCommand("retry", item.announcementId)} disabled={Boolean(busy) || needsStepUp}>Resume delivery</button> : null}
                  {item.status === "sent" || item.status === "partial" ? <button className={styles.smallButton} type="button" onClick={() => historyCommand("retract", item.announcementId)} disabled={Boolean(busy) || needsStepUp}>Retract</button> : null}
                  {item.status === "retracted" ? <button className={styles.smallButton} type="button" onClick={() => prepareCorrection(item)} disabled={Boolean(busy)}>Prepare correction</button> : null}
                </div>
              </li>
            ))}
          </ol>
        )}
        {nextCursor ? <Link className={styles.panelLink} href={`/admin/announcements?cursor=${encodeURIComponent(nextCursor)}`}>Next page</Link> : null}
      </section>
    </div>
  );
}
