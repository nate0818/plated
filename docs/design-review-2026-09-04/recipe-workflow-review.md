# Recipe workflow: a stricter design review

September 4, 2026

## Judgment

The first concept was a promising visual direction and an incomplete product design. It made the app calmer, but omitted existing Edit and Serves controls, simplified recipe detail too aggressively, and did not establish how changes propagate into dinner and groceries. It should not have been presented as evidence of a complete, elite experience.

A rigorous product team would judge the design by whether a person can confidently make, understand, and reverse changes across the entire task. The standard is a coherent experience under realistic conditions, including interruptions and failure. Attractive screens are one part of that standard.

This is my assessment using those criteria, not a claim that specific designers have reviewed Plated.

## What already exists

- Recipe detail has a labeled **Edit** control that opens the existing recipe editor. [Editor presentation](../../Plated/Views/CookbookView.swift#L1166).
- The **Serves** chip beside ingredients changes the ingredient display. From a cookbook recipe it sets a temporary viewing amount; from a planned meal it updates that meal's servings. The current choices are 1, 2, 4, 6, 8, and 12. The chip appears only when there is at least one numeric ingredient quantity. [Serves control](../../Plated/Views/CookbookView.swift#L1742).
- The editor stores the recipe's base yield separately from a planned meal's servings. It already supports natural ingredient entry, stable draft step identities, and nongesture reordering. These are useful foundations to preserve. [Editor](../../Plated/Views/NewRecipeView.swift#L9), [planned meal](../../Plated/Models/PlannedMeal.swift#L14).

The recommendation is to make these capabilities more discoverable and coherent, not to remove them in pursuit of minimalism.

## Three changes that must mean three different things

| User intent | Interaction | What changes |
|---|---|---|
| “Show me enough for six.” | Tap **Serves 4**, choose six; quantities update immediately. | A viewing preference. The saved recipe and scheduled dinners stay unchanged. |
| “Six people are coming tonight.” | Carry six into the dinner plan; show the affected quantities and apply the update. | This scheduled dinner and, when selected, its shopping requirements. |
| “The recipe was mislabeled; these quantities make six.” | **Edit recipe → These ingredient amounts make → 6**. | The recipe's base yield. Ingredient amounts remain as entered. |

“Make a larger batch” belongs to scaling, while “correct the yield” belongs to editing. Putting both behind a generic Servings field creates ambiguity. The labels should express that distinction without asking people to learn a data model.

A stepper should sit beside an obvious value, with direct entry for larger changes. This follows Apple's [stepper guidance](https://developer.apple.com/design/human-interface-guidelines/steppers).

## The proposed recipe experience

**Recipe detail:** Edit remains visible in the top bar. Serves sits beside Ingredients. The photo is compact enough that actual controls and quantities appear early. The saved recipe, a scaled preview, and a planned meal each have clear context. Share, duplicate, archive, and history are secondary actions; editing must not depend on discovering an unlabeled overflow menu.

**Editing:** use a dedicated full-screen editor with a stable Cancel / Save bar. Put the recipe name, base yield, ingredient lines, and method ahead of optional classification. Keep natural entry such as “1/2 tbsp butter.” Put structured amount/unit correction behind an ingredient's details control. Support paste, insert, remove, reorder, keyboard navigation, and undo. Preserve the exact last keystroke when saving. Imported source text and attribution should survive a local edit.

**Drafts:** keep edits isolated until Save. Preserve a recoverable local draft through interruption or termination; returning to another screen is not a discard action. Ask about discarding only when work would actually be lost. A failed save leaves the draft intact and the error next to the relevant problem. The prototype demonstrates Save, Cancel, discard protection, and undo, but does not implement durable storage across reloads.

**Applying a recipe edit to dinner:** editing the cookbook should not silently rewrite an active cooking session or a previously cooked meal. Use recipe revisions or snapshots for those contexts. For upcoming meals, offer a concise way to apply the edited recipe and inspect the grocery impact. Avoid prompting on every minor metadata change; distinguish changes to yield, ingredients, or method from cosmetic edits. The prototype exposes this review as a separate step so the boundary can be assessed.

**Shopping:** show changed requirements in place. A previous checkbox means the user considered the old requirement covered; it does not measure the contents of their fridge or the size of the package they bought. If two tablespoons were previously checked and the new requirement is three, show **“1 tbsp more to check.”** Let the person confirm they already have enough or buy more. Preserve manual entries and other meals' contributions.

**Cooking:** use the chosen recipe version and serving count throughout the session. Keep all steps available, preserve the current step, and make ingredients reachable. Ingredient quantities can scale; temperature, time, pan capacity, and cooking technique must not be mechanically multiplied. Ambiguous amounts stay as written and can be corrected. The prototype uses short sample instructions to show the interaction; it is not a validated cooking recipe.

**Recovery:** name the change being undone and reverse the associated state coherently. Do not show a generic Undo that only restores the visible label while leaving shopping quantities changed. Apple emphasizes predictable undo outcomes in its [undo guidance](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo).

## Concrete implementation concerns found in the current source

These are code-path findings. They were not independently exercised in the installed app during this follow-up.

| Finding | Consequence | Required behavior |
|---|---|---|
| Cookbook scaling uses `servesLens`, but `PlateAssignSheet` receives only the recipe and writes `recipe.servings` when creating a meal. | Someone can view six servings and then plan the base four. | Carry the selected quantity into the planning draft; show and persist it. |
| The header's Serves count reads the meal or recipe, while ingredients can use the temporary lens. | Two areas of the same page can report different serving counts. | Use one clearly labeled display context; retain base yield only where it is explained. |
| Grocery checked state is carried by ingredient name and unit, without comparing the old and new requirement. | A larger requirement can remain marked complete. | Reconcile coverage with changed requirements and expose the extra amount for review. |
| A matching manual grocery key suppresses the auto-generated line wholesale. | A manual quantity is not necessarily enough to cover several planned meals using that ingredient. | Treat manual intent and meal contributions separately; reconcile quantity instead of treating name equality as fulfillment. |
| A planned meal reads ingredients through its live Recipe relationship. | Later edits can change what a previous or active dinner appears to have used. | Define revision/snapshot policy for upcoming, active, and completed meals. |
| Saving a recipe rebuilds every Ingredient child. | Ingredient identity is unsuitable for stable contribution tracking or field-level merge without further work. | Preserve identities or introduce a stable logical identity/version layer before building those behaviors. |

Evidence: [servings display and lens](../../Plated/Views/CookbookView.swift#L1025), [ingredient scaling](../../Plated/Views/CookbookView.swift#L1471), [assignment entry](../../Plated/Views/CookbookView.swift#L1170), [assignment save](../../Plated/Views/CookbookView.swift#L2035), [grocery state and manual suppression](../../Plated/Services/GroceryListBuilder.swift#L47), [live meal scaling](../../Plated/Models/PlannedMeal.swift#L61), [editor ingredient replacement](../../Plated/Views/NewRecipeView.swift#L991).

## How I would expect a strong cross-functional team to evaluate it

| Discipline | Questions that determine quality |
|---|---|
| Product and UX | Can people find Edit and Serves without instruction? Do they know which dinner changes? Can they recover? Does a task remain coherent across screens? |
| Visual and interaction design | Are primary actions visible without visual clutter? Does the same control mean the same thing? Does the app retain Plated's character with real, missing, and poor-quality photos? |
| Frontend engineering | Does state survive navigation, sheets, keyboard changes, backgrounding, and Dynamic Type? Do focus, scroll position, row identity, and announcements remain stable? Do errors preserve work? |
| Backend and data engineering | Are recipe, meal, session, and grocery records distinct? Are updates idempotent? Do revisions, offline writes, permissions, and concurrent edits produce a truthful UI? |
| Research and quality assurance | Can planners and cooks complete realistic tasks without coaching? Are unintended edits, incorrect shopping requirements, and lost drafts absent in the tested scenarios? |

No numeric “elite score” would be credible from mockups alone. The concept is ready to evaluate as a task flow; it is not evidence of production readiness.

## The underlying data contract

The app already separates Recipe and PlannedMeal. Build on that boundary:

1. **Recipe:** the editable kitchen copy, with base yield, structured ingredient data, original text, ordered steps, and revision identity.
2. **Planned meal:** date, cook, number of people, and the selected recipe revision. Changing one night's count does not modify the base recipe.
3. **Cooking session:** the actual version, scale, current step, and timers being used. Backgrounding cannot silently substitute a different recipe.
4. **Shopping requirement:** contributions from each planned meal, alongside independent manual lines. Coverage/check state is distinct from the required amount.

Commit related local changes coherently. Treat sync as a separate, observable process; a successful local write does not prove another person's device received it. Do not assume a multi-record local update becomes an atomic remote operation. Retries must not duplicate dinners or grocery contributions. Shared editing, if introduced, needs real authorization and conflict handling; a visibility flag is insufficient. Current recipe storage is private, and the proposed controls should continue to say so until the sharing implementation changes.

Store source quantities without repeatedly scaling the stored base. Scale from that base each time and round only for display. Retain fractions, ranges, preparation notes, and unparsed text. Convert units only when dimensions and ingredient-specific information support it. Recipe amount and supermarket package size are different values.

## The acceptance scenario

Before accepting the implementation, observe this complete sequence with real recipes:

1. Find a saved dish, open it, and edit an ingredient without help.
2. Cancel once and verify nothing changed; save once and verify the entire last entry survived.
3. Preview four → six → four servings without changing the stored base or accumulating rounding error.
4. Plan six servings and confirm that dinner and shopping both use six.
5. Increase a requirement that was already checked; preserve coverage and expose the additional requirement.
6. Apply a recipe edit to one upcoming dinner while preserving a completed meal and an active session.
7. Reverse that update and verify both dinner and groceries return together.
8. Interrupt editing, lose connectivity, return from another tab, and repeat with large text and VoiceOver.

The browser concept demonstrates local recipe editing, fraction formatting, scaling, planning, grocery coverage, and undo. Persistence after termination, real sync, conflict handling, accessibility on iOS, and multiple simultaneous meal contributions remain implementation and validation work.
