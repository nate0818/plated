# The plan across Apple IDs

How a night planned on one phone reaches every phone in the household, and
why it never becomes a `PlannedMeal` on any of them. Decided Sept 7 2026
(open decision 17, now closed), then converged the same evening with the
household invite's contract in `docs/household.md`: the plan rides the
**household** zone that invite mints, as a `PlatedHouseholdPlan` record,
and lands on other phones in a ledger beside the plates, not in the
SwiftData mirror. It does not ride the Table zone, because a Table guest,
a friend in another household, must not be able to read the week through
CloudKit, which the Sept 4 review forbade. Reviewed the same day by a
three-lens panel; every issue it raised is answered below and marked with
the rule it produced.

The seam with `docs/household.md`: that document owns the zone, its share,
joining, leaving and removal, the roster, recipes and grocery marks, and
writes one app-group key saying which household this phone is in. This
document owns the plan record, the publisher, the reader, the ledger, the
overlay, the notices and the reminders. A night is never merged into
`PlannedMeal` by either.

## The shape in one paragraph

Each phone publishes its own `PlannedMeal` rows into its household's zone,
as `PlatedHouseholdPlan` records named `plan-<shoppingID>`, by
diffing the plan against a book of what it last published. Every phone
already pulls that zone's changes; plan records land in `PlanLedger`, a JSON
book in the app group, and are drawn by the planner beside the phone's own
nights, where they can be changed (see "Changing a household night"). The digest raises "Nate planned Tacos for
Thursday", and a remote night whose cook is the reader schedules "Your
night tomorrow" the way a local one does. Nothing about a remote night is
ever written into `PlannedMeal`, so nothing that counts, moves, swaps,
mutates or mirrors a `PlannedMeal` has to learn a new flag.

## Why not a mirrored PlannedMeal

Five independent reasons, each sufficient, each verified against the code:

1. Two of one person's devices each insert the same record and the mirror
   then carries each row to the other: `TablePost` has this bug today (no
   dedupe by `shareRecordName`; only the bell rows are deduped) and a night
   would show twice on every second device.
2. Every planner surface reads an unfiltered `@Query` and takes `.first`
   per day and slot (`WeekView.dinner(on:)`, `DayDetailView.dayMeals`,
   `MonthPlannerView.selectedMeals`, `PlanNightSheet.meal`); a second row
   on a night is silently collapsed, and `MealPlanMove` would swap it.
3. About thirty aggregators count `PlannedMeal` rows as this household's
   activity: `Recipe.timesCooked`, `Awards.metrics` (nil-cook meals credited
   to the owner), `HouseholdStatsView`, `CookRotation`'s per-week counts,
   `WidgetBridge.plannedCount`, `NotificationScheduler.scheduleTurns`.
4. `GroceryListBuilder.rebuild` and `MainShellView` mutate fetched meals
   (backfilling `shoppingID`, rehoming `cook`); a remote copy would be
   edited locally and diverge from the zone.
5. CLAUDE.md: share-derived state does not go in the mirror. The zone is the
   one authority; the mirror would be a second writer.

## Changing a household night

Read-only was the first step. A member can now change any night the ledger
holds, and the change **writes the zone record. It never writes a
`PlannedMeal`.** Nate's words, 2026-09-08, and the whole reason this is a
record and not a merged row:

> That model is in a store set to `cloudKitDatabase: .automatic`, so a
> household fact there has two writers by construction: the zone, and your
> own mirror carrying it to your other devices while they merge the same
> record. `collapseDuplicates` repairs that shape rather than fixing it.

The five reasons under "Why not a mirrored PlannedMeal" do not weaken when
the write comes from a member instead of the head; the fifth is the one that
decides it. So `PlannedMeal` is a private, per-Apple-ID model, a household
night is a `PlatedHouseholdPlan` record held locally in `PlanLedger`, and
nothing merges one into the other in either direction.

**What a person can change:** the dish (a recipe from their cookbook, a new
one, "Pick for me", or Eating out), the cook, the servings, the tag line the
dish arrives with, and taking the night off the plan for everybody. The
servings stepper parks its edit before its 700ms debounce, not after it:
a kill inside that window left a row showing six servings, the stray
sweep clearing the one mark that said so, and nothing anywhere ever
sending it.

**What they cannot:** move it to another date. A move is a swap, and the
night on the other date is very often this phone's own `PlannedMeal`, so one
gesture would be two writes in two authorities with nothing to roll either
back if the other refused. `RemotePlanRow` therefore still carries no drag
lift and no Move, `MoveMealSheet` still takes a `PlannedMeal`, and both say
so at the line. Nor a Cooked toggle: cooking is a thing that happens at a
stove, and the phone that planned the night is where its cook session lives.

### `PlanShare.Edit` and the write

`Edit` names the record, the household it was made in, the day and slot, the
`modifiedAt` this phone last saw, and **only the fields the person touched**
(a `nil` field is "leave what the record says"), so two people changing two
different things about one night do not undo each other's work unless they
land inside one version.

`PlanShare.write(_:photo:)` is the whole path:

1. `PlanLedger.applyLocally` changes the row under the finger and marks it
   `pendingSince`. A queued write is not a landed write, and the row says
   "Not sent yet" until it is one. A delete marks the row `pendingRemoval`
   and **keeps it**. Removing the entry outright made an offline delete a
   night that vanished from the deleter's planner while it still stood on
   every other phone, with nothing on any screen saying so: the honesty
   rule, and the one edit on this path that was not already answered by
   `pendingSince`. The row draws as going, captioned "Still on the other
   phones", and it leaves for real when the delete lands or comes back when
   it is refused. A night on its way off is still counted by the widget, the
   grocery window and every "N planned" count: it is still on the plan until
   the zone says otherwise, and hiding it from the counts would be this
   phone claiming the delete that has not happened, which is the same lie in
   the other direction. A change made on a night whose delete is waiting is
   refused rather than folded away, because the queue keeps the delete.
2. The edit is parked in `plan-edits.json`, an app-group queue beside
   `plan-share.json`, per device for the reason `TableOutbox` and
   `HouseholdOutbox` are: a mirrored queue is a distributed queue with no
   lease. The fingerprint book cannot hold an intent (it answers what this
   phone last published), so this is the small queue beside it. One entry per
   record: a second edit folds onto the first, keeping the earlier `seenAt`,
   which is the version the person started from. A delete stays a delete. A
   photograph rides as a downscaled file under `plan-edit-photos/<record>.jpg`,
   so the queue stays small and a kill loses neither.
3. The record is fetched by name. When its `modifiedAt` differs from
   `seenAt` by a second or more, **somebody got there first**: the server
   version is folded into the ledger, the edit is dropped, and the answer is
   `.theirs`, which the sheet says out loud. Whole seconds, because a `Date`
   goes to CloudKit and comes back through a double.
4. Otherwise the changed fields go onto the fetched instance, `modifiedAt`
   becomes now, and it saves through the publisher's own `savePlans`, which
   carries the `.serverRecordChanged` fetch-and-retry. **Last writer wins on
   `modifiedAt`.**
5. A record the zone no longer holds, for a night the ledger has, is **not a
   mint**. A ledger entry exists only because the record was delivered, so
   its absence can only be somebody's delete: a race the other person won,
   answered the way `movedOn` is. The deletion is folded into the ledger, the
   edit is dropped, and the sheet says the night was taken off on another
   phone. Re-minting it stood a permanent ghost on every phone but one,
   because the mint carries the night's ORIGINAL author and that author's
   publish book no longer holds the name, so nothing on their phone would
   ever republish or re-delete it. `wasTakenOffElsewhere` is the line: an
   edit with a `seenAt` came off a delivered record; an edit without one is
   the genuine mint, a night with no record at all. That mint writes the
   `parent` reference and `setParent` the publisher writes, and the night's
   ORIGINAL author. Never the editor: `absorb` keeps nothing this phone
   wrote (its own nights are `PlannedMeal` rows), and there is no
   `PlannedMeal` behind somebody else's night, so a record authored by the
   editor would vanish from the one phone that just changed it while standing
   on every other.
6. A delete deletes the record; `.unknownItem` is success.
7. `settle` takes the queue and the ledger through the answer, and hands
   back the answer the person is actually owed: landed drops the edit and
   stamps the entry with the record's own clock (or the delivery that brings
   this phone's own edit back reads as a change and the digest raises a
   notice about the reader's own action), and for a delete it is the line
   where the row finally goes; queued keeps it and counts a refusal,
   dropping it after twenty and **answering refused when it does**, because
   the person was otherwise told it would go out later while the row snapped
   back in front of them; theirs and refused drop it, and refused puts the
   night back the way it was, unless the household has moved under it, which
   would write dead data into a book `rehome` has just cleared.

**The row's clock is not the record's clock.** `Entry.changedAt` is the
record's `modifiedAt` as this phone last saw it, and `Edit(changing:)` reads
it straight into `seenAt`. `applyLocally` therefore may NOT stamp it with
this phone's own clock: the optimistic row would make the next edit on the
night claim to descend from a version that exists on no server, and the
write's own fetch would read the real server clock as somebody else's,
telling the person "This night changed on another phone first" about their
own previous tap. The servings stepper said it on the FIRST tap, because it
applies locally and then builds its edit from the row it just moved. Only
`settle(.landed)` moves `changedAt`, and it moves it to the clock the record
was actually saved with.

**The wire carries the queue's entry, not the caller's.** `enqueue` folds a
second change onto a waiting first one, so the queue entry is the union of
everything this phone has done to the night and has not sent. `deliver`
reads that entry and sends it. Sending the caller's own edit put only the
newest field on the wire and then dropped the whole folded entry on
`.landed`, so a title changed offline and a cook changed after the phone
came back left the ledger showing both, with nothing queued and nothing
said, while the household had only the cook.

**One writer to the zone.** `publish` guards itself with `inFlight` and
`write` ignored it, so a pass draining this phone's own queued edit while a
`write` was on the wire landed that edit, and the write's own fetch then read
a `modifiedAt` newer than its `seenAt` and told the person somebody else had
changed their night. Nobody had. Both go through `PlanShare.exclusively`
now, one at a time, and a `write` that finds its own edit no longer queued
reports what the drain answered rather than sending it a second time.

**What "queued" says.** `.queued` carries its sentence, because its causes
are not one thing: no iCloud account, a household zone that would not read, a
record that would not fetch, a save the zone did not take. "It goes out when
this phone is back online" was said to a person on four bars whose zone was
the problem. A queued write also asks for a pass itself: nothing else was
coming for it, since the publisher runs on a scene change or three seconds
after a `ModelContext` save and an edit to somebody else's night is neither.

**Offline.** Nothing is lost by a kill: the edit is on disk before the wire
is touched. Every publish pass drains the queue before its own diff, because
somebody is looking at a change they made. A pass also clears any
`pendingSince` with nothing queued behind it, which is what a kill between
the ledger write and the queue write leaves. Edits for a household this phone
has left are dropped and said so.

### Drawing it

`RemotePlanRow` is a door now, not a fact: on the day page a tap opens
`PlanNightSheet` for that night, named by record, because a slot can hold
this phone's dinner and somebody else's at once and only the tap says which
is being changed. In the week and the month the row still opens the day, the
way the local row does, so the two stay peers.

`PlanNightSheet` gained **one more source of truth, not a second sheet**: the
night it changes is this phone's `PlannedMeal`, or the household night when
there is no local meal in the slot (or when a row named one). Every control
acts on whichever is there; the local path is untouched when there is no
household night. The card, the servings stepper and the cook menu are the
same controls; the trash takes the night off for everybody. A stepper held
down is one intention, so the row moves on every tap and the zone hears the
number they stopped on. A change on somebody else's night raises no local
bell row: a notice about the reader's own action is the rule
docs/notifications.md breaks for nothing.

### Who changed it: `editorID` and `editorName`

The record carries the person who PLANNED the night, and any member may now
change one, so the author is the wrong person to name for a change. Before
these two fields, after Riley changed Nate's Thursday every other phone said
"Nate changed Thursday to Ragu": a claim about what somebody did, and false.
Riley's own phone said it too, because the own-action guard compared the
author's id to `TableIdentity.cached` and the author was not Riley.

So the record carries `editorID` and `editorName`, the identity that made
THIS version. Written unconditionally, the way `modifiedAt` is, by both
writers: `TableShare.planRecord` takes them from the author, because the
publisher only ever sends its own `PlannedMeal` rows and the two are the
same person there, and `PlanShare.record(for:)` takes them from
`PlanShare.editor()`, this phone's identity and its own roster row's name.
They ride on the `Edit` rather than being resolved when the queue drains: a
drain happens on a scene change with no sheet and no roster in front of it.

`PlanLedger.Entry` carries them as optionals, for the reason
`pendingRemoval` is one, and `Entry.changedByID` is the editor, or the
author when there is none. `PlanLedger.edited(_:by:)` does NOT fold them
onto the optimistic row: like `changedAt` they are the record's stamp and
not a field the person touched, and what keeps a reader quiet about their
own edit is the digest's guard, which reads the record.

`TableNews.planNotices` names the editor on a change and the author on a
night newly planned or taken off, and its `changer(_:)` is the fallback
ladder: the editor when the record names one, the author when it does not
(every record written before these fields), and **nobody at all** when the
editor is somebody this phone cannot name, because falling back to the
author there would print the false sentence again. `learnNames` folds the
editor's id and name the way it folds the author's and the cook's.

`-plated-prime-share` mints both non-nil through the probe's author, and the
schema is deployed to Production before a build writes them.

### The two phones disagree, on purpose, and say so

This was the open question. It is now decided, and the decision is a limit
rather than a mechanism, so it is written here to stop a later session
"fixing" it back into the thing this whole document rules out.

**The author's own phone does not hear the edit, and nothing reconciles the
two.** Nate's Thursday is a `PlannedMeal` on Nate's phone. `absorb` keeps
nothing he wrote, and his publisher sends only what his own diff changed,
so the zone holds Riley's version and Nate's planner holds his. Three
things were considered and two were refused:

- **Folding the record back into his `PlannedMeal`** is the two writers on
  one fact that the argument at the top of this file exists to forbid.
  Refused, and it is the one answer that can never be taken.
- **Drawing the ledger for a night the household has edited**, so the zone
  becomes that night's truth. Proposed and withdrawn after review. There is
  no stopping point between drawing it and owning it: `PlanNightSheet` takes
  this phone's `PlannedMeal` when one exists in the slot, so the first tap on
  a drawn ledger row opens a different dinner from the one on screen, which
  is the continuity law. And the predicate is not stable across the author's
  own devices, because `plan-share.json` is per device, so an iPad with no
  book entry mints a full record and erases the edit with nobody touching it.
- **What shipped**: the publisher refuses to overwrite, and the interface
  says the two disagree. `pass` fetches before every save and stands down
  when `movedOn` says the record has moved since `BookEntry.serverModifiedAt`,
  which also closes the second-device case above. The stand-down is stable,
  so the night is re-offered and re-refused every pass rather than two phones
  taking turns overwriting each other. `PlanShare.Contest` carries the nouns
  and `PlanNightSheet.contestLine(for:)` draws one sentence on the night
  itself: "Riley changed this night on their phone. Your plan still says
  Tacos", or, on a record written before `editorID`, the same sentence
  naming nobody rather than inventing a "Someone".

**Where the sentence is drawn, and the one place it is not yet.** v1 puts it
on `PlanNightSheet` only, which is where a person goes to CHANGE a night and
therefore the one place where acting on a stale night does damage. It is
deliberately not on the week row, the hero or the month grid: a contested
night is rare, and a line on four surfaces would make the quiet case loud.

The gap that leaves, named here rather than left to be rediscovered: the day
page on the day itself. That is where somebody reads the plan before cooking,
and a person cooking the wrong dinner is the one consequence of this
divergence that happens away from the sheet, which is exactly where they are
not looking at that moment. Adding it there is the next step, and it is the
only surface that has an argument for it.

**A stated disagreement is not a lie; a silently overwritten edit is.** That
is the whole of the reasoning. Nobody's change is destroyed, and the person
holding the phone is told what happened and left to decide. Reconciliation
is a later step with its own conflict rules, and the sentence is what makes
its absence honest rather than hidden.

## Which zone is the household's



**The household invite answers.** `docs/household.md` records membership
in the app group under `plated.household.owner` (read here through
`TableShare.householdOwnerKey`): "" when this Apple ID is the head and the
household zone is its own, the host's user record name when it joined
somebody's household, absent when it is in none. Written on join and on
the head's first mint, cleared on leave and when the zone disappears from
the shared database. One household per Apple ID, so there is nothing to
choose. `PlanLedger.householdOwner` reads that key first.

**Reachable, or not yet.** The key names a zone; `householdZone(ownedBy:)`
finds it in the private database ("") or the shared one (a host). A key
written a breath before the zone shows in the shared database is "could
not ask yet", never "none": the pass leaves the book and the ledger as
they were and tries again.

**Before the key exists** (an install from before the household invite, a
phone between households), the resolution falls back to the household
zones' shares, with the rule the panel produced and the code learned once
already for posts: **a zone does not count because it exists.** The own
household zone counts only when its `CKShare` has at least one participant
with `acceptanceStatus == .accepted`; every `PlatedHousehold` zone in the
shared database counts; one candidate is the household; several fall to
the owner already written down, then to the mutual-invite tie-break (the
lexicographically smallest owner id, computed alike on every phone), then
to **unresolved**, where nothing is published or drawn and Settings shows
the choice; none is none. The fallback writes its answer to
`plated.plan.householdOwner`, the ledger's own key, which the invite's key
supersedes the moment it exists.

**When the answer changes** (a join, a leave, a removal, a chosen table):
book entries whose `zoneOwner` differs from the new target are deleted
from the old zone where it is still reachable and treated as unpublished;
ledger entries for the old owner are dropped; the newly resolved zone's
change token is forgotten through `requestReplay` and `TablePull` reads it
whole, because a zone's deltas never come twice. Leaving the **Table**
touches none of this: the plan is not there.

**When a member leaves** the household, nothing cascades: the `.deleteSelf`
reference fires only when `household-root` is deleted, which nothing does.
So the head, on a delta whose household share changed
(`Changes.householdShareChanged`), sweeps: plan records in the own
household zone whose `authorID` is no longer an accepted participant are
deleted (the head owns the zone and may), their ledger entries dropped, and
their rows and banners withdrawn without a notice, because the head took
them off, not their author.

## The record: `PlatedHouseholdPlan`

In the `PlatedHousehold` zone, parented to `household-root` (both
`setParent` and a `parent` reference with `.deleteSelf`, exactly as
`PlatedDish` is to `table-root`), so the household share covers it and the
Table share never does. Name `plan-<shoppingID>`: deterministic, so a moved or
edited night updates one record rather than minting another, and a deleted
name says what it was. Added to `assertNoEntityCollision`'s `written` set
(TableShare.swift, the line that lists `rootType, postType, …`). Not the
name of any `@Model`, so the mirror cannot adopt it.

Fields, every one non-nil when primed, no lists, no Bools:

| field | type | note |
|---|---|---|
| `authorID` | String | `TableIdentity.cached` of the phone that planned it |
| `authorName` | String | |
| `authorColorHex` | String | |
| `editorID` | String | `TableIdentity.cached` of the phone that made THIS version; the author's own id when the author published it |
| `editorName` | String | that person as their own household knows them; "" when this phone cannot name them, and a reader then says nothing rather than naming the author |
| `cookID` | String | the cook's `participantID`; the owner's own id when the cook is the owner; "" otherwise |
| `cookName` | String | "" when the cook's seat is `.invited`: a name typed five seconds ago is not a cook |
| `cookColorHex` | String | |
| `cookSeat` | String | `HouseholdMember.Seat` raw value, or "" |
| `day` | String | `PlanDay.string(date)`, `yyyy-MM-dd` Gregorian in the writer's time zone. A string, not a Date: "Thursday" has to stay Thursday across time zones. `PlanDay` (DeepLink.swift) is the one formatter for this field and for the plan deep link |
| `slot` | String | `MealSlot` raw value |
| `title` | String | `meal.title` at publish time |
| `servings` | Int64 | |
| `tagline` | String | |
| `cooked` | Int64 | 0 or 1, read with `TableShare.int` (made internal) |
| `cookedAt` | Date | meaningful when `cooked == 1`; primed non-nil, nil later is allowed |
| `hasRecipe` | Int64 | 1 when the night has a recipe anywhere, so a reader can say "Not in your cookbook" and never "in their cookbook" |
| `recipeMinutes` | Int64 | `recipe.totalMinutes` |
| `recipeOriginKey` | String | `recipe.originID`, which is "" for every home-written recipe. **An empty key never matches.** |
| `shoppingID` | String | the same id as in the name |
| `photo` | CKAsset | optional; the recipe photo downscaled to 600px JPEG 0.7 |
| `createdAt` | Date | `meal.createdAt` |
| `changedAt` | Date | the writer's clock at publish; the digest windows replays on it. On the wire the key is `modifiedAt`, the household contract's name for the same fact |

## Publishing: `PlanShare`

`Plated/Services/PlanShare.swift`, `@MainActor enum`. Diff-based, not
hooked into the eleven insert sites, thirty edit sites and four delete
sites, half of which rely on autosave with no explicit save call.

- **Target.** `householdZone()` as above. Unresolved or nil: the pass does
  nothing and says so in the console.
- **Window.** Meals dated from 7 days ago to 90 days ahead, every slot.
- **Fingerprint.** A hash of day, slot, title, servings, cookID, cookName,
  cookSeat, tagline, cooked, cookedAt, hasRecipe, recipeMinutes and
  recipeOriginKey. The photo is fingerprinted separately on the SOURCE
  bytes, `recipe.photoData?.count`, so a pass never decodes a photo it has
  already sent, and the asset is rebuilt and set only when that component
  changed; other edits leave `record["photo"]` untouched so readers do not
  re-download it.
- **Book.** `plan-share.json` in the app group: record name to
  `{fingerprint, photoCount, zoneOwner, day, slot}`. Day and slot are there
  so the delete rule can tell a night taken off from one that aged out.
- **Save.** For each meal whose fingerprint or photo count differs from the
  book, or whose book `zoneOwner` differs from the target (republish after
  a flip or an identity reset): a record the book has never seen is
  created outright; a known one is fetched by name first. Saves go in
  batches of 20 through `modifyRecords(saving:deleting:)`. On
  `.serverRecordChanged` fetch that record once more and save again; on any
  other error leave the book alone and try next pass. On success write the
  fingerprint.
- **Delete.** A book entry with no meal in the window whose day is on or
  after 7 days ago is a night taken off: delete, then drop the entry.
  `.unknownItem` is success. An entry whose day is more than 30 days past
  is deleted from the zone too, so the zone does not keep a year of
  dinners; readers treat any past-day deletion as housekeeping (below).
- **Identity.** Nothing is published while `TableIdentity.isPlaceholder`.
  `TableIdentity.reset()` (an Apple ID change) clears the book, the
  ledger and `householdOwner`, so the next pass republishes into the new
  account's table.
- **When, and how much.** Kicked off AFTER `ShareAcceptor.absorb` returns
  (never inside the 24-second silent-push budget), on scene `.active` and
  `.background`, and three seconds after the last `ModelContext.didSave`
  (iOS 18, observed in `PlatedApp`). One pass at a time; a request during a
  pass runs one more after, the `TablePull` pattern. A pass that runs
  while the app is not active touches at most 10 records and leaves the
  rest for the next foreground pass. The pass task clears its own slot as
  its last act, so a request that lands between the pass finishing and
  its awaiting caller resuming starts a pass rather than joining a
  finished one; `TablePull` clears its slot the same way.
- **shoppingID.** Backfilled at publish time if nil, the same way
  `GroceryListBuilder` does. A backfill on two devices mints two names for
  one night; the digest cancels a removed and an added entry with the same
  day, slot and title inside one delivery so readers never see the pair.

The publisher writes nothing to `PlannedMeal` except that backfill.

## Receiving: `PlanLedger`

`Plated/Services/PlanLedger.swift`, `@MainActor @Observable final class`,
JSON at `plan-ledger.json` in the app group, photos as files under
`plan-photos/<record>.jpg`. Modelled on `TableLedger`.

- `struct Entry: Codable, Identifiable, Equatable`: every wire field plus
  `zoneOwner` (canonical, "" for own) and `hasPhoto`; `date` computed from
  `day` through `PlanDay`; `id` is the record name.
- `absorb(_ changes: TableShare.Changes, me: String) -> Delta`: for each
  `RemotePlan` whose `authorID != me`, overwrite the entry and write the
  photo file if one came; for each deleted name with the `plan-` prefix,
  drop the entry and its photo. Entries whose `authorID == me` are never
  kept: the phone's own nights, and its other devices' nights, are local
  `PlannedMeal` rows already. **A replayed zone carries no deletions**, so
  for every owner in `changes.replayedOwners` the delivered set is the
  whole truth: entries for that owner not in it are dropped. Which is why
  a zone's read is all or nothing in `postChanges`: its records and its
  owner join `Changes` only once every page has come and the token is
  stored, and a read that throws folds nothing, so one page of a table
  can never be taken for the whole of it. Returns
  `Delta { added, changed: [(before, after)], removed }` computed before
  the overwrite; `removed` and `changed` carry only entries whose day is
  today or later, because a past-day deletion is the writer's
  housekeeping and never news. Prunes entries older than 30 days or
  further than 180 days before diffing.
- `householdOwner: String?` from the app group; `plans(on: Date, slot:)`
  returns only entries whose `zoneOwner == householdOwner`. Unresolved
  means nothing is drawn.
- `forget(zoneOwner:)` for a leave or a flip; `clear()` for the identity
  reset and tests; `reattribute(from:to:)` drops entries whose `authorID`
  is the new id. `forget` and `clear` post `PlanLedger.nightsDropped` when
  they dropped anything, and `PlatedApp` answers with a reminder rebuild:
  these paths have no delivery delta, and without it "Your night
  tomorrow" for a table this phone has left fires at 19:00 regardless.
- `photo(for record:) -> Data?` cached in memory.
- `isMine(cook entry) -> Bool` is `entry.cookID == TableIdentity.cached`.
  `cookLine(for entry) -> String?`: nil when `cookName` is empty or
  `cookSeat` is `invited`; "You're cooking" when mine; "<first name> is
  cooking" otherwise, the hero's existing strings.

`TableShare.merge` skips `plan-` names in its deletion loops (they are not
posts and the plate ledger has nothing to forget), and its early-return
guard counts `plans`.

## Drawing a remote night

A remote night is an `Entry`, never a `PlannedMeal`, and the surfaces that
draw it get one sibling component, `RemotePlanRow` in
`Plated/Views/Components/RemotePlanRow.swift`, with `plannedRow`'s
geometry (canvas ground at `Radius.row`, the 0.5pt hairline underline, the
40pt `dateColumn`, 60pt `RecipeArtwork` at `Radius.small`, minHeight 76),
because peers look like peers. What it may never have: a swipe tray, a
drag lift, an ellipsis, Move, Cooked, or a Let's cook it cannot honour. A
control that does nothing is the honesty rule broken. Edit is no longer on
that list: a tap on the day page opens the night in `PlanNightSheet`, which
writes the record. The caption carries "Not sent yet" while a change made
here is still queued, and "Still on the other phones" while a night taken off
here has not gone yet: those are different facts and the row says which
(`Entry.pendingLine`, `pendingSentence`, `pendingSpoken`).

- **WeekView.** Each day: the local dinner as today; then any remote
  dinner on that day as a `RemotePlanRow` beneath it (both when both exist;
  two nights on one day is the truth). The row: date column, artwork from
  the ledger photo or the title well, the title, the cook line, and a
  caption in `inkSecondary` micro type set with `.plType(.micro)` (not
  `MicroLabel`, which uppercases): "Planned by Nate", joined to the tag
  line with the existing " · ". Tap opens `DayDetailView` for the date:
  `.contentShape(Rectangle())`, `.accessibilityElement(children:
  .combine)`, `.accessibilityAddTraits(.isButton)`, hint "Opens the day",
  label as a sentence: "Thursday, Tacos, Riley is cooking, planned by
  Nate". The week's "N planned" count, the date strip's dots and
  `openAheadCount` count remote nights too: a night is a night.
- **The tonight hero.** A third branch beside the local card and the empty
  card: when there is no local dinner tonight and a remote one exists, the
  hero draws the remote: photo, title, the cook line (omitted when the
  ledger has none, as the row omits it; "Cook unassigned" is a fact about
  a local night and a claim about a remote one). The Let's cook
  button appears only when a recipe in this cookbook has the same
  non-empty `originID`; there is no title fallback, because the reader's
  own "Tacos" is not the night Nate planned. Where the button would be, a
  caption: "Planned by Nate. Not in your cookbook." when `hasRecipe` and
  no match, "Planned by Nate." when the night has no recipe. The header's
  ellipsis keeps its empty-night items (Plan this night, Eating out, Pick
  for me), which are honest on a remote-only night.
- **DayDetailView.** Remote nights listed under local ones, same row, no
  Remove and no Cooked toggle.
- **MonthPlannerView.** A day with only a remote night gets its planned
  marker; the selected day lists remote nights read-only.
- **PlanNightSheet.** Unchanged in v1 except one caption when a remote
  night already exists that day: "Nate planned Tacos for this night."
- **Widgets.** `WidgetBridge` falls back to a remote dinner for a day with
  no local one: title, minutes, photo, and the cook. When the cook is me,
  the snapshot carries the owner's own name, initial and colour, so the
  widget's string comparison says "You" the way the app does.
- **Cook line and face.** By `cookID`, never by name. The face is the
  `HouseholdMember` whose `participantID == cookID` when one exists,
  otherwise a neutral monogram from `cookName`. Asymmetry, stated: a
  guest's roster has no row for the host, so "You cook" flows from the
  head's phone to a member's, not the other way, until the guest side
  learns identities from the share (not in v1).
- **Groceries.** Unchanged in v1: a remote night carries no ingredients.
  When the window holds no local meal at all but does hold remote dinners
  still to cook, the empty state says "This week's dinners were planned by
  <authors>. The list covers nights planned on this phone." with the
  names from the entries, never "their cookbook". Not when this phone
  planned anything in the window, even "Eating out": that is a dinner
  this phone planned, and the sentence would be false of it.

## Reminders

`NotificationScheduler.rebuild` reads `PlanLedger.shared` itself, so no
caller can forget it: for each ledger entry whose cook is me, on a day
with no local meal at all, it schedules "Your night tomorrow" (the
existing title) at 19:00 the day before, body "<title>. Planned by <author
first name>.", identifier `plated.turn.remote.<record>`, category
`Category.plan` (no grocery action: the list has nothing for that night).
One turn reminder per day, ever. `rebuild` is also called from
`ShareAcceptor.absorb` when the ledger delta (or the head's sweep) is not
empty, and by `PlatedApp` when the ledger says nights left it outside a
delivery. `Notifier.nudgeTurnIfNeeded` treats a remote dinner tonight as
plated.

This chooses, for remote nights, the second answer to open decision 1c
(the cook's own reminder only); local nights keep their current behaviour
and §1c says so.

## Notices

- `TableNews.Notice.Kind.plan`; `NewsPreferences.Category.planning`
  ("Planning", "When somebody plans a night, moves it, or takes it off the
  week", symbol `calendar`); `PlatedNotificationKind.planShared`
  (`isAboutSomebody`, symbol `calendar`, distinct from the local
  `.mealPlanned`'s badge); `NotificationRouter.category(for: .plan)` is
  the existing `Category.plan`.
- **A plan notice is about a night, never a word to you.** It is never
  `addressed` and never `direct`: `NewsPreferences.category(for:)` routes
  `.plan` to `.planning` BEFORE the addressed check, and `.planShared`
  likewise in the `PlatedNotificationKind` overload, so the Planning switch
  and the badge both govern it. Quiet hours apply; the 19:00 reminder
  already carries the sound for the obligation.
- `digest` takes the ledger `Delta`. Added, by somebody else: "Nate
  planned Tacos for Thursday" with body "You cook." when the cook is me
  (relevance 0.8) or "Riley is cooking." when the cook has a real seat
  (head, joined, notOnPlated), nothing otherwise. Changed: day changed,
  "Nate moved Tacos to Friday"; cook changed to me, "Nate put you down to
  cook Thursday: Tacos" (what Nate did, a field set, nothing more); title
  changed, "Nate changed Thursday to Tacos"; anything else raises nothing.
  Every one of those names the EDITOR, not the author: the record's
  `editorID` and `editorName` say who made this version, and the guard that
  keeps a notice off the reader's own phone compares `Entry.changedByID`
  rather than the author's id.
  Removed, day today or later: **retraction or news, decided by the row.**
  If the `plan:<record>` row is unread or absent, retract: delete the row,
  `removeDeliveredNotifications` for `plated.news.plan:<record>`, and say
  nothing. If the row was read, raise "Nate took Tacos off Thursday",
  passive, under Planning. Both cases rebuild reminders. A removal is not
  windowed on `changedAt` (that is the writer's last save, not when the
  night went): it is about now, and the row already bounds it.
- Keys carry no "|": `remember` splits on it. `plan:<record>:<hash>` where
  the hash is over day, slot, title, cookID and the writer's `changedAt`,
  so an edit re-keys only when it meant something, and a night moved back
  to a day it was on before, or a cook handed back, is said again rather
  than swallowed by the memory. A replay hands back the same `changedAt`,
  so the same publish still keys the same. Identifier and rowKey
  `plan:<record>`, so one night is one banner and one row. `learnNames`
  folds authorID/authorName and cookID/cookName. Added and changed nights
  window on `changedAt` under replay.
- Night phrases through `Stamp.nightPhrase`: "tonight", "tomorrow", a
  weekday within six days, then "12 Aug", then with the year; "last
  Thursday" a few days back. The phrase carries no preposition, the
  sentence does ("planned Tacos for", "moved Tacos to", "took Tacos off",
  "put you down to cook"), so every rung reads.
- Deep link `plated://plan?day=yyyy-MM-dd` (`DeepLink.url(plan:)`,
  `planDay(in:)`); the shell selects Plan and parks the day in `LinkRelay`;
  `WeekView` moves its anchor. `Presence.planVisible` keeps a plan banner
  to the list while the week is on screen. All in place.
- Rehearsal (`-plated-fake-table-news`, simulator only) adds two remote
  nights by Riley: tomorrow with Riley cooking and the day after with the
  reader cooking, sets `householdOwner` and their `zoneOwner` to
  `rehearsal-zone`, and prints the pending `plated.turn.remote.` requests.
  The next launch without the flag drops every `rehearsal-zone` entry.

## Priming and deploy

`-plated-prime-share` writes one `PlatedHouseholdPlan` with every field set,
`editorID` and `editorName` among them, and a photo into the own household
zone, dated `2000-01-01` so every
reader's prune discards it silently, then deletes it. It needs that zone
to exist, so the order is `-plated-prime-household` (the invite's primer,
which mints the zone) and then `-plated-prime-share`; without the zone the
plan line of the summary says "skipped" rather than failing. Nate runs both
once on a phone signed into iCloud and deploys the schema to Production in
the CloudKit console. Until then a
production build's plan saves fail and `PlanShare` retries next pass; no
screen claims anything was shared.

## Not in v1, on purpose

- **Moving** a night planned on another phone, for the reason under
  "Changing a household night": a move is two writes in two authorities.
  Editing one in place is built.
- The author's own phone hearing about an edit at all. Written out at the
  end of "Changing a household night"; not a thing to discover later.
  Naming the editor is no longer on this list: `editorID` and `editorName`
  ride the record.
- Ingredients across Apple IDs. Groceries stay per phone.
- A conflict sheet when two phones plan the same night. Both show.
- The guest side learning the host's identity from the share's
  participants, which would let "You cook" flow member to head.
- A writer who changes time zone republishes every night under a new day
  string and readers see "moved"; that matches what the writer's own
  planner then shows, so it is honest, and rare.

## Statements this change makes false, edited in the same commit

docs/notifications.md: the pipe table (the Table pipe carries plans), what
counts as news, the "five finer ones … no Planning switch" paragraph, the
tap-lands section, the rehearsal section, the test list, and the whole
"Sharing the plan (not built)" section, which becomes a pointer here.
docs/open-decisions.md §17 deleted; §1c gains the remote-night sentence.
NewsPreferences.swift's "not here because the plan does not cross" comment.
SettingsSheet.swift's Table activity captions. NotificationScheduler's
"we schedule at most eight". CLAUDE.md's share-derived-state paragraph
names `PlanLedger` and `plan-share.json` beside `TableLedger` and
`TableOutbox`, and `plan-edits.json` beside those once the write path
landed (2026-09-08): it is the same rule, a queue that may not be mirrored.

## Tests

Pure and held in `PlatedTests`: `PlanShare.fingerprint`,
`PlanShare.plan(for:)` (cook id and seat rules, day string, hasRecipe),
`PlanShare.diff(book:meals:target:)` (save set incl. republish after a
zone flip, delete set, aged-out set), `TableShare.chooseHousehold(own:
joined:stored:)` (the candidate rules, incl. empty own share and the
mutual-invite tie-break), `PlanLedger.absorb` (mine skipped, delete by
prefix, replayed owner reconciliation, past-day deletions silent,
household filter, delta before overwrite), `TableNews.digest` plan notices
(added, moved, put-you-down, title changed, removed-as-retraction vs
removed-as-news, mine ignored, replay window on changedAt, `remember` then
`digest` again raises nothing, removed+added pair cancelled),
`NewsPreferences.category` for `.plan` and `.planShared` with addressed
true, the editor on a changed night (the editor named and not the author, a
night the reader changed raising nothing though its author is somebody else,
a record with no editor falling back to the author, an editor this phone
cannot name saying nothing at all, `learnNames` folding the editor), `PlanShare.record(for:)` (the mint's fields, the original author, both
links, and only the touched fields on a fetched record), `PlanShare.movedOn`
(the second's tolerance and the no-record case), the edit queue (one entry
per night, the fold keeping the earlier `seenAt`, a delete staying a delete,
surviving a relaunch), `PlanLedger.applyLocally` and `settle` (the row moves
and says it has not landed, the record's clock on landing, a refusal putting
the night back, `clearPending`), a delete keeping the row until it lands and
counting until then, `PlanShare.wasTakenOffElsewhere` and the night that
stays gone, `PlanShare.exclusively` letting one writer into the zone at a
time, the twenty-refusal drop answering refused rather than queued, a
refusal not putting a night back into a household this phone has left,
the edit coming back as no news at all,
`Stamp.nightPhrase`, `DeepLink` plan day round trip, the reminder
dedupe (local night wins the day).
