# Open decisions

Things found, measured, and deliberately **not** decided, because each one is
a judgment call with two defensible answers and a visible cost either way.
They are here rather than in a commit message so the next person to open the
question starts from the measurement instead of the argument.

Everything in this file has been verified against the code as it stands. If a
line names a file, check it still says what this says before acting on it.

---

## 1. Avatar initials fail contrast, and the owner does not

`AvatarCircle` paints the initials in the person's `tone` on that person's
`tint`. Measured on canvas in the light room:

| pair | ratio |
|---|---|
| tomato on `tomatoTint` | 2.73:1 |
| basil on `basilTint` | 2.87:1 |
| amber on `mangoTint` | 2.98:1 |
| **neutral (the owner)** on `fill` | **15.09:1** |

The floor for a glyph this size is 3.0:1, so all three colour pairs miss it,
and becoming a coloured member measurably makes your own name harder to read
than the owner's.

**The two answers pull opposite ways.** Ink letters on the existing pale tint
gives 15:1 and stays inside DESIGN.md's quiet register, but the person's
colour nearly disappears at 22pt. White letters on a *saturated* disc gives
3.10–3.56:1, keeps identity legible across the app, and is what Messages and
Contacts do — but a grid of saturated discs is louder than "quiet chrome,
earned colour" describes.

Either changes every avatar in the app. Not a 4am call.

## 1b. "Everyone plated" is measured against the reader's household

`TablePost.hasChefsKiss(seats:)` is called from nine places, every one of
them passing `members.count`: the number of `HouseholdMember` rows on the
phone doing the reading. That is not the number of people who can plate. A
by-name seat (a kid, a grandparent) cannot plate and inflates it; a guest
who joined a table but keeps a one-person household of their own deflates
it, so on their phone the kiss fires at a single plate. The push notice for
the kiss inherits the same denominator, so two phones can disagree about
whether a dinner earned the kiss.

The honest denominator is the table's participants (`TableShare.participants`),
which is a CloudKit round trip and not available synchronously in a body.
Caching it per zone in the ledger would fix all nine sites at once. Not done
here because it changes what the feed, the profile and Home have said the
kiss means since it shipped, and that is a product call.

**Decided:** `TableKiss.seating` counts `.head`/`.joined` plus unique guest
authors (first-name match). CloudKit participants cache still open if a
sharper denominator is needed later.

## 1c. The reminder that says "Nothing for you to do"

`NotificationScheduler.scheduleTurns` sends "Riley cooks tomorrow. Sheet-pan
chicken. Nothing for you to do." to everybody who is not Riley, with a
sound, at 19:00. The design panel of Sept 4 judged it the one reminder
that lights a screen to say there is nothing to do, and offered two
answers: keep it and deliver it passively (in the list, no sound, body
just the dish), or send only the cook's own reminder and let the widget
carry the rest, with the Settings caption becoming "The evening before
your night, and Sundays when the week's still open." Both are defensible.
The first keeps a household informed; the second is what a person who
hates being nagged would choose. Nate's call. Remote nights, planned on
another phone and read from the shared zone, already take the second
answer: `NotificationScheduler` schedules only the cook's own reminder
for them (`docs/plan-share.md`, "Reminders"); local nights keep the
first until this is decided.

**Decided:** cook-only — local `scheduleTurns` skips non-cook reminders;
remote nights keep cook-only and now also say "Check the grocery list tonight."

## 1d. Opening the feed reads the dishes below the fold

`TableNews.markRead(post:)` reads one dish's notices when its thread opens.
The panel proposed that opening the Table itself reads every dish and ask
notice, the way Messages reads a whole conversation on open, since eight
people cannot bury anything. The narrower rule (only what scrolled on
screen, via `Presence`) is more exact and more work. Not done pending a
yes; the bell's own read-on-leave already covers the rows.

## 2. `symbolMatching` and `gabaritoMatching` have zero call sites

`BrandFonts.swift` defines both, with worked cap-height ratios and a comment
saying "every glyph-next-to-text pair in the app was off by roughly 6%". Grep
returns no callers anywhere.

Meanwhile every SF Symbol in the app is `.font(.system(size:))`, which is
frozen: it does not scale with Dynamic Type at all. Inside `.plChrome()` that
is correct — chrome caps its type on purpose. In content it is not.

Adopting the helpers wholesale resizes icons on every screen at once, which
needs a device pass at several type sizes before anyone can say it looks
right. Until then the two functions are a solution sitting next to its
problem, which is worse than not having them, because a future session will
read them and assume the app is cap-matched.

## 3. "Saved by others" cannot count what it says

`Awards.recordSaveReceived(by:)` is called **on this device** when *you* save
somebody's post, keyed by that post's author. So the ledger records "on this
phone, I saved N dishes by <author>".

`HouseholdStatsView` then sums `savesReceived(by:)` across household members
and labels it "Saved by others". It cannot ever count a save another
household made — that happens on their device and nothing carries it here.
On your own profile the number is structurally zero.

Relabelling it to what it counts ("dishes you saved") makes it honest but
turns a social signal into a personal one. Removing it is a product decision.
Leaving it is the only option that is definitely wrong.

**Decided:** relabelled to "Dishes you saved".

## 4. `safeAreaBar` and the scroll edge effect

No scroll view in the app registers a scroll edge effect, so content runs out
from beside and under the floating tab bar instead of dissolving into it.
`safeAreaBar(edge:)` is the iOS 26 answer and is callable from an 18.0 target
behind `#available`.

The reason it is not done: eleven scroll views hand-pad with
`Layout.floatingChromeInset`, which this branch just changed to follow
`ProngsbyFeature`. Adopting `safeAreaBar` makes the OS apply that inset
itself, so the two would double up until every call site is unwound
together. It is a single coherent change across a dozen files, and it wants
someone watching the screen while it lands.

## 5. The layered app icon

`AppIcon.appiconset` holds three flat PNGs (default, dark, tinted) and no
`.icon` document. On iOS 26 that means no layered lighting and no artwork at
all for the Clear appearance.

The mark is already two layers by construction — persimmon ground, white
wordmark with its dot — so this is a rebuild in Icon Composer rather than a
redesign, and DESIGN.md's ban on inventing a logo badge is not in the way.
It cannot be authored headlessly.

## 6. Calendar rotation still needs a physical-device pass

September 4 update: Month is now an explicit choice alongside Week, with
Today, month navigation, a responsive date grid, and the selected day's meals.
The native portrait month and week have been inspected in simulator screenshots;
the old fixed-width portrait overflow no longer applies. Entering landscape
selects Month and the segmented control follows the visible mode.

A physical-device rotation and larger-text interaction pass is still needed.
The calendar scrolls, so the test should confirm that the selected day's agenda
and planning actions stay easy to reach in a short landscape viewport.

## 7. TextField placeholders use the system tint

Every `TextField` in the app relies on iOS's default `placeholderText`, which
is very light. DESIGN.md names placeholders explicitly among the things that
must not be painted in a tone too faint to read.

This is the platform default that Apple itself ships, and overriding it
touches every text field in the app. Worth a deliberate decision rather than
a drive-by.

## 8. The plate count is painted tomato

`TableFeedView` paints the plate count `tomato` when you are among the
platers: 3.10:1 on canvas, at `.body` bold (15pt), which clears the 3.0:1
floor for large text. So it passes — but the *glyph* beside it already fills
tomato, so the colour is carrying the same fact twice, and Instagram
deliberately paints the count in its label colour and reserves red for the
heart.

Fifteen other `Text` sites paint tomato legitimately (today markers, which
DESIGN.md explicitly permits, and action labels), so there is no blanket rule
to apply here. Marginal, passing, and a matter of taste.

## 9. Sign in with Apple fails silently

`SignInView` opens the door on any non-cancel failure, saves no identity, and
never mentions it. The comment argues the case — planning must not be hostage
to an Apple outage — and that reasoning holds.

The gap is only that the person is never told they are running without an
identity, and features that depend on one will quietly do nothing. Where to
say so, and how loudly, is a design question about a screen somebody has
already left.

---

## 10. The pin toggle buzzes `plate`, not `select`

`CookbookView`'s pin action fires `Haptic.plate()`. The vocabulary in
Theme.swift gives `select` to "the tick of moving between options" and
`plate` to something landing.

A pin is both. It is a change of position in a list, which is `select`, and
it is the dish landing at the top of the shelf, which is `plate`. Favourite,
one line away, is a state change and fires `tap`. Whichever way this goes,
the three should agree, and picking one means saying what a pin *is*.

## 11. `kiss` versus `plate` on a saved recipe

`RecipeImportSheet` saves with `Haptic.kiss`; `RecipeEditorView` saves with
`Haptic.plate`. Theme.swift explicitly defends letting a call site keep its
own — "a save that earns the kiss must keep it. Flattening every pill to one
buzz is how a shared component quietly costs a screen its voice."

So the disagreement may be deliberate. Whether an imported recipe and a
hand-written one have earned the same beat is a taste question, not a bug,
and it is the kind of thing that should be felt on a phone rather than
argued.

## 12. Meal chips are not presence-filtered; genres are

The filter sheet hides "Kind of dish" when no recipe carries a genre
(`presentGenres`), and always shows all six Meal chips.

For filtering: symmetry, and never offering a filter that cannot match.
Against: genre is a set *discovered* from the data, while the meal taxonomy
is a fixed filing system the cook chooses *from* — hiding "Dessert" until a
dessert exists tells somebody the app has no idea what a dessert is. Left
asymmetric deliberately.

## 13. "Saved from a post" does not name who cooked it

A recipe saved from the Table or from Discover shows "Saved from a post".
Naming the household or the cook would be warmer and more specific, which
DESIGN.md prefers.

It needs the name stored on the `Recipe` at both save paths; the Discover
author currently survives only as a parsed `tags` string, and the shared
`prefill` initialiser that would have to carry it is also used by
`TableFeedView`. That is real plumbing for a byline, so the neutral true noun
ships until somebody decides the byline is worth it.

## 14. An ingredient range is silently narrowed to its low end

`parseIngredientLine` takes the lower bound of "2-3 cloves garlic" and stores
2, with a comment saying so. Pasting that recipe gives a cookbook entry and a
grocery line that both say 2, and nothing on screen records that the recipe
said 2 to 3.

For narrowing: one number is what a quantity field holds, a shopping list
wants a number, and you can always use the third clove. Against: it is a
quiet edit to what the recipe said, which is the class of thing this
codebase is otherwise strict about — and the review step exists precisely so
quiet edits are visible.

Storing the range would mean a second quantity on `Ingredient` (CloudKit-safe
if optional) and a decision about what the grocery aggregation does with it.
Measured and left alone.

## 15. The three-state Reach stops at the cookbook shelf

`CookbookView` now distinguishes still-looking, empty, and could-not-reach.
`RecipePickerSheet` deliberately does not: it is a modal opened mid-planning
with no refresh path, where a spinner is arguably worse than the invitation
it already offers.

`DiscoverView` shows a third, cheaper answer — phrase the claim to what this
phone actually knows and skip the machine entirely. Which of the three every
remaining empty state deserves is a per-screen judgment, and doing it by rule
would put a spinner in front of somebody choosing dinner.

## 16. A Notification Service Extension for the Table pipe

Considered and not built. Four reasons: an extension can rewrite a banner
but cannot withhold one, and withholding is most of what `TableNews` does;
a `CKDatabaseSubscription` alert cannot name a person, because
`alertLocalizationArgs` read fields off a record the shared-database
subscription does not carry; a third target cannot import `Theme.swift`,
which is the widget's drift trap again; and on the server pipe the invite
alert is already named, so an extension would buy only an opaque payload
and a face. Reopen if Apple lets a service extension suppress a delivery,
or if the directory grows a per-person "who to tell" so named Table alerts
could be sent from a server that knows the author, at which point "never
about your own action" has to be re-proven there before one alert is sent.

## 17. A link-joined participant is removed one at a time, and CloudKit may not allow it

`Seats.remove` (`Plated/Services/Seats.swift`, line 216) evicts a joined seat
through `HouseholdShare.removeParticipant` (`Plated/Services/HouseholdShare.swift`,
line 1535), which finds the participant by `userRecordID` on the household
share and saves the share without them. docs/household.md section 1 records
the constraint underneath it: Apple documents participant edits as allowed
only while `publicPermission` is `.none`, and the household share is
`.readWrite` public on purpose, because the participant-only shares the
Table tried admitted almost nobody. So this code is written against a
behaviour Apple has not promised. When it works, one person leaves and the
rest keep the plan. When it is refused, the row says "Couldn't remove Riley"
and stops, and the only certain eviction is the one nobody wants: set
`publicPermission = .none`, which drops every participant at once, and then
re-invite the others.

The two answers: keep the one-at-a-time attempt and accept that Remove may
be a control that says no on some accounts, or replace it with the certain
version and make Remove mean "start the household's guest list again",
which is honest but turns a one-person action into an everyone action.
What settles it is a measurement, not an argument: Remove, on three phones
with three Apple IDs, on a share that has two link-joined participants.
Until that has been run once, the code tries, says what happened, and this
entry stands.

## 18. The chef's kiss denominator, now that the roster is shared

Entry 1b measured `hasChefsKiss(seats:)` against the reader's own
`members.count`. The household zone changes half of that. Every member's
phone now carries the same roster, so `members.count` agrees across a
household and the member's phone stops firing the kiss at a single plate.
What it does not fix is the other half: a Table-only friend can plate and
is not in the roster, and a by-name seat is in the roster and cannot plate.
Ten call sites still pass `members.count` (`TablePost.hasChefsKiss`,
`Plated/Models/TablePost.swift`, line 157; four of the sites are in
`TableFeedView`).

The honest denominator is still the Table's participants, which is a
CloudKit round trip and unavailable in a body. Two ways to get there:
count `.joined` seats plus the Table share's non-roster participants, cached
in the ledger per zone, which changes what the kiss has meant since it
shipped; or leave the roster count, which is now right for a household with
no Table guests and wrong by exactly the number of guests otherwise. The
first is a product call about what "everyone" means at a table that has
guests. The second is what ships. A test that seeds two seats and one guest
and asserts which plate count earns the kiss would make the choice visible
either way.

**Decided:** same as §1b — `TableKiss.seating` (head/joined + guest authors).

## 19. "Nothing for you to do" now reaches every member

Entry 1c is about one reminder on one phone. The shared plan makes it
several. `NotificationScheduler.scheduleTurns`
(`Plated/Services/NotificationScheduler.swift`, line 216) sends "Riley cooks
tomorrow. Sheet-pan chicken. Nothing for you to do." with a sound at 19:00
to everybody who is not the cook, and it is rebuilt on every phone after
every household pull, from the same meals. Before the household crossed
Apple IDs that was the host's phone and a kid's; now it is every member's
phone, and a household of four hears three phones say there is nothing to
do about the fourth one's night.

The two answers from the Sept 4 panel have not changed and neither has who
decides: keep it and make it passive, or send only the cook's own reminder
and let the widget carry the rest. What has changed is the cost of leaving
it. It used to be a single reminder that arguably over-shared; it is now the
one household notification that scales with the household. Nate's call,
still, and this entry only records that the number went up.

**Decided:** same as §1c — cook-only locally; no "Nothing for you to do."

## 20. A joiner's past cooked nights stay on their phone and never travel

`HouseholdSync.clearBeforeFirstPull` (`Plated/Services/HouseholdSync.swift`,
line 1050) deletes a joiner's planned meals from today on and keeps the
earlier ones. The reason for the deletion has changed and the decision has
not: the household's week is now drawn beside this phone's own nights out of
`PlanLedger` (docs/plan-share.md), so a joiner who kept their future nights
would see every evening described twice. docs/household.md section 14 states
the intent: their insights are theirs;
the household's are the household's. The visible effect is on
`HouseholdStatsView` and `Awards.metrics`: a person who cooked forty nights
before joining still sees forty on their own phone, and the household they
joined sees none of them, which is right for the household and can read as
a loss to the person the moment they compare phones.

The other answer is to push past nights as history with the joiner's seat
as cook, which gives the household an honest record of what its new member
cooked and gives every other phone forty rows of somebody else's dinners
from before they met. Both are defensible. What would settle it is a
household where this actually happened: one joiner with a real history and
a host looking at the month view afterwards. Until then the quieter answer
ships. A later push of history would need `PlanShare` to publish outside its
seven-day-back window and every reader to keep entries it currently prunes,
which nothing today does.

## 21. Extra photos arrive with the recipe and every mirror re-exports them

`HouseholdShare.merge` (`Plated/Services/HouseholdShare.swift`, line 1223)
replaces a recipe's `RecipePhoto` rows from `extraPhotos` on arrival, so a
member's phone holds every photo the moment the recipe lands and the
member's own private mirror then uploads all of them again to that
member's iCloud. docs/household.md section 2 accepts the cost in words: a
household of four stores its cookbook four times over plus once in the
zone. The photos are most of the bytes, so the sentence is really about
them. Fetching extras on demand would keep each phone to the hero image
until a person opens the recipe, and would put a spinner on a photo strip
that is instant today, on a screen that works offline today.

Two defensible answers, and the tie-breaker is a number nobody has yet: how
big a real household's cookbook gets. Six recipes with three photos each
is nothing; two hundred with six each is a storage complaint. What settles
it is the first such complaint, or a measurement of the mirror's upload
after a join on a phone with a full cookbook, read off iCloud storage in
Settings before and after. Section 14 already says revisit then; this entry
says what to measure.
