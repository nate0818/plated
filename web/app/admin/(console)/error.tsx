"use client";

import styles from "../admin.module.css";

export default function ConsoleError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <div className={styles.serviceError} role="alert">
      <p className={styles.serviceErrorTitle}>We couldn’t load this page</p>
      <p>Please try again in a moment.</p>
      <button className={styles.secondaryButton} type="button" onClick={reset}>Try again</button>
    </div>
  );
}
