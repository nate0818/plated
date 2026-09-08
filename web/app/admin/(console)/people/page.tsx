import Link from "next/link";
import { decodePeople } from "../../../lib/admin/decode";
import { loadAdminPageData } from "../../../lib/admin/page-data";
import styles from "../../admin.module.css";
import { EmptyState, formatCount, formatWhen, PageHeader, ServiceError, StatusPill } from "../../components/UI";

function notificationState(news: boolean | null, authorization: string | null, eligible: number) {
  if (news === null || authorization === null) return { label: "Unknown", status: "unknown" };
  if (!news) return { label: "news off", status: "unavailable" };
  if (authorization === "denied") return { label: "iOS off", status: "attention" };
  if (eligible > 0) return { label: "Eligible", status: "ready" };
  return { label: authorization.replaceAll("_", " "), status: "unknown" };
}

export default async function PeoplePage({ searchParams }: { searchParams: Promise<{ cursor?: string }> }) {
  const params = await searchParams;
  const cursor = typeof params.cursor === "string" ? params.cursor.slice(0, 100) : undefined;
  const result = await loadAdminPageData(
    { op: "people", limit: 50, ...(cursor ? { cursor } : {}) },
    decodePeople,
  );

  return (
    <div className={styles.pageStack}>
      <PageHeader eyebrow="Directory" title="People" description="Operational registration details only. Personal IDs, phone hashes, API tokens and push tokens never leave the server." />
      {!result.ok ? <ServiceError result={result} /> : (
        <section className={styles.tablePanel} aria-labelledby="people-table-title">
          <header className={styles.tableHeader}>
            <div><h2 id="people-table-title">Directory registrations</h2><p>{formatCount(result.data.data.totalCount)} total · snapshot {formatWhen(result.data.generatedAt)}</p></div>
          </header>
          {result.data.data.rows.length === 0 ? <EmptyState title="No registered people" detail="Directory registrations will appear after the app registers an account." /> : (
            <div className={styles.tableScroll}>
              <table className={styles.table}>
                <thead><tr><th>Person</th><th>Directory</th><th>Devices</th><th>News reach</th></tr></thead>
                <tbody>
                  {result.data.data.rows.map((person) => {
                    const reach = notificationState(person.newsEnabled, person.notificationAuthorization, person.eligibleDeviceCount);
                    return (
                      <tr key={person.personKey}>
                        <td><strong>{person.displayName || "Name unavailable"}</strong><span className={styles.tableSubtext}>{person.phoneOnFile ? "Phone on file" : "No phone on file"}</span></td>
                        <td>{formatWhen(person.lastDirectoryRegistrationAt)}<span className={styles.tableSubtext}>Joined {formatWhen(person.joinedAt)}</span></td>
                        <td>{person.deviceCount}<span className={styles.tableSubtext}>{person.latestBuild ? `Latest build ${person.latestBuild}` : "Build unknown"}{person.latestVersion ? ` · ${person.latestVersion}` : ""}{person.releaseChannel ? ` · ${person.releaseChannel.replaceAll("_", " ")}` : ""}</span></td>
                        <td><StatusPill status={reach.status} label={reach.label} /><span className={styles.tableSubtext}>{person.eligibleDeviceCount} eligible{person.lastDeviceRegistrationAt ? ` · refreshed ${formatWhen(person.lastDeviceRegistrationAt)}` : " · no device registration"}</span></td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
          <footer className={styles.tableFooter}>
            <p>Registration times describe directory and notification setup, not app activity.</p>
            {result.data.data.nextCursor ? (
              <Link className={styles.panelLink} href={`/admin/people?cursor=${encodeURIComponent(result.data.data.nextCursor)}`}>Next page</Link>
            ) : null}
          </footer>
        </section>
      )}
    </div>
  );
}
