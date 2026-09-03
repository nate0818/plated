# DESIGN.md

How Plated looks, moves, and speaks. `Plated/Support/Theme.swift` is the
implementation; this is the reasoning, so a change can be judged rather than
just compiled.

**Before adding any UI: reuse before you invent.** Almost everything below
already exists as a token, a component, or a modifier. Every design mistake
worth naming in this file came from building a thing that was already there.

---

## The register

**Quiet chrome, earned colour.** Chrome is calm and near-monochrome so that a
family's own photographs are the only loud thing on screen. Colour appears when
something good happens, never as decoration.

- The `+` button is the single always-tomato element in chrome.
- A plate reaction filling, the Chef's kiss, a seat turning real: these earn colour.
- Never reintroduce ambient accent colour into chrome. The one standing exception
  is today's tinted date card in the Plan list, which Nate asked for explicitly.

Fun lives in **motion, haptics and voice** — never in loud paint.

## Colour

Use the token, never a literal. Every token carries its own dark value.

| Token | Light | Use |
|---|---|---|
| `canvas` | `#FFFFFF` | page and card ground |
| `ink` | `#221B14` | primary text |
| `inkSecondary` | `#7F7364` | every supporting sentence |
| `inkFaint` | `#B5AC9E` | decoration only, never a word |
| `hairline` | `#F0EBE4` | card borders |
| `hairlineSoft` | `#F7F3EE` | row separators |
| `hairlineDashed` | `#EFE7DD` | empty-state dashes |
| `navHairline` | `#EFECE7` | floating bar edge |
| `fill` / `chipFill` | `#F4F1EC` / `#F7F5F1` | wells, chips |
| `tomato` | `#FF5A3C` | the one accent |
| `onTomato` | `#FFFFFF` | text on tomato, both rooms — never a literal white |
| `basil` | `#3DA35D` | progress, cooked, seated |
| `mango` | `#FFB020` | the Chef's kiss, nothing else |
| `grape` | `#B95CF4` | calendar events |

Tints (`tomatoTint`, `basilTint`, …) are for surfaces, not text.

**Two text colours, not three.** `ink` and `inkSecondary` are the only tokens
that may paint a word. `inkFaint` measures 2.24:1 on canvas and 3.08:1 after
dark: it cannot legibly carry a glyph-shaped letter at any size, so it paints
strokes, dashed outlines, and the icon on a control that is genuinely off, and
nothing else. That includes the cases every design system loses first —
placeholders, timestamps, counts, eyebrow labels, disabled-looking-but-tappable
buttons, and inactive tab titles. All of those are things a person reads.

The third level of hierarchy is size and weight, which is what the type scale
is for. It is not a third grey. Sixty-one call sites were painting sentences in
`inkFaint` when this was written, and `MicroLabel` — the eyebrow above almost
every title in the app — defaulted to it, which is most of why the app read as
washed out rather than quiet.

`inkSecondary` was `#8A8074` and measured 3.87:1, under the 4.5:1 floor for
text at these sizes. `#7F7364` is the same hue and saturation at 4.63:1. If a
token has to be lightened for a design to work, the design is wrong.

## Type

- **Gabarito** carries display: titles, date numerals, the wordmark. Weight
  ceiling 700; lighter is allowed and often better at large sizes.
- **Plus Jakarta Sans** carries everything else.
- Both ship as variable TTFs and are registered at launch. On the web they come
  from Google Fonts, which keeps plated.food identical to the app.

**The wordmark is `PlatedWordmark`** in Theme.swift: lowercase Gabarito medium
"plated", tracking −0.022em, tomato dot at 0.27em seated 0.34em down. Plated has
no logo badge. Do not invent one; a "P" in a rounded square is not this product.

## Shape and elevation

Two-shape grammar: **circles are dishes and planning, rounded rectangles are
moments and feed.**

Radii live in `Radius` (`chip` 16, `row` 18, `card` 20, `hero` 24, `sheet` 28).
Shadows live in four steps — `plCardShadow`, `plFloatShadow`, `plDishShadow`,
`plTileShadow`. Add a fifth only if none of them fits, and put it in Theme.swift
rather than inline.

**One row, one geometry.** Rows stacked in a list must share a corner radius and
a stroke weight. Mixing an 18pt/1pt row with a 20pt/2pt row reads as crooked
even when nobody can say why.

Stronger, and the version that was actually broken: **peers look like peers.**
A set of choices gets one treatment. Emphasis inside a set is position and
copy, never paint — a filled ground is this app's SELECTION idiom and putting
it on a row nobody selected is a lie about state. Where two screens draw the
same kind of row, they use the same component: `OptionRow` exists because two
hand-kept copies of it drifted apart, and both grew the same `weighted` flag.

**A stroke has to be visible against the ground behind it.** The border is
part of the geometry, so a border that does not render is a row with different
geometry from the row beside it, whatever the code says. Ratios on canvas:

| stroke | on canvas | on chipFill | on fill |
|---|---|---|---|
| `hairline` | 1.19 | 1.09 | **1.05 — gone** |
| `hairlineSoft` | 1.11 | **1.02 — gone** | **1.02 — gone** |
| `hairlineDashed` | 1.23 | 1.13 | 1.09 |
| `navHairline` | 1.18 | 1.08 | **1.05 — gone** |

Under about 1.08:1 there is no line on the screen. `hairline` over `fill` was
drawn in three places and seen in none of them. A filled well does not need a
border: the fill already draws the shape.

**Chrome caps its Dynamic Type; content does not.** A tab bar, a masthead's
icon cluster, a badge, a date chip: fixed-size furniture with nowhere to
reflow. At AX5 the five tab labels ran into each other, the bell's 16pt badge
held 32pt digits, and the Plan list's 66pt date chip set "MON" as "M" over "O"
over "N". The dish name beside that chip has a whole row to grow into and
should keep going. `.plChrome()` in Theme.swift holds furniture at xxLarge;
everything a person is reading runs to AX5. It changes what is drawn, never
what VoiceOver reads. A title is content, so it wraps to a second line rather
than truncating to "Your...".

**A detent is a measurement, not a guess.** `.presentationDetents([.height(575)])`
was a number typed for six rows in a sheet where two of them are conditional,
so on a phone without Messages it opened with two hundred points of nothing
under the last option. Measure the content with `onGeometryChange` and feed
that; Dynamic Type moves these numbers too. Measure the SCROLL CONTENT, not a
view in the same stack as the scroll view: a `ScrollView` takes whatever
height the detent gives it, so measuring its sibling measures the detent's own
answer coming back around, and the sheet walks itself taller every pass.

**The floating sheet is the OS, not us.** On iOS 26 a detented sheet sits 8pt
off the screen's sides, rounds all four corners, and stops short of the bottom
edge, so the dimmed app shows behind its lower corners. That happens with
`presentationBackground` and `presentationCornerRadius` removed entirely: it
was measured that way. Do not chase it with negative padding.

## Motion

- Springs are `plPop`, `plSnap`, `plSettle`. Use them; don't hand-roll durations.
- **An icon may morph into its own opposite. It may never perform about a tap.**
  Magic Replace is allowed exactly where a symbol swaps for its matched pair and
  the swap *is* the state: `bookmark` to `bookmark.fill` on Save, `circle` to
  `checkmark.circle.fill` on a vote, `heart` to `heart.fill` on a favourite.
  Everything else stays banned: no bouncing tabs, no spinning `+`, no thump on a
  plate tap. The test is whether the symbol is showing you what changed or
  celebrating that you touched it. Colour still carries the meaning and the
  haptic still carries the feedback.
- A toggle must be **one view in both states**. An `if/else` around the two
  symbols swaps SwiftUI's identity, the view is torn down and rebuilt, and no
  transition can survive it — the animation silently does nothing and the code
  looks correct.
- Every animation respects Reduce Motion.
- **Theatre is owed once.** The full launch opener runs 4.3 seconds and is
  right exactly once, on a person's first launch; after that it is a 0.65s
  fade of the settled wordmark off the persimmon plate. Anything that plays
  on every launch has to earn its length every launch.
- Haptics have meaning: `tap` for chrome, `select` for position changes, `plate`
  for something landing, `kiss` for the good thing, `warn` for a refusal.

## Continuity

**The thing you tapped is the thing that opens.** Every push into a detail
view carries a `matchedTransitionSource` on the tile, row or face you touched
and a `.navigationTransition(.zoom(sourceID:in:))` on the destination. A
recipe page that slides in from the right with no relationship to the plate
under your finger is the loudest single reason an app reads as a stack of
screens rather than one place.

- Model-backed sources key on `persistentModelID`. Anything else uses
  `ZoomID` in Theme.swift, so ids stay a shared vocabulary rather than a
  literal per file.
- Two sources may not share one id in one namespace. Where a screen offers
  two doors to the same destination (the owner is both the masthead face and
  a row in People), the tap records which door it came through.
- A source that has scrolled away falls back to a plain push on its own.
  Nothing needs guarding.

## Copy

**A button is a verb that names the outcome. A title is a noun. A caption is a
fact.** If a reader must decode a metaphor to know what a control does, the copy
has failed. "Post", not "Set it on the Table". "Add", not "Lay their place".

- **No em dashes anywhere a person can read them** — buttons, labels, captions,
  empty states, errors, notification bodies, web copy. Use a colon, a comma, or
  a full stop. This does not apply to code comments or `print()` output, and must
  never be applied to `RecipeImporter`'s separator character sets.
- No dashboard voice where a person is being spoken to, and no whimsy in
  functional chrome. Metaphor is allowed only in ambient copy where it is
  unambiguous: "Nothing plated yet" survives because it is instantly clear.
- Say the specific true thing over the clever thing. Specificity is the warmth.
- Never describe what another person did or feels. "Waiting on them" was a claim
  about somebody who had never been contacted.

## Honesty

The rule this codebase has broken most often, and the most expensive to fix.

**The interface may never claim something happened that did not.** A seat that
says "Invited" must correspond to a message that actually sent. A push saying
"Riley cooks tomorrow" must be about a person who exists to the app. A count must
count the real thing. If the app cannot do something, it says so plainly rather
than showing a control that quietly does nothing.

Corollary: **an empty screen must know why it is empty.** "Nothing here"
is a claim, and it is only true when the app actually asked and got an
answer. Three states, never one: *still asking* (a spinner, no words),
*asked and there is nothing* (the invitation), *could not ask* (say so, and
offer the retry). A screen that cannot reach iCloud may not say "Nothing
plated yet", and a search over a corpus that was never populated may not
tell the reader to try a different word. See `TableFeedView.Reach`.

Corollary: **state is recorded, never asserted.** `HouseholdMember.Seat` is set
from a composer reporting `.sent` or CloudKit reporting `.accepted` — never from
optimism. See `Plated/Services/Seats.swift`.

## The Table

The social surface, and the one place the app invites comparison with
products built by much larger teams. Take their craft; refuse their scale.

**The Table is eight people, not eight thousand.** Invite-only, a household
plus the seats it gave away. So the Instagram patterns that exist to manage
scale do not transfer and must not be copied: follower counts, algorithmic
ranking, Explore, story rings as a growth device, likes as social proof. The
patterns that exist for craft do transfer and are the whole point: post card
anatomy, the overflow menu, comment threading, double-tap to react, the
composer flow, edit versus delete, relative timestamps, optimistic posting.
A feed of eight people posting dinner is closer to a family group chat with
photographs than to Instagram, so where the two disagree, study Messages.

**A count is evidence, never furniture.** No numeral until there is something
to count. Instagram draws no like row at zero, Slack no pill, Messages no
chip. In a room this small a mounted zero is not neutral: it is a verdict on
a dinner nobody has got to yet. The same rule retires "0 plates" and
"COMMENTS · 0".

**A reaction notice goes to the author or it goes nowhere.** A like never
appears in the liker's own activity, because you already know what you did.

**A relative timestamp runs only while it is unambiguous.** Weekday for six
days, then a date, then a date with a year. "Thursday" on a three-week-old
post asserts a week that is not the week it means.

**Your own post's menu is not everyone else's menu.** One menu with items
conditionally hidden is how a product ends up offering Nate a link to Nate's
profile. Own-post actions get their own section, destructive last.

**The photograph is the content, so it keeps its own shape**, clamped to 4:5
and 1.91:1 so one tall picture cannot take the whole screen. A fixed band is
for photographs that are furniture: a banner, a hero, a preview.

**Delete means everyone.** See the Honesty section: a local delete of a
published post is not a delete, it is a post that comes back.

## Checked, not remembered

Three of the rules above are greppable, and each was broken at scale before
anybody noticed: sentences painted in `inkFaint`, em dashes through the
notification bodies, colours spelled out where a token belonged.
`scripts/check-design` enforces those three on every build that reaches a
phone or TestFlight. A rule a hundred call sites have to remember is a rule
that gets forgotten at the hundred and first.

A deviation is still allowed. It just has to be visible:

    Circle().strokeBorder(Color.white.opacity(0.06))  // design-ok(literal-colour): a rim highlight is light, not a palette colour

The rest of this file is not checkable and never will be. Voice, register and
continuity need somebody to look.

## Components to reuse

`AvatarCircle` · `DishView` · `SwipeRow` · `MicroLabel` · `OptionRow` ·
`TomatoPillButton` · `InkPillButton` · `CountBlock` · `PhotoWell` ·
`PlatedWordmark` · `.pressable` · `plTappableField` · the `plShadow` family

A `.padding` on a `TextField` makes the pill bigger but **not** tappable — add
`.contentShape` plus a tap that focuses it, or the keyboard never appears. Same
class of bug: `.frame(minWidth: 44)` alone is not hit-testable.

## Accessibility

- 44pt minimum touch target, enforced with `.frame(minWidth:minHeight:)` **and**
  `.contentShape`.
- A row that combines its children needs `.accessibilityElement(children:)` and a
  label that reads as a sentence. A bare "72°" is a stray number; say the
  condition the way Weather does.
- Any gesture-only affordance (long press, swipe, drag) needs an equivalent
  that is not a gesture. `SwipeRow` vends its actions through
  `.accessibilityActions`; a context menu is bridged by SwiftUI on its own.
  Dragging a plate between nights had no equivalent at all, so the night menu
  carries "Move to another night" — a gesture nobody is told about is not a
  feature most people have.
- **A control with a chosen state says so.** `.accessibilityAddTraits(active
  ? .isSelected : [])` on every segment, chip and tab. Colour and a raised
  pill are not audible; without the trait VoiceOver reads eight identical
  buttons and never says which one is on.
- **Reduce Motion is answered in Theme.swift, not at the call site.**
  `plPop`, `plSnap` and `plSettle` flatten to a cross-fade on their own, and
  `plArrive` / `plRise` / `plUnfold` drop their travel. A rule that has to be
  remembered at a hundred and eighteen `withAnimation` calls is a rule that
  gets forgotten at the hundred and nineteenth.
- Dynamic Type must not break layout. Fixed heights that exactly fit their
  content will overflow on a real device: pad and floor instead.
