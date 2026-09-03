import type { Metadata } from "next";
import Link from "next/link";
import Wordmark from "../components/Wordmark";
import styles from "./page.module.css";

export const metadata: Metadata = {
  title: "Privacy",
  description: "What Plated keeps, where it keeps it, and what it never collects.",
};

// Every sentence here is a claim about the running system, so it is written
// from Directory.swift and the Supabase schema, not from what the app used to
// be. The old "Plated has no server" line was true until the directory shipped.
export default function Privacy() {
  return (
    <>
      <header className={`${styles.header} wrap`}>
        <Link href="/" aria-label="Plated home" className={styles.home}>
          <Wordmark size={26} />
        </Link>
      </header>

      <main className={`${styles.article} wrap`}>
        <p className="micro">Privacy</p>
        <h1 className={styles.title}>What Plated keeps, and where.</h1>
        <p className={`${styles.updated} secondary`}>Last updated 3 September 2026</p>

        <p className={styles.lede}>
          Plated is a dinner planner for a household. Your recipes, plans,
          photographs and household stay in your own iCloud account. Plated runs
          one small server, and this page says exactly what it holds.
        </p>

        <h2>In your iCloud</h2>
        <p>
          Recipes, meal plans, grocery lists, household members, gatherings,
          photographs, posts to your Table and cooking history are saved on your
          device and synced through your private iCloud database using
          Apple&rsquo;s CloudKit. When you share a Table, CloudKit shares it with
          the people you invited and nobody else. The developer cannot read any
          of it.
        </p>

        <h2>On Plated&rsquo;s server</h2>
        <p>
          Plated keeps a directory so the app can answer one question: which of
          your contacts already use Plated. iOS no longer offers a way to answer
          that on the device, so the directory is the one part of Plated that is
          not in your iCloud. It holds:
        </p>
        <ul>
          <li>
            A salted hash of your phone number, never the number itself. The
            salt lives only on the server, so the table cannot be turned back
            into a phone book.
          </li>
          <li>The first name you already show your household.</li>
          <li>
            Your Apple account identifier, and a token that lets your phone ask
            the directory questions.
          </li>
        </ul>
        <p>
          When you look for contacts already on Plated, the phone numbers from
          your address book are sent to the server over an encrypted connection,
          hashed there, compared, and not stored. People who are not on Plated
          are never kept. The server is hosted by Supabase in the United States.
        </p>

        <h2>On this website</h2>
        <p>
          If you join the waitlist, plated.food stores the email address you
          typed and the time you typed it. It is used for one announcement when
          Plated is available and is deleted after that. Write to the address at
          the bottom of this page to be removed sooner.
        </p>

        <h2>What Plated never collects</h2>
        <p>
          Plated contains no analytics, no advertising, no tracking and no
          third-party SDKs. Nothing you do in the app is measured, profiled or
          sold.
        </p>

        <h2>Permissions Plated asks for, and why</h2>
        <ul>
          <li>
            <strong>Sign in with Apple</strong> establishes who owns the table
            and registers you with the directory above. Plated never receives
            your password.
          </li>
          <li>
            <strong>Contacts</strong> are read on your device to fill a seat.
            Numbers leave the phone only when you ask who is already on Plated,
            as described above, and are not stored.
          </li>
          <li>
            <strong>Location</strong> is used only to request a local forecast
            from Apple&rsquo;s WeatherKit. It is passed to Apple to answer that
            request and is not stored by Plated.
          </li>
          <li>
            <strong>Calendar</strong>: when you sync a gathering, Plated writes
            the event to a calendar you choose, on your device.
          </li>
          <li>
            <strong>Reminders</strong>: when you send a grocery list, Plated
            writes those items to your own Reminders list.
          </li>
          <li>
            <strong>Photos</strong> you add to a recipe or a post are stored with
            it in your own iCloud account.
          </li>
        </ul>
        <p>
          Every one of these is optional. Decline any of them and the rest of
          Plated keeps working; the feature that needed it stays quiet rather
          than nagging you.
        </p>

        <h2>Children</h2>
        <p>
          Plated is rated 4+ and does not knowingly collect information from
          children.
        </p>

        <h2>Deleting your data</h2>
        <p>
          Your Plated data lives in your iCloud account. Deleting the app removes
          the local copy. To remove the synced copy, delete Plated&rsquo;s data
          from iCloud in Settings, then your name, then iCloud, then Manage
          Account Storage. To remove your entry from the directory or the
          waitlist, write to the address below and it will be deleted.
        </p>

        <h2>Changes to this policy</h2>
        <p>
          If this policy changes, the revised version will be posted at this
          address with a new date at the top.
        </p>

        <hr className={styles.rule} />
        <p className="secondary">
          Questions about privacy in Plated:{" "}
          <a href="mailto:privacy@getplated.food" className={styles.link}>
            privacy@getplated.food
          </a>
        </p>
      </main>

      <footer className={`${styles.footer} wrap`}>
        <Wordmark size={20} />
        <Link href="/" className={styles.footerLink}>
          Home
        </Link>
      </footer>
    </>
  );
}
