import styles from "./Wordmark.module.css";

// Editorial identity: the same Newsreader wordmark as PlatedMasthead.
export default function Wordmark({ size = 26 }: { size?: number }) {
  return (
    <span
      className={styles.mark}
      style={{ fontSize: size }}
      role="img"
      aria-label="Plated"
    >
      Plated
    </span>
  );
}
