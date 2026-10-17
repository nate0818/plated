import type { Metadata } from "next";
import Link from "next/link";
import AppShowcase from "../components/AppShowcase";
import WaitlistForm from "../components/WaitlistForm";
import Wordmark from "../components/Wordmark";
import styles from "./page.module.css";

export const metadata: Metadata = {
  title: "Request early access",
  description: "Request an invitation to try Plated with your household. Early access for iPhone and iPad.",
  alternates: { canonical: "/early-access" },
};

export default function EarlyAccess() {
  return <>
    <header className={styles.header}>
      <Link href="/#main" aria-label="Plated home"><Wordmark size={32} /></Link>
      <Link href="/#main" className={styles.back}><span aria-hidden="true">←</span> Back to Plated</Link>
    </header>
    <main className={styles.main}>
      <div className={styles.copy}>
        <p className={styles.eyebrow}>Early access</p>
        <h1>Try Plated<br />together.</h1>
        <p className={styles.description}>Leave your email to request an invitation for your household. We’re inviting people in batches.</p>
        <div className={styles.form}><WaitlistForm intent="early-access" /></div>
        <p className={styles.expectation}>If invited, you’ll install Plated through Apple’s TestFlight app. Available for iPhone and iPad.</p>
      </div>
      <aside className={styles.preview} aria-label="Inside Plated">
        <AppShowcase screen="plan" appearance="light" compact capture={{ src: "/app/plan-sam-light-818.png", alt: "Plated’s shared dinner plan showing Pizza Night and Sam is cooking" }} />
        <p>Sam’s cooking Pizza Night.</p>
      </aside>
    </main>
  </>;
}
