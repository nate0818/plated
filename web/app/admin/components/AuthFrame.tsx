import Link from "next/link";
import Wordmark from "../../components/Wordmark";
import styles from "../admin.module.css";

export default function AuthFrame({
  eyebrow,
  title,
  detail,
  children,
}: {
  eyebrow: string;
  title: string;
  detail: string;
  children: React.ReactNode;
}) {
  return (
    <main className={styles.authPage}>
      <section className={styles.authCard}>
        <header className={styles.authBrand}>
          <Link href="/" aria-label="Plated home">
            <Wordmark size={28} />
          </Link>
          <span className={styles.privateBadge}>Private</span>
        </header>
        <div className={styles.authCopy}>
          <p className={styles.eyebrow}>{eyebrow}</p>
          <h1 className={styles.authTitle}>{title}</h1>
          <p className={styles.bodyMuted}>{detail}</p>
        </div>
        {children}
      </section>
    </main>
  );
}

export function AuthSetupState() {
  return (
    <AuthFrame
      eyebrow="Setup needed"
      title="Connect the founder account"
      detail="The console stays closed until its public Supabase connection is configured."
    >
      <div className={styles.callout}>
        <p className={styles.calloutTitle}>Vercel environment</p>
        <code>NEXT_PUBLIC_SUPABASE_URL</code>
        <code>NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY</code>
        <p className={styles.smallMuted}>Invite the founder account in Supabase Auth. The admin principal and API secret are checked again by the server before any data is returned.</p>
      </div>
    </AuthFrame>
  );
}
