import Image from "next/image";
import Link from "next/link";
import AppShowcase from "./components/AppShowcase";
import PhoneScreenshot from "./components/PhoneScreenshot";
import WaitlistForm from "./components/WaitlistForm";
import Wordmark from "./components/Wordmark";
import { INSTALL_URL } from "./lib/store";
import styles from "./page.module.css";

const dinnerIdeas = [
  { name: "Lemon butter salmon", image: "salmon", note: "A little bright. A little buttery.", time: "25 min" },
  { name: "Pizza night", image: "pizza", note: "The night everyone agrees on.", time: "37 min" },
  { name: "Poke bowls", image: "poke", note: "Fresh things, all in one bowl.", time: "15 min" },
  { name: "Pancakes for dinner", image: "pancakes", note: "Because some nights call for it.", time: "25 min" },
];

const questions = [
  { question: "Can I try Plated now?", answer: <>Yes. Plated is available in early access for iPhone and iPad through Apple TestFlight. <a href={INSTALL_URL}>Join the beta</a> to try it while we keep making it better.</> },
  { question: "Can I bring my own recipes?", answer: <>Absolutely. Save recipes from a link, add your own, or start with the sample cookbook. Keep the meals you actually want to cook close at hand.</> },
  { question: "How does sharing with my household work?", answer: <>Your household shares a meal plan, cookbook, and grocery list. You can choose a night, add a meal, and assign a cook so the thinking and the doing can be shared.</> },
  { question: "Is my household the same as my Table?", answer: <>They serve different purposes. Your household is where you plan and cook together. Your Table is an invite-only place to share a meal with your people. Saving a recipe or cooking dinner never posts it automatically.</> },
];

function Arrow({ diagonal = false }: { diagonal?: boolean }) {
  return <span aria-hidden="true">{diagonal ? "↗" : "→"}</span>;
}

export default function Home() {
  return (
    <>
      <a className={styles.skip} href="#main">Skip to content</a>
      <header className={styles.header}>
        <Link className={styles.homeLink} href="/" aria-label="Plated home"><Wordmark size={40} /></Link>
        <nav className={styles.navigation} aria-label="Main navigation">
          <a href="#how-it-works">The app</a>
          <a href="#sharing">Made for sharing</a>
          <a href="#questions">Questions</a>
        </nav>
        <a className={styles.headerAction} href={INSTALL_URL}>Get early access <Arrow diagonal /></a>
      </header>

      <main id="main">
        <section className={styles.hero} aria-labelledby="hero-title">
          <div className={styles.heroCopy}>
            <p className={styles.eyebrow}><span className={styles.tinyRule} /> The shared meal planner</p>
            <h1 id="hero-title">Your week,<br />well fed.</h1>
            <p className={styles.intro}>Good dinners start with a little less figuring it out.</p>
            <p className={styles.heroDescription}>Bring your recipes, your people, and the week ahead together. Plated makes room for everyone to help.</p>
            <div className={styles.heroActions}>
              <a className={styles.primaryAction} href={INSTALL_URL}>Try Plated on TestFlight <Arrow diagonal /></a>
              <a className={styles.textAction} href="#how-it-works">Take a look inside <span aria-hidden="true">↓</span></a>
            </div>
            <p className={styles.availability}>Early access for iPhone &amp; iPad</p>
          </div>
          <figure className={styles.heroVisual}>
            <div className={styles.heroPhoto}>
              <Image src="/editorial/shared-table.webp" alt="Hands passing a bowl of vegetable pasta around a warmly lit dinner table" fill sizes="(max-width: 760px) 90vw, 44vw" priority />
            </div>
            <div className={styles.heroPhone}><PhoneScreenshot screen="recipes" priority /></div>
            <figcaption><span>Less planning alone.</span> More of this.</figcaption>
          </figure>
        </section>

        <section className={styles.inspiration} aria-labelledby="inspiration-title">
          <div className={styles.sectionHeading}>
            <div><p className={styles.eyebrow}>A few ideas for your week</p><h2 id="inspiration-title">Something good<br />to look forward to.</h2></div>
            <p>Your old favourites. A new find.<br />A very good reason to stay in.</p>
          </div>
          <div className={styles.recipeGrid}>
            {dinnerIdeas.map((recipe) => <figure className={styles.recipe} key={recipe.image}>
              <div className={styles.recipeImage}><Image src={`/editorial/${recipe.image}.webp`} alt={recipe.name} fill sizes="(max-width: 600px) 44vw, (max-width: 1000px) 22vw, 290px" loading="eager" /></div>
              <figcaption><div className={styles.recipeTitle}><h3>{recipe.name}</h3><span>{recipe.time}</span></div><p>{recipe.note}</p></figcaption>
            </figure>)}
          </div>
          <p className={styles.galleryNote}>A taste of Plated&rsquo;s sample cookbook. Make it yours with the recipes you love.</p>
        </section>

        <section id="how-it-works" className={styles.product} aria-labelledby="product-title">
          <div className={styles.productHeading}>
            <p className={styles.eyebrow}>A little order. A lot to enjoy.</p>
            <h2 id="product-title">From saved recipe<br /> to dinner sorted.</h2>
            <p>One place for the recipes, the plan, and everything you need to pick up.</p>
          </div>
          <AppShowcase />
        </section>

        <section id="sharing" className={styles.sharing} aria-labelledby="sharing-title">
          <div className={styles.sharingCopy}>
            <p className={styles.eyebrow}>Made for your people</p>
            <h2 id="sharing-title">Everyone eats.<br />Everyone gets a say.</h2>
            <p className={styles.sharingIntro}>The thinking behind dinner shouldn&rsquo;t all fall on one person.</p>
            <div className={styles.sharingDetail}><span className={styles.detailNumber}>01</span><div><h3>Your household, in sync.</h3><p>A shared plan, cookbook, and grocery list. Pick the meals together, assign a cook, and know what&rsquo;s happening tonight.</p></div></div>
            <div className={styles.sharingDetail}><span className={styles.detailNumber}>02</span><div><h3>A place at your Table.</h3><p>Made something worth sharing? Post it to your invite-only Table. A small circle of your people, with dinner at the centre.</p></div></div>
          </div>
          <figure className={styles.tableVisual}>
            <div className={styles.tableMasthead}><span>The Table</span><span>Good food. Your people.</span></div>
            <div className={styles.tableScreen}><PhoneScreenshot screen="table" /></div>
            <figcaption>Shared when you choose.<br />Only with the people you invite.</figcaption>
          </figure>
        </section>

        <aside className={styles.privacyNote}>
          <svg width="22" height="25" viewBox="0 0 22 25" fill="none" aria-hidden="true"><path d="M4 11V7a7 7 0 0 1 14 0v4M3 11h16v12H3zM11 16v3" stroke="currentColor" strokeWidth="1.3" /></svg>
          <p>Your recipes, plans, and photos live in your iCloud. Your Table stays invite-only.</p>
          <Link href="/privacy">Privacy, plainly <Arrow diagonal /></Link>
        </aside>

        <section id="questions" className={styles.questions} aria-labelledby="questions-title">
          <div><p className={styles.eyebrow}>Before you pull up a chair</p><h2 id="questions-title">A few good<br /> questions.</h2></div>
          <div className={styles.questionList}>{questions.map(({ question, answer }) => <details key={question}><summary>{question}<span aria-hidden="true" /></summary><div className={styles.answer}>{answer}</div></details>)}</div>
        </section>

        <section className={styles.closing} aria-labelledby="closing-title">
          <p className={styles.eyebrow}>Good food. Less figuring it out.</p>
          <h2 id="closing-title">Make room<br />for good dinners.</h2>
          <a className={styles.primaryAction} href={INSTALL_URL}>Try Plated on TestFlight <Arrow diagonal /></a>
          <p className={styles.availability}>For iPhone &amp; iPad. Bring your people.</p>
        </section>
        <section className={styles.waitlist} aria-labelledby="waitlist-title">
          <div><h2 id="waitlist-title">Prefer to wait for launch?</h2><p>Leave your email. We&rsquo;ll let you know when it&rsquo;s ready.</p></div>
          <WaitlistForm compact />
        </section>
      </main>

      <footer className={styles.footer}>
        <div className={styles.footerWordmark} aria-label="Plated">Plated</div>
        <div className={styles.footerBottom}><p>A little more together, every day.</p><nav aria-label="Footer navigation"><a href="#how-it-works">The app</a><Link href="/privacy">Privacy</Link><a href={INSTALL_URL}>Get Plated <Arrow diagonal /></a></nav><span>© {new Date().getFullYear()} Plated</span></div>
      </footer>
    </>
  );
}
