import type { Metadata } from "next";
import { Suspense } from "react";
import Link from "next/link";
import Wordmark from "../components/Wordmark";
import Invitation from "./Invitation";
import Fallback from "./Fallback";
import styles from "./page.module.css";

export const metadata: Metadata = {
  title: "A seat at the table",
  description: "Someone kept you a seat at their table on Plated.",
  openGraph: {
    title: "A seat at the table",
    description: "Someone kept you a seat at their table on Plated.",
  },
  // An invitation is addressed to one person. Search engines are not invited.
  robots: { index: false, follow: false },
  alternates: { canonical: "/join" },
};

// A phone that has Plated never gets here: iOS opens the app straight from
// the link, because /join is in the association file. So the single action
// on this page is getting the app. Everything else is a hairline or a whisper.
export default function Join() {
  return (
    <div className={styles.page}>
      <header className={styles.header}>
        <Link href="/" aria-label="Plated home" className={styles.home}>
          <Wordmark size={26} />
        </Link>
      </header>

      <main className={styles.main}>
        <Suspense fallback={<Fallback />}>
          <Invitation />
        </Suspense>

        <div className={styles.facts}>
          <p className={styles.fact}>
            <i className={styles.dot} aria-hidden="true" />
            <span>
              <b>Invite only.</b> Nothing here is public, and nobody sees a table
              they weren&rsquo;t given a seat at.
            </span>
          </p>
          <p className={styles.fact}>
            <i className={styles.dot} aria-hidden="true" />
            <span>
              <b>Your seat is held.</b> Install Plated, tap this link again, and
              you&rsquo;re in.
            </span>
          </p>
          <p className={styles.fact}>
            <i className={styles.dot} aria-hidden="true" />
            <span>
              <b>No account to make.</b> Sign in with Apple, and that&rsquo;s the
              whole setup.
            </span>
          </p>
        </div>
      </main>

      <footer className={styles.footer}>
        <Link href="/privacy">Privacy</Link>
      </footer>
    </div>
  );
}
