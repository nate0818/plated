# The household

How a household crosses Apple IDs, and how it differs from the Table. This is
the contract the code is written to. `docs/notifications.md` holds the law for
what the app says out loud; DESIGN.md holds the register. Read those first.

Written 2026-09-07 from a full read of the codebase, from how comparable
products handle invitations (Apple Reminders, Notes, Family Sharing, Invites,
AnyList, Cozi, Splitwise, 1Password, Notion, Slack), and from an adversarial
review by four critics whose findings are folded in below. Every
meal-planning competitor shares a household by sharing a password. Plated does
not, and the seat model in `Seats.swift` is why it cannot: a person has to
exist to be named.

---

## 1. Two rooms, two shares

**The household** is the people you plan and cook with. Everyone in it sees
the same week, the same grocery list, the same cookbook and the same roster,
and everyone can change them. One household per Apple ID.

**The Table** is the household plus the seats it gave away: friends in other
households who share what they cook. A Table guest sees dishes, asks, plates
and replies. A Table guest never sees the plan, the list or the cookbook.

These are two CloudKit shares on two zones in the host's private database:

| | zone | root record | share | who accepts it |
|---|---|---|---|---|
| Table | `PlatedTable` (exists) | `table-root`, type `Table` | `.readWrite` public | household members and friends |
| Household | `PlatedHousehold` (new) | `household-root`, type `PlatedHousehold` | `.readWrite` public | household members only |

A household member holds both shares. The household root record carries the
Table share's URL (`tableShareURL`), so accepting a household invitation
accepts the Table in the same motion and the joiner never sees two links.

The Sept 4 design review required exactly this: "Household-only content must
not be placed beneath that broad share and hidden in UI. Design a separately
restricted share/record hierarchy, acceptance flow, and migration."

**Why the household share is still a link.** The Table learned, expensively,
that participant-only shares (`publicPermission = .none`) admit almost nobody:
the number in your Contacts is very often not the address on the person's
iCloud account, and every such invitation failed. A household invitation that
does not open is worse than the theoretical risk of a forwarded text. So the
link is the credential, sent by hand in a message the host wrote, and the app
adds four things the Table does not have: every link names the seat it was
minted for, the host sees who joined and can remove them, a removed person is
told and cannot walk back in on the old link (section 8), and identity is set
once on a seat and never replaced. This is a deliberate deviation from
"separately restricted" and it is written here rather than made quietly.
Revisit if iOS 26's access-request APIs (`CKShare.allowsAccessRequests`,
`oneTimeURL`) prove functional on a phone.

**No participant operations on a public share, ever.** Apple's documentation
says a share's participant list may only be modified while `publicPermission`
is `.none`, and the field report that measured it says `addParticipant` on a
`.readWrite` share raises an Objective-C exception that `try?` cannot catch.
The Table's `invite` has that line and has only survived because lookups
usually fail. The household never calls `addParticipant`, never calls
`shareParticipant(forPhoneNumber:)`, and never sets `publicPermission` to
`.none` on a share that has participants (that evicts everyone). The Table's
`invite` loses its `addParticipant` line in the same change. Link joiners are
`publicUser` participants with no lookup info, so nothing anywhere matches a
participant by phone or email; identity is the only key.

## 2. Where the truth lives

SwiftData mirrors the private database only, so nothing in the mirror can
cross Apple IDs. The store stays the thing every screen renders from. The
household zone is the cross-account authority, exactly as the Table zone is
for `TablePost`.

- **Same Apple ID, two devices:** the mirror carries the row, as it always
  has.
- **Different Apple IDs:** the household zone carries a record, and `merge`
  folds it into the local store keyed on `shareRecordName`, update-or-insert,
  never delete-and-reinsert (cook sessions, the local nights that point at a
  recipe, and the rota all depend on row identity).

`PlannedMeal` is not in this. It is a private, per-Apple-ID row, and the
week crosses Apple IDs through the plan pipe in the same zone, never through
the mirror. Section 3.2 says why.

**The mirror does not dedupe.** A member's second device can receive one
record twice: once through the pull (an insert keyed on `shareRecordName`)
and once through the mirror (a second row the mirror imported from the first
device, with the same `shareRecordName`). This is the class that multiplied
seats before. `HouseholdSync.collapseDuplicates(in:)` runs after every merge
and on every remote-change notification: for every synced entity, rows with
one `shareRecordName` collapse onto the oldest by `createdAt`, the
relationships that point at them (a night's `.recipe`, `.cook` and
`.gathering`, `Ingredient.recipe`, `RecipePhoto.recipe`) are rehomed onto the
survivor, cook sessions are re-keyed, and the rest are deleted. There is no
pass over `PlannedMeal` and there must never be one again: a night has no
household record to be duplicated by, and a collapse there was the repair for
a shape section 3.2 has taken out instead.

**Names are minted at birth.** Every synced model mints `shareRecordName` in
its initialiser, like `shoppingID`, so the mirror exports the row already
named and two devices of one Apple ID can never name one row twice. Rows that
predate the field (empty name) are named by exactly one device: the one that
transitions the household into `.hosting` (publishAll) or `.member` (join),
inside that transaction, and it records itself as the minter in the app
group. Any other device of that Apple ID that finds membership set and rows
unnamed waits for the mirror and never mints. On pull, before inserting an
unmatched record, `merge` looks for a nameless local twin (a recipe by title
and `createdAt`; a seat by name; a gathering by title and `startDate`) and
adopts the name onto it instead of inserting.

**Enqueueing is content-based, never save-based.** A save observer that
enqueues whatever saved would loop: the merge saves, the bookkeeping after a
push saves, and each save would re-enqueue the row. So every synced row
carries `shareFingerprint`, a hash of its wire fields (never of bookkeeping,
`isFavorite`, `isPinned`, `reminderID`, `calendarEventID`; photos enter as a
hash of their bytes). `willSave` computes the fingerprint of every inserted or
changed synced row and parks an outbox entry only when it differs from the
stored one; `didSave` commits the parked entries. The merge and the post-push
bookkeeping set `shareFingerprint` to the version exchanged, in the same
save, so they never enqueue. A launch-time sweep enqueues every row whose
live fingerprint differs from its stored one, because a kill between the
store commit and the outbox write loses the entry with no other repair.

**Versions, not clocks.** A push fetches the server record first. If the
server's `modifiedAt` differs from the row's `shareModifiedAt` (the version
this device last exchanged), somebody else wrote since this device last
looked: the server version is merged locally, the outbox entry is dropped,
and for a recipe a bell row says so ("Riley changed Ragù after you did. Their
version is showing."). Otherwise the fetched instance (it carries
the change tag) is saved with `modifiedAt` = the outbox entry's `at`, which
is the time of the first local change since the row last matched the server,
never a later re-enqueue. A `.serverRecordChanged` from the save takes the
server record out of the error, re-runs the comparison and retries, bounded
at three. A pull applies a record only when its `modifiedAt` differs from the
local `shareModifiedAt`, and skips any row with a pending outbox entry.
Wall-clock `modifiedAt` is on the wire for display and for the digest, never
as an arbiter between phones. Seats have field rules on top (section 3.1).
Deletion wins any conflict, as CloudKit's own semantics do.

**Gone from the wire.** A push whose fetch returns exactly `.unknownItem`, on
a row whose `shareModifiedAt` is non-nil, means a member deleted it: the local
row is deleted and the entry dropped. Any other error is a retry, never a
delete. A row with `shareModifiedAt == nil` was never synced and is created.
Leave and removal reset every kept row to never-synced (section 8), so the
rule can never fire on a person's own recipes in their next household.

**The mirror is not free.** Every member's private mirror re-exports the
merged household, photos included, into that member's own iCloud storage. A
household of four stores its cookbook four times over plus once in the zone.
That is an accepted cost of keeping one store; it is not a correctness fault,
because the hand-written types carry a reserved prefix the mirror ignores.

## 3. What travels

Every hand-written type carries the reserved `PlatedHousehold` prefix and is
added to `TableShare.assertNoEntityCollision`. The mirror adopts any
private-database record whose type equals a SwiftData entity name (the ghost
post), so no record may ever be typed `PlannedMeal`, `Recipe`,
`HouseholdMember`, `GroceryItem`, `Gathering` or `HouseholdProfile`.

Every child record sets `parent` to `household-root` (the share hierarchy)
and a `.deleteSelf` reference to it (the cascade). Every record carries
`modifiedAt: Date`, `modifiedBy` (the identity that last pushed it; the
notices name this person and the own-action guard checks it) and, where
ownership matters for leaving, `authorID` (the identity that created it,
never changed). Bools are INT64 read through `TableShare.int`. A list key is
omitted when the list is empty, never written as `[]`.

Wire dates that mean a calendar day travel as `yyyy-MM-dd` strings and are
turned back into a `Date` with `Calendar.current` on the reading phone, so two
time zones cannot move a dinner between days.

What the household carries is **the roster, the cookbook, gatherings and the
grocery list**. The week is in the same zone but is not one of these: it
rides the plan pipe, as `PlatedHouseholdPlan` records, and docs/plan-share.md
owns it end to end.

### 3.1 `PlatedHouseholdSeat` (one per `HouseholdMember`)

`name`, `role`, `roleLine`, `colorHex`, `dietaryNotes`, `avoidedIngredients`
(omit if empty), `cookWeekdays` (omit if empty), `isPrimaryCook` (INT64),
`seat` (the raw seat string), `invitedAt`, `joinedAt`, `leftAt`,
`participantID`, `userRecordName`, `bio`, `photo` (CKAsset), `authorID`,
`modifiedBy`, `modifiedAt`.

**`phoneE164` and `inviteEmail` never travel.** They are the address a
private invitation went to, picked from the host's Contacts under a screen
that says "Never uploaded", and a member's phone has no use for them. They
stay on the host's row; a pulled seat never clears them.

Field rules, applied on both push-conflict and pull:

- `seat` only moves forward: notOnPlated or invited may become joined; joined
  may become left; nothing goes backwards. `head` is accepted only on the
  seat whose `userRecordName` is the zone owner's record name.
- `role == "owner"` is accepted only on that same seat; any other seat
  arriving as owner is merged as partner. A member's own device rewrites
  owner to partner and head to joined on its own seat before every push. The
  zone has exactly one head and it is the host's.
- `userRecordName` is set once and never changed. A claim on a seat that
  already carries somebody else's identity creates a fresh seat instead.
  `participantID`, `joinedAt` and `leftAt` are never cleared once set.
- `name`, `bio` and `photo` belong to the person the seat is: when the seat's
  `userRecordName` is this device's identity, the local values win over the
  wire, and no device ever writes those fields on a seat carrying another
  identity (the shell's owner repair included).
- `role` and `cookWeekdays` belong to the household; last writer wins, with
  the owner rule above.

### 3.2 The plan is not a household record

There is no `PlatedHouseholdMeal`, and there must never be one.

A night used to travel here as a household record and merge into
`PlannedMeal`. `PlannedMeal` is a `@Model` in a store configured
`cloudKitDatabase: .automatic`, so a household fact placed there is owned by
the zone AND by the writer's own private mirror at the same time, and that
mirror carries it to the same person's other devices, which are themselves
merging the same zone record. That is two writers on one fact by
construction. `collapseDuplicates` running after every merge repaired that
shape rather than fixing it: it held in the cases somebody tested and failed
quietly in the rest. Nate's call, 2026-09-08: drop the meal merge.

So a household night is a `PlatedHouseholdPlan` record in this same zone,
held on the reading phone in `PlanLedger` beside the plates, and drawn by the
planner beside that phone's own nights. **docs/plan-share.md** owns the
record, the publisher, the reader, the ledger, the overlay, the notices and
the reminders, including the write path that makes a remote night editable;
last writer wins on the record's `modifiedAt`. Nothing in either document
ever merges a plan into a `PlannedMeal`.

What `PlannedMeal` keeps is `shoppingID` (the grocery and drag key, which
predates all of this and is minted with the row) and `authorID` (what
`Awards.metrics` reads to decide whose night an unassigned one is). It
carries no `shareRecordName`, no `shareModifiedAt` and no `shareFingerprint`:
there is no record for them to be about.

### 3.3 `PlatedHouseholdRecipe` (one per `Recipe`)

Every field on `Recipe` except `isFavorite` and `isPinned`, plus
`ingredientsJSON` (the ordered ingredient list as one JSON string: name,
quantity, unit, aisle, isPantryStaple, sortIndex), `photo` (CKAsset),
`extraPhotos` ([CKAsset], omit if empty), `photoHash`, `authorID`,
`modifiedBy`, `modifiedAt`.

Ingredients are one write unit with the recipe because the editor already
rebuilds them wholesale on every save; the merge replaces the local ingredient
rows from the JSON. A push leaves the `photo` and `extraPhotos` keys of the
fetched record untouched when the local photo hash equals the record's
`photoHash`, so a title edit does not re-upload six assets.

**Favourite and pin are per person** and never travel. A pin is "what I am
cooking this week"; one phone's heart must not reorder everyone's cookbook.

### 3.4 `PlatedHouseholdGathering` (one per `Gathering`)

`title`, `notes`, `startDate`, `endDate`, `guestCount`, `location`,
`authorID`, `modifiedBy`, `modifiedAt`. `calendarEventID` never travels: it is
this device's EventKit identifier, and syncing it would make every phone
create a duplicate event.

### 3.5 Groceries: marks and lines, never rows

Auto lines are regenerated from the plan on every phone by
`GroceryListBuilder`, keyed on `GroceryMeasure.key(name, unit)`. Two phones
each rebuilding from one shared plan produce identical keys, sources and
quantities, but each mints its own rows, and a shared row would be deleted by
whichever phone rebuilt second. So rows never travel. What travels is the
human-owned fact, and it travels the way a plate does: a timestamped value,
last writer wins, never a monotonic merge (a max can never carry an uncheck).

- `PlatedHouseholdGroceryMark`, one per line key, record name
  `mark-<first 32 hex of sha256(lineKey)>` (a raw key has spaces and can
  exceed a record name): `lineKey`, `purchasesJSON` (`[shoppingID: Double]`,
  an empty map means unchecked and is a value, never a missing key),
  `dismissedUntil` (yyyy-MM-dd or absent: the last day of the window it was
  dismissed in, so a dismissal expires with the window as it does today),
  `modifiedBy`, `modifiedAt`. `fold` applies a remote mark only when its
  `modifiedAt` is later than the local one and replaces the whole value;
  `record` always writes now. Locally the marks live in `GroceryMarks`, a JSON
  book in the app group beside `TableLedger`. `GroceryItem.setPurchased`, the
  undo path and the dismiss swipe call `GroceryMarks.record`; the builder
  folds `GroceryMarks.mark(for:)` into purchases and dismissal before writing
  a row; and `fold` also finds the live `GroceryItem` by key and applies the
  mark to it in the same pass, so a check-off from another phone appears
  while the sheet is open.
- `PlatedHouseholdGroceryLine`, one per manual line: `name`, `quantity`,
  `unit`, `aisle`, `day` (the day it was typed), `originTitle`, `isChecked`
  (INT64), `authorID`, `modifiedBy`, `modifiedAt`. Manual rows get
  `shareRecordName` = `line-<UUID>` at both insert sites; deleting one deletes
  the record.

`reminderID` never travels for the same reason `calendarEventID` does not.

### 3.6 The root: `PlatedHousehold`

`name` (the household's display name: the typed name, else the host's Apple
family name, else the host's surname, resolved on the host's phone),
`hostName`, `hostPhoto` (CKAsset), `banner` (CKAsset), `tableShareURL`,
`autoRotateOpenNights` (INT64), `publishedAt` (set when the host's outbox
first drains empty after `publishAll`), `removedIDs` ([String], omit if
empty), `modifiedAt`.

The join sheet is drawn from this record before acceptance (section 7). The
name is written to `AppStorage("householdName")` on merge only when the wire
value differs, and pushed from Settings on commit only (submit or loss of
focus) and only when the trimmed value differs from `lastSyncedHouseholdName`,
a second app-group value the merge and the post-push bookkeeping both set. On
a member's phone `HouseholdIdentity` reads the root's name alone. The banner
is written to the one `HouseholdProfile` row on merge.

## 4. What stays on the phone

Plates and ballots (`TableLedger`), the queues (`TableOutbox`,
`HouseholdOutbox`), change tokens, `isFavorite`, `isPinned`, `reminderID`,
`calendarEventID`, `phoneE164`, `inviteEmail`, awards ledgers, drafts,
`remindersOn`, `autoRotateOpenNights` as a per-device override, and the
notification seen-set. Nothing here is a fact the household owns.

## 5. Who I am

`HouseholdMember` gains `userRecordName: String?`, the CloudKit user record
name (`TableIdentity.cached` once confirmed). `member.isMe` is
`userRecordName != nil && userRecordName == TableIdentity.cached`.
`[HouseholdMember].me` is the first row that `isMe`. While no row carries an
identity and membership is `.solo` or `.hosting`, it falls back to the head
row (every household that predates this document). While membership is
`.member`, it falls back to the row whose `shareRecordName` equals the seat
claimed at join, remembered in the app group as `plated.household.mySeat`,
so a placeholder identity on an offline launch cannot make the host "you".

**`isOwner` means head of table and nothing else.** It gates Remove, Change
role and the Plated+ seat count. Every site that used `isOwner` to mean "the
person holding the phone" now uses `isMe`. The classification, from reading
all sixty sites:

- **Me:** `WidgetBridge` (the snapshot's `ownerName` becomes the name of the
  person holding the phone, so the widget's `ownerName == cookName` keeps
  meaning "you" without touching the widget target), `NotificationScheduler`
  ("Your night tomorrow"), `Notifier.nudgeTurnIfNeeded`, `TonightCard`,
  `TonightAnswer`, `PlanNightSheet` (cook picker "You", planned-night row,
  ask author, tag chips), `WeekView` (featured card, rows, cook menu,
  cooksLine, rota), `MonthPlannerView`, `CookbookView` (plate sheet,
  fallback cook, planned-night row), `DayDetailView`, `PostThreadView`
  (author, canRemove), `TableComposerSheet` (author, tag chips),
  `RecipeShareSheet`, `NewRecipeView` (notification actor, fallback cook),
  `TableFeedView` (`isMine` fallback, avatar cluster, saves), `PersonProfileView`
  (`isMe`, Edit profile, the row the sheet edits), `AccountButton`,
  `SettingsSheet`, `TableNews.myNames` and reply author, `ProngsbyBrain`,
  `HouseholdHomeView` (masthead avatar, "You" label, the day chip hidden for
  me), `HouseholdMember.messageURL` (a member must not be offered a Message
  button to themselves).
- **Head of table:** `Seats.migrate`, `CookRotation`'s owner fallback,
  `ContactsView.finish`, `HouseholdHomeView` (the reserved tomato, "Head of
  table", swipe actions Remove and Change role), `TableSeatsSheet.canRemove`,
  `PostEditSheet`, `TableFeedView.hostName` for minting the share,
  `MainShellView`'s repair (rewritten below).
- **Both:** `AccountHomeView`'s eyebrow ("Head of table" needs the me row to
  also be the head; otherwise "Your account").
- **Neither, and rewritten:** `Awards.metrics` attributes an unassigned meal by
  `meal.authorID`, falling back to the head only when it is empty, and
  `cookbookRecipes` counts recipes whose `authorID` is mine (an empty
  `authorID` counts as mine on the device that created it, which is every
  recipe that predates the field). `HouseholdHomeView.cycleCook` orders
  members by `shareRecordName`, not by `@Query` order, which differs per phone
  once seats arrive by merge.

The owner row is stamped with the device's identity the first time
`TableIdentity.confirm()` answers while membership is `.solo` or `.hosting`.
Rows created while the identity was a placeholder carry `authorID =
local-<uuid>`; `HouseholdSync.reattribute(from:to:)` rewrites them when the
real identity arrives, as `TableLedger` and `TableOutbox` already do, and the
outbox holds back entries while the identity is a placeholder.

**The shell's owner repair is rewritten around identity.** It fetches rows
whose `userRecordName` is this device's identity, keeps the one with a
non-empty `shareRecordName` (else the oldest), rehomes `assignedMeals` and
deletes the rest; the parked onboarding photo and the typed name are hung on
that row only; a row carrying another identity is never touched. The
insert-a-head branch runs only while membership is `.solo` or `.hosting`. The
placeholder rename runs only on the me row.

## 6. Inviting somebody to the household

Home, Add someone. The role chips (Partner, Kid, Member; default Partner,
caption "Partners share cook nights.") sit above both doors and apply to
both.

**Invite someone** runs `InviteFlow` with `kind: .household`: contact picker,
then `Seats.prepareInvite(kind: .household)` mints the zone, root and share
on first use (and the Table share, whose URL goes on the root), mints a seat
record name, and hands back a link that names it:
`https://plated.food/join/household?s=<share>&h=<host>&seat=<seat-record-name>`.
`InviteFlow.Result.sent` carries the seat name back. Only when the composer
reports `.sent` does `Seats.confirmSent` insert the `.invited` row with that
record name and push it. Cancelling calls `Seats.abandon`, which has nothing
to take back: no row was inserted and no participant was ever added. Resend
sends the same link.

The message body for a household invitation is its own sentence, never the
Table's: "Nate invited you to plan dinners together on Plated. Open the link
to join their household."

Caption under the pill: "They get a text with a link. Anyone who joins sees
the plan, the grocery list and the cookbook, and can change them."

When Messages is unavailable the pill is replaced by **Copy link**, which
copies a seatless household link; the joiner picks their seat on arrival
(section 7).

**Add by name** stays as it is: a kid, a grandparent, a full seat that is
honest about being one.

The host's first invitation is also the moment the household starts
publishing: `HouseholdSync.publishAll` names every unnamed row, stamps
`authorID`, and enqueues every seat, recipe, gathering and manual line.
The drain batches by kind into `CKModifyRecordsOperation` calls of at most
200 records and under 2 MB of non-asset payload, honours
`CKError.retryAfterSeconds`, halves on `.limitExceeded`, never counts a
rate limit or a network error as a try, runs under a background task, and
runs on launch, on foreground, before every pull and after every push, not
only when a feed is open. While the host's outbox holds entries from
`publishAll`, Home shows one quiet line under the masthead: "Sharing with
your household, 40 of 360." When it first drains empty, `publishedAt` is
written on the root.

The onboarding screen ("Invite your household") is a household invite through
the same door. The owner's row is laid at the end of `ProfileSetupView` (name,
photo, identity stamp), not in `ContactsView.finish`, so the host seat exists
before the first invitation. `ContactsView` mints nothing in `.task`; the
share is minted when a person taps Invite or Share a link, so a joiner
passing through onboarding never hosts an empty Table.

## 7. Accepting

A Universal Link now lands on `RootView`, which parks it in `LinkRelay`. When
the parked link is a household invitation, onboarding runs SignIn, then
ProfileSetup, then `JoinHouseholdSheet` full screen, then the Tour, and never
shows the invite-your-people screen: a person who installs from the link is
joined at the end of onboarding instead of being asked to invite their own
people to a plan they are about to give up.

Every road (Universal Link, `plated://join`, the directory's `plated://invite`
push, a raw iCloud link through the CloudKit delegate) ends in
`ShareAcceptor.received(shareURL:seat:)`, which fetches the metadata with
`shouldFetchRootRecord = true` and dispatches on
`metadata.hierarchicalRootRecordID?.zoneID.zoneName`, never on what the URL
claimed. A link that says household and resolves to a Table share is handled
as a Table invitation.

**Table share:** the confirmation dialog, on every road. Title "Nate kept
you a seat at their table", buttons **Join the Table** and **Not now**,
message "Their dishes and asks join your Table, and they see what you post."

**Household share:** `JoinHouseholdSheet`, drawn from the metadata's owner
identity first and the root record second (`hostName`, `hostPhoto`, `name`),
never from the link's `h`. When neither yields a name it reads "Someone
invited you to their household" over the neutral monogram.

Three states, never one. **Still asking:** the sheet opens with the monogram,
a spinner and no words; Join disabled. **Could not ask**, keyed on
`TableSync.accountState`: no account, "Sign in to iCloud on this iPhone to
join, then open the link again."; restricted, "iCloud is restricted on this
iPhone, so Plated can't join a household."; `unknownItem`, "This link doesn't
work anymore. Ask Nate for a new one."; otherwise "Couldn't reach iCloud.
Check your connection and open the link again." **Asked:** the host's face and
name, the household's name when it has one, and the facts:

- "You'll see the plan, the grocery list and the cookbook, and you can change
  them."
- "Your recipes come with you." When the joiner has meals from today onward:
  "Your N planned meals from today on are replaced by Nate's plan." When the
  joiner has manual grocery lines or marks: "Your grocery list is replaced by
  the household's." When the joiner has by-name seats: "Max comes with you."
- While the root's `publishedAt` is nil: "Nate's cookbook and plan arrive as
  their phone uploads them."
- "Leave any time from Settings."

Before the facts, the sheet compares the metadata's owner to membership:

- Same owner as my current household, with a seat claimed: no sheet; route
  Home with a toast "You're already in Nate's household."
- Same owner, but no seat ever claimed: the sheet opens straight into the
  seat question below.
- My own share: "This is your own household's link. Send it to someone else
  from Home."
- Hosting with joined seats: refuse, "You host a household with Sam and Jo.
  Remove them first, or ask Nate to join yours."
- Hosting with only by-name seats, or a member of another household: the
  first fact is preceded by "You'll leave the Meadows household first." and
  the button reads **Leave and join**.
- My identity is in the root's `removedIDs`: "Nate removed you from this
  household. Ask them for a new invitation." and no button.

Otherwise the buttons are **Join** and **Not now**. While joining, the pill
reads "Joining" and is disabled. Failure is an inline problem row, the same
component Add someone uses.

The seat question comes AFTER the accept and the first pull, not before it:
the roster is a record in the host's zone and there is nothing to list until
the share has been accepted and merged. So a seatless link joins first and
then `join` returns `.needsSeat(candidates:)`, and the sheet replaces its
body with "Which seat is yours?" over the roster's unclaimed rows, "None of
these" last. By then the share is accepted, the previous household left and
the plan cleared, so "Not now" is a choice that no longer exists: the picker's
own "None of these" is the only way out, and the sheet is not dismissible
past it. A join killed at that question is recoverable rather than refused:
membership names this zone but `mySeat` is nil, so re-opening the link goes
straight back to the picker instead of "You're already in Nate's household."

**On Join,** `HouseholdSync.join(metadata, seat:)`:

1. Accept the household share. Then fetch the Table share's metadata from the
   root's `tableShareURL` and accept it only when `participantStatus` is not
   already `.accepted`. Join succeeds on the household accept alone; the
   Table accept is also a standing step of every household pull, so a
   failure here is retried, not fatal.
2. Record membership as `.member(owner:)` in the app group, with the zone
   epoch and, once claimed, `plated.household.mySeat`.
3. Pull the zone whole. Merge the roster, recipes, gatherings, lines and
   marks; the week arrives beside them as plan records and lands in
   `PlanLedger`, never in the store. This first pull raises no notices except one bell row, "You joined
   Nate's household."
4. Claim the seat. If a seat record carries this identity, it is me. Else if
   the link named a seat that exists, is still `.invited` and carries no
   identity, write `userRecordName`, `seat = joined`, `joinedAt`, and my
   name, bio and photo onto it and push. Else create a seat from my own owner
   row (role partner, or the chosen seat's role) and push it. The local owner
   row minted at onboarding is retired: every meal in its `assignedMeals` is
   re-pointed to the claimed seat in the same save, its identity, name, bio
   and photo move to the claimed seat, the awards ledger key moves with the
   name, and then the old row is deleted locally.
5. Adopt what I brought. Every recipe, gathering and by-name seat I own is
   stamped `authorID` = me and enqueued. Planned meals from today onward and
   every grocery row and mark are deleted locally. The nights go BEFORE the
   first pull, and they go because the household's week is drawn beside this
   phone's own (section 3.2): a joiner who kept theirs would open the Plan to
   every night described twice, once by the household and once by the week
   they planned alone, with no way for a reader to tell which one dinner is.
   Past nights are kept as history: they are this person's, nobody else is
   describing them, and their insights are theirs. Table posts are untouched.
6. Haptic kiss and the Plan tab. Until the root's `publishedAt` is set, the
   Plan and Cookbook show a quiet line above whatever has landed: "Still
   arriving from Nate's phone."

The host learns of the join on their next pull: the seat arrives `.joined`,
and `Seats.reconcile` (now reading the household share's standings)
corroborates the `participantID`. Nothing is matched by address.

## 8. Leaving, removing, being removed

**Leave** lives in Settings, Household, for members only. The sheet says what
happens: "You'll leave the Table too. Your recipes and awards stay with you,
and the household keeps its copy of your recipes. The plan and the grocery
list stay with the household." When a by-name seat I brought exists: "Max
comes with you." Button **Leave**. On confirm, in order:

1. Push my seat with `seat = left` and `leftAt`, and wait for the save.
2. Delete the household zone and the household's Table zone from the shared
   database, forgetting only those zones' tokens.
3. Set membership to `.solo`, clear `HouseholdOutbox`, `GroceryMarks` and
   `plated.household.mySeat`.
4. Delete every local row that came from the household: seats other than
   mine and the by-name seats I brought, gatherings, grocery rows, and
   recipes whose `authorID` is non-empty, not mine, and whose
   `shareModifiedAt` is non-nil. A row with an empty `authorID` is kept,
   always. Nights are not touched: every `PlannedMeal` here is this Apple
   ID's own, and the household's week goes when `PlanLedger` forgets that
   zone.
5. Reset every kept row to never-synced: `shareModifiedAt = nil`,
   `shareFingerprint = ""`, a fresh `shareRecordName`.
6. Promote my seat back to owner and head. Forget cook sessions for deleted
   recipes, republish the widget snapshot, sync the badge.
7. One bell row: "You left Nate's household and their Table. Your recipes
   stayed with you."

On the host's phone a seat arriving `left` is deleted from the roster, its
nights and standing cook weekdays return to unplanned, and the digest says
"Riley left your household." The digest reads the row's name, so the deletion
happens after `TableNews.deliver`, never before it. A member's phone clears
the nights but keeps the row: nothing local can delete a record in the host's
zone, and the host's own deletion arrives on its own through
`changes.deleted`. A seat arriving `left` that this phone has no row for is
not seeded at all, so a fresh joiner never inherits the household's leavers.
`Seats.reconcile` also treats a `joined` seat whose identity is absent from a
successfully read participant list as `left`, and retires it the same way.

**Remove** lives on the member row for the host only, and goes through
`Seats.remove`: call `removeParticipant` on both shares matched by
`userIdentity.userRecordID`; on refusal say so and stop ("Couldn't remove
Riley. Check your connection and try again."); never write
`publicPermission = .none`. On success delete the seat record, append the
identity to the root's `removedIDs`, push the root, delete the row, and hand
that person's cook nights back to unplanned. The confirmation says what is
true: "Riley loses the plan, the grocery list and the cookbook. Their own
recipes stay in the cookbook." A removed identity is refused at join
(section 7) and never seated by reconcile.

**Being removed** is noticed only on positive evidence: a
`CKFetchDatabaseChangesOperation` on the shared database reporting the
household zone deleted, or `recordZoneChanges` throwing `.zoneNotFound` while
`accountStatus == .available` and a direct `recordZone(for:)` also returns
`.zoneNotFound`. A thrown listing, an empty listing, a signed-out account or
a network error changes nothing. Then, with membership still `.member`,
`handleRemoved` dismisses every sheet, pops navigation to the tab roots, runs
steps 3 to 6 of Leave, and posts, in the passive Apple Invites uses, "Nate's
household is no longer on this phone. Your recipes stayed with you, and the
household kept its copy." The Plan tab's first empty week afterwards says
that sentence instead of the ordinary invitation.

**Migration of rows seated from the Table.** Every `.joined` row that exists
today was seated by `Seats.reconcile` from the Table share; those people hold
no household share. On first launch of this design, while membership is
`.solo`, each such row is downgraded to `.notOnPlated` keeping its
`participantID`, and one bell row per person says "Sam is at your Table but
not in your household yet. Invite them from Home to share the plan." The seats
sheet lists a Table participant whose identity matches a roster row once,
under Household.

## 9. Inviting somebody to the Table

Table, the avatar cluster, `TableSeatsSheet`. The sheet is rebuilt on one
source per group:

- **Household**: the roster, subtitles from seat and role (section 10).
- **At your table**: Table share participants who are not in the roster,
  "Sees what you cook", named from the participant identity when iOS gives
  one and from their posts otherwise. Remove for the host only.
- **Invited to the table**: entries from `TableInvites`, a small JSON book in
  the app group written only when a Table invitation's composer reported
  `.sent`: "Invited Tuesday", Send again, Cancel. Every Table link carries the
  entry's id (`i=`); on accept the joiner writes a `PlatedDishClaim` record
  (`inviteID`, `userRecordName`) under `table-root`, and the host's next Table
  pull settles the entry. An entry that never settles can always be cancelled
  by hand.
- **Tables you've joined**: Table zones in the shared database that are not
  this household's, "Dan's table", Leave. Leaving the household's own Table
  is Leave household, in Settings.

**Invite to the Table** runs `InviteFlow` with `kind: .table` and never
creates a `HouseholdMember`. Caption: "They see what everyone here cooks.
They don't see the plan." The legacy `pendingSeats` string, its "Invited"
group and the feed's "You invited" strip are deleted; they were the third and
fourth notions of "invited" and none of them reconciled.

**On a member's phone the Table is the household's.** `TableShare` answers
"which table" from `HouseholdShare.membership`: when `.member(owner:)`,
`invitationURL` returns the root's `tableShareURL` and mints nothing,
`standings` and `participants` read the share from the shared database,
`myWritableZone` is the owner's zone, Remove is unavailable (only the owner
edits participants), and `leaveTable(owner:)` refuses the household's owner.
`isGuest` is deleted; membership answers. New posts from a household member
go to the household's Table zone, never to a zone the member happens to host.

## 10. What the app says

Bell rows and banners, through `TableNews`, with the law in
`docs/notifications.md`:

| event | key | copy | delivery |
|---|---|---|---|
| a seat joined the household | `household:<userRecordName>` | "Riley joined your household" / "They can see the plan, the grocery list and the cookbook now." | active with sound by day, passive 22:00 to 08:00 |
| a seat left | `household-left:<userRecordName>` | "Riley left your household" / "Their nights are open again." | passive |
| somebody added a recipe | `recipe:<recipeRecordName>` | "Riley added Ragù" / "It's in the cookbook." | passive |
| your edit lost to theirs | `conflict:<recordName>` | "Riley changed Ragù after you did" / "Their version is showing." | passive, bell only |

A planned night is not on this table. It comes from the plan pipe, whose
notice is `Notice.Kind.plan`: "Riley planned Tacos for Thursday", under the
Planning switch, with its own key and its own retraction rule
(docs/plan-share.md). One evening, one digest.

Never about your own action, on any of your devices (`modifiedBy != me`).
Never unnamed. A join to the household also joins the Table, so the Table's
seat notice is suppressed for any participant who holds a household seat
with the same identity; the Table-only notice keeps its own key and its own
sentence, "They can see the Table now." The join pull and any household pull
from the beginning raise nothing except the one "You joined" row; incremental
household deltas inherit the Table's 36-hour window and the four-banner cap.
Household rows are gated by the switch now titled "Household and Table
activity".

Subtitles, by seat and role: me, "You · Partner" or "You · Head of table";
head, "Head of table"; joined partner, "Plans and cooks with you"; joined kid
or member, "Sees the plan with you"; invited, "Invited Tuesday"; notOnPlated,
"You cook for them". `PersonProfileView.roleLine` is the person's role, with
"Head of table" only for the owner row. The me row takes the neutral tone; on
a member's phone the host keeps their colour.

**Change role** is a menu on the member row for the host: Partner, Kid,
Member, caption "Partners share cook nights." Demoting a partner who holds
cook nights says "Riley's cook nights are cleared." and clears them.

**Settings, Household.** Host: the name field and "You host this household
with Riley and Max." Member: the name read-only with "Nate can rename it",
"Nate's household. You joined Tuesday.", and the Leave row. On a member's
Home, when `TableSync.accountState` is not available: "Can't reach iCloud.
Changes reach your household when it's back."

Copy that was false and is now true or rewritten:

- Onboarding: "Anyone who joins sees the plan, the grocery list and the
  cookbook, and can change them."
- Settings: "Your plan and cookbook are shared with your household and nobody
  else. Only posts you choose to share appear at the Table."
- Recipe page: "Everyone in your household can see this" only when a second
  seat is `.joined`; otherwise "Only you can see this".
- Profile, Saved: "Recipes you save from the Table appear here. Your household
  can see them too."
- The join page and the invite push name the kind: "Nate invited you to their
  household" against "Nate kept you a seat at their table".
- The Table dialog's verb is "Join the Table", not "Take the seat".
- Privacy policy: the household paragraph and the directory sentence.

## 11. Debug and verification

- `-plated-rehearse-household` (DEBUG, simulator only) stamps the seeded Nate
  with this device's identity, then merges a fake household arriving from
  "Sam" so the member's view, the join sheet and the notices can be
  photographed without a second Apple ID.
- `PlatedTests/HouseholdSyncTests.swift` covers the pure parts: merge
  update-or-insert and the nameless-twin adoption, duplicate collapse with
  relationships rehomed, version-based conflict, the deletion rules, the seat
  field rules (forward-only seat, owner only on the owner, identity set once),
  the seat claim, a household delta never touching the local plan, grocery
  mark last-writer-wins and dismissal expiry, leave-then-join keeping a
  recipe, the fingerprint excluding bookkeeping, link grammar in and out, and
  the notices with their own-action guard and first-pull silence. The week's
  own tests are `PlanShareTests` and `PlanNewsTests`. Tests reset every app-group book
  and membership in setUp and tearDown, and the save observer ignores every
  context but `PlatedStore.shared.mainContext`.
- `-plated-prime-household` writes one of every household record type and
  retracts it, run only while membership is `.solo`. `SchemaPrimer` and
  `SampleData.seed` stamp every new field and run with the observer
  suppressed.
- `-plated-purge-cloud` now also deletes the `PlatedHousehold` and
  `PlatedTable` zones from the private database, every change token, every
  app-group book and every `plated.*` default, and prints what it removed.
- Only a phone signed into iCloud can exercise the zone, and only two Apple
  IDs can exercise a join. The simulator on this Mac has no iCloud account.
  The decisive rehearsal is the one the design review named: a host, a
  member and a Table guest on three phones, with the guest unable to open
  household-only content. The first thing to prove there is Remove.

## 12. Interface sketch

The signatures the pieces are written against. Names are final; bodies are
not.

```swift
enum HouseholdShare {
    static let zoneName = "PlatedHousehold"
    static let rootRecordName = "household-root"
    enum Membership: Codable, Equatable { case solo, hosting, member(owner: String) }
    static var membership: Membership { get }              // app-group cache, sync
    static var mySeat: String? { get set }                 // plated.household.mySeat
    static func refreshMembership() async -> Membership   // asks CloudKit

    static func invitationURL(hostName: String) async -> URL?   // mints zone, root (+ Table share URL), share
    static func mintSeatName() -> String                         // "seat-<UUID>"
    static func standings() async -> [TableShare.Standing]      // host reads own share; member reads shared DB
    static func removeParticipant(userRecordName: String) async -> Bool
    static func leave() async -> Bool                            // shared-DB zone delete, own tokens only
    static func accept(_ metadata: CKShare.Metadata) async -> Bool

    struct RemoteRoot { name, hostName, hostPhoto: Data?, banner: Data?, tableShareURL: URL?, autoRotate: Bool, publishedAt: Date?, removedIDs: [String], modifiedAt }
    struct RemoteSeat, RemoteRecipe, RemoteGathering, RemoteLine, RemoteMark
    struct Changes { root: RemoteRoot?, seats, recipes, gatherings, lines, marks,
                     deleted: Set<String>, sharesChanged, replayed, zoneGone, failed: Bool,
                     plan: TableShare.Changes /* collected here, folded by PlanLedger */ }
    static var isRateLimited: Bool { get }                       // §6, honoured before a drain starts
    static func fetchChanges() async -> Changes
    struct MergeOutcome { newSeats, leftSeats: [HouseholdMember], newRecipes: [Recipe], conflicts: [String] }
    @MainActor static func merge(_ changes: Changes, into context: ModelContext) -> MergeOutcome

    enum PushOutcome { case saved(modifiedAt: Date), remoteNewer(theirs: Changes), gone, retry, failed }
    @MainActor static func push(entries: [HouseholdOutbox.Entry], context: ModelContext) async -> [String: PushOutcome]
    static func pushRoot(_ root: RemoteRoot) async -> Bool
    static func delete(recordNames: [String]) async -> Bool
}

@MainActor final class HouseholdOutbox {           // app group JSON, per device
    static let shared: HouseholdOutbox
    enum Kind: String, Codable { case seat, recipe, gathering, line, mark, root }   // no meal, §3.2
    struct Entry: Codable, Identifiable { var id: String /* recordName */; var kind: Kind; var isDelete: Bool; var at: Date; var tries: Int }
    func enqueueUpsert(_ kind: Kind, _ recordName: String, at: Date)   // keeps the earliest `at`
    func enqueueDelete(_ kind: Kind, _ recordName: String)
    func hasPending(_ recordName: String) -> Bool
    var pending: [Entry]; var isEmpty: Bool
    @discardableResult func drain(context: ModelContext) async -> Bool  // ordered seat, recipe, gathering, line, mark, root; true when it ran
    func clear()
}

@MainActor enum HouseholdSync {
    static func observe(_ context: ModelContext)   // willSave parks (kind, name, fingerprint); didSave commits; filters on identity of context
    static var suppressed: Bool                    // fixtures and merge saves, held only across synchronous work
    static func fingerprint(of: any PersistentModel) -> String?
    static func sweep(in: ModelContext)            // launch: enqueue rows whose fingerprint drifted
    static func ensureRecordNames(in: ModelContext)   // the single minter, transition only
    static func publishAll(in: ModelContext)
    static func collapseDuplicates(in: ModelContext)
    static func reattribute(from: String, to: String, in: ModelContext)
    static func stampIdentityIfUnshared(in: ModelContext)
    struct SeatCandidate: Identifiable, Equatable { var id: String /* shareRecordName */; var name: String; var role: String }
    enum JoinOutcome { case joined, needsSeat(candidates: [SeatCandidate]), refused(String), failed(String) }
    // JoinPreview.State carries the same `needsSeat(candidates:)`, for a
    // link re-opened after a join that was killed at the seat question.
    static func join(_ metadata: CKShare.Metadata, root: HouseholdShare.RemoteRoot?, seat: String?, context: ModelContext) async -> JoinOutcome
    static func claimSeat(named: String?, context: ModelContext) async -> JoinOutcome   // after .needsSeat; nil means a fresh seat
    static func leave(context: ModelContext) async -> Bool
    static func handleRemoved(context: ModelContext)
    static func adoptMySeat(in: ModelContext)              // second device of an Apple ID; adopts, never mints
    static func claimFreshSeat(replacing: HouseholdMember, in: ModelContext)   // §7, the seat was taken
    static func retireLeftSeat(_: HouseholdMember, in: ModelContext)           // §8
    static func openSeats(in: [HouseholdMember]) -> [SeatCandidate]
    static func absorb(_ changes: HouseholdShare.Changes, context: ModelContext) async   // merge, collapse, news, widget, scheduler
}

@MainActor @Observable final class GroceryMarks {  // app group JSON
    struct Mark: Codable { var lineKey: String; var purchases: [String: Double]; var dismissedUntil: String?; var at: Date; var by: String }
    static let shared: GroceryMarks
    func mark(for lineKey: String) -> Mark?
    func record(lineKey: String, purchases: [String: Double], dismissedUntil: String?)   // now, me; enqueues while shared
    func rewrite(lineKey: String, purchases: [String: Double])   // same `at` and `by`: a fold is not a tap
    func fold(_ mark: Mark, into context: ModelContext) -> Bool      // LWW on at; applies to the live row
    func clear()
}

@MainActor final class TableInvites {              // app group JSON
    struct Entry: Codable, Identifiable { var id: String; var name: String; var phone: String?; var email: String?; var sentAt: Date }
    static let shared: TableInvites
    var pending: [Entry]
    func mint(name:phone:email:) -> Entry            // before the composer opens
    func record(_ entry: Entry)                      // on .sent
    func cancel(_ id: String)
    func settle(claims: [TableShare.Claim])
    func clear()
}

enum Seats {   // additions and changes
    enum Kind { case household, table }
    struct Prepared { var outcome: TableShare.InviteOutcome; var seat: String?; var invite: String? }
    static func prepareInvite(kind: Kind, hostName: String) async -> Prepared
    static func confirmSent(kind: Kind, prepared: Prepared, name: String, phone: String?, email: String?, role: String, in: ModelContext)
    static func abandon(kind: Kind, prepared: Prepared)
    static func resend(_ member: HouseholdMember, hostName: String) async -> Prepared
    static func remove(_ member: HouseholdMember, in: ModelContext) async -> Bool   // the only door
    static func changeRole(_ member: HouseholdMember, to: String, in: ModelContext)
    static func reconcile(in: ModelContext) async       // household standings; joins and lefts
    static func me(in: ModelContext) -> HouseholdMember?
    @discardableResult static func migrateTableSeats(in: ModelContext) -> Bool   // one-shot downgrade; true when it changed a row
}

enum InviteFlow {   // changes
    enum Result { case sent(name: String, phone: String?, prepared: Seats.Prepared)
                  case notSent(name: String, phone: String?, prepared: Seats.Prepared)
                  case cancelled
                  case noLink(name: String, reason: String) }
    struct Recipient { var name: String; var phone: String? }
    static func run(kind: Seats.Kind, hostName: String, to recipient: Recipient? = nil, prepare: @escaping () async -> Seats.Prepared, completion: @escaping (Result) -> Void)
}

enum Invitation {   // changes
    static func wrapped(_ share: URL, hostName: String, kind: Seats.Kind, seat: String?, invite: String?) -> URL
    struct Parsed { var share: URL; var kind: Seats.Kind; var seat: String?; var invite: String?; var host: String }
    static func parse(_ url: URL) -> Parsed?      // plated.food/join, /join/household, plated://join, plated://invite
    static func body(hostName: String, kind: Seats.Kind, link: URL) -> String
}

enum ShareAcceptor {   // changes
    static func received(shareURL: URL, seat: String?, invite: String?, linkHost: String) async   // fetch metadata (root), dispatch on zone, present
}
```

Model additions, all defaulted or optional so the mirror stays CloudKit-safe,
each written non-empty by `SchemaPrimer`:

- `HouseholdMember`: `userRecordName: String?`, `bio: String = ""`,
  `shareRecordName: String = ""` (init mints `seat-<UUID>`), `shareModifiedAt:
  Date?`, `shareFingerprint: String = ""`, `authorID: String = ""`,
  `leftAt: Date?`, `Seat.left`, `var isMe: Bool`, `[HouseholdMember].me`.
- `PlannedMeal`: `authorID: String = ""` and nothing else. A night carries no
  record name, version or fingerprint, because it is not a household record
  (§3.2); `authorID` is there for `Awards.metrics`.
- `Recipe`: `shareRecordName` (`recipe-<UUID>`), `shareModifiedAt`,
  `shareFingerprint`, `authorID`, `sharePhotoHash: String = ""`.
- `Gathering`: `shareRecordName` (`gathering-<UUID>`), `shareModifiedAt`,
  `shareFingerprint`, `authorID`.
- `GroceryItem`: `shareRecordName` (`line-<UUID>`, manual rows only),
  `shareModifiedAt`, `shareFingerprint`, `authorID`.
- `HouseholdProfile`: `shareModifiedAt: Date?`.

## 13. Build order

New files need no project edit (synchronized groups). The signature changes
land in this order so the tree compiles between steps:

1. Models and fixtures. `HouseholdMember`, `Recipe`, `Gathering`,
   `GroceryItem`, `HouseholdProfile` (`PlannedMeal` takes `authorID` only,
   §3.2); `SchemaPrimer`;
   `SampleData`; the CLAUDE.md namespace sentence.
2. The me migration, per the classification in section 5. `isOwner` stays
   defined, so this compiles alone.
3. The books, no CloudKit: `HouseholdOutbox`, `GroceryMarks`, `TableInvites`,
   `GroceryItem.setPurchased` and the dismiss path recording marks,
   `GroceryListBuilder` folding them and no longer minting `shoppingID` for
   named rows, `TableIdentity.reset` clearing everything.
4. The wire, needs 3: `HouseholdShare`, `TableShare` helpers made internal
   (`int`, `asset(from:)`, the token helpers, `zone(ownedBy:)`,
   `canonicalOwner`), `leaveTable(owner:)`, membership-aware
   `myWritableZone`/`invitationURL`/`standings`/`participants`, the
   `addParticipant` line removed from `invite`, plates saved through
   `CKModifyRecordsOperation` with `.changedKeys` (today a fresh `CKRecord`
   saved over an existing plate is refused as `serverRecordChanged` and
   reported as success, so an un-plate never reaches the wire),
   `PlatedDishClaim`, `assertNoEntityCollision` additions,
   `TableSync.purgeMirroredData` additions, `HouseholdSyncTests`.
5. The glue, one commit because `prepareInvite`'s signature changes every
   caller: `HouseholdSync`, `TablePull` (both outboxes drained, both zones
   fetched, in one gate), `ShareAcceptor` (root fetch, zone dispatch,
   `received`), `Seats`, `Invitation`, `InviteFlow`, `PlatedApp` and the
   intents (observer install), `MainShellView` (repair keyed on identity,
   route, dialogs, the `-plated-tab` block moved back out of the `didAccept`
   handler where a Sept 2 edit stranded it), `RootView` (link parking and the
   join-first onboarding order), `ProfileSetupView` (lays the owner's place),
   `HouseholdHomeView`, `ContactsView`, `TableSeatsSheet` call sites,
   `TableNews` household digest.
6. UI and copy, any order after 5: `JoinHouseholdSheet`, `TableSeatsSheet`
   rebuild and the `pendingSeats` deletion (`TableFeedView` strip too),
   Settings Household and Leave, Change role, the copy table in section 10,
   `docs/notifications.md`, the privacy policy.

The web `/join/household` page and the directory's `kind` are independent
and must be live before the first household link is sent.

## 14. Deliberately left open

- **Decided 2026-09-08, and closed: the plan does not travel as a household
  record.** Both designs were built far enough to compare, and the meal merge
  lost on the argument in §3.2: `PlannedMeal` lives in a mirrored store, so a
  household fact placed there has two writers by construction, and
  `collapseDuplicates` was repairing that shape rather than fixing it. The
  merge, `PlatedHouseholdMeal`, the outbox's `meal` kind and the night notice
  are gone; the week rides the plan pipe (docs/plan-share.md), which grows
  the two-way write path. Last writer wins on the record's `modifiedAt`.
- Whether a link-joined participant can be removed one at a time; the code
  tries and says so (section 8).
- Chef's kiss denominator (open-decisions 1b): a shared roster makes
  `members.count` agree across a household, which fixes the member's phone;
  Table-only friends still inflate it.
- "Nothing for you to do" (open-decisions 1c) now goes to every member; the
  reminder is unchanged and the decision is still Nate's.
- A joiner's past cooked nights are kept locally and never pushed. Their
  insights are theirs; the household's are the household's.
- Recipe `visibility` and `householdCanEdit` stay dead. Every recipe in a
  household is the household's.
- Extra photos are merged into local `RecipePhoto` rows on arrival rather
  than fetched on demand, so the mirror re-exports them too. Revisit if
  storage complaints arrive.
