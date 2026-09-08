import Link from "next/link";
import { decodeOverview } from "../../lib/admin/decode";
import { loadAdminPageData } from "../../lib/admin/page-data";
import styles from "../admin.module.css";
import { CoverageGap, formatCount, formatWhen, Metric, PageHeader, Panel, ServiceError, StatusPill } from "../components/UI";

export default async function FounderOverviewPage() {
  const result = await loadAdminPageData({ op: "overview" }, decodeOverview);

  return (
    <div className={styles.pageStack}>
      <PageHeader
        eyebrow="Founder console"
        title="What Plated can see"
        description="A current operational view of the public directory, notification registrations, waitlist and founder announcements."
        action={<Link className={styles.primaryLink} href="/admin/announcements">New announcement</Link>}
      />
      {!result.ok ? <ServiceError result={result} /> : (() => {
        const overview = result.data.data;
        const latest = overview.announcements[0];
        return (
          <>
            <div className={styles.metricGrid}>
              <Metric label="Directory accounts" value={formatCount(overview.accounts.directoryCount)} detail="Registered with Plated's public directory" />
              <Metric label="Eligible devices" value={formatCount(overview.devices.eligibleForNewsCount)} detail={`${formatCount(overview.devices.registeredCount)} registrations in total`} />
              <Metric label="Waitlist" value={formatCount(overview.waitlist.totalCount)} detail="Email addresses awaiting launch" />
              <Metric label="Invites, 24 hours" value={formatCount(overview.invitations.last24HoursCount)} detail={`Metadata expires after ${overview.invitations.retentionDays} days`} />
            </div>

            <div className={styles.twoColumn}>
              <Panel title="Notification eligibility" detail="Settings reported during device registration. They do not measure app activity.">
                <dl className={styles.definitionGrid}>
                  <div><dt>Eligible for News</dt><dd>{overview.devices.eligibleForNewsCount}</dd></div>
                  <div><dt>iOS denied</dt><dd>{overview.devices.deniedNotificationCount}</dd></div>
                  <div><dt>Authorization unknown</dt><dd>{overview.devices.unknownAuthorizationCount}</dd></div>
                  <div><dt>Total registrations</dt><dd>{overview.devices.registeredCount}</dd></div>
                </dl>
                <Link className={styles.panelLink} href="/admin/people">Review registrations</Link>
              </Panel>
              <Panel title="Latest announcement" detail={latest ? `Created ${formatWhen(latest.createdAt)}` : "No announcement has been prepared."}>
                {latest ? (
                  <>
                    <div className={styles.releaseLine}><span className={styles.releaseBuild}>{latest.acceptedCount} / {latest.targetedCount}</span><StatusPill status={latest.status} /></div>
                    <p className={styles.bodyMuted}>{latest.acceptedLabel}. {latest.pendingCount ? `${latest.pendingCount} still pending.` : "No pending deliveries."}</p>
                  </>
                ) : <p className={styles.bodyMuted}>The delivery history is empty.</p>}
                <Link className={styles.panelLink} href="/admin/announcements">Open announcement history</Link>
              </Panel>
            </div>

            <Panel title="Registration mix" detail={`Server snapshot ${formatWhen(result.data.generatedAt)}`}>
              <div className={styles.twoColumn}>
                <dl className={styles.sourceList}>
                  {Object.entries(overview.devices.byReleaseChannel).map(([channel, value]) => <div key={channel}><dt>{channel.replaceAll("_", " ")}</dt><dd>{value}</dd></div>)}
                </dl>
                <dl className={styles.sourceList}>
                  {Object.entries(overview.devices.byGateway).map(([gateway, value]) => <div key={gateway}><dt>{gateway} APNs</dt><dd>{value}</dd></div>)}
                </dl>
              </div>
            </Panel>

            <div className={styles.twoColumn}>
              <Panel title="Centrally readable" detail="Limited records needed to operate the service.">
                <ul className={styles.plainList}>{overview.privacyBoundary.centrallyReadable.map((item) => <li key={item}>{item}</li>)}</ul>
              </Panel>
              <Panel title="Private in iCloud" detail="These categories never enter the founder control plane.">
                <CoverageGap title="Household content" detail={overview.privacyBoundary.privateInCloudKit.join(", ") + "."} href="/admin/releases" />
              </Panel>
            </div>
          </>
        );
      })()}
    </div>
  );
}
