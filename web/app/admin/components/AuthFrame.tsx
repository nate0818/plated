import Link from "next/link";
import Wordmark from "../../components/Wordmark";
import styles from "../admin.module.css";

/// The signed-out frame. It carries the wordmark, a plain title, and the form.
/// It deliberately does not name the surface it protects, badge itself
/// private, or describe the sign-in policy: a person who belongs here already
/// knows all three, and a stranger learns nothing worth telling them.
export default function AuthFrame({
  title,
  detail,
  children,
}: {
  title: string;
  detail?: string;
  children: React.ReactNode;
}) {
  return (
    <main className={styles.authPage}>
      <section className={styles.authCard}>
        <header className={styles.authBrand}>
          <Link href="/" aria-label="Plated home">
            <Wordmark size={28} />
          </Link>
        </header>
        <div className={styles.authCopy}>
          <h1 className={styles.authTitle}>{title}</h1>
          {detail ? <p className={styles.bodyMuted}>{detail}</p> : null}
        </div>
        {children}
      </section>
    </main>
  );
}

/// Shown when the public Supabase values are missing. Naming the variable
/// that is unset would tell an anonymous visitor exactly how this is broken,
/// so the operator reads that in the server log and the page stays quiet.
export function AuthSetupState() {
  console.error(
    "Founder console is unconfigured: NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY must be set.",
  );
  return (
    <AuthFrame title="Not available" detail="This page cannot be reached right now.">
      <></>
    </AuthFrame>
  );
}
