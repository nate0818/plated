import Link from "next/link";
import Wordmark from "./Wordmark";
import Ketchup404Scene from "./Ketchup404Scene";
import styles from "./Ketchup404.module.css";

export default function Ketchup404() {
  return (
    <div className={styles.page}>
      <header className={styles.header}>
        <Link href="/" aria-label="Plated home" className={styles.wordmark}>
          <Wordmark size={30} />
        </Link>
        <Link href="/" className={styles.home}>Back to home <span aria-hidden="true">↗</span></Link>
      </header>
      <main className={styles.main}>
        <Ketchup404Scene />
      </main>
      <footer className={styles.footer}>404 / Page not found</footer>
    </div>
  );
}
