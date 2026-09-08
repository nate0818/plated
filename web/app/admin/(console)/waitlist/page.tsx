import Link from "next/link";
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
      <PageHeader title="Waitlist" description="Launch demand from plated.food. Email addresses stay masked in this view and are never exported by the console." />
      {!result.ok ? <ServiceError result={result} /> : (
        <>
          <div className={styles.metricGridThree}>
            <Metric label="Waiting" value={formatCount(result.data.data.totalCount)} detail="Stored email addresses" />
            <Metric label="Raw address access" value="Unavailable" detail="The console receives masked addresses only" />
            <Metric label="Trend analytics" value="Unavailable" detail="No acquisition analytics source is connected" />
          </div>
          <div className={styles.twoColumnWide}>
            <section className={styles.tablePanel} aria-labelledby="waitlist-table-title">
              <header className={styles.tableHeader}><div><h2 id="waitlist-table-title">Recent signups</h2><p>Snapshot {formatWhen(result.data.generatedAt)}</p></div></header>
              {result.data.data.rows.length === 0 ? <EmptyState title="No waitlist entries" detail="New signups from plated.food will appear here." /> : (
                <div className={styles.tableScroll}>
                  <table className={styles.table}>
                    <thead><tr><th>Email</th><th>Source</th><th>Joined</th></tr></thead>
                    <tbody>{result.data.data.rows.map((row) => <tr key={`${row.emailMasked}:${row.joinedAt}`}><td><strong>{row.emailMasked}</strong></td><td>Not recorded</td><td>{formatWhen(row.joinedAt)}</td></tr>)}</tbody>
                  </table>
                </div>
              )}
              <footer className={styles.tableFooter}>
                <p>Raw addresses remain available only to the server workflow that sends the launch notice or fulfills deletion requests.</p>
                {result.data.data.nextCursor ? <Link className={styles.panelLink} href={`/admin/waitlist?cursor=${encodeURIComponent(result.data.data.nextCursor)}`}>Next page</Link> : null}
              </footer>
            </section>
            <Panel title="Retention" detail="The API states the policy applied to this dataset.">
              <p className={styles.bodyMuted}>{result.data.data.retention}</p>
              <p className={styles.smallMuted}>This view cannot reveal or export raw addresses. Deletion requests are handled through the privacy inbox.</p>
            </Panel>
          </div>
        </>
      )}
    </div>
  );
}
