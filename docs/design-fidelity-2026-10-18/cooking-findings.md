# Recipes, groceries and cooking: approved-design fidelity

Reference: the unchanged October 18 approved `docs/design-polish-review-2026-10-18/review.js` and `review.css`. Baseline inspected: build 45 captures from `docs/design-parity-recheck-2026-10-18/after`; source `fc87ad1` before this worktree's edits. This file is a correction/coverage ledger, not a pass certificate.

## Confirmed differences and implementation

| Surface | Build 45 mismatch | Approved requirement and correction |
| --- | --- | --- |
| Recipe library | Opaque favorite backing, heavier metadata, loose tile rhythm | Photo overlay uses translucent scrim and white 19pt glyph within 44pt target. Standard photos 148pt high/radius9; title20pt with10pt/6pt spacing; metadata11pt; row gap22pt/column14pt. |
| Library search | 52pt field, long low-contrast placeholder | 46pt minimum field,13pt readable “Dish or ingredient”; filtering/clear/search retained. |
| Missing photo | Unverified; generic fork icon | Restrained library book42pt placeholder, no fabricated image or repeated title; same image geometry. |
| Recipe detail | Bold category and separate attribution, ingredient rows about62pt apart | One quiet12pt attribution/context line. Checklist14pt,47pt minimum rows, no10pt gaps between rows. Actual quantities retained. |
| Recipe detail actions | Bordered favorite unlike other icons, translucent header, boxed serving control | Plain44pt favorite; opaque header; explicit Adjust servings near checklist. Existing scaling, import/save, grocery addition, edit/share and contextual actions retained. |
| Section jumps | All labels looked active, no indicator |12pt jumps with2pt selected underline and selected accessibility trait. Initial selection is the first real section; viewport crossings update it during manual scrolling; a short explicitly selected final section stays selected until the next scroll gesture. Empty unavailable sections remain omitted rather than invented. |
| Groceries | Large/heavy quantity and provenance, faint input, reversed footer hierarchy |14pt item /12pt quantity /11pt provenance; readable13pt Add an item. Count and checked total/Undo above3pt progress on neutral surface. |
| Grocery Undo | Generic Undo and capped AX footer | Item-specific visible Undo; stable44pt target. Footer scales/reflows rather than silently capping the reading/control size. |
| Cooking header | Leading filled minimize tile shifted title | Cooking title at left; plain minimize/options at right,44pt targets. |
| Cooking checklist | Quantities prepended to names | Frozen snapshot rendered as name left, original quantity right;14pt/47pt minimum. At accessibility size quantity reflows under name. If a legacy line cannot be split exactly, retain it intact. |
| Cooking step | No approved introduction or segmented step context | Real written steps use “Let’s make dinner,” progress segments (bounded fallback for >10 steps), step number and29pt method. No invented illustrative directions. |
| Active timer | Olive panel, duplicate Set timer, unlabeled options and vague running state | Neutral12pt card/18pt padding; Kitchen timer;34pt digits; direct Pause/Resume; explicit alert state and Timer options. Active timer duration remains editable through its menu. |
| Timer accessibility evidence | Retained AX5 screenshot captured overlapping Pause/Resume transition | Pause/Resume label transaction disables animation. Stable timer-state identifier exposes Running/Paused/Finished separately from system alert authorization. Settled recapture required. |
| Cooking complete | Finished / large success icon / Dinner, made / Done; sharing in body | Cooking / Dinner, done / Nicely done; compact truthful save receipt with dinner/day; optional outlined110pt note; Back to Plan plus Share at the Table in footer. Back to Plan saves notes, dismisses, and routes to the completed date through existing LinkRelay. |

## Honest data and accessibility constraints

- No recipe quantities, photographs, authored instructions, membership, activity or completed dinners are invented to imitate sample data.
- Shared-save pending/refused/conflict states still use their real outcome; a failed save does not display success. Note-save errors preserve the draft.
- Timer status checks actual notification authorization on appearance, after permission requests, and when returning from Settings; muted, paused, completed and denied states do not falsely say Alert on.
- Completion naming uses the saved first name, with “Nicely done.” fallback. The dinner identity/date is preserved before the session is cleared.
- Native interaction targets are at least44pt. The interactive grocery Undo makes the stable native footer slightly taller than the HTML concept's non-native36pt text action; its hierarchy, surface, progress size and alignment now follow the proposal.
- Large-type library becomes one column; ingredients, timer controls and grocery quantities reflow. Only later native verification can establish those renders are satisfactory.

## Required fresh evidence

Implementation and syntax parsing are complete; **runtime/visual checks remain pending** at the time of this entry. Do not mark these rows passed based on source.

- Library: both appearances; missing photo; long titles; under30 filter and no matches; Favorites/Collections navigation; AX5; loading/offline/error.
- Detail: both appearances; no photo; actual directions/notes; section jumps and selected state; servings/quantities; ingredient toggle; unplanned, tonight, future, cooked; AX5; import/save and grocery add failures.
- Groceries: ordinary, checked/item-specific Undo, all checked, empty, manual-only; keyboard; long names and package quantities; category grouping; remove/restore; failure/retry; AX5/short window.
- Cooking: no instructions, real steps, both appearances; timer running/paused/resumed/finished/muted/denied; rapid interruption/relaunch; ingredient persistence; completion receipt; Back to Plan target; notes saved/failed retry; optional sharing; AX5 including settled Pause/Resume pixels.
- Compact/current phones, minimum OS, iPad support, in-place upgrade and device-only alert behavior remain separate checks.

Source-only verification: `swiftc -frontend -parse` on the three owned screen files and `git diff --check` passed. No build or native rendering was performed by this implementation agent.

## First fresh native inspection and corrections

Inspected all six initial native captures in `build/fidelity-initial-named` (Recipes, detail, Groceries; light/dark) and their accessibility trees. These captures precede the viewport section tracking and permission-refresh corrections; they are not final evidence.

- Library photo wells now measure 148pt and ingredient rows measure 47pt. Both appearances show the intended neutral surfaces and quiet title/metadata hierarchy. Real recipe titles, times, ownership and photography remain data differences.
- Found an extra 10pt before the recipe grid: zero-height anchor plus implicit scroll spacing and20pt inset produced28pt; an explicit zero-spacing content stack and18pt inset now match the approved18pt gap.
- Corrected the selected collection label from semibold to regular, retaining the underline/color selection cue.
- Accessibility trees exposed favorite overlays with the recipe's name instead of the favorite action. The recipe accessibility label now precedes the overlay, preserving the independent favorite label.
- The same trees exposed only29.7–29.8pt targets for collection/section jumps. Their44pt label frames now contain explicit content shapes. Timer Pause/Resume and grocery Undo received the same label-level target correction.
- Finished-cooking reflection heading now uses the approved22pt size.
- The grocery progress surface had an18pt blank gap above native tabs in the first captures. It now reserves the actual measured `tabBarReservedHeight` supplied by the shell, without the old extra gap. Feature-perch height/spacing remains reserved only when enabled. Fresh capture is required to confirm the seam at each text/window size.
- Final CSS overrides `.app .micro` to11px, so the native11pt micro label remains correct. Original HTML `.app button` font inheritance makes tab labels15px; the apparent `.tab`10px declaration is overridden. The native15pt tab text is therefore not a discrepancy. The oversized native bar height is a separate shared-shell discrepancy.

The Mac locked before a fresh reference browser session could open. Reference comparison uses the previously inspected original rendered artifact and its unchanged source; no fresh side-by-side browser capture is claimed. All changed targets, spacing and states require recapture.
