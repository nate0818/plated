import styles from "./page.module.css";
import { APP_STORE_URL } from "./store";

// What the server renders before the query string is known. Same shape, no
// name, so nothing jumps when the client fills the name in. A server
// component on purpose: a static property on the client component would
// not survive the server boundary, which is how the build first failed.
export default function Fallback() {
  return (
    <>
      <h1 className={styles.title}>
        Someone kept
        <br />
        you a seat.
      </h1>
      <p className={`${styles.lede} secondary`}>
        Plated is where a household keeps track of what it&rsquo;s actually
        cooking: the week ahead, who&rsquo;s at the stove, and the dishes worth
        making again.
      </p>
      <div className={styles.actions}>
        <a className={styles.cta} href={APP_STORE_URL}>
          Get Plated
        </a>
      </div>
    </>
  );
}
