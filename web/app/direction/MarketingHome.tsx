import Link from "next/link";
import Image from "next/image";
import AppShowcase from "../components/AppShowcase";
import SiteFrame from "../components/SiteFrame";
import DirectionDemo from "./DirectionDemo";
import DirectionTable from "./DirectionTable";
import DirectionQuestions from "./DirectionQuestions";
import styles from "./direction.module.css";

function Arrow({ diagonal = false }: { diagonal?: boolean }) {
  return <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true">{diagonal ? <path d="M6 18 18 6M6 6h12v12" /> : <path d="M4 12h15m-6-6 6 6-6 6" />}</svg>;
}

const questions = [
  ["How can I try Plated?", "Request early access for iPhone or iPad. We’re inviting households a few at a time. Invitations arrive by email with instructions to install Plated through Apple TestFlight."],
  ["Can I add my own recipes?", "Yes. Add a recipe yourself, save one from a link, or save one a friend shares at your Table. Your household can use the same recipe book."],
  ["What can my household share?", "A meal plan, recipe book, and grocery list. Choose meals together and assign a cook to each night, so everyone knows who’s making what."],
  ["Who can see my Table posts?", "Only the friends you invite to your Table. Cooking a meal or saving a recipe doesn’t post it. You choose what to share."],
] as const;

const benefits = [
  { title: "Plan dinner together", detail: "See your meals for the week in one place", icon: <><rect x="4" y="5" width="20" height="19" rx="3" /><path d="M9 3v4m10-4v4M4 11h20m-15 5h4m-4 4h8" /></> },
  { title: "See who’s cooking", detail: "Take turns and share the work", icon: <><circle cx="14" cy="9" r="4" /><path d="M6 25v-3a8 8 0 0 1 16 0v3m-2-12 3 3 5-5" /></> },
  { title: "Share a grocery list", detail: "Everyone can see what’s left to buy", icon: <><path d="M5 10h18l-2 15H7L5 10Zm5 1V7a4 4 0 0 1 8 0v4m-7 6 3 3 5-6" /></> },
];

export default function MarketingHome() {
  return <div className={styles.direction} data-theme="paper">
    <SiteFrame mainId="content">
    <main id="content">
      <section className={styles.hero} aria-labelledby="direction-title">
        <div className={styles.heroPhoto}>
          <Image src="/hero-kitchen-plated-2026.webp" alt="Plated’s landscape iPad meal plan on a sunlit kitchen island" width={1536} height={1024} unoptimized priority />
        </div>
        <div className={styles.heroIntro}>
          <p className={styles.eyebrow} data-reveal>Meal planning for your household</p>
          <h1 id="direction-title" data-reveal="stagger"><span data-reveal="line">Dinner shouldn’t be</span>{" "}<span data-reveal="line">one person’s job</span></h1>
          <div className={styles.heroBottom} data-reveal>
            <p>Plan meals, take turns cooking, and share a grocery list.<br className={styles.desktopBreak} /> Everyone knows what’s for dinner and who’s making it.</p>
            <div className={styles.heroConversion}><Link className={styles.cta} href="/early-access">Request early access <Arrow /></Link><span>For iPhone and iPad</span></div>
          </div>
        </div>
      </section>

      <div className={styles.heroBenefits}><ul className={styles.principles} aria-label="What your household shares" data-reveal="stagger">{benefits.map(benefit => <li key={benefit.title}><svg viewBox="0 0 30 30" width="30" height="30" fill="none" stroke="currentColor" strokeWidth="1.4" aria-hidden="true">{benefit.icon}</svg><h3>{benefit.title}</h3><p>{benefit.detail}</p></li>)}</ul></div>

      <section className={styles.sharedPlan} aria-label="See who’s cooking">
        <DirectionDemo />
      </section>

      <section id="product" className={styles.product} aria-labelledby="product-heading">
        <div className={styles.sectionIntro} data-reveal>
          <p className={styles.eyebrow}>Recipes and groceries</p>
          <h2 id="product-heading">Less back-and-forth<br />before dinner</h2>
          <p>Save a recipe, add it to the meal plan, and bring the ingredients into your grocery list.</p>
        </div>
        <div className={styles.features} data-reveal="stagger">
          <article className={styles.feature}>
            <div className={`${styles.featureVisual} ${styles.recipeVisual}`} data-depth><div data-depth-item><AppShowcase screen="recipes" appearance="light" compact /></div></div>
            <div className={styles.featureCopy}><span className={styles.featureNumber}>01 / Recipes</span><h3>Your favorites<br />in one recipe book</h3><p>Save your own recipes, ones you find online, and favorites from friends. Keep them together in a recipe book your household can share.</p></div>
          </article>
          <article className={styles.feature}>
            <div className={`${styles.featureVisual} ${styles.groceryVisual}`} data-depth><div data-depth-item><AppShowcase screen="groceries" appearance="light" compact /></div></div>
            <div className={styles.featureCopy}><span className={styles.featureNumber}>02 / Groceries</span><h3>One grocery list<br />for everyone</h3><p>Add ingredients from planned meals to a shared list. Anyone in your household can see what’s still needed.</p></div>
          </article>
        </div>
      </section>

      <section id="table" className={styles.table} aria-labelledby="table-heading">
        <div className={styles.tableInner} data-depth>
          <div className={styles.tableIntro} data-reveal><p className={styles.eyebrow}>Your Table</p><h2 id="table-heading">Dinner ideas<br />from friends</h2><p>Share a recipe, a new food find, or tonight’s dinner. Keep up with what your friends are cooking and find something you’d like to try.</p><div className={styles.tablePrivacy}><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.4" aria-hidden="true"><rect x="5" y="10" width="14" height="11" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3" /></svg>Only the friends you invite</div><Link href="/privacy" className={styles.textLink}>Privacy at Plated <Arrow diagonal /></Link></div>
          <DirectionTable />
        </div>
      </section>

      <section className={styles.invitation} aria-labelledby="invite-heading" data-reveal="stagger">
        <p className={styles.eyebrow}>Early access</p><h2 id="invite-heading">Get everyone<br />in on dinner</h2><div><p>Try Plated with your household. We’re sending invitations a few at a time.</p><Link href="/early-access" className={styles.darkCta}>Request early access <Arrow /></Link><span>For iPhone and iPad · Invitations by email</span></div>
      </section>

      <section id="questions" className={styles.questions} aria-labelledby="questions-heading"><div data-reveal><p className={styles.eyebrow}>Questions</p><h2 id="questions-heading">A few things<br />to know</h2></div><DirectionQuestions questions={questions} /></section>
    </main>
    </SiteFrame>
  </div>;
}
