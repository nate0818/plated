import Link from "next/link";
import AccessRequests from "../../components/AccessRequests";
import { callAdminEdge } from "../../../lib/admin/bff";
import { decodeAccessRequests } from "../../../lib/admin/testflight";
import type { AccessFilter } from "../../../lib/admin/contracts";
import styles from "../../admin.module.css";
import { PageHeader, ServiceError } from "../../components/UI";
export const metadata = { title: "Early access" };
export default async function WaitlistPage(
  { searchParams }: {
    searchParams: Promise<{ filter?: string; offset?: string }>;
  },
) {
  const params = await searchParams;
  const filter: AccessFilter =
    ["active", "invited", "archived", "all"].includes(params.filter ?? "")
      ? params.filter as AccessFilter
      : "active";
  const candidate = Number(params.offset ?? 0);
  const offset =
    Number.isSafeInteger(candidate) && candidate >= 0 && candidate <= 10_000_000
      ? candidate
      : 0;
  const result = await callAdminEdge<unknown>("testflight", {
    op: "list",
    filter,
    offset,
  });
  let data;
  if (result.ok) {
    try {
      data = decodeAccessRequests(result.data);
    } catch { /* Fail closed on provider contract drift. */ }
  }
  return (
    <div className={styles.pageStack}>
      <PageHeader
        title="Early access"
        description="Choose who joins Plated. Send their TestFlight invitation here, then follow their progress."
      />
      {!result.ok
        ? result.code === "mfa_step_up_required"
          ? (
            <section className={styles.panel}>
              <h2 className={styles.panelTitle}>Verify to manage requests</h2>
              <p className={styles.bodyMuted}>
                Request emails and invitation controls are protected by a fresh
                MFA check.
              </p>
              <Link
                className={styles.primaryLink}
                href="/admin/mfa?stepup=1&next=%2Fadmin%2Fwaitlist"
              >
                Verify MFA
              </Link>
            </section>
          )
          : <ServiceError result={result} />
        : data
        ? (
          <AccessRequests
            key={`${filter}:${offset}`}
            data={data}
            filter={filter}
            offset={offset}
          />
        )
        : (
          <p role="alert">
            Access requests are temporarily unavailable. Refresh to try again.
          </p>
        )}
    </div>
  );
}
