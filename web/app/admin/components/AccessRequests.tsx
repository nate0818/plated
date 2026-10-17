"use client";
import Link from "next/link";
import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import {
  type AccessFilter,
  type AccessRequestsDTO,
  type AccessStatus,
  ADMIN_CSRF_HEADER,
  ADMIN_CSRF_VALUE,
  type TestFlightRequest,
} from "../../lib/admin/contracts";
import { accessStatusLabel } from "../../lib/admin/testflight";
import { EmptyState, formatCount, formatWhen, Metric, StatusPill } from "./UI";
import styles from "../admin.module.css";
import access from "./AccessRequests.module.css";
const MAX_BATCH = 10;
const filters: Array<[AccessFilter, string]> = [
  ["active", "To review"],
  ["invited", "Invited"],
  ["archived", "Archived"],
  ["all", "All requests"],
];
function statusTone(status: AccessStatus) {
  return ["invited", "accepted", "installed"].includes(status)
    ? "ready"
    : ["failed", "uncertain", "revoked"].includes(status)
    ? "attention"
    : "unknown";
}
export default function AccessRequests(
  { data, filter, offset }: {
    data: AccessRequestsDTO;
    filter: AccessFilter;
    offset: number;
  },
) {
  const router = useRouter();
  const running = useRef(false);
  const [selected, setSelected] = useState<string[]>([]);
  const [reviewing, setReviewing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [stepUp, setStepUp] = useState(false);
  const eligible = data.rows.filter((r) =>
    ["new", "failed"].includes(r.status)
  );
  function toggle(id: string) {
    setReviewing(false);
    setSelected((s) =>
      s.includes(id)
        ? s.filter((i) => i !== id)
        : s.length < MAX_BATCH
        ? [...s, id]
        : s
    );
  }
  async function command(payload: TestFlightRequest) {
    const response = await fetch("/api/admin/testflight", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        [ADMIN_CSRF_HEADER]: ADMIN_CSRF_VALUE,
      },
      body: JSON.stringify(payload),
    });
    const result = await response.json();
    if (!response.ok) {
      if (result.code === "mfa_step_up_required") setStepUp(true);
      throw new Error(result.error ?? "The request could not be updated.");
    }
    return result as { status: AccessStatus };
  }
  async function run(
    op: "invite" | "archive" | "restore" | "sync",
    ids: string[],
  ) {
    if (running.current) return;
    running.current = true;
    setBusy(true);
    setMessage("");
    setStepUp(false);
    setReviewing(false);
    let completed = 0;
    let attention = 0;
    try {
      for (const id of ids) {
        setMessage(
          `${op === "invite" ? "Sending invitations" : "Updating requests"} ${
            completed + 1
          } of ${ids.length}…`,
        );
        const result = await command({ op, id });
        completed++;
        if (!["invited", "accepted", "installed"].includes(result.status)) {
          attention++;
        }
      }
      setSelected([]);
      setMessage(
        op === "invite"
          ? `${completed - attention} invitation${
            completed - attention === 1 ? "" : "s"
          } confirmed by Apple.${
            attention
              ? ` ${attention} need a status check. Refresh those requests before trying again.`
              : ""
          }`
          : op === "sync"
          ? "Status checked with Apple. No email was sent."
          : op === "archive"
          ? "Requests archived. No email was sent."
          : "Request moved back to review.",
      );
    } catch (error) {
      setMessage(
        `${completed ? `${completed} completed. ` : ""}${
          error instanceof Error
            ? error.message
            : "Connection interrupted. Refresh request status before trying again."
        }`,
      );
    } finally {
      setSelected([]);
      running.current = false;
      setBusy(false);
      router.refresh();
    }
  }
  return (
    <>
      <div className={`${styles.metricGridThree} ${access.metrics}`}>
        <Metric
          label="To review"
          value={formatCount(data.counts.pending)}
          detail="New requests and anything needing attention"
        />
        <Metric
          label="Invited"
          value={formatCount(data.counts.invited)}
          detail="Includes accepted and installed testers"
        />
        <Metric
          label="Archived"
          value={formatCount(data.counts.archived)}
          detail="Kept for later; no invitation sent"
        />
      </div>
      <section className={styles.tablePanel} aria-labelledby="access-title">
        <header className={access.header}>
          <div>
            <h2 id="access-title">Access requests</h2>
            <p className={styles.smallMuted}>
              People who asked to try Plated. Launch-only subscribers stay on
              the launch list.
            </p>
          </div>
          <div className={access.connection}>
            <StatusPill
              status={data.connection.ready ? "ready" : "attention"}
              label={data.connection.ready ? "Apple connected" : "Needs setup"}
            />
            <p>
              {data.connection.ready
                ? `${data.connection.groupName} · Build ${data.connection.build}`
                : data.connection.message}
            </p>
          </div>
        </header>
        <nav className={access.filters} aria-label="Request status">
          {filters.map(([value, label]) => (
            <Link
              key={value}
              href={`/admin/waitlist?filter=${value}`}
              aria-current={filter === value ? "page" : undefined}
            >
              {label}
            </Link>
          ))}
        </nav>
        <div className={access.toolbar}>
          <label className={access.selectAll}>
            <input
              type="checkbox"
              aria-label="Select up to ten available requests"
              disabled={busy || !eligible.length}
              checked={selected.length > 0 &&
                eligible.slice(0, MAX_BATCH).every((r) =>
                  selected.includes(r.id)
                )}
              onChange={(e) => {
                setReviewing(false);
                setSelected(
                  e.target.checked
                    ? eligible.slice(0, MAX_BATCH).map((r) => r.id)
                    : [],
                );
              }}
            />
            <span>
              {selected.length
                ? `${selected.length} selected`
                : "Select requests"}
            </span>
          </label>
          <div className={access.buttons}>
            <button
              className={styles.textButton}
              disabled={!selected.length || busy}
              onClick={() => void run("archive", selected)}
            >
              Archive
            </button>
            <button
              className={styles.primaryButton}
              disabled={!selected.length || busy || !data.connection.ready}
              aria-expanded={reviewing}
              aria-controls="access-invitation-review"
              onClick={() => setReviewing(true)}
            >
              Review invitations
            </button>
          </div>
        </div>
        {reviewing && (
          <div
            className={access.review}
            id="access-invitation-review"
            role="region"
            aria-label="Review invitation batch"
          >
            <div>
              <h3>
                Invite {selected.length}{" "}
                {selected.length === 1 ? "person" : "people"} to Plated?
              </h3>
              <p>
                Apple will email each selected address an invitation to the{" "}
                {data.connection.groupName}{" "}
                TestFlight group. They’ll be able to test its available builds.
              </p>
              <ul
                className={access.recipients}
                aria-label="Invitation recipients"
              >
                {data.rows.filter((row) => selected.includes(row.id)).map(
                  (row) => <li key={row.id}>{row.email}</li>,
                )}
              </ul>
            </div>
            <div className={access.buttons}>
              <button
                className={styles.textButton}
                onClick={() => setReviewing(false)}
              >
                Cancel
              </button>
              <button
                className={styles.secondaryButton}
                onClick={() => void run("invite", selected)}
              >
                Send {selected.length}{" "}
                {selected.length === 1 ? "invitation" : "invitations"}
              </button>
            </div>
          </div>
        )}
        {message && <p className={access.feedback} role="status">{message}</p>}
        {stepUp && (
          <Link
            className={access.mfa}
            href="/admin/mfa?stepup=1&next=%2Fadmin%2Fwaitlist"
          >
            Verify MFA to continue
          </Link>
        )}
        {!data.rows.length
          ? (
            <EmptyState
              title={filter === "active" ? "All caught up" : "No requests here"}
              detail={filter === "active"
                ? "New early-access requests will appear here."
                : "Choose another status to see more requests."}
            />
          )
          : (
            <div className={styles.tableScroll}>
              <table className={`${styles.table} ${access.table}`}>
                <thead>
                  <tr>
                    <th scope="col">
                      <span className={access.srOnly}>Select</span>
                    </th>
                    <th scope="col">Person</th>
                    <th scope="col">Status</th>
                    <th scope="col">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {data.rows.map((row) => (
                    <tr key={row.id}>
                      <td>
                        <label className={access.checkbox}>
                          <input
                            type="checkbox"
                            aria-label={`Select ${row.email}`}
                            checked={selected.includes(row.id)}
                            disabled={busy ||
                              !["new", "failed"].includes(row.status) ||
                              (!selected.includes(row.id) &&
                                selected.length >= MAX_BATCH)}
                            onChange={() => toggle(row.id)}
                          />
                        </label>
                      </td>
                      <td>
                        <strong className={access.email}>{row.email}</strong>
                        <span className={styles.tableSubtext}>
                          Requested {formatWhen(row.requestedAt)}
                        </span>
                      </td>
                      <td>
                        <StatusPill
                          status={statusTone(row.status)}
                          label={accessStatusLabel[row.status]}
                        />
                        <span className={styles.tableSubtext}>
                          {row.status === "uncertain"
                            ? "Refresh status before another send."
                            : row.status === "sending"
                            ? "Check again in two minutes."
                            : row.invitedAt
                            ? `Recorded ${formatWhen(row.invitedAt)}`
                            : row.status === "failed"
                            ? "Apple did not confirm an invitation."
                            : row.status === "archived"
                            ? "No invitation sent."
                            : "Ready for your review."}
                        </span>
                        {row.checkedAt && (
                          <span className={styles.tableSubtext}>
                            Checked {formatWhen(row.checkedAt)}
                          </span>
                        )}
                      </td>
                      <td>
                        <div className={access.rowActions}>
                          {row.status === "archived"
                            ? (
                              <button
                                className={styles.textButton}
                                disabled={busy}
                                onClick={() => void run("restore", [row.id])}
                              >
                                Restore
                              </button>
                            )
                            : (
                              <>
                                <button
                                  className={styles.textButton}
                                  disabled={busy}
                                  onClick={() => void run("sync", [row.id])}
                                >
                                  Refresh status
                                </button>
                                {["new", "failed"].includes(row.status) && (
                                  <button
                                    className={styles.textButton}
                                    disabled={busy}
                                    onClick={() =>
                                      void run("archive", [row.id])}
                                  >
                                    Archive
                                  </button>
                                )}
                              </>
                            )}
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        <footer className={access.footer}>
          <p>
            Up to ten people per batch. Apple handles invitation emails; their
            status doesn’t confirm inbox delivery.
          </p>
          <div className={access.buttons}>
            {offset > 0 && (
              <Link
                className={styles.panelLink}
                href={`/admin/waitlist?filter=${filter}&offset=${
                  Math.max(0, offset - 50)
                }`}
              >
                Previous
              </Link>
            )}
            {offset + data.rows.length < data.totalCount && (
              <Link
                className={styles.panelLink}
                href={`/admin/waitlist?filter=${filter}&offset=${offset + 50}`}
              >
                Next page
              </Link>
            )}
          </div>
        </footer>
      </section>
      <p className={styles.smallMuted}>
        Archiving keeps the request for later and doesn’t remove a tester from
        Apple. Requests remain until the person asks Plated to delete them.{" "}
        <a
          href="https://appstoreconnect.apple.com/apps/6804332064/testflight"
          target="_blank"
          rel="noreferrer"
        >
          Open App Store Connect ↗
        </a>
      </p>
    </>
  );
}
