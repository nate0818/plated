import { decodeReleases } from "../../../lib/admin/decode";
import { loadAdminPageData } from "../../../lib/admin/page-data";
import styles from "../../admin.module.css";
import { CoverageGap, formatWhen, PageHeader, Panel, ServiceError, StatusPill } from "../../components/UI";

export const metadata = { title: "Releases" };

export default async function ReleasesPage() {
  const result = await loadAdminPageData({ op: "releases" }, decodeReleases);
  return (
    <div className={styles.pageStack}>
      <PageHeader title="Releases" />
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
                <CoverageGap title="Product engagement" detail="No analytics source. No active people, retention or funnels." />
                <CoverageGap title="Household content" detail="Recipes, plans, groceries, Table posts and photos stay in private iCloud." />
                <CoverageGap title="Crashes and performance" detail="No crash reporter connected." />
                <CoverageGap title="Revenue and subscriptions" detail="No commerce source connected." />
                <CoverageGap title="Support" detail="Privacy inbox not connected." />
                <CoverageGap title="Notification reads" detail="Apple reports acceptance, not whether anyone saw it." />
              </div>
            </section>
          </>
        );
      })()}
    </div>
  );
}
