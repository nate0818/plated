import Link from "next/link";
import type { AdminEdgeResult } from "../../lib/admin/bff";
import type { AuditEvent } from "../../lib/admin/contracts";
import styles from "../admin.module.css";

export function PageHeader({
  eyebrow,
  title,
  description,
  action,
}: {
  eyebrow?: string;
  title: string;
  description?: string;
  action?: React.ReactNode;
}) {
  return (
    <header className={styles.pageHeader}>
      <div>
        {eyebrow ? <p className={styles.eyebrow}>{eyebrow}</p> : null}
        <h1 className={styles.pageTitle}>{title}</h1>
        {description ? <p className={styles.pageDescription}>{description}</p> : null}
      </div>
      {action ? <div className={styles.pageAction}>{action}</div> : null}
    </header>
  );
}

export function Panel({
  title,
  detail,
  children,
  className = "",
}: {
  title: string;
  detail?: string;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <section className={`${styles.panel} ${className}`}>
      <header className={styles.panelHeader}>
        <h2 className={styles.panelTitle}>{title}</h2>
        {detail ? <p className={styles.panelDetail}>{detail}</p> : null}
      </header>
      {children}
    </section>
  );
}

export function Metric({ label, value, detail }: { label: string; value: string; detail: string }) {
  return (
    <article className={styles.metric}>
      <p className={styles.metricLabel}>{label}</p>
      <p className={styles.metricValue}>{value}</p>
      <p className={styles.metricDetail}>{detail}</p>
    </article>
  );
}

export function StatusPill({ status, label }: { status: string; label?: string }) {
  const normalized = ["ready", "succeeded", "allowed", "available", "sent"].includes(status)
    ? "ready"
    : ["attention", "failed", "denied", "partial"].includes(status)
      ? "attention"
      : ["unavailable", "coverage_gap", "retracted"].includes(status)
        ? "unavailable"
        : "unknown";
  return <span className={`${styles.status} ${styles[`status_${normalized}`]}`}>{label ?? status.replaceAll("_", " ")}</span>;
}

export function EmptyState({ title, detail }: { title: string; detail: string }) {
  return (
    <div className={styles.emptyState}>
      <span className={styles.emptyMark} aria-hidden="true">·</span>
      <p className={styles.emptyTitle}>{title}</p>
      <p className={styles.smallMuted}>{detail}</p>
    </div>
  );
}

export function ServiceError({ result }: { result: Extract<AdminEdgeResult<unknown>, { ok: false }> }) {
  const title = result.status === 403
    ? "This account is not an active administrator"
    : result.status === 503
      ? "The console needs server setup"
      : "The operational service is unavailable";
  return (
    <div className={styles.serviceError} role="alert">
      <p className={styles.serviceErrorTitle}>{title}</p>
      <p>{result.error}</p>
      <p className={styles.requestId}>Request {result.requestId}</p>
    </div>
  );
}

export function CoverageGap({ title, detail, href }: { title: string; detail: string; href?: string }) {
  return (
    <article className={styles.coverageGap}>
      <span className={styles.coverageIcon} aria-hidden="true">○</span>
      <div>
        <h3>{title}</h3>
        <p>{detail}</p>
        {href ? <Link href={href}>See what is available</Link> : null}
      </div>
    </article>
  );
}

export function AuditList({ rows }: { rows: AuditEvent[] }) {
  if (rows.length === 0) {
    return <EmptyState title="No recorded events" detail="Administrative actions will appear here after they occur." />;
  }
  return (
    <ol className={styles.auditList}>
      {rows.map((row) => (
        <li className={styles.auditRow} key={row.auditId}>
          <span className={`${styles.auditDot} ${styles[`auditDot_${row.outcome}`]}`} aria-hidden="true" />
          <div>
            <div className={styles.auditTopline}>
              <strong>{row.action.replaceAll("_", " ")}</strong>
              <StatusPill status={row.outcome} />
            </div>
            <p>{row.targetType ? `${row.targetType}${row.targetId ? ` · ${row.targetId}` : ""}` : "Administrative read or action"}</p>
            <p className={styles.tableSubtext}>{formatWhen(row.createdAt)} · {row.actor.replaceAll("_", " ")}{row.requestId ? ` · request ${row.requestId}` : ""}</p>
          </div>
        </li>
      ))}
    </ol>
  );
}

export function formatCount(value: number | null | undefined): string {
  return typeof value === "number" && Number.isFinite(value) ? value.toLocaleString("en-US") : "Unavailable";
}

export function formatWhen(value: string | null | undefined): string {
  if (!value) return "Not recorded";
  const date = new Date(value);
  if (Number.isNaN(date.valueOf())) return "Not recorded";
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
    timeZone: "America/New_York",
    timeZoneName: "short",
  }).format(date);
}
