# Plated: the finished product direction

Latest interaction pass: [motion, navigation, complete Table, and release requirements](interaction-and-table-standard.md).

September 4, 2026. Design recommendation and interactive concept, not an implementation sign-off.

## The decision

Keep Plated's original orange, `#FF5A3C`. Build around warm ink, near-white porcelain, Gabarito, Plus Jakarta Sans, good food photography, and small moments of warmth. Retire the darker red proposed in the earlier concept as the dominant brand color. The aubergine and green identity studies are also superseded by this direction.

The product should feel approachable, capable, and a little playful. Its polish must be visible in everyday use: the right dinner opens, the serving count carries through, a recipe edit has a clear scope, and a failed operation keeps the person's work.

The interactive concept is open at [the local preview](http://127.0.0.1:8769/). The inline version also has design controls for orange versus ink primary buttons, editorial versus circular dish photography, light/dark appearance, missing photographs, larger content text, first launch, and loading/empty/offline/error states.

## What carries over from the landing page

I inspected the live [Plated landing page](https://plated.food/) in the browser, and the matching [page source](../../web/app/page.tsx), [color and type definitions](../../web/app/globals.css), [wordmark](../../web/app/components/Wordmark.module.css), and [food animation](../../web/app/components/FallingFood.tsx).

The page's personality comes from generous Gabarito type, a bright orange action, warm ink, open white space, food imagery expressed through emoji, and language about cooking with people you know. Those elements form the connection to the app.

Translate them into the product with different intensity:

- Keep the exact original orange visible in the wordmark, creation controls, the selected dinner date, and the main action where appropriate.
- Preserve the distinctive fonts and the actual wordmark proportions. A new logo badge would weaken continuity.
- Use the playful food vocabulary at first launch, in selected empty states, and after completing a meaningful task. Keep sustained reading and editing areas quiet.
- Make food photos the principal visual content. A missing photo should still leave a deliberate composition with a recognizable dish title.
- Keep functional language direct. Friendly surrounding copy can make the product welcoming; the button should still say what happens.

The marketing page can sustain ambient animation while someone evaluates the product. Daily cooking and shopping need a steadier pace. Repeated decoration should never slow a repeat user or compete with an instruction.

The site promises imports from links, photos, and typed recipes, plus groceries in Reminders. Preserve those capabilities in the product design. A redesign must not accidentally delete them while simplifying navigation.

## Color, type, shape, and hierarchy

| Role | Recommended light value | Application |
|---|---|---|
| Brand orange | `#FF5A3C` | Recognition, selected dinner date, creation, primary actions |
| Warm ink | `#221B14` | Main reading text and labels on original orange |
| Porcelain | `#FFFEFC` | Main canvas |
| Surface | `#FFFFFF` | Sheets and action areas |
| Soft well | `#F4F1EC` | Inputs and quiet grouping |
| Supporting text | `#675D50` | Secondary information that remains readable on tinted surfaces |
| Orange text | `#A93620` | Small accent-colored words on pale surfaces |
| Completion | `#386449` | Checked/cooked status, always accompanied by a label or symbol |

Separate brand paint from readable text paint. Keeping the original orange does not require putting small white labels on it. In the updated prototype, primary orange buttons use warm ink. Dark appearance has its own surfaces and foregrounds; it is not a dark overlay applied to the light screens.

Keep the type family, but tighten its use: display type for page titles, dates, and dish names; Jakarta for controls and body copy. The prototype uses approximately 34–38 px page titles, 28–33 px dish headings, 14–16 px everyday content, and 11–13 px supporting labels. These are web study values. Native implementation must use the existing semantic text styles and content scaling, with no fixed-height container that clips a growing label.

Use shapes with purpose. Circular dates, people, and a possible plated dish treatment provide character. Rounded photographs, editors, and sheets provide practical space. Avoid stacking a border, a filled well, a shadow, and another card around the same content. Native sheets and navigation should keep their platform behavior.

The orange primary-action treatment is my recommendation. The ink-action alternative preserves orange in the date, logo, and creation controls for a quieter balance. This is an adjustment within Plated's identity, not a competing rebrand.

## The experiences that should distinguish Plated

### 1. A week that is immediately understandable

Open to a clear current dinner and a short view of what is next. Make the cook, number of people, and cooking action visible. A recipe photograph and its title open the same dinner. Empty nights have an explicit choice: recipe, leftovers, eating out, or takeaway.

Date selection must agree with the date shown in the content. Choosing a date outside the current range updates the visible range. Moving dinner preserves its recipe and serving count. An occupied destination must show the existing dinner and provide a deliberate replacement or another date; do not silently overwrite it.

The current prototype selects the next available night for a new recipe plan and rejects an occupied date with an inline error. A richer replacement preview, calendar month layout, rotation setup, and gathering behavior remain native design/implementation work.

### 2. Recipes that feel like a personal cookbook

Keep search permanently discoverable. Search titles, ingredients, notes, and meaningful tags. Preserve filters, scroll, and navigation when someone changes tabs. Make favorite and collection operations reversible. Long dish names wrap. Photo-free recipes still have a designed tile.

On the recipe page, show **Edit** and **Serves** directly. A persistent action area offers cooking and planning. The action should carry the quantity the person is currently viewing.

Imports are a review workflow: original source, extracted title, yield, ingredients, steps, time, and photo. Clearly flag missing or uncertain information without treating every line as suspect. Show the original image or source alongside corrections when useful. Preserve fractions, ranges, ingredient groups, notes, and unparsed text. Save the last entered character, even if the field still has focus.

### 3. Serving changes with an obvious scope

There are three distinct operations:

1. Preview a saved recipe at another serving count.
2. Change the people eating one planned dinner.
3. Correct the recipe's base yield in its editor.

Each needs different language and consequences. Previewing six must not rewrite the saved recipe. Planning from that preview must carry six. Correcting the base yield must not silently rescale the ingredient amounts the person entered. Cooking time and temperature cannot be multiplied by the serving ratio.

A recipe edit should not silently alter an active cooking session or the dinner someone already made. Show which upcoming dinners still use an earlier version, and offer a review of a selected dinner before applying the new recipe and grocery requirements.

### 4. Groceries that deserve to be trusted

Give groceries a full destination. Show the included dates and let people inspect which dinners contribute to a quantity. Sort rows consistently so editing a dinner does not reorder the shopping list. Keep manual additions separate from generated requirements.

**Shopping scope, September 4:** keep a visible **Whole week / By meal** choice above the list. By meal opens a dinner picker with photos, dates, and serving counts; choose one dinner or several for a single trip. Keep aisle grouping within that selection. The week combines all planned dinner requirements in the chosen dates. Each ingredient names its contributing dinners directly beneath the item; tapping its quantity opens each dinner’s requirement and a route into the recipe. Other dinners needing that ingredient remain visible in the detail, explicitly outside the current selection. Remember the selected dinners when returning from a recipe. Unassigned extras appear in the weekly list and can be included explicitly when shopping by meal. Adding an extra in meal mode makes it visible immediately. Text copy follows the current scope and includes dinner names.

Track checked quantities once and retain their meal allocations. Buying Monday’s lemon must leave Friday’s lemon outstanding; increasing Friday’s servings must not consume Monday’s recorded allocation. Combining dinner selections must not duplicate that purchase. In this preview, numeric purchase amounts and per-meal allocations live in memory, with reversible checks. Native implementation must persist purchase records and meal contributions together and reconcile household edits, removed dinners, shopping windows, and consumption; this is not a pantry inventory system.

**User preference, September 4: groceries use U.S. shopping measures.** Generated grocery weights display as pounds or ounces; liquid metric measures convert to U.S. fluid ounces. Keep counts, bunches, and explicitly specified packages. Do not invent a can or package size, or convert weight to cups without ingredient-specific information. The preview rounds shopping weights up to practical quantities and shows the smaller recipe requirement in the detail sheet. A checked item records the displayed purchase amount, so the extra remains available when a dinner grows. Original recipe quantities and scaling math are preserved. Quantity details, planning changes, and text export follow the same U.S. presentation. Cross-unit aggregation is a separate native implementation requirement; this preview still groups by the source ingredient/unit key.

A checked ingredient is evidence about the amount that was checked. If the total increases, preserve that amount and expose the additional requirement. For example: butter changes from 2 to 3 tablespoons; the list says that 2 were previously checked and 1 more needs checking. It must not claim that an app checkbox proves current pantry inventory.

Changing a dinner and its grocery contribution should be one coherent local operation with one undo. Keep provenance and compatible units. Do not guess conversions between weight and volume, or merge ambiguous ingredient strings as if they were identical.

Keep Reminders export in the secondary menu with a truthful receipt: the target list, number of items written, which permission is needed, and what happens on a repeated export. A copy-and-open shopping action must use language that describes copying and opening, not ordering.

Verified in the preview: one-dinner filtering, multiple-dinner aggregation, ingredient provenance, drill-down into a planned recipe, scope retained on return, newly added extras remaining visible, and text copy excluding unrelated meals and manual extras. Focused checks also cover allocation to a later dinner, weekly remaining amounts, serving increases, unchecking one meal without clearing another, pre-existing checked amounts, and U.S. purchase rounding. The dinner picker and combined ingredient rows fit a 320-pixel frame without horizontal overflow; browser runtime checks reported no errors. These checks do not establish native persistence or household synchronization.

### 5. Cooking with continuity

Show the current step generously, with ingredients and the full method still available. Use stable units and fractions. Make Next, Previous, timer, and return actions easy to find and operate with a thumb.

Capture the recipe revision and serving count at session start. Minimize into a compact resume control and return to the same step. Starting a different dish requires a choice about the existing session. Background timers need native scheduling and clear expiry behavior; a browser timer is not evidence that those work.

Completion can have a small, warm moment: “Nicely done,” a restrained visual response, and an optional note for next time. Record the meal before encouraging a photo post. A cooked dinner and a published dish are separate events.

### 6. A Table that feels personal

Prioritize the dish, the person, and the conversation. Keep private scope visible without filling the feed with repeated warnings. Do not manufacture engagement statistics, popularity rankings, or empty counters.

Restore the full social profile already conceived in the native app: cover, portrait, bio, and a three-column grid of shared dishes, each opening its thread. Give questions and polls a Conversations section, and show private Saved content only to its owner. The global avatar opens your social profile, with Settings available there. Signup should offer an explicit contact-photo selection, Photos, or camera; Apple does not provide its account picture automatically. The updated preview and native handoff are described in [Social profiles and photo identity](social-profiles-and-photo-identity.md).

A shared recipe is a published copy. Saving it creates the recipient's private copy; editing that copy should not change the original post. Editing a post must preserve existing replies and reactions. Own-post actions differ from someone else's post actions.

The household and the Table have different permissions. A Table guest can see posted dishes and replies without being granted access to private plans or the cookbook. Invitation status needs to reflect sent and accepted events, not the opening of a share sheet. A failed post stays as a draft with a retry. A deletion can appear locally with a pending state; it must propagate to the authorized audience before the interface claims the post is gone everywhere.

### 7. Setup and settings with the same care

First launch should establish the product's promise and get someone to a useful dinner quickly. Ask for optional permissions at the moment they enable a useful task. Joining an existing household requires a clear preview of who is inviting them and what joining grants.

Profile and household settings need the same type, controls, spacing, and error handling as recipes. Keep owner/member/guest roles clear. Separate planned dinners from cooked activity. Defaults affect new plans, not existing dinners. Notification settings must have corresponding working native behavior.

## Coverage across the whole product

The first review covered 37 simulator screenshots and the relevant implementation. This table sets the end-state requirement for surfaces beyond the main four tabs; it is not a claim that the prototype implements them all.

| Surface | Required finished behavior |
|---|---|
| Launch and onboarding | Branded first impression; fast repeat launch; accessible reduced-motion alternative; useful first task |
| Sign-in and account recovery | Clear need for account/iCloud; canceled authentication preserves progress; retry does not duplicate setup |
| Household creation/join | Membership and owner permissions visible before committing; truthful invitation/acceptance state |
| Plan day/week/month | One date vocabulary, stable selection, visible current night, no clipped titles, clear past versus upcoming state |
| Meal assignment and move | Preserve dish, cook, servings, and notes; preview occupied destinations; update grocery contributions coherently |
| Rotation and gatherings | Readable schedule; manual exceptions survive; group attendance and serving counts are distinguishable |
| Recipe search/filter/collections | Stable state, meaningful filters, clear clearing behavior, useful no-results state |
| Link/photo/text imports | Preserve source, review extraction, expose uncertainty, retain draft when extraction fails |
| Recipe editing | Explicit save/cancel, last entry preserved, stable row identities, accessible reordering, local draft recovery |
| Recipe detail and scaling | Obvious Edit/Serves; clear base-versus-preview-versus-meal quantities; no scaling drift |
| Cooking and timers | Frozen session, resumption, background handling, full method access, explicit completion |
| Groceries | Provenance, compatible aggregation, quantity-aware checks, stable rows, separate manual intent |
| Reminders and shopping handoff | Permission recovery, truthful export receipt, idempotent repeats, return path |
| Table feed and composer | Correct audience, natural photo treatment, saved drafts, real pending/error/sent states |
| Replies, reactions, and saved copies | Preserve identity and ownership; private copies; undo where appropriate |
| Post edit/delete | Preserve reactions/replies on edit; propagate authorized deletion; retained state on failure |
| Household/profile/settings | Consistent controls, accurate roles and activity labels, meaningful defaults |
| Widgets and notifications | Open the exact night, recipe, or session; handle deleted content, permissions, stale data, and expired timers |
| Offline and concurrent edits | Show cached versus pending state honestly; retain user work; resolve conflicts without silent loss |
| Small/large layouts and accessibility | Reachable controls, readable contrast, large content text, keyboard/VoiceOver order, reduced motion |

## Frontend and backend are part of the design

The current app is SwiftUI/SwiftData with CloudKit relationships. Build on those boundaries rather than treating visual updates as a reason to rewrite the stack.

- **Recipe:** base yield, stable ingredient and step identity, raw source text, structured quantities, source attribution, and revision.
- **Planned meal:** date, cook, servings, notes, and the chosen recipe revision.
- **Cooking session:** frozen revision, scale, current step, timers, and completion record.
- **Shopping requirement:** each meal's contribution plus separate manual lines; checked coverage is separate from required quantity.
- **Published recipe/post:** a snapshot with real audience authorization, separate from the author's editable private recipe.

Use typed, idempotent operations for updates and retries. Preserve draft identity through navigation and process interruption. Undo should reverse the relevant action without rewinding an unrelated cooking session. Do not rely on row recreation to represent edits when other records need stable ingredient identities.

Distinguish a durable local write from remote delivery. A local multi-record transaction does not establish that a multi-device update is remotely atomic. Pending, retrying, failed, and confirmed states need actual data behind their labels. Two household members making changes at once must not result in silent data loss or duplicate grocery contributions.

## Motion, feedback, and accessibility

Use the app's existing `plPop`, `plSnap`, `plSettle`, matched navigation sources, and haptic vocabulary. Keep the dish associated with the surface it opens. A checking action can change the check and amount; it does not need to bounce the whole row. One completed dinner earns a small celebration. Routine navigation should not perform for attention.

Native sheets should size to their content and available space, with a real close path and preserved keyboard input. Native focus and VoiceOver must follow the operation. Every gesture has an equivalent visible or accessibility action. Respect Reduce Motion and test foreground/background transitions on a device.

The original orange with warm ink is approximately 5.49:1, while white on that orange is approximately 3.10:1. Use the stronger pairing for small button labels. These are palette calculations, not an accessibility certification. Audit all rendered combinations, dynamic type sizes, focus states, empty states, and error states on the actual platform.

## What the prototype demonstrates

The unified local prototype includes the four primary destinations, recipe editing with draft cancellation, fraction entry, serving previews, multiple dinner contributions, dinner changes, grocery checks and manual additions, undo/history, frozen cooking sessions and resumption, a foreground timer, completion notes, Table copies, local composing/replies/reactions, household versus Table membership, preferences, and sample state studies.

Link and photo imports use explicitly labeled sample extraction results. Plain text import supports a limited Ingredients/Method format. No recipe is retrieved from an entered URL, and photos selected in the scan study are not analyzed. Example recipes and food photos are illustrative fixtures, not validated cooking instructions or real household evidence.

All preview changes are local and reset on reload. CloudKit, account setup, invitations, notifications, process-restored drafts, native background timers, export APIs, photo OCR, and conflict resolution are not connected. The larger-text control is a layout study, not native Dynamic Type or VoiceOver validation. The state selector illustrates visual states; it does not induce real network failures.

## Validation performed on the concept

Browser checks covered all four main destinations, a four-to-six dinner update, quantity-aware grocery checks, fraction entry and last-keystroke saving, dirty-edit cancellation, a shared recipe saved as a private copy, cooking minimized and resumed at step two, a new plan choosing the next unoccupied night, and first launch through text import to an editable recipe and a valid plan. The core routes were checked in the live preview; a 320-pixel iframe fixture confirmed the narrow layout without page overflow. Dark appearance, the empty-plan state, welcome screen, and color study were inspected visually. JavaScript syntax validation passed.

A dark text-inheritance defect found during the visual checks was corrected. Grocery rows were made stable across dinner updates. Unknown cooking durations now read “Time not added” and are excluded from the quick filter. Completed cooking notes reappear on the recipe the next time it is opened. These checks cover the demonstrated paths, not every possible interaction sequence.

Selecting the empty-household design state resets the sample data for that study. Reloading the preview restores the sample household. Native keyboard behavior, Dynamic Type, VoiceOver, background execution, real persistence, and network behavior still require device validation.

## Acceptance before calling the shipped app finished

Run complete tasks with actual household members, existing saved recipes, and imperfect photos. The bar is observed behavior:

1. Import a recipe, correct an uncertain quantity, save the final keystroke, and find it again.
2. Preview four to six to four, then plan six without changing the saved base recipe.
3. Increase an already-checked grocery requirement and see the additional amount; undo the dinner and list change together.
4. Edit the saved recipe while a dinner and a cooking session exist. Choose the upcoming dinner to update; preserve the active and completed records.
5. Interrupt an editor, background the app, change tabs, lose the connection, and return with work intact.
6. Resume cooking at the same step, receive a real background timer, record completion, and optionally post the dish.
7. Save a Table recipe as a private copy, edit it, and verify the original post is unchanged.
8. Exercise invitation cancellation, permission refusal, failed export, failed post, concurrent edits, and deletion across devices.
9. Repeat critical tasks at the smallest supported layout, large accessibility text sizes, dark appearance, Reduce Motion, and VoiceOver.

A coherent concept establishes the direction. Passing these tasks establishes whether the product deserves the finished feeling it presents.

## Deliberate changes to existing design rules

The user authorized reconsidering the whole experience and then explicitly retained the original orange. This direction preserves the brand fonts, original orange, wordmark, and warm register. It deliberately proposes orange for meaningful primary actions and selected dates, a separate readable orange text color, darker supporting text, a direct Groceries destination, and editorial dish photography as an alternative to the current circle-only dish treatment. These are visible design decisions, not silent changes to `DESIGN.md` or `Theme.swift`.

No app source files have been changed as part of this design study.
