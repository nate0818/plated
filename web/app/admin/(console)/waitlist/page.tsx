import Link from "next/link";
import AccessExport from "../../components/AccessExport";
import { decodeWaitlist } from "../../../lib/admin/decode";
import { loadAdminPageData } from "../../../lib/admin/page-data";
import styles from "../../admin.module.css";
import { EmptyState, formatCount, formatWhen, Metric, PageHeader, Panel, ServiceError } from "../../components/UI";

export const metadata = { title: "Waitlist" };

export default async function WaitlistPage({ searchParams }: { searchParams: Promise<{ cursor?: string }> }) {
  const params = await searchParams;
  const cursor = typeof params.cursor === "string" ? params.cursor.slice(0, 100) : undefined;
  const result = await loadAdminPageData({ op: "waitlist", limit: 50, ...(cursor ? { cursor } : {}) }, decodeWaitlist);

  return (
    <div className={styles.pageStack}>
      <PageHeader title="Waitlist" />
      {!result.ok ? <ServiceError result={result} /> : (
        <>
          <div className={styles.metricGridThree}>
            <Metric label="Saved addresses" value={formatCount(result.data.data.totalCount)} detail="Requests and launch signups" />
            <Metric label="Invitations" value="By email" detail="Reviewed in batches" />
            <Metric label="Address access" value="Protected" detail="Founder export with fresh MFA" />
          </div>
          <div className={styles.twoColumnWide}>
            <section className={styles.tablePanel} aria-labelledby="waitlist-table-title">
              <header className={styles.tableHeader}><div><h2 id="waitlist-table-title">Recent signups</h2><p>Snapshot {formatWhen(result.data.generatedAt)}</p></div></header>
              {result.data.data.rows.length === 0 ? <EmptyState title="No waitlist entries" detail="Signups from plated.food appear here." /> : (
                <div className={styles.tableScroll}>
                  <table className={styles.table}>
                    <thead><tr><th>Email</th><th>Source</th><th>Joined</th></tr></thead>
                    <tbody>{result.data.data.rows.map((row) => <tr key={`${row.emailMasked}:${row.joinedAt}`}><td><strong>{row.emailMasked}</strong></td><td>{row.source === "plated.food/early-access" ? "Early access" : row.source === "plated.food" ? "Launch list" : row.source ?? "Not recorded"}</td><td>{formatWhen(row.joinedAt)}</td></tr>)}</tbody>
                  </table>
                </div>
              )}
              <footer className={styles.tableFooter}>
                <p>Addresses stay masked in this view. The founder can download early-access requests after confirming MFA.</p>
                {result.data.data.nextCursor ? <Link className={styles.panelLink} href={`/admin/waitlist?cursor=${encodeURIComponent(result.data.data.nextCursor)}`}>Next page</Link> : null}
              </footer>
            </section>
            <Panel title="Invite a batch">
              {result.data.data.exportAvailable ? <AccessExport /> : <p className={styles.smallMuted}>Request downloads are available to the founder after fresh MFA.</p>}
              <p className={styles.smallMuted}>Review the downloaded addresses, then add the people you choose to an external testing group in App Store Connect. Apple sends the invitation; downloading a list does not send one.</p>
              <a className={styles.panelLink} href="https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/" target="_blank" rel="noreferrer">Apple’s invitation guide ↗</a>
            </Panel>
            <Panel title="Retention">
              <p className={styles.bodyMuted}>{result.data.data.retention}</p>
              <p className={styles.smallMuted}>Deletion requests go through the privacy inbox.</p>
            </Panel>
          </div>
        </>
      )}
    </div>
  );
}
