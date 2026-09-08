import { decodeReleases } from "../../../lib/admin/decode";
import { loadAdminPageData } from "../../../lib/admin/page-data";
import styles from "../../admin.module.css";
import { CoverageGap, formatWhen, PageHeader, Panel, ServiceError, StatusPill } from "../../components/UI";

export default async function ReleasesPage() {
  const result = await loadAdminPageData({ op: "releases" }, decodeReleases);
  return (
    <div className={styles.pageStack}>
      <PageHeader eyebrow="Releases & coverage" title="Know what the numbers can say" description="Device-reported builds, an explicit authoritative-source status and gaps where Plated has no instrumentation." />
      {!result.ok ? <ServiceError result={result} /> : (() => {
        const releases = result.data.data;
        const channels = Object.entries(releases.deviceReported);
        return (
          <>
            <Panel title="Authoritative release source" detail={`Snapshot ${formatWhen(result.data.generatedAt)}`}>
              <div className={styles.releaseHero}>
                <div><p className={styles.releaseBuild}>{releases.authoritativeSource.provider}</p><p className={styles.bodyMuted}>{releases.authoritativeSource.reason}</p></div>
                <StatusPill status={releases.authoritativeSource.status} label={releases.authoritativeSource.connected ? "Connected" : "Coverage gap"} />
              </div>
            </Panel>

            <Panel title="Builds reported by devices" detail={releases.caveat}>
              {channels.length ? (
                <div className={styles.releaseCards}>
                  {channels.map(([channel, item]) => (
                    <article className={styles.releaseCard} key={channel}>
                      <p className={styles.metricLabel}>{channel.replaceAll("_", " ")}</p>
                      <p className={styles.releaseBuild}>{item.highestBuild === null ? "Build unknown" : `Build ${item.highestBuild}`}</p>
                      <p className={styles.bodyMuted}>{item.deviceCount} registered {item.deviceCount === 1 ? "device" : "devices"}</p>
                      <p className={styles.tableSubtext}>{item.versions.length ? `Versions ${item.versions.join(", ")}` : "No version reported"}</p>
                    </article>
                  ))}
                </div>
              ) : <p className={styles.bodyMuted}>No device has reported a build or release channel.</p>}
            </Panel>

            <section className={styles.coverageSection} aria-labelledby="coverage-heading">
              <div><p className={styles.eyebrow}>Coverage map</p><h2 id="coverage-heading" className={styles.sectionTitle}>Deliberate boundaries and missing sources</h2></div>
              <div className={styles.coverageGrid}>
                <CoverageGap title="Product engagement" detail="Plated has no app analytics or tracking. The console cannot report daily active people, retention, funnels or feature use." />
                <CoverageGap title="Household content" detail="Recipes, plans, grocery lists, Table posts and photos live in private CloudKit databases that the developer cannot read." />
                <CoverageGap title="Crashes and performance" detail="No crash or app-performance provider is connected, so this console has no crash-free-session or latency metric." />
                <CoverageGap title="Revenue and subscriptions" detail="Plated has no connected commerce source. Revenue, conversion, refunds and subscription health are unavailable." />
                <CoverageGap title="Support" detail="The privacy inbox is not connected to the console. Messages and response time are unavailable here." />
                <CoverageGap title="Notification reads" detail="Apple reports whether it accepted a push request, not whether a person saw or acted on it. No read rate is inferred." />
              </div>
            </section>
          </>
        );
      })()}
    </div>
  );
}
