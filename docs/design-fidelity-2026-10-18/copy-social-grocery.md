# Social, profile and grocery copy reconciliation

Scoped review on October 20, 2026. Isolated candidate: `/Users/natemeadows/.codex/worktrees/plated-approved-fidelity/Plated`. This review resumed earlier edits already present in the three files; it did not alter their product source.

The immutable reference is `docs/design-polish-review-2026-10-18/review.js` (SHA-256 `cb45d1f300a0719674ad9ea87db7044789365d7b545133b377557ee156df5d6b`), specifically `composer`, `profile`, and `groceries`, plus their approved annotations. `AGENTS.md` and `DESIGN.md` govern state truth and verification.

## Reconciled source

| Surface and acceptance criterion | Candidate implementation | State truth |
| --- | --- | --- |
| Composer identifies the selected private audience beside its author. | Own destination reads **Your Table · Private**. Other destinations retain their actual destination label and **· Private**. | Loading says **Finding your Table**. No writable destination says **Table unavailable · Private**. Multiple destinations require a choice. |
| Composer explains privacy once near posting using the approved wording. | Own destination reads **Only people at your Table can see this.** Other destinations name the actual selected Table. | During loading the reminder says **Finding your Table…**. With no destination it says **Your post stays on this device until a Table is available.** With an unresolved selection it asks the user to choose a Table. At accessibility sizes the reminder stays in the scrollable content so it does not consume the writing area above the keyboard. |
| Both self and household-member pages use the destination title **Profile**. | `PersonProfileContent.topBar` uses `Text("Profile")`; the person's name remains in the identity group. | Self-only editing/settings and private Saved access remain conditional on actual identity. No example activity/counts were introduced. |
| Grocery shopping range spells out the month, as in **October 18–24 · Next 7 days**. | `shoppingRangeText` uses `.month(.wide)`, omits duplicate same-month text, includes both months across a boundary, and includes both years across a year boundary. | The range still derives from the selected shopping start and six days later. The suffix becomes **Selected meals** when meal filtering is active. |
| Grocery aisle counts reflect what is still needed after checking an item. | Each aisle counts `aisleItems.filter { !checked($0) }`, with the shared singular/plural formatter. | `checked` uses `isPurchased(for: selectedIDs)`, matching the same meal-filter scope as the footer and rows. Checked rows stay present and Undo remains available. No example counts were hardcoded. |

## Adjacent difference corrected in source; native proof pending

The original member-profile reference includes a trailing **Profile options** overflow. The candidate now supplies a 44-point overflow with real **View posts**, **View recipes**, and, for household members, **View household** actions. The self profile retains Settings. `FidelityAdditionalStatesTests` checks the member actions, tab selection, household navigation and absence of private self controls. Those newly extended native checks have not run. The earlier profile hash below is historical and predates this correction.

## Verification and limits

- Passed `xcrun swiftc -frontend -parse` for the three files (syntax only, not type checking or a native render).
- Passed `git diff --check --` for the three files.
- Read the source branches for loading, missing audience, explicit audience selection, other Table destinations, self/member identity, selected-meal shopping counts, and month/year date boundaries.
- No simulator, app build, physical phone, live account, or notification check was run by this scoped review. The parent owns the fresh candidate build and native comparison. These source checks must not be recorded as visual or live passes.

Product source SHA-256 at freeze:

- `Plated/Views/TableComposerSheet.swift`: `c7497a5e433fcd5360b1fe221c8f6c630a5936f3994ca8c6503bc1b02c46108a`
- `Plated/Views/PersonProfileView.swift`: `765e18b1e7ba38f8a2c721ea38f8aea850575269e15eeac32491e3e53b8d640f`
- `Plated/Views/GrocerySheet.swift`: `e9f1a0c011413bef1b84e0f474a8c5b22ec290260ae584c27af27b50110098dd`
