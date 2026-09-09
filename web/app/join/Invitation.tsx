"use client";

import { useSearchParams } from "next/navigation";
import styles from "./page.module.css";

import { INSTALL_URL, INSTALL_LABEL } from "../lib/store";
import { COPY, appLink, recordName, type Kind } from "./copy";

// ?h= is the host's first name, ?s= the share URL, ?seat= the household seat
// the link was minted for, ?i= the Table invitation's id. Read on the client
// so the page can be statically served and still say "Nate kept you a seat."
export default function Invitation({ kind }: { kind: Kind }) {
  const params = useSearchParams();
  const host = (params.get("h") ?? "").trim().slice(0, 40);
  const share = params.get("s") ?? "";
  const seat = recordName(params.get("seat"));
  const invite = recordName(params.get("i"));
  const copy = COPY[kind];

  // The direct-open fallback for the window before Apple has fetched the
  // association file. Only ever an iCloud share URL: this link is handed to
  // the reader, so it does not forward wherever a query string points.
  const rawOK = /^https:\/\/(www\.)?icloud\.com\//.test(share);
  const [firstLine, secondLine] = host ? copy.titleAfterName : copy.titleAnonymous;

  return (
    <>
      <h1 className={styles.title}>
        {host ? (
          <>
            <span className={styles.who}>{host}</span> {firstLine}
            <br />
            {secondLine}
          </>
        ) : (
          <>
            {firstLine}
            <br />
            {secondLine}
          </>
        )}
      </h1>
      <p className={`${styles.lede} secondary`}>{copy.lede(host)}</p>

      <div className={styles.actions}>
        <a className={styles.cta} href={INSTALL_URL}>
          {INSTALL_LABEL}
        </a>
        {rawOK && (
          <a className={styles.quiet} href={appLink(kind, share, { seat, invite, host })}>
            Already have it? Open the invitation
          </a>
        )}
      </div>
    </>
  );
}
