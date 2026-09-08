import styles from "../admin.module.css";

export default function ConsoleLoading() {
  return (
    <div className={styles.loading} aria-live="polite">
      <span className={styles.loadingDot} />
      <span>Loading current operations…</span>
    </div>
  );
}
