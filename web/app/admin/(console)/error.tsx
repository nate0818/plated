"use client";

import styles from "../admin.module.css";

export default function ConsoleError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <div className={styles.serviceError} role="alert">
      <p className={styles.serviceErrorTitle}>This view could not be drawn</p>
      <p>The console did not expose any private data. Try loading the view again.</p>
      <button className={styles.secondaryButton} type="button" onClick={reset}>Try again</button>
    </div>
  );
}
