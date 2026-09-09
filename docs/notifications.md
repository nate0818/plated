# Notifications

How Plated reaches a person who is not holding it. Three mechanisms, one
voice, and a set of rules that decide when to say nothing, which is most of
the time.

## The pipes

| Pipe | Carries | Where it is decided | Needs |
|---|---|---|---|
| Local schedule | Cook reminders, the Sunday ritual, the cook timer | `NotificationScheduler` | nothing |
| CloudKit silent push, then a local banner | Everything at the Table: dishes, asks, comments, plates, votes, seats | `ShareAcceptor` fetches, `TableNews` decides | notification permission |
| CloudKit silent push, then a local banner | Everything in the household: a seat joined or left, a night another phone planned, a recipe added, an edit that lost | `TablePull` drives it, `HouseholdShare` reads the zone, `ShareAcceptor.absorb` folds the nights into `PlanLedger` and hands the rest to `HouseholdSync`, `TableNews` decides | notification permission |
| APNs through the directory | An invitation to somebody already on Plated, to their Table or their household | `supabase/functions/invite` | APNs key on the server |

The middle two rows are one mechanism over two shared zones, and each zone
has exactly one reader. The nights do **not** ride the Table zone: a Table
guest must not be able to read the week. They are
`PlatedHouseholdPlan` records in the household zone, and the one reader
that walks that zone, `HouseholdShare.fetchChanges`, collects them along
with the seats and hands them on as `TableShare.Changes.plans`. Two
readers with two cursors over one zone is a delta each of them only half
sees, so `TableShare.postChanges` walks `PlatedTable` zones and nothing
else. `docs/plan-share.md` is the law for what happens to a night once
the ledger has it.

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
- Somebody else planned a night, moved it, put you down to cook it,
  renamed it, or took it off the week. The night rides the same zone
  as the dishes and lands in `PlanLedger`, never in `PlannedMeal`;
  `docs/plan-share.md` is the law for it.

And the household (docs/household.md section 10), through the same
digest, the same keys, the same 36-hour window and the same four-banner
cap, gated by the switch titled "Household and Table activity":

| event | key | copy | delivery |
|---|---|---|---|
| a seat joined the household | `household:<userRecordName>` | "Riley joined your household" / "They can see the plan, the grocery list and the cookbook now." | active with sound by day, passive 22:00 to 08:00 |
| a seat left | `household-left:<userRecordName>` | "Riley left your household" / "Their nights are open again." | passive |
| somebody added a recipe | `recipe:<recipeRecordName>` | "Riley added Ragù" / "It's in the cookbook." | passive |
| your edit lost to theirs | `conflict:<recordName>` | "Riley changed Ragù after you did" / "Their version is showing." | bell only, never a banner |

A planned night is not on this table and never comes back to it. The
household digest had a night row of its own, written when a household meal
record merged into `PlannedMeal`; that merge is gone (docs/household.md
§3.2) and the row went with it. The plan pipe's notice, "Riley planned
Tacos for Thursday", is the one and only thing said about an evening.

The person is `modifiedBy` on the record, named through their seat. A
join to the household also joins the Table, so the Table's seat notice is
suppressed for any participant whose identity holds a household seat. The
join pull, and any household pull read from the beginning, raises nothing
but the one row the join itself writes, "You joined Nate's household."
Every household notice writes a bell row and stacks under "household";
a recipe opens the cookbook, a seat Home. A plan notice opens the night
it is about (`plated://plan?day=`), which is the plan pipe's own rule.

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
  told once, now. The one exception is a household still being uploaded: a
  joiner's pull is incremental from the moment they joined, so the host's
  `publishAll` would otherwise arrive as one fresh recipe per record. While
  the root carries no `publishedAt` (the Plan and the Cookbook are saying
  "Still arriving from Nate's phone") the digest raises no recipes. Seats,
  departures and conflicts still speak. The mirror image on the host's phone is the cookbook a joiner
  brings: recipes whose `modifiedBy` is a seat arriving in the same
  delivery are what they came with, and "Riley joined your household"
  already says it.
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
- **A plan notice is about a night, never a word to you.** It is never
  addressed and never direct: "Riley put you down to cook Thursday" is
  what Riley did to the week, so the Planning switch governs it, quiet
  hours apply, and the 19:00 reminder carries the sound for the
  obligation. A night taken off is a retraction or news, decided by the
  row: unread or absent, the row and the banner go and nothing is said;
  read, "Riley took Tacos off Thursday" lands passively under Planning.
- **The lock screen names the person before the unlock.** Every category
  reveals its title and subtitle under Show Previews: When Unlocked, with
  a placeholder body ("Open to read it."). Never "Plated: Notification".
  The placeholder names the door the tap opens, so it cannot be shared by
  notices that open different doors: a household seat says "Open Home.", a
  household recipe "Open the cookbook.", a planned night "Open the plan."
- **Read on one device, quiet on the other.** On every return to the
  front, and whenever the bell is read, banners still sitting in
  Notification Centre about dishes whose rows are read are withdrawn.
- **Not while you are looking.** `Presence` records the open feed or thread;
  the router keeps a banner about the post on screen to the list, no banner
  and no sound.
- **Direct news makes a sound**, and carries the higher relevance score so
  a summary orders a reply above a plate.
- **A person speaking wears their face.** A dish, an ask, a comment, or a
  single plate is donated as a message (`INSendMessageIntent`) and the
  banner is drawn like one: the first name as the title, "The Table" or
  "Your ragù" under it, the deed as the body ("Plated Sheet-pan chicken.
  Crispy edges tonight."), and the seat's monogram in the colour that seat
  has earned (seats do not carry photographs yet; only the owner's row
  does, and the owner is never the sender). The seat is matched on
  identity, never on name alone. A person with no seat row here, the host
  seen from a guest's phone, gets the neutral monogram. Focus's
  allowed-people rule can then let your partner through.
  Needs the Communication Notifications capability
  (`config/PlatedApp.entitlements`) and `NSUserActivityTypes` in the plist.
  If the App ID lacks the capability the device build fails at signing
  (`-allowProvisioningUpdates` usually adds it; otherwise tick it once
  under Signing and Capabilities). A phone that runs this build is
  entitled. `updating(from:)` changes nothing you can read: the system
  substitutes the name and the conversation line when it draws the banner,
  which only a phone can show. The simulator draws the dressed content as
  a plain banner, so the dressing is compiled out there and the plain
  banner (title plus caption) is what it shows.

## What the person can turn off (`NewsPreferences`)

Every switch decides whether a notice lights the screen. None decides
whether the bell keeps the row: the list is the record, and off is quiet,
not blind. The icon counts only rows the person still wants to hear.

- **Cook reminders** and **Household and Table activity** are the two
  coarse switches, each honest about the iOS permission in three states.
- Under Household and Table activity, six finer ones, the categories that
  actually exist in the pipe: Dishes and asks, Replies and mentions,
  Comments on your dishes, Plates and votes on yours, New seats, Planning.
  The household's notices answer to the same six: a household seat and a
  Table seat are both New seats, a recipe joining the cookbook is Dishes.
  A night is the plan pipe's and is Planning. There is no seventh switch, because a
  second kind of seat is not a second thing a person wants to decide.
  A tag, a reply and a mention are words to you and live under Replies
  whatever record carried them. A plan notice answers to Planning before the
  addressed question is asked, because it is never a word to you. There
  is still no grocery switch: groceries do not cross Apple IDs, and a
  switch for a notice that cannot fire is a lie.
- **Mute this dish**, in the dish's own menu. Silent to everyone else, the
  author never learns, and the card shows a small bell.slash where its
  time is. The room's chatter about that dish stays in the list; a reply
  to you, a mention or a tag still gets through, and the toast says so.

The filter runs in `TableNews.show` before the fold, so "3 more" counts
what would actually have shown, and in `AppBadge.count`.

## The bell and the icon

Every notice writes one activity row keyed by event. The row stores the
sentence as parts (`template`, `actorID`, `objectTitle`) beside the prose,
and composes it when drawn with the actor's current name, so a rename
follows into last week's rows without any stored text being rewritten.
Rows written before the parts existed draw their `body`.

The list reads top to bottom: New (unread), then Today, This week and
Earlier for what has been read. A row about a dish carries the dish's
photograph on the right when it has one. Swipe reveals Clear; Clear all
empties the list after one confirmation. Nothing at the Table changes
either way. While the list is on screen, `Presence` keeps every banner to
Notification Centre: the row a banner would repeat is already in front.

 Plates and votes on
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

## The cook timer

The one time-bound thing in the app, done the way a delivery app does an
order. Starting a timer in Cook Mode requests a Live Activity
(`CookTimerLive`, attributes in `CookTimerActivity.swift`, hand-copied
into the widget target and diffed by `scripts/check-tokens`). The system
draws the countdown on the Lock Screen and in the Dynamic Island with no
update from the app; past the finish the content is stale and the view
says "Done" until Cook Mode is opened again and takes it down. Clear and
End take it down at once. The finish itself is the local notification,
delivered Time Sensitive so it breaks through a Focus, with the capability
in `config/PlatedApp.entitlements`. Nothing else in Plated earns a Live
Activity: a day-long "tacos tonight" has no end and is the billboard
Apple's guideline 4.5.3 names.

## Where a tap lands

Every notice carries a `plated://` link. A dish or a comment opens that
post's thread; a seat opens Home; a reminder opens the plan. A plan notice,
and the reminder for a night somebody else planned, open the plan on that
night: `plated://plan?day=yyyy-MM-dd` (`DeepLink.url(plan:)`,
`planDay(in:)`). The shell selects Plan and parks the day in `LinkRelay`,
and `WeekView` moves its anchor to it; while the week is on screen,
`Presence.planVisible` keeps a plan banner to the list. The tap arrives
at `NotificationRouter`, is parked in `LinkRelay`, and the shell collects it
through the same `route(_:)` that `onOpenURL` uses. Activity rows written by
the news carry the same link and open the same way.

Actions, drawn by the system: **Plate it** on a dish, **Reply** on a
comment, **Grocery list** on your own cook reminder. The reminder for a
night planned on another phone carries no grocery action: the list has
nothing for that night. They write through the
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

`/invite` pushes a `plated://invite` link carrying the kind. The app never
seats anybody on a tap: every road (the push, a plated.food Universal
Link, a raw iCloud link through the CloudKit delegate) ends in
`ShareAcceptor.received`, which reads the share's metadata with its root
record, decides table or household by the zone the share sits on, and
posts `invitationReceived` for the shell to present: the Table's
"Nate kept you a seat at their table" dialog with Join the Table and Not
now, or the household's join sheet. Nothing is accepted before the first
button. A link that accepted on tap would let any push put a person at a
stranger's table.

## The server pipe

`Directory.registerDevice` sends the APNs token to `/device` once the phone
has a directory session. `Directory.notifyInvite` asks `/invite` to nudge an
invitee who already has the app. The functions live in `supabase/functions`
and the sender in `invite/apns.ts`, beside the one function that sends.

**Half deployed, and not sending yet.** State on the `plated` project as of
2026-09-08:

- Done: the migration is applied, as `20260908113335_device_tokens_sandbox`.
  `device_tokens.sandbox` and the two `invites` columns exist, both indexes
  exist, RLS is on with no policies and the service role holds the grants.
- Done: `device` is deployed and ACTIVE with `verify_jwt` off, matching
  `register` and `lookup`. A phone with a directory session can register a
  token today.
- Still Nate's: create an APNs key in the Apple Developer portal (Keys, then
  a new key with Apple Push Notifications service). The `.p8` downloads once
  and never again.
- Still Nate's: set `APNS_TEAM_ID`, `APNS_KEY_ID` and `APNS_KEY_P8` on the
  project.
- Still Nate's: deploy `invite` with `verify_jwt` off. It needs both
  `index.ts` and its sibling `apns.ts` in the same deploy.

Until the key and the secrets are set, `apns.ts` returns
`{ configured: false }` and the caller carries on, so an unconfigured push
is a missing nicety rather than an error. The app's calls to a function
that is not deployed fail silently too, which is the designed behaviour for
every directory call: no error a person can see, nothing the app claims to
have done.

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
Three debug flags stand in:

- `-plated-ask-notifications` spends the permission prompt at launch.
- `-plated-fake-table-news` writes a dish by "Riley" into the store and
  runs it through `TableNews` as if it had just arrived, with a comment and
  a plate on your newest own post when there is one. It also folds two
  nights Riley planned into `PlanLedger`: tomorrow with Riley cooking and
  the day after with you cooking, in a zone of their own
  (`PlanLedger.rehearsalOwner`, `rehearsal-zone`) that the flag makes
  the household, so both bodies and the remote reminder can be looked
  at. It then rebuilds the reminders and prints the pending
  `plated.turn.remote.` requests. A launch without the flag drops every
  `rehearsal-zone` entry, so a real table's nights are never mixed with
  Riley's.
- `-plated-rehearse-household` seeds the sample household if the store is
  empty, stamps its head with this identity, sets membership to a fake
  host "Sam" and absorbs a household delta from him: two seats and two
  recipes, so the household notices and the member's view can be
  photographed without a second Apple ID. Sam's week is not in that delta:
  a night is not a household record, and `-plated-fake-table-news`
  rehearses remote nights through `PlanLedger`.

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

`make test` runs `PlatedTests`. `TableNews.digest` (Table and household),
`select`, `content`, `thread`, `staleDelivered`, `list`, `AppBadge.count`,
`Seats.match` and `NotificationRouter.presentation` are pure and hold the
rules above, and `HouseholdSyncTests` holds the household digest to its
own-action guard (held one half at a time, with a seat for the reader in
the fixture so that silence is the guard answering and not "named, or not
sent"), its first-pull silence, the host's first publish, the cookbook a
joiner brings, the seat that left, and a household delta never touching
the local plan: never
about you, named or not sent, once, the replay window, coalescing, the
cap, the fold, passive plates outside the cap, the kiss, quiet hours with
the direct exception, threads, retractions that are never re-dated, rows
that keep the event's time, read-elsewhere withdrawal, the badge counting
only other people, a seat matched on identity, deep-link parsing, the
invite link's https rule. The merge's reaction-dropping bug was found by
one of them.

`PlanNewsTests` holds the plan pipe to `docs/plan-share.md`:
`PlanLedger.absorb` (mine skipped, deletion by the `plan-` prefix, a
replayed owner reconciled against what was delivered, past-day deletions
silent, the household filter, the delta computed before the overwrite, a
removed and added pair cancelled), the plan notices (added, moved, put
you down, renamed, an edit that means nothing, removed as retraction and
as news, mine ignored, the replay window on `changedAt`, once), the
Planning switch before the addressed question, the plan banner kept to
the list over the week, the deep link's day round trip, the night phrase
ladder, and the reminder dedupe (a local night wins the day).

## The plan pipe

Built Sept 7 2026; `docs/plan-share.md` is the law and this is only the
pointer. A night planned on one phone rides the household zone the
household invite mints (`docs/household.md`), as a `PlatedHouseholdPlan`
record, and lands on every other phone in the household in `PlanLedger`,
a JSON book beside the plates, never in `PlannedMeal`. It does not ride the
Table zone: a Table guest must not be able to read the week. The rules the
pipe decided:

- A plan notice answers to the **Planning** switch, and to nothing else.
- It is **never addressed and never direct**: a night is a fact about the
  week, not a word to you, even when the cook it names is you.
- **Quiet hours apply.** The 19:00 reminder carries the sound for the
  obligation, so the notice does not need to.
- A night taken off is **a retraction or news, decided by the row**: unread
  or absent, the row and the banner go silently; read, a passive "took it
  off" line.
- **One reminder per night.** A remote night whose cook is you schedules
  "Your night tomorrow" the way a local one does, on a day no local meal
  claims; a local night wins the day, and for a remote night only the
  cook's own reminder is sent.

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
- **The digest reads shared state** (`TableIdentity`, `TableLedger`,
  `PlanLedger`, the app group). The tests reset it in `setUp`/`tearDown`,
  which means they wipe a simulator's real ledgers when run there, and
  `PlanNewsTests` puts the household owner back. Injecting them would
  make the tests pure; not done because it touches every caller.
