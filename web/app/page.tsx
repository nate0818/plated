import Link from "next/link";
import Wordmark from "./components/Wordmark";
import WaitlistForm from "./components/WaitlistForm";
import FallingFood from "./components/FallingFood";
import AppStoreMark from "./components/AppStoreMark";
import AppStoreBadge from "./components/AppStoreBadge";
import styles from "./page.module.css";

// Structured data for the search engines that read it. A software
// application with no offer attached: it is not on the store yet, and a
// price or a download URL here would be a claim the badge cannot keep.
const structuredData = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "Organization",
      "@id": "https://plated.food/#org",
      name: "Plated",
      url: "https://plated.food",
      logo: "https://plated.food/apple-icon",
    },
    {
      "@type": "WebSite",
      "@id": "https://plated.food/#site",
      url: "https://plated.food",
      name: "Plated",
      publisher: { "@id": "https://plated.food/#org" },
      inLanguage: "en-US",
    },
    {
      "@type": "SoftwareApplication",
      name: "Plated",
      applicationCategory: "LifestyleApplication",
      operatingSystem: "iOS, iPadOS",
      description:
        "A dinner planner for households and the people they cook for. Plan the week together, keep the recipes you love, and share what you made with the people you invite.",
      url: "https://plated.food",
      publisher: { "@id": "https://plated.food/#org" },
    },
  ],
};

export default function Home() {
  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData) }}
      />
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
              <span>Built for iPhone and iPad</span>
            </p>
          <h1 className={styles.title}>
            A week of dinners,
            <br />
            planned together.
          </h1>
          <p className={`${styles.lede} secondary`}>
            For people who love food and the people they share it with. Plan
            the week together, cook it, and show them how it turned out.
          </p>
          <div id="waitlist" className={styles.heroForm}>
            <WaitlistForm />
          </div>
          <div className={styles.store}>
            <AppStoreBadge height={52} />
            <p className={`${styles.soon} secondary`}>Coming soon</p>
          </div>
          </div>
        </section>

        <section className={`${styles.features} wrap`} aria-label="What Plated does">
          <article className={styles.feature}>
            <h2>Decide the week together.</h2>
            <p className="secondary">
              You take Monday and Tuesday, they take Wednesday, the kids pick
              Saturday. Everyone can see the plan and everyone gets a say.
            </p>
          </article>
          <article className={styles.feature}>
            <h2>Share it with your people.</h2>
            <p className="secondary">
              Post what you made to the family and friends you invite, whether
              they live with you or across the country. Nobody else sees it.
            </p>
          </article>
          <article className={styles.feature}>
            <h2>Keep the recipes you love.</h2>
            <p className="secondary">
              Paste a link, take a photo of the card, or type it in. The
              week&rsquo;s ingredients turn into a grocery list in Reminders.
            </p>
          </article>
          <article className={styles.feature}>
            <h2>Your stuff is yours.</h2>
            <p className="secondary">
              We don&rsquo;t store your recipes, plans or photos.{" "}
              <Link href="/privacy" className={styles.inlineLink}>
                Here&rsquo;s what we do store
              </Link>
            </p>
          </article>
        </section>

        <section className={`${styles.closer} wrap`}>
          <h2 className={styles.closerTitle}>End the group chat.</h2>
          <WaitlistForm compact />
          <div className={`${styles.store} ${styles.storeCenter}`}>
            <AppStoreBadge height={52} />
            <p className={`${styles.soon} secondary`}>Coming soon</p>
          </div>
        </section>
      </main>

      <footer className={`${styles.footer} wrap`}>
        <div className={styles.footerRow}>
          <Wordmark size={20} />
          <nav className={styles.footerNav} aria-label="Footer">
            <Link href="/privacy">Privacy</Link>
          </nav>
        </div>
        {/* Required wherever Apple's badge appears, in their wording. */}
        <p className={`${styles.legal} secondary`}>
          Apple, the Apple logo, iPhone and iPad are trademarks of Apple Inc.,
          registered in the U.S. and other countries and regions. App Store is
          a service mark of Apple Inc.
        </p>
      </footer>
    </>
  );
}
