# Design implementation — September 4, 2026

## Date and planning refinement

The oversized date tiles have been replaced with an aligned date column. Only today's numeral sits on an orange circle; weekdays stay neutral. Empty past nights are compressed, planned dishes retain their photos, and open nights have a quiet plus. Native swipe actions, drag-to-move, context menus, accessible row actions, and day detail navigation remain.

Week and Month are explicit choices. Month has a seven-column calendar, planned-meal dots, and an agenda for the selected date. Today returns to the current date from either mode. Month navigation updates the selected date; the picker now reflects the actual displayed mode, including rotation.

The [interactive design source](plated-complete.html), shown in the browser preview at localhost:8769, includes the revised agenda, month navigation, Today, and outside-tap dismissal. Its sample date is fixed at September 4, 2026. It remains a design preview with sample household data; its sample interactions do not call the production backend.

## Native work included

- **Groceries:** selectable seven-day window, meal filtering, ingredient-to-meal provenance, US shopping measures, upward rounding, per-meal purchased quantities, stable rows, checkmark undo, manual-item drafts, expanded initial sheet, scoped Reminders export, and the authenticated Instacart handoff.
- **Table:** actual parent comment relationships, reply hierarchy with collapse/expand, tombstones that preserve replies, queued deletion updates, stale-write protection, and persisted comment drafts. New model fields are optional for existing stores.
- **Profiles:** single-contact photo selection during profile setup and editing, explicit Save profile, preserved edit drafts, and profile/settings access on recipe, day, and thread detail screens.
- **Cooking:** ingredient access while following steps, without replacing the current step. Recipe edit/share/assignment/ingredient sheets now share one presentation route.
- **Navigation:** each visited tab retains its view state. Unvisited tabs are mounted on first access. Floating controls use native Liquid Glass on iOS 26, with older-OS and Reduce Transparency fallbacks. Sheet dismissal keeps native dragging and adds an outside-tap gesture where applied.
- **Account boundaries:** sign-out clears the directory/shopping session; changing Apple identities invalidates the previous session; shopping-link cache entries are scoped to the current session.

## Evidence

- Signed Debug simulator build succeeded after the final changes.
- `make phone` built the current working tree, installed it on Nate's paired iPhone 16 Pro, and launched it successfully. This was a normal install with no purge or TestFlight upload.
- `make design`: 114 Swift files passed. `make tokens`: all 10 shared widget tokens matched.
- 13 native grocery regression checks passed in a separate memory-only SwiftData container. Coverage includes serving increases, one-meal purchases, stable rebuilding, moved meals, returning to an earlier shopping window, undo, manual groceries, legacy checks, sufficient US quantity conversions, and unmeasured ingredients.
- 10 Instacart handler tests passed. The deployed endpoint rejected an unauthenticated request with HTTP 401.
- Native screenshots inspected: week agenda, monthly calendar, grocery sheet before and after expanding the default presentation.
- Browser interactions inspected: Week/Month, next month, Today, calendar sheet dismissal by tapping its backdrop. No browser errors were reported. Inline JavaScript syntax validation passed.

## Release work still required

The Instacart partner secret and an approved production account remain external dependencies. The deployed function is authenticated and ready for configuration; a real partner link and checkout have not been verified. See `backend/instacart/README.md`.

Before TestFlight, exercise the new comment fields in CloudKit Development and deploy the corresponding Production schema. Verify reply creation/deletion and offline replay across two signed-in devices. No CloudKit schema deployment or TestFlight upload was performed in this pass.

Contact-photo picking, native outside-tap dismissal, VoiceOver, larger text, interrupted cooking, and CloudKit interactions still need physical-device interaction checks. Simulator screenshots and a successful build do not establish those behaviors. The browser preview demonstrates outside-tap dismissal; native gesture verification remains open.

The eight accepted design recommendations cover more than this implementation pass. Cookbook collection architecture, a complete cooking-session redesign, notification tuning, layered app-icon artwork, and a coordinated native scroll-edge treatment remain unfinished. This document records concrete progress, not an assertion that the entire product has reached its final design.
