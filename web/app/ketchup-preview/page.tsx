import type { Metadata } from "next";
import Link from "next/link";
import Wordmark from "../components/Wordmark";
import KetchupScene from "./KetchupScene";
import styles from "./page.module.css";

export const metadata: Metadata = {
  title: "Out of sauce",
  robots: { index: false, follow: false },
};

export default function KetchupPreview() {
  return (
    <div className={styles.page}>
      <header className={styles.header}>
        <Link href="/" aria-label="Plated home" className={styles.wordmark}>
          <Wordmark size={30} />
        </Link>
        <Link href="/" className={styles.home}>Back to home <span aria-hidden="true">↗</span></Link>
      </header>
      <main className={styles.main}>
        <KetchupScene />
      </main>
      <footer className={styles.footer}>404 / Page not found</footer>
    </div>
  );
}
