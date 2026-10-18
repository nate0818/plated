import type { Metadata } from "next";
import WaitlistForm from "../components/WaitlistForm";
import SiteFrame from "../components/SiteFrame";
import HouseholdPreview from "../components/HouseholdPreview";
import styles from "./page.module.css";

export const metadata: Metadata = {
  title: "Request early access",
  description: "Request early access to Plated for iPhone and iPad. Plan meals, take turns cooking, and share a grocery list with your household.",
  alternates: { canonical: "/early-access" },
};

export default function EarlyAccess() {
  return <SiteFrame action="home">
    <main id="main" className={styles.main}>
      <div className={styles.copy} data-reveal="stagger">
        <p className={styles.eyebrow}>Early access</p>
        <h1>Try Plated{" "}<br />together</h1>
        <p className={styles.description}>Request an invitation for your household. We’re sending them a few at a time.</p>
        <div className={styles.form}><WaitlistForm intent="early-access" /></div>
        <p className={styles.expectation}>Available for iPhone and iPad. Your invitation will include instructions to install Plated with Apple TestFlight.</p>
      </div>
      <aside className={styles.preview} aria-label="A look at Plated" data-reveal><HouseholdPreview /></aside>
    </main>
  </SiteFrame>;
}
