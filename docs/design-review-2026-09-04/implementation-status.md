# Design implementation — September 4, 2026

## TestFlight release follow-up

The design changes, planner holds, recipe-step controls, and widget updates are pushed to `main`. Version `0.1.0 (11)` passed Release archive, export, and signature verification; Apple processed it successfully, and it is available to both Internal and External TestFlight testers. CloudKit Console sign-in and verification/deployment of the seven new persisted fields remain outstanding and are disclosed in the beta test notes. See [the build 11 release record](testflight-11.md) for the exact source commit, artifact, validation, and distribution status. The earlier pass-level evidence below describes what was verified before this release follow-up.

## Date and planning refinement

The oversized date tiles have been replaced with an aligned date column. Only today's numeral sits on an orange circle; weekdays stay neutral. Empty past nights are compressed, planned dishes retain their photos, and open nights have a quiet plus. Native swipe actions, drag-to-move, context menus, accessible row actions, and day detail navigation remain.

Week and Month are explicit choices. Month has a seven-column calendar, planned-meal dots, and an agenda for the selected date. Today returns to the current date from either mode. Month navigation updates the selected date; the picker now reflects the actual displayed mode, including rotation.

The [interactive design source](plated-complete.html), shown in the browser preview at localhost:8769, includes the revised agenda, month navigation, Today, and outside-tap dismissal. Its sample date is fixed at September 4, 2026. It remains a design preview with sample household data; its sample interactions do not call the production backend.

## Planner swipe follow-up

Native Week and Month planned meals now reveal **Edit, Move, and Remove**. Open nights reveal **Plan and Eat out**. Cooked meals omit Move. Day detail keeps its cooked-state actions and now exposes a visible actions button. Labeled trays can be opened with the three-dot button; the existing horizontal gesture, predicted settling, named accessibility actions, and drag-to-move remain. The tray closes before invoking an action, and shifted planner content is clipped to its row.

Edit exposes servings and cook assignment in the native night sheet. Move uses a graphical date picker, swaps meals occupying the same slot, rejects cooked destinations, preserves meal identity, and restores dates if saving fails. Existing drag-to-move now also protects cooked meals and past destinations. Native removal retains its existing immediate-delete behavior; the preview's undo is not a claim of native removal undo.

The browser preview supports touch, mouse dragging, trackpad scrolling, and keyboard reveal/dismissal. Touch previously cancelled when pointer capture transferred from the pressed child to the scrolling container; only losing the container's own capture now cancels the swipe. Cancelled gestures restore the prior reveal state, and tapping elsewhere closes the tray. Move offers a month picker with explicit occupied-date swap copy. Editing a cooked preview meal preserves its cooked state.

All 13 checks in `scripts/check-preview-gestures.cjs` passed against the final source using an isolated Chrome profile: touch, cancellation, pointer dragging, vertical-scroll rejection, trackpad reveal/close, keyboard controls, outside tap, swap with retained cook/servings, undo, remove, edit, Month actions, and open-night actions; no browser runtime errors occurred. Run with Playwright available to Node and Chrome installed: `node scripts/check-preview-gestures.cjs`. Set `PLATED_PREVIEW_URL` to override the default local preview address. The fixture uses September 4, 2026.

Signed simulator and device builds passed. Week/light and Month/dark action trays were inspected using a DEBUG-only reveal flag; this verifies native layout, not physical gesture behavior. The updated app installed on Nate's iPhone, but launch was blocked because the phone was locked. Open Plated after unlocking to test the native swipe feel. `make design` passed for 115 Swift files; all 10 shared widget tokens matched.

## Long-hold and date-spacing follow-up

The circled Today numeral is smaller: 17px in the preview and the 17pt display-family callout token in the native Week planner. The circle, date column, and other date numerals retain their sizes.

Native Week retains its existing press-and-drag movement and now offers cook assignment and a full date picker in its context menu. Month meals can be lifted onto a calendar date, with a visible destination highlight; occupied matching slots swap while cooked meals and past destinations are protected. Breakfast, lunch, and other slots retain their identity during a Month drop. The recipe editor retains its existing long-press step reordering and keyboard move controls; the step number now includes a visible grip with a 44pt target. Gesture-state cleanup settles the lift after interruption.

In the preview, hold a planned meal for 350ms, then release for Edit, Move, cook assignment, or Remove. Hold and drag to move onto a Week row or Month date, with destination/swap feedback, scrolling near the edge, and Undo. Quick swipes still reveal their original action trays. In Edit recipe, hold a step grip to drag it before or after another step; tap the grip for Move up/down. Native text selection stays available in the text fields. Step moves stay in the draft until Save, and cancelling a preview drag leaves the draft unchanged. Undo restores both meal data and the original calendar selection after a move.

The 11 checks in `scripts/check-preview-holds.cjs` passed, covering cook assignment, pointer and touch meal moves, Week swaps, Month drops, cancellation, pointer and touch step reordering, menu alternatives, saved step order, and runtime errors. All 13 existing swipe checks also passed after the hold changes. Both scripts require Playwright and Chrome and accept `PLATED_PREVIEW_URL`; they use isolated browser profiles and sample data. Native simulator and device builds passed. The latest device build installed; launch remained blocked by the locked phone. Native touch feel and drag cancellation still require physical-device interaction checks.

## Native work included

- **Groceries:** selectable seven-day window, meal filtering, ingredient-to-meal provenance, US shopping measures, upward rounding, per-meal purchased quantities, stable rows, checkmark undo, manual-item drafts, expanded initial sheet, scoped Reminders export, and the authenticated Instacart handoff.
- **Table:** actual parent comment relationships, reply hierarchy with collapse/expand, tombstones that preserve replies, queued deletion updates, stale-write protection, and persisted comment drafts. New model fields are optional for existing stores.
- **Profiles:** single-contact photo selection during profile setup and editing, explicit Save profile, preserved edit drafts, and profile/settings access on recipe, day, and thread detail screens.
- **Cooking:** ingredient access while following steps, without replacing the current step. Recipe edit/share/assignment/ingredient sheets now share one presentation route.
- **Navigation:** each visited tab retains its view state. Unvisited tabs are mounted on first access. Floating controls use native Liquid Glass on iOS 26, with older-OS and Reduce Transparency fallbacks. Sheet dismissal keeps native dragging and adds an outside-tap gesture where applied.
- **Account boundaries:** sign-out clears the directory/shopping session; changing Apple identities invalidates the previous session; shopping-link cache entries are scoped to the current session.

## Evidence

- Signed Debug simulator build succeeded after the final changes.
- The initial pass built, installed, and launched on Nate's paired iPhone 16 Pro. The latest swipe follow-up also installed; its launch was blocked by the locked phone, as recorded above. No purge or TestFlight upload was performed.
- `make design`: 115 Swift files passed. `make tokens`: all 10 shared widget tokens matched.
- 13 native grocery regression checks passed in a separate memory-only SwiftData container. Coverage includes serving increases, one-meal purchases, stable rebuilding, moved meals, returning to an earlier shopping window, undo, manual groceries, legacy checks, sufficient US quantity conversions, and unmeasured ingredients.
- 10 Instacart handler tests passed. The deployed endpoint rejected an unauthenticated request with HTTP 401.
- Native screenshots inspected: week agenda, monthly calendar, grocery sheet before and after expanding the default presentation.
- Browser interactions inspected: Week/Month, next month, Today, calendar sheet dismissal by tapping its backdrop. No browser errors were reported. Inline JavaScript syntax validation passed.

## Release work still required

The Instacart partner secret and an approved production account remain external dependencies. The deployed function is authenticated and ready for configuration; a real partner link and checkout have not been verified. See `backend/instacart/README.md`.

Verify the new comment and grocery fields in CloudKit Development and deploy any required additive Production schema changes. Verify reply creation/deletion and offline replay across two signed-in devices. CloudKit schema access remains blocked on Apple Account sign-in; build 11 is available externally with this verification gap disclosed in its test notes.

Contact-photo picking, native outside-tap dismissal, VoiceOver, larger text, interrupted cooking, and CloudKit interactions still need physical-device interaction checks. Simulator screenshots and a successful build do not establish those behaviors. The browser preview demonstrates outside-tap dismissal; native gesture verification remains open.

The eight accepted design recommendations cover more than this implementation pass. Cookbook collection architecture, a complete cooking-session redesign, notification tuning, layered app-icon artwork, and a coordinated native scroll-edge treatment remain unfinished. This document records concrete progress, not an assertion that the entire product has reached its final design.
