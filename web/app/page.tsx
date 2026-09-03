import Link from "next/link";
import Wordmark from "./components/Wordmark";
import WaitlistForm from "./components/WaitlistForm";
import FallingFood from "./components/FallingFood";
import AppStoreMark from "./components/AppStoreMark";
import styles from "./page.module.css";

export default function Home() {
  return (
    <>
      <header className={`${styles.header} wrap`}>
        <Link href="/" aria-label="Plated home" className={styles.home}>
          <Wordmark size={26} />
        </Link>
        <a href="#waitlist" className={styles.headerLink}>
          Join the waitlist
        </a>
      </header>

      <main>
        <section className={styles.heroBand}>
          <FallingFood />
          <div className={`${styles.hero} wrap`}>
            <p className={`micro ${styles.eyebrow}`}>
              <AppStoreMark />
              <span>Built for iPhone and iPad. Coming soon.</span>
            </p>
          <h1 className={styles.title}>
            A week of dinners,
            <br />
            planned together.
          </h1>
          <p className={`${styles.lede} secondary`}>
            Plated is where a household decides what it&rsquo;s cooking: the week
            ahead, who&rsquo;s at the stove, and the dishes worth making again.
          </p>
          <div id="waitlist" className={styles.heroForm}>
            <WaitlistForm />
          </div>
          </div>
        </section>

        <section className={`${styles.features} wrap`}>
          <article className={styles.feature}>
            <p className="micro">The week</p>
            <h2>Tonight, then the rest of the week.</h2>
            <p className="secondary">
              Every night has a dish and a cook. Tap a night, pick from your own
              recipes, and the week fills in. The forecast sits beside each date,
              so grill night lands on grill weather.
            </p>
          </article>
          <article className={styles.feature}>
            <p className="micro">The Table</p>
            <h2>A private Table for the people you feed.</h2>
            <p className="secondary">
              Post a photograph of what came out of the oven. Your household and
              the seats you gave away see it, and nobody else. Eight people, not
              eight thousand.
            </p>
          </article>
          <article className={styles.feature}>
            <p className="micro">Recipes</p>
            <h2>The recipes you actually make.</h2>
            <p className="secondary">
              Paste a link, type one in, or scan the card. Ingredients from the
              week roll into one grocery list, and one tap sends it to Reminders.
            </p>
          </article>
          <article className={styles.feature}>
            <p className="micro">Yours</p>
            <h2>Kept in your iCloud, not on ours.</h2>
            <p className="secondary">
              Recipes, plans and photographs live in your own iCloud account and
              sync between your devices. Plated&rsquo;s server keeps only what it
              takes to find friends already here.{" "}
              <Link href="/privacy" className={styles.inlineLink}>
                How that works
              </Link>
            </p>
          </article>
        </section>

        <section className={`${styles.closer} wrap`}>
          <h2 className={styles.closerTitle}>Be there for the first dinner.</h2>
          <WaitlistForm compact />
        </section>
      </main>

      <footer className={`${styles.footer} wrap`}>
        <Wordmark size={20} />
        <nav className={styles.footerNav} aria-label="Footer">
          <Link href="/privacy">Privacy</Link>
          <a href="mailto:privacy@getplated.food">Contact</a>
        </nav>
      </footer>
    </>
  );
}
