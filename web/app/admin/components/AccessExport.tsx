"use client";

import Link from "next/link";
import { useState } from "react";
import { ADMIN_CSRF_HEADER, ADMIN_CSRF_VALUE } from "../../lib/admin/contracts";
import styles from "../admin.module.css";
import { csvCell } from "../../lib/admin/csv";

export default function AccessExport() {
  const [busy, setBusy] = useState(false);
  const [cursor, setCursor] = useState<string | null>(null);
  const [message, setMessage] = useState("");
  const [stepUp, setStepUp] = useState(false);
  const [started, setStarted] = useState(false);

  async function download() {
    setBusy(true); setMessage(""); setStepUp(false);
    try {
      const response = await fetch("/api/admin/waitlist-export", { method: "POST", headers: { "Content-Type": "application/json", [ADMIN_CSRF_HEADER]: ADMIN_CSRF_VALUE }, body: JSON.stringify({ cursor }) });
      const result = await response.json();
      if (!response.ok) { setStepUp(result.code === "mfa_step_up_required"); throw new Error(result.error ?? "The list could not be downloaded."); }
      const data = result.data;
      if (!Array.isArray(data?.rows) || data.rows.some((row: { email?: unknown; requestedAt?: unknown }) => typeof row.email !== "string" || typeof row.requestedAt !== "string")) throw new Error("The request list was unreadable.");
      const csv = ["Email,Requested", ...data.rows.map((row: { email: string; requestedAt: string }) => `${csvCell(row.email)},${csvCell(row.requestedAt)}`)].join("\r\n");
      const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
      const link = document.createElement("a"); link.href = url; link.download = `plated-access-${new Date().toISOString().slice(0, 10)}.csv`; link.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      setCursor(typeof data.nextCursor === "string" ? data.nextCursor : null); setStarted(true);
      setMessage(`${data.rows.length} requests downloaded. No invitations were sent.${data.nextCursor ? " The next batch is ready to download." : " You’ve reached the end of the list."}`);
    } catch (error) { setMessage(error instanceof Error ? error.message : "The list could not be downloaded."); }
    finally { setBusy(false); }
  }
  return <div>
    <p className={styles.smallMuted}>Download up to 100 early-access requests at a time, oldest first. Launch-only signups are excluded.</p>
    <button className={styles.secondaryButton} disabled={busy} onClick={download}>{busy ? "Preparing…" : cursor ? "Download next batch" : started ? "Download from the start" : "Download requests (.csv)"}</button>
    {message && <p className={styles.smallMuted} role="status">{message}</p>}
    {stepUp && <Link className={styles.panelLink} href="/admin/mfa?stepup=1&next=%2Fadmin%2Fwaitlist">Verify MFA to download</Link>}
  </div>;
}
