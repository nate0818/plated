import styles from "./page.module.css";
import { INSTALL_URL, INSTALL_LABEL } from "../lib/store";
import { COPY, type Kind } from "./copy";

// What the server renders before the query string is known. Same shape, no
// name, so nothing jumps when the client fills the name in. A server
// component on purpose: a static property on the client component would
// not survive the server boundary, which is how the build first failed.
export default function Fallback({ kind }: { kind: Kind }) {
  const copy = COPY[kind];
  const [firstLine, secondLine] = copy.titleAnonymous;
  return (
    <>
      <h1 className={styles.title}>
        {firstLine}
        <br />
        {secondLine}
      </h1>
      <p className={`${styles.lede} secondary`}>{copy.lede("")}</p>
      <div className={styles.actions}>
        <a className={styles.cta} href={INSTALL_URL}>
          {INSTALL_LABEL}
        </a>
      </div>
    </>
  );
}
