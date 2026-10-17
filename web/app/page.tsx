import Link from "next/link";
import AppShowcase from "./components/AppShowcase";
import AppStoreBadge from "./components/AppStoreBadge";
import FoodGallery from "./components/FoodGallery";
import HeroPreview from "./components/HeroPreview";
import ProductTour from "./components/ProductTour";
import WaitlistForm from "./components/WaitlistForm";
import Wordmark from "./components/Wordmark";
import { INSTALL_URL } from "./lib/store";
import styles from "./page.module.css";

const questions = [
  {
    question: "Can I try Plated now?",
    answer: <>Yes. Plated is in early access for iPhone and iPad through Apple TestFlight. <a href={INSTALL_URL}>Try Plated</a> while we keep improving it.</>,
  },
  {
    question: "Can I use my own recipes?",
    answer: <>Yes. Save a recipe from a link or add one yourself. You can also save recipes friends share at your Table. Your household shares the same recipe book.</>,
  },
  {
    question: "What does my household share?",
    answer: <>Your household shares a meal plan, recipe book, and grocery list. Add meals to the plan and assign a cook for each night, so everyone knows what’s happening.</>,
  },
  {
    question: "Who can see my meals?",
    answer: <>Your shared plan is for your household. To share a meal with friends, post it to your invite-only Table. Saving a recipe or cooking a meal never posts it automatically. Your recipes, plans, and photos live in your iCloud.</>,
  },
];

function Arrow() {
  return <svg viewBox="0 0 20 20" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="1.4" aria-hidden="true"><path d="M3 10h13m-5-5 5 5-5 5" /></svg>;
}

export default function Home() {
  return <>
    <a className={styles.skip} href="#main">Skip to content</a>
    <header className={styles.header}>
      <div className={styles.headerInner}>
        <Link className={styles.homeLink} href="/" aria-label="Plated home"><Wordmark size={34} /></Link>
        <nav className={styles.navigation} aria-label="Main navigation">
          <a href="#recipes">The food</a>
          <a href="#how-it-works">How it works</a>
          <a href="#questions">Questions</a>
        </nav>
        <a className={styles.headerAction} href={INSTALL_URL}>Try Plated <Arrow /></a>
      </div>
    </header>

    <main id="main">
      <section className={styles.hero} aria-labelledby="hero-title">
        <div className={styles.heroCopy}>
          <h1 className={styles.eyebrow}>The meal planner for your household</h1>
          <h2 id="hero-title" className={styles.heroTitle}>Dinner plans.<br />Made together.</h2>
          <p className={styles.heroDescription}>Decide what&rsquo;s for dinner, who&rsquo;s cooking, and what to pick up. One shared plan for your whole household.</p>
          <div className={styles.heroActions}>
            <a className={styles.primaryAction} href={INSTALL_URL}>Try Plated on TestFlight <Arrow /></a>
            <a className={styles.secondaryAction} href="#how-it-works">See how it works</a>
          </div>
          <p className={styles.availability}>Early access for iPhone and iPad</p>
        </div>
        <div className={styles.heroProduct}>
          <HeroPreview />
        </div>
      </section>

      <FoodGallery />

      <section id="how-it-works" className={styles.product} aria-labelledby="product-title">
        <div className={styles.productHeading}>
          <p className={styles.category}>How Plated works</p>
          <h2 id="product-title">Share the plan.<br />Share the cooking.</h2>
          <p>Choose dinner together. Give each night a cook.<br className={styles.desktopBreak} /> Keep everyone in the loop, from the recipe to the shopping.</p>
        </div>
        <ProductTour />
      </section>

      <section className={styles.tableSection} aria-labelledby="table-title">
        <div className={styles.tableCopy}>
          <p className={styles.category}>Your Table</p>
          <h2 id="table-title">Good meals are<br />worth sharing.</h2>
          <p>A weeknight win. An old family recipe. Pancakes for dinner. Share what you&rsquo;ve cooked with the friends you invite to your Table.</p>
          <div className={styles.privateNote}>
            <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" strokeWidth="1.3" aria-hidden="true"><rect x="5" y="10" width="14" height="11" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3m-4 5v2" /></svg>
            <div><strong>Invite-only. Shared by you.</strong><span>Cooking a meal never posts it automatically.</span></div>
          </div>
          <Link className={styles.textLink} href="/privacy">How Plated keeps things private <Arrow /></Link>
        </div>
        <figure className={styles.tableVisual}>
          <AppShowcase screen="table" compact />
          <figcaption>Share a dish with your Table</figcaption>
        </figure>
      </section>

      <section className={styles.closing} aria-labelledby="closing-title">
        <div><h2 id="closing-title">Your next dinner,<br />planned together.</h2><p>Bring your recipes. Invite your household. Start with one night.</p></div>
        <div className={styles.closingActions}>
          <a className={styles.primaryAction} href={INSTALL_URL}>Try Plated on TestFlight <Arrow /></a>
          <p className={styles.availability}>Early access for iPhone and iPad</p>
          <details className={styles.launchUpdates}>
            <summary>Get an email when Plated launches</summary>
            <div className={styles.waitlist}><WaitlistForm compact /></div>
          </details>
        </div>
      </section>

      <section id="questions" className={styles.questions} aria-labelledby="questions-title">
        <h2 id="questions-title">A few things to know.</h2>
        <div className={styles.questionList}>
          {questions.map(({ question, answer }) => <details key={question}>
            <summary>{question}<span aria-hidden="true" /></summary>
            <div className={styles.answer}>{answer}</div>
          </details>)}
        </div>
      </section>
    </main>

    <footer className={styles.footer}>
      <div className={styles.footerBrand}><Link href="/" aria-label="Plated home"><Wordmark size={34} /></Link><p>A shared plan for the food<br />and people you love.</p></div>
      <nav aria-label="Footer navigation"><a href="#recipes">The food</a><a href="#how-it-works">How it works</a><a href="#questions">Questions</a><Link href="/privacy">Privacy</Link></nav>
      <div className={styles.footerNote}><AppStoreBadge /><span>© {new Date().getFullYear()} Plated</span></div>
    </footer>
  </>;
}
