"use client";

import Link from "next/link";
import SiteFrame from "./components/SiteFrame";
import styles from "./status.module.css";

export default function SiteError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return <SiteFrame action="home">
    <main id="main" className={styles.main}>
      <p className={styles.eyebrow}>Something went wrong</p>
      <h1>We couldn’t<br />load this page</h1>
      <p className={styles.description}>Please try again in a moment, or head back to Plated.</p>
      <div className={styles.actions}><button type="button" onClick={reset}>Try again</button><Link href="/">Back to Plated</Link></div>
    </main>
  </SiteFrame>;
}
