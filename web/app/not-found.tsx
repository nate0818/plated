import type { Metadata } from "next";
import Link from "next/link";
import Wordmark from "./components/Wordmark";
import Kitchen from "./components/Kitchen";
import styles from "./not-found.module.css";

export const metadata: Metadata = {
  title: "Sent back to the kitchen",
};

export default function NotFound() {
  return (
    <div className={styles.page}>
      <header className={styles.header}>
        <Link href="/" aria-label="Plated home" className={styles.home}>
          <Wordmark size={26} />
        </Link>
      </header>

      <main className={styles.main}>
        <h1 className={styles.title}>
          That page got sent
          <br />
          back to the kitchen.
        </h1>
        <p className={`${styles.lede} secondary`}>
          It was never on the menu. The kitchen is open, though. Tap the plate.
        </p>

        <Kitchen />

      </main>
    </div>
  );
}
