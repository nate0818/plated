import { Suspense } from "react";
import Link from "next/link";
import Wordmark from "../components/Wordmark";
import Invitation from "./Invitation";
import Fallback from "./Fallback";
import styles from "./page.module.css";
import { COPY, type Kind } from "./copy";

// One page for both invitations, told apart by `kind`. /join and
// /join/household used to be candidates for two copies of this file, and two
// copies of a page drift the way two copies of a row did in the app
// (DESIGN.md, "peers look like peers"): the copy lives in copy.ts and this
// shell draws whichever kind the route names.
//
// A phone that has Plated never gets here: iOS opens the app straight from
// the link, because /join and /join/* are in the association file. So the
// single action on this page is getting the app. Everything else is a
// hairline or a whisper.
export default function JoinPage({ kind }: { kind: Kind }) {
  return (
    <div className={styles.page}>
      <header className={styles.header}>
        <Link href="/" aria-label="Plated home" className={styles.home}>
          <Wordmark size={26} />
        </Link>
      </header>

      <main className={styles.main}>
        <Suspense fallback={<Fallback kind={kind} />}>
          <Invitation kind={kind} />
        </Suspense>

        <div className={styles.facts}>
          {COPY[kind].facts.map((fact) => (
            <p className={styles.fact} key={fact.lead}>
              <i className={styles.dot} aria-hidden="true" />
              <span>
                <b>{fact.lead}</b> {fact.rest}
              </span>
            </p>
          ))}
        </div>
      </main>

      <footer className={styles.footer}>
        <Link href="/privacy">Privacy</Link>
      </footer>
    </div>
  );
}
