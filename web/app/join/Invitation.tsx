"use client";

import { useSearchParams } from "next/navigation";
import styles from "./page.module.css";

import { APP_STORE_URL } from "../lib/store";

// ?h= is the host's first name, ?s= the share URL. Read on the client so the
// page can be statically served and still say "Nate kept you a seat."
export default function Invitation() {
  const params = useSearchParams();
  const host = (params.get("h") ?? "").trim().slice(0, 40);
  const share = params.get("s") ?? "";

  // The direct-open fallback for the window before Apple has fetched the
  // association file. Only ever an iCloud share URL: this link is handed to
  // the reader, so it does not forward wherever a query string points.
  const rawOK = /^https:\/\/(www\.)?icloud\.com\//.test(share);

  return (
    <>
      <h1 className={styles.title}>
        {host ? (
          <>
            <span className={styles.who}>{host}</span> kept
            <br />
            you a seat.
          </>
        ) : (
          <>
            Someone kept
            <br />
            you a seat.
          </>
        )}
      </h1>
      <p className={`${styles.lede} secondary`}>
        {host
          ? `${host} is planning dinners on Plated: the week ahead, who’s at the stove, and the dishes worth making again. Your place is set.`
          : "Plated is where a household keeps track of what it’s actually cooking: the week ahead, who’s at the stove, and the dishes worth making again."}
      </p>

      <div className={styles.actions}>
        <a className={styles.cta} href={APP_STORE_URL}>
          Get Plated
        </a>
        {rawOK && (
          <a className={styles.quiet} href={share}>
            Already have it? Open the invitation
          </a>
        )}
      </div>
    </>
  );
}
