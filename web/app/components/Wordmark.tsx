import styles from "./Wordmark.module.css";

// The wordmark to the same rule the app draws it by (PlatedWordmark in
// Theme.swift): lowercase Gabarito medium, tracking -0.022em, tomato dot at
// 0.27em seated 0.34em down. Plated has no logo badge. Do not invent one.
export default function Wordmark({ size = 26 }: { size?: number }) {
  return (
    <span
      className={styles.mark}
      style={{ fontSize: size }}
      role="img"
      aria-label="Plated"
    >
      <span className={styles.word}>plated</span>
      <i className={styles.dot} aria-hidden="true" />
    </span>
  );
}
