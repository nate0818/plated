# Notifications

How Plated reaches a person who is not holding it. Three pipes, one voice,
and a set of rules that decide when to say nothing, which is most of the time.

## The three pipes

| Pipe | Carries | Where it is decided | Needs |
|---|---|---|---|
| Local schedule | Cook reminders, the Sunday ritual, the cook timer | `NotificationScheduler` | nothing |
| CloudKit silent push, then a local banner | Everything at the Table: dishes, asks, comments, plates, votes, seats | `ShareAcceptor` fetches, `TableNews` decides | notification permission |
| APNs through the directory | An invitation to somebody already on Plated | `supabase/functions/invite` | APNs key on the server |

The Table pipe is the interesting one. CloudKit sends a silent push when a
shared zone changes. The app fetches the delta in the delegate, folds it
into the store, and only then decides what a person should see. The
notification is composed on the phone from what actually arrived, never
from the push payload, which carries no truth of its own.

A silent push is not delivered to an app the person has force-quit, and
is deferred in Low Power Mode. Plated does not work around that with an
extension (see `docs/open-decisions.md` §16). The bell catches up on the
next open: every return to the front pulls, at most once a minute.

Every pull, from the push, the feed, an accepted share, a tapped notice or
the front door, goes through `TablePull`, one at a time. A pull that lands
mid-pull joins it and runs once more after, so two roads can never race
for one change token or raise one banner twice.

## What counts as news (`TableNews`)

- Somebody else plated a dish, asked the table, or tagged you in a dish.
- Somebody wrote on your dish, replied to you, or mentioned you.
- Plates and votes on what you put on the table, coalesced per post and
  read back from the ledger, so "Riley, Sam and Jo plated your ragù" names
  everybody so far, not just this delivery. Everyone plating yours is the
  Chef's kiss.
- A seat became real: an invitation was accepted.

And the rules that keep it quiet:

- **Never about you.** Your own post arriving from your own iPad is not
  news. The identity is confirmed with CloudKit before any of this is
  decided; a placeholder id decides nothing.
- **Named, or not sent.** A plate or vote from somebody the phone cannot
  name (a table from before ballots carried names) stays a count on the
  dish and never becomes a sentence.
- **Once.** Every event has a key, remembered in the app group. A change
  token reset that replays a zone raises nothing twice.
- **History is not news.** A delta read from the beginning of a zone (fresh
  install, refused token) is windowed to 36 hours. An incremental delta is
  trusted whole: a dish written on a plane last week and uploaded today is
  told once, now.
- **Few.** At most four banners per delivery. The rest fold into "3 more
  from Riley and Sam". Every one still lands in the bell.
- **A plate or a vote is always delivered passively:** it is in the list
  and on the icon, and the screen stays dark. Replacing the same line for
  every plate in a room of eight lit the phone seven times for a fact the
  Table already draws as a count. The kiss is the exception. Passive
  notices never count toward the four-banner cap, so plates cannot crowd
  out a dish.
- **Quiet at night for the room, not for you.** 22:00 to 08:00 a dish is
  delivered passively. A reply, a mention, a word on your dish, or the kiss
  is delivered at any hour; that is what a person's Focus is for.
- **The room is one conversation, a dish is another.** Dishes, asks and
  seats stack under "The Table"; everything about one dish stacks under
  that dish, and every notice about a dish carries its photograph.
- **A retraction takes its notice with it.** An un-plate rewrites the line
  to whoever still stands, or removes it; a deleted comment removes its
  banner and its row. Neither reads as fresh news.
- **The lock screen names the person before the unlock.** Every category
  reveals its title and subtitle under Show Previews: When Unlocked, with
  a placeholder body ("Open to read it."). Never "Plated: Notification".
- **Read on one device, quiet on the other.** On every return to the
  front, and whenever the bell is read, banners still sitting in
  Notification Centre about dishes whose rows are read are withdrawn.
- **Not while you are looking.** `Presence` records the open feed or thread;
  the router keeps a banner about the post on screen to the list, no banner
  and no sound.
- **Direct news makes a sound**, and carries the higher relevance score so
  a summary orders a reply above a plate.

## The bell and the icon

Every notice writes one activity row keyed by event. Plates and votes on
one dish update the same row (it moves to the top and reads as new again).
`PlatedNotification` is mirrored, so a person with two devices writes the
row twice and then keeps the older: `TableNews.dedupeRows`. Rows about a
person show the person's face. Opening a dish reads its rows, clears its
banners from Notification Centre and updates the icon.

The icon counts unread rows other people caused, and only while Table
activity is on. Your own "You posted" rows never badge the Home Screen.

Every pull, not only the push, goes through `ShareAcceptor.absorb`, so a
night in Low Power Mode or a force-quit cannot leave the bell asserting
that nothing happened: the next pull tells it, once, and the banners are
kept to the list if the feed is in front.

## Where a tap lands

Every notice carries a `plated://` link. A dish or a comment opens that
post's thread; a seat opens Home; a reminder opens the plan. The tap arrives
at `NotificationRouter`, is parked in `LinkRelay`, and the shell collects it
through the same `route(_:)` that `onOpenURL` uses. Activity rows written by
the news carry the same link and open the same way.

Actions, drawn by the system: **Plate it** on a dish, **Reply** on a
comment, **Grocery list** on your own cook reminder. They write through the
same road a tap in the feed would take, so a plate from the lock screen is
in the ledger and the outbox before the app opens.

## The one permission prompt

iOS grants one ask. It is spent at whichever earned moment comes first:
planning a first night, posting a first dish, accepting a seat at somebody
else's table, or reaching for either switch in Settings. Never at launch,
and never under the opener: a seat accepted on a cold start parks the ask
and the shell spends it once it has been in front for a beat.

Settings has two switches, both honest about permission, in three states:
never asked (the switch asks), refused (the caption sends you to iOS
Settings), allowed. The state is re-read whenever the app comes back to
the front.

## An invitation from a push

`/invite` pushes a `plated://invite` link. The app never seats anybody on a
tap: it shows "Riley saved you a seat at their table" with Take the seat
and Not now, and accepts only on the first. A link that accepted on tap
would let any push put a person at a stranger's table.

## The server pipe

`Directory.registerDevice` sends the APNs token to `/device` once the phone
has a directory session. `Directory.notifyInvite` asks `/invite` to nudge an
invitee who already has the app. The functions live in `supabase/functions`
and the sender in `_shared/apns.ts`.

**Not deployed yet, and not sending yet.** Three things have to happen, in
order, and all three are Nate's:

1. Create an APNs key in the Apple Developer portal (Keys, then a new key
   with Apple Push Notifications service). Download the `.p8` once; it
   cannot be downloaded again.
2. Set the secrets on the `plated` Supabase project:
   `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_KEY_P8`.
3. Apply `supabase/migrations/20260904_device_tokens_sandbox.sql` and deploy
   `device` and `invite` with `verify_jwt` off, like `register` and `lookup`.

Until then the app's calls to `/device` and `/invite` fail silently, which is
the designed behaviour for every directory call: no error a person can see,
nothing the app claims to have done.

What the server refuses on its own: more than twenty invitations a day from
one host, more than two a day from one host to one number, a share link
that is not an iCloud or plated.food https URL, a token that is not 32
bytes of hex, more than eight tokens per person (oldest dropped). The
response to `/invite` is the same whether or not the number is known, and
both lookups run either way. The share URL is stored only for a number that
belongs to somebody, because that is what the push needs, and is never
logged.

## Rehearsing on a simulator

Silent pushes need a real APNs token, so a simulator never receives one.
Two debug flags stand in:

- `-plated-ask-notifications` spends the permission prompt at launch.
- `-plated-fake-table-news` writes a dish by "Riley" into the store and
  runs it through `TableNews` as if it had just arrived, with a comment and
  a plate on your newest own post when there is one.

Always `simctl terminate` before a flag-carrying launch; a running process
keeps its original arguments.

`xcrun simctl push` does **not** exercise the silent path. A visible payload
lands in `NotificationRouter.willPresent`; a content-available payload with
`ck.met.sid = plated-shared-v1` never reached
`application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` in
either the async or the handler spelling, foreground or background (Sept 4
2026, iOS 26.2 simulator). The silent pipe is therefore verified only as
far as the fetch-and-digest logic the rehearsal flag drives. Proving the
delegate wiring needs a phone, a second device posting to a shared table,
and the console open, watching for `[Push] silent push from`.

## Tests

`make test` runs `PlatedTests`. `TableNews.digest`, `select`, `content`,
`thread`, `staleDelivered`, `list`, `AppBadge.count`, `Seats.match` and
`NotificationRouter.presentation` are pure and hold the rules above: never
about you, named or not sent, once, the replay window, coalescing, the
cap, the fold, passive plates outside the cap, the kiss, quiet hours with
the direct exception, threads, retractions that are never re-dated, rows
that keep the event's time, read-elsewhere withdrawal, the badge counting
only other people, a seat matched on identity, deep-link parsing, the
invite link's https rule. The merge's reaction-dropping bug was found by
one of them.

## Still open

Found by the Sept 4 review and left deliberately, each with a reason:

- **"Replied to you" and mentions match on display name, not identity.**
  The wire carries `replyToName` and `mentions` as names because that is
  what the composer stores. Two people called Sam at one table would both
  be told. Fixing it means stamping `replyToID` on the note record and in
  `TableComment`, a wire change worth doing with the mention rendering
  rework `docs/engineering-notes.md` already asks for.
- **The Chef's kiss denominator** is the reader's household count. See
  `docs/open-decisions.md` §1b: a product call, not a 4am fix.
- **Provisional authorization** would let Table news land quietly before
  the prompt is ever spent. Not used: it is not clear that a later full
  prompt is still offered once provisional has been granted, and the one
  prompt is not worth the experiment.
- **`PlatedNotification.body` still stores whole sentences.** See the note
  in `docs/engineering-notes.md`; the news rows follow the existing pattern
  rather than fixing the class. A rename after the fact leaves the old name
  in old rows.
- **An Apple ID change mid-fetch.** `TableIdentity.confirm` can write the
  new id while `reset` erases it; a push absorbed in that window could
  stamp the person's own posts remote. Rare, bounded to one delivery, and
  the next confirm repairs the id. Not worth a lock yet.
- **iPad with two windows** shares one `Presence` and one `LinkRelay`. A
  notice could be kept to the list because the other window shows the
  post. Harmless; noted so nobody rediscovers it.
- **The digest reads shared state** (`TableIdentity`, `TableLedger`, the
  app group). The tests reset it in `setUp`/`tearDown`, which means they
  wipe a simulator's real ledger when run there. Injecting the three
  would make them pure; not done because it touches every caller.
