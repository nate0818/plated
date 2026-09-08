import Link from "next/link";
import { decodeAudit } from "../../../lib/admin/decode";
import { loadAdminPageData } from "../../../lib/admin/page-data";
import styles from "../../admin.module.css";
import { AuditList, formatCount, formatWhen, PageHeader, Panel, ServiceError } from "../../components/UI";

export const metadata = { title: "Audit trail" };

export default async function AuditPage({ searchParams }: { searchParams: Promise<{ cursor?: string }> }) {
  const params = await searchParams;
  const cursor = typeof params.cursor === "string" ? params.cursor.slice(0, 100) : undefined;
  const result = await loadAdminPageData({ op: "audit", limit: 100, ...(cursor ? { cursor } : {}) }, decodeAudit);

  return (
    <div className={styles.pageStack}>
      <PageHeader title="Audit trail" description="Append-only" />
      {!result.ok ? <ServiceError result={result} /> : (
        <Panel title="Administrative events" detail={`${formatCount(result.data.data.totalCount)} total · snapshot ${formatWhen(result.data.generatedAt)}`}>
          <AuditList rows={result.data.data.rows} />
          <div className={styles.tableFooter}>
            <p>{result.data.data.appendOnly ? "Existing entries cannot be edited or deleted through the admin service." : "Audit immutability could not be confirmed."}</p>
            {result.data.data.nextCursor ? <Link className={styles.panelLink} href={`/admin/audit?cursor=${encodeURIComponent(result.data.data.nextCursor)}`}>Next page</Link> : null}
          </div>
        </Panel>
      )}
    </div>
  );
}
