import type { ReactNode } from "react";
import Link from "next/link";
import Wordmark from "./Wordmark";
import AppStoreBadge from "./AppStoreBadge";
import SiteMotion from "./SiteMotion";
import styles from "./SiteFrame.module.css";

export function SiteArrow({ back = false }: { back?: boolean }) {
  return <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true"><path d={back ? "M20 12H5m6-6-6 6 6 6" : "M4 12h15m-6-6 6 6-6 6"} /></svg>;
}

export function SiteHeader({ action = "access", mainId = "main" }: { action?: "access" | "home"; mainId?: string }) {
  return <>
    <a className={styles.skip} href={`#${mainId}`}>Skip to content</a>
    <header className={styles.header} data-site-header>
      <div className={styles.headerInner}>
        <Link href="/#content" className={styles.brand} aria-label="Plated home"><Wordmark size={32} /></Link>
        <nav aria-label="Main navigation" data-section-nav><Link href="/#product">How it works</Link><Link href="/#table">Your Table</Link><Link href="/#questions">Questions</Link></nav>
        <Link className={action === "home" ? styles.back : styles.navCta} href={action === "home" ? "/#content" : "/early-access"}>
          {action === "home" ? <><SiteArrow back /> Back to Plated</> : <>Request access <SiteArrow /></>}
        </Link>
      </div>
    </header>
  </>;
}

export function SiteFooter({ compact = false }: { compact?: boolean }) {
  return <footer className={styles.footer}>
    <Link href="/#content" className={styles.brand} aria-label="Plated home"><Wordmark size={32} /></Link>
    <span>Dinner, together</span>
    <nav aria-label="Footer navigation"><Link href="/privacy">Privacy</Link><Link href="/early-access">Early access</Link></nav>
    {!compact ? <div className={styles.store}><AppStoreBadge height={42} /><small>© {new Date().getFullYear()} Plated</small></div> : <small>© {new Date().getFullYear()} Plated</small>}
  </footer>;
}

export default function SiteFrame({ children, action = "access", mainId = "main", compactFooter = false }: { children: ReactNode; action?: "access" | "home"; mainId?: string; compactFooter?: boolean }) {
  return <SiteMotion className={styles.page}><SiteHeader action={action} mainId={mainId} />{children}<SiteFooter compact={compactFooter} /></SiteMotion>;
}
