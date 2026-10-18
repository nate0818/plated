import type { Metadata } from "next";
import SiteFrame from "../components/SiteFrame";
import styles from "./page.module.css";

export const metadata: Metadata = {
  title: "Privacy",
  description: "What Plated stores, where it lives, and how to manage your data.",
  alternates: { canonical: "/privacy" },
};

const sections = [
  ["icloud", "Your data in iCloud"],
  ["server", "Directory and notifications"],
  ["website", "This website"],
  ["permissions", "Permissions"],
  ["deletion", "Deleting your data"],
  ["contact", "Contact"],
] as const;

// Data handling and retention details are preserved from the existing policy.
export default function Privacy() {
  return <SiteFrame>
    <main id="main" className={styles.main}>
      <header className={styles.intro} data-reveal="stagger">
        <p className={styles.eyebrow}>Privacy</p>
        <h1>Your data<br />and your privacy</h1>
        <p className={styles.lede}>Your recipes, plans, and photos are stored in your iCloud account. Plated also runs directory and notification services, explained below.</p>
        <time className={styles.updated} dateTime="2026-10-18">Updated October 18, 2026</time>
      </header>
      <div className={styles.document}>
        <nav className={styles.contents} aria-label="On this page">
          <p>On this page</p>
          <ul>{sections.map(([id, label]) => <li key={id}><a href={`#${id}`}>{label}</a></li>)}</ul>
        </nav>
        <article className={styles.policy} aria-label="Privacy policy">
        <h2 id="icloud">Your data in iCloud</h2>
        <p>
          Recipes, meal plans, grocery lists, household members, gatherings,
          photos, posts to your Table and cooking history are saved on your
          device and synced through your private iCloud database using
          Apple&rsquo;s CloudKit. The notification service processes the limited
          shared activity described below; it does not copy your recipe book or photos.
        </p>
        <p>
          If you join a household, the plan, the grocery list, the recipe book and
          the people list are shared with the other members of that household
          through iCloud, and each member&rsquo;s own iCloud keeps a copy.
          Leaving takes your recipes with you and removes the rest from your
          phone. The household keeps its copy of the recipes you shared with
          it, including the ones you brought when you joined.
        </p>
        <p>
          When you share a Table, CloudKit shares your posts with the people
          you invited and nobody else. A Table guest never sees the plan, the
          grocery list or the recipe book.
        </p>

        <h2 id="server">Directory and notification services</h2>
        <p>
          Plated keeps a directory so the app can answer one question: which of
          your contacts already use Plated. iOS no longer offers a way to answer
          that on the device. The directory and notification service are hosted
          outside your iCloud. They hold:
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
          <li>
            An opaque push-notification token issued by Apple, the app version
            and build, its release channel, whether iOS currently allows
            notifications, your News preference and the last time that
            registration was refreshed. Plated uses these to deliver invitations,
            shared activity and service notices, and
            diagnose delivery failures.
          </li>
        </ul>
        <p>
          The directory is used for two things. When you look for contacts
          already on Plated, the phone numbers from your address book are sent
          to the server over an encrypted connection, hashed there, compared,
          and not stored. People who are not on Plated are never kept. When
          somebody invites you and your number is in the directory, the server
          sends a notice to your phone saying who it is from, which it can do
          because it holds a push token for each phone you have signed in on.
          The invitation link itself is never stored. What stays behind is a
          record that the invitation happened: who sent it, the hashed number
          and the time, so that no host can turn invitations into a mailing
          list. The server is hosted by Supabase in the United States.
        </p>

        <h2 id="invitations">When someone invites you</h2>
        <p>
          Plated records the inviter, a salted hash of the invited phone number,
          the inviter&rsquo;s first name, the delivery result and the time of the
          invitation. If the invited number already belongs to a Plated account,
          its private CloudKit share link is sent to the server only to compose
          that immediate notification and is not stored. The remaining
          invitation metadata is retained for 30 days for abuse limits and
          operational troubleshooting, then deleted.
        </p>

        <h2 id="notifications">Shared activity notifications</h2>
        <p>
          To deliver phone alerts without waiting for the recipient to open Plated,
          the app sends a short-lived Apple authorization token and a reference to
          a confirmed comment, reaction or accepted invitation to Plated&rsquo;s
          Supabase notification service in the United States. The service verifies
          the sender, reads the referenced shared record and its related post or
          comment, and checks current share membership. The authorization token
          is used only during that request and is never stored. Photos and recipe
          contents are not fetched.
        </p>
        <p>
          The service keeps verified iCloud account identifiers, a device identifier,
          Apple push tokens, notification preferences, muted thread and blocked
          account identifiers, and a time-zone name. Notification text can include
          the sender&rsquo;s name, a post title and a short comment excerpt. Text
          and delivery status are retained for at most three days for retries and
          troubleshooting; duplicate-prevention identifiers are retained for at
          most eight days. Apple receives the payload to deliver it to the
          intended device. Account deletion removes device registrations and
          related delivery records.
        </p>
        <p>
          Notification preferences control phone alerts. Muting or blocking is
          private; the other person is not informed. The in-app activity list
          remains in iCloud.
        </p>

        <h2 id="website">On this website</h2>
        <p>
          If you request early access or join the launch list, plated.food stores
          your email address, the time you submitted it and which list you
          requested. Early-access addresses are used to manage invitations and
          email you about your request. Launch-list addresses are used to
          announce when Plated is available. They remain until you ask Plated
          to delete them.
          Write to the address at the bottom of this page to be removed.
        </p>

        <h2 id="collection">What Plated doesn’t collect</h2>
        <p>
          Plated contains no analytics, no advertising, no tracking and no
          third-party SDKs. Nothing you do in the app is measured, profiled or
          sold.
        </p>

        <h2 id="permissions">Permissions and what they’re for</h2>
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
          <li>
            <strong>Notifications</strong> let Plated tell you about invitations,
            household joins, comments, replies, reactions and rare service or
            release notices. Your choice is
            optional. News from Plated starts off and must be turned on separately;
            allowing Table or cooking notifications does not subscribe you to
            founder announcements. Plated stores the delivery details described
            above, and removes a device token when Apple reports that it is no
            longer valid.
          </li>
        </ul>
        <p>
          Every one of these is optional. Decline any of them and the rest of
          Plated keeps working; the feature that needed it stays quiet rather
          than nagging you.
        </p>

        <h2 id="children">Children</h2>
        <p>
          Plated is rated 4+ and does not knowingly collect information from
          children.
        </p>

        <h2 id="deletion">Deleting your data</h2>
        <p>
          Your Plated data lives in your iCloud account. Deleting the app removes
          the local copy. To remove the synced copy, delete Plated&rsquo;s data
          from iCloud in Settings, then your name, then iCloud, then Manage
          Account Storage.
        </p>
        <p>
          The directory is separate. In Plated, open Settings and choose
          <strong> Delete directory account</strong>. After you confirm, Plated
          removes your directory profile, invitations associated with it,
          registered devices, directory sessions and personal notification
          delivery records, then signs this iPhone out. It does not delete
          recipes, plans, grocery lists, household data, Table posts,
          photos or any other content in your private iCloud. If this
          iPhone no longer has a verified directory session, write to the
          address below for help removing an earlier registration. Waitlist
          email removal also remains available by email. This version does not
          retain the Apple refresh token needed to revoke Sign in with Apple
          automatically. After deletion, it shows the separate path in iOS
          Settings: your name, Sign in with Apple, Plated, then Delete.
        </p>

        <h2 id="changes">Changes to this policy</h2>
        <p>
          If this policy changes, the revised version will be posted at this
          address with a new date at the top.
        </p>

        <hr className={styles.rule} />
        <p id="contact" className="secondary">
          Questions about privacy in Plated:{" "}
          <a href="mailto:privacy@getplated.food" className={styles.link}>
            privacy@getplated.food
          </a>
        </p>
        </article>
      </div>
    </main>
  </SiteFrame>;
}
