import { decodeOperations } from "../../../lib/admin/decode";
import { loadAdminPageData } from "../../../lib/admin/page-data";
import styles from "../../admin.module.css";
import { formatCount, formatWhen, Metric, PageHeader, Panel, ServiceError, StatusPill } from "../../components/UI";

export default async function OperationsPage() {
  const result = await loadAdminPageData({ op: "operations" }, decodeOperations);
  return (
    <div className={styles.pageStack}>
      <PageHeader eyebrow="Control plane" title="Operations" description="Configuration, delivery state and the current limits of what the server can prove." />
      {!result.ok ? <ServiceError result={result} /> : (() => {
        const operations = result.data.data;
        const pending = (operations.push.deliveryCounts.pending ?? 0) + (operations.push.deliveryCounts.claimed ?? 0);
        return (
          <>
            <div className={styles.metricGrid}>
              <Metric label="Active administrators" value={formatCount(operations.adminAuth.activePrincipalCount)} detail="Invite-only principals currently enabled" />
              <Metric label="Pending deliveries" value={formatCount(pending)} detail="Persisted work not yet accepted or failed" />
              <Metric label="Retryable" value={formatCount(operations.push.deliveryCounts.retryable)} detail="Transient APNs failures awaiting another attempt" />
              <Metric label="Retry limit" value={formatCount(operations.push.exhaustedRetryCount)} detail="Rows at the ten-attempt ceiling" />
            </div>

            <div className={styles.twoColumn}>
              <Panel title="Core services" detail={`Snapshot ${formatWhen(result.data.generatedAt)}`}>
                <ul className={styles.checkList}>
                  <li className={styles.checkRow}><div><p className={styles.checkLabel}>Database</p><p className={styles.tableSubtext}>Privileged tables respond through the Edge Function.</p></div><StatusPill status={operations.database.status} /></li>
                  <li className={styles.checkRow}><div><p className={styles.checkLabel}>APNs credentials</p><p className={styles.tableSubtext}>{operations.push.acceptedLabel} is the strongest delivery claim available.</p></div><StatusPill status={operations.push.configured ? "ready" : "attention"} label={operations.push.configured ? "Configured" : "Missing"} /></li>
                  <li className={styles.checkRow}><div><p className={styles.checkLabel}>Founder authentication</p><p className={styles.tableSubtext}>MFA and signed server requests are required.</p></div><StatusPill status={operations.adminAuth.mfaRequired && operations.adminAuth.signedRequestsRequired ? "ready" : "attention"} /></li>
                  <li className={styles.checkRow}><div><p className={styles.checkLabel}>Device ownership</p><p className={styles.tableSubtext}>Push tokens have global ownership and sign-out unregister support.</p></div><StatusPill status={operations.deviceDirectory.tokenOwnership === "global" && operations.deviceDirectory.signOutUnregisterSupported ? "ready" : "attention"} /></li>
                  <li className={styles.checkRow}><div><p className={styles.checkLabel}>Phone hashing</p><p className={styles.tableSubtext}>Directory phone hashes require the server-only pepper.</p></div><StatusPill status={operations.phoneHashing.configured ? "ready" : "attention"} label={operations.phoneHashing.configured ? "Configured" : "Missing"} /></li>
                </ul>
              </Panel>
              <Panel title="Integrations" detail="A missing integration stays visible as a coverage gap.">
                <ul className={styles.checkList}>
                  <li className={styles.checkRow}><div><p className={styles.checkLabel}>Instacart</p><p className={styles.tableSubtext}>{operations.integrations.instacart.reason}</p></div><StatusPill status="unavailable" label="Coverage gap" /></li>
                  <li className={styles.checkRow}><div><p className={styles.checkLabel}>App Store Connect</p><p className={styles.tableSubtext}>Authoritative release status and build readiness are not connected to this service.</p></div><StatusPill status="unavailable" label="Coverage gap" /></li>
                </ul>
              </Panel>
            </div>

            <Panel title="Data handling checks" detail="Operational facts that protect user privacy and delivery correctness.">
              <div className={styles.proseGrid}>
                <div><h3>Invitation links</h3><p>{operations.invitations.shareUrlsStored ? "The server reports stored share URLs and needs review." : `Share URLs are not stored. Remaining invitation metadata expires after ${operations.invitations.metadataRetentionDays} days.`}</p></div>
                <div><h3>Latest device registration</h3><p>{operations.deviceDirectory.lastRegistrationAt ? formatWhen(operations.deviceDirectory.lastRegistrationAt) : "No device has registered yet."} Registration is an operational check-in, not an activity event.</p></div>
                <div><h3>Admin retention</h3><p>Preview intents expire after {operations.adminRetention.previewIntentMinutes} minutes and delivery can resume for {operations.adminRetention.resumableDeliveryHours} hours. Terminal delivery tokens are cleared {operations.adminRetention.terminalDeliveryTokensCleared}.</p></div>
              </div>
            </Panel>
          </>
        );
      })()}
    </div>
  );
}
