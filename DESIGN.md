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
| `inkSecondary` | `#8A8074` | supporting text |
| `inkFaint` | `#B5AC9E` | the quietest legible thing |
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

## Motion

- Springs are `plPop`, `plSnap`, `plSettle`. Use them; don't hand-roll durations.
- **An icon must never perform its own state change.** No bouncing tabs, no
  spinning `+`, no symbol-effect thump on a heart. Colour carries the meaning and
  the haptic carries the feedback.
- Every animation respects Reduce Motion.
- Haptics have meaning: `tap` for chrome, `select` for position changes, `plate`
  for something landing, `kiss` for the good thing, `warn` for a refusal.

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

Corollary: **state is recorded, never asserted.** `HouseholdMember.Seat` is set
from a composer reporting `.sent` or CloudKit reporting `.accepted` — never from
optimism. See `Plated/Services/Seats.swift`.

## Components to reuse

`AvatarCircle` · `DishView` · `SwipeRow` · `MicroLabel` · `TomatoPillButton` ·
`InkPillButton` · `CountBlock` · `PhotoWell` · `PlatedWordmark` · `.pressable` ·
`plTappableField` · the `plShadow` family

A `.padding` on a `TextField` makes the pill bigger but **not** tappable — add
`.contentShape` plus a tap that focuses it, or the keyboard never appears. Same
class of bug: `.frame(minWidth: 44)` alone is not hit-testable.

## Accessibility

- 44pt minimum touch target, enforced with `.frame(minWidth:minHeight:)` **and**
  `.contentShape`.
- A row that combines its children needs `.accessibilityElement(children:)` and a
  label that reads as a sentence. A bare "72°" is a stray number; say the
  condition the way Weather does.
- Any gesture-only affordance (long press, swipe) needs an
  `.accessibilityAction` equivalent.
- Dynamic Type must not break layout. Fixed heights that exactly fit their
  content will overflow on a real device: pad and floor instead.
