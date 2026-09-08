"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useState } from "react";
import Wordmark from "../../components/Wordmark";
import { ADMIN_CSRF_HEADER, ADMIN_CSRF_VALUE } from "../../lib/admin/contracts";
import styles from "../admin.module.css";

const NAVIGATION = [
  { href: "/admin", label: "Overview", glyph: "⌂" },
  { href: "/admin/people", label: "People", glyph: "◎" },
  { href: "/admin/waitlist", label: "Waitlist", glyph: "↗" },
  { href: "/admin/announcements", label: "Announcements", glyph: "◉" },
  { href: "/admin/operations", label: "Operations", glyph: "◇" },
  { href: "/admin/audit", label: "Audit trail", glyph: "□" },
  { href: "/admin/releases", label: "Releases & coverage", glyph: "△" },
];

export default function AdminShell({ userLabel, children }: { userLabel: string; children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const [signingOut, setSigningOut] = useState(false);
  const [signOutError, setSignOutError] = useState("");

  function current(href: string) {
    return href === "/admin" ? pathname === href : pathname === href || pathname.startsWith(`${href}/`);
  }

  async function signOut() {
    if (signingOut) return;
    setSigningOut(true);
    setSignOutError("");
    try {
      const response = await fetch("/api/admin/sign-out", {
        method: "POST",
        headers: { [ADMIN_CSRF_HEADER]: ADMIN_CSRF_VALUE },
        cache: "no-store",
      });
      if (!response.ok) {
        setSignOutError("Sign-out could not be completed. Try again.");
        return;
      }
      router.replace("/admin/login");
      router.refresh();
    } catch {
      setSignOutError("The authentication service could not be reached.");
    } finally {
      setSigningOut(false);
    }
  }

  return (
    <div className={styles.console}>
      <a className={styles.skipLink} href="#admin-main">Skip to content</a>
      <aside className={styles.sidebar}>
        <Link className={styles.brandLink} href="/admin" aria-label="Plated admin">
          <Wordmark size={25} />
          <span className={styles.founderWord}>Admin</span>
        </Link>
        <nav className={styles.nav} aria-label="Admin">
          {NAVIGATION.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className={`${styles.navLink} ${current(item.href) ? styles.navLinkCurrent : ""}`}
              aria-current={current(item.href) ? "page" : undefined}
            >
              <span className={styles.navGlyph} aria-hidden="true">{item.glyph}</span>
              <span>{item.label}</span>
            </Link>
          ))}
        </nav>
        <div className={styles.identity}>
          <span className={styles.identityLabel}>Verified with MFA</span>
          <span className={styles.identityEmail} title={userLabel}>{userLabel}</span>
          <button className={styles.signOut} type="button" onClick={signOut} disabled={signingOut}>
            {signingOut ? "Signing out…" : "Sign out"}
          </button>
        </div>
      </aside>
      <div className={styles.mobileBar}>
        <Link href="/admin" aria-label="Plated admin"><Wordmark size={23} /></Link>
        <span className={styles.founderWord}>Admin</span>
        <button className={styles.signOut} type="button" onClick={signOut} disabled={signingOut}>Sign out</button>
      </div>
      <nav className={styles.mobileNav} aria-label="Admin">
        {NAVIGATION.map((item) => (
          <Link
            key={item.href}
            href={item.href}
            className={`${styles.mobileNavLink} ${current(item.href) ? styles.mobileNavCurrent : ""}`}
            aria-current={current(item.href) ? "page" : undefined}
          >
            {item.label}
          </Link>
        ))}
      </nav>
      {signOutError ? <p className={styles.sessionAlert} role="alert">{signOutError}</p> : null}
      <main id="admin-main" className={styles.main}>{children}</main>
    </div>
  );
}
