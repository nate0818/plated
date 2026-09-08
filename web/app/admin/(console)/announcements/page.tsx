import { adminEdgeConfigured } from "../../../lib/admin/bff";
import { getAdminAuthState } from "../../../lib/admin/auth";
import { decodeAnnouncements } from "../../../lib/admin/decode";
import { loadAdminPageData } from "../../../lib/admin/page-data";
import styles from "../../admin.module.css";
import AnnouncementConsole from "../../components/AnnouncementConsole";
import { PageHeader, ServiceError } from "../../components/UI";

export const metadata = { title: "Announcements" };

export default async function AnnouncementsPage({ searchParams }: { searchParams: Promise<{ cursor?: string }> }) {
  const params = await searchParams;
  const cursor = typeof params.cursor === "string" ? params.cursor.slice(0, 100) : undefined;
  const [history, configuration, auth] = await Promise.all([
    loadAdminPageData({ op: "announcements", limit: 50, ...(cursor ? { cursor } : {}) }, decodeAnnouncements),
    Promise.resolve(adminEdgeConfigured()),
    getAdminAuthState(),
  ]);

  return (
    <div className={styles.pageStack}>
      <PageHeader title="Announcements" description="Preview an immutable audience snapshot, authorize that exact intent, then follow each delivery attempt in the audit trail." />
      {!history.ok ? <ServiceError result={history} /> : (
        <AnnouncementConsole
          history={history.data.data.rows}
          totalCount={history.data.data.totalCount}
          nextCursor={history.data.data.nextCursor}
          commandReady={configuration.command && configuration.secret}
          stepUpRequired={auth.kind === "ready" && !auth.recentTotp}
        />
      )}
    </div>
  );
}
