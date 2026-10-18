# Approved polish implementation

**Correction:** build 43 only partially implemented the approved Plan proposal.
The checked implementation list below records that release's scope, not complete
visual parity. See [the Plan correction and verification record](../plan-parity-2026-10-18/README.md)
for the missing states and subsequent fixes.

Nate approved all 15 comparison screens in `docs/design-polish-review-2026-10-18` on October 18 and requested launch. This authorizes implementing the proposed design and releasing to the existing internal/external TestFlight audience. It does not turn illustrative people, counts, weather or notification examples into production data.

Experience contract: standard SwiftUI profile; Plan answers dinner/cook/next action, Table prioritizes people and content, Recipes supports selection and cooking, Groceries prioritizes shopping. Preserve current native navigation, data ownership, frozen cooking sessions, household permissions, draft persistence, attribution and existing tested sync behavior. Adapt to narrow iPhone, horizontal iPad windows and accessibility text. Nate subsequently requested landscape-only iPad; both landscape orientations are declared while iPhone orientation support is unchanged. No new decorative motion; use existing reduced-motion-aware transitions and opaque semantic surfaces.

Implementation checklist:
- [x] Compact shared headers and contextual creation
- [x] Selected-day Plan hierarchy, actions, weather/history, compact household context, adaptive iPad composition
- [x] Table audience, media rhythm and consistent reactions
- [x] Composer attachments, drafts and posting hierarchy
- [x] Thread/reply grouping, target context and delivery feedback
- [x] Activity read semantics, contextual rows and notification verification
- [x] Household settings, members and explicit rotation assignment
- [x] Recipe library, missing images, detail hierarchy and anchors
- [x] Grocery density, progress and undo
- [x] Profile hierarchy and secondary milestones
- [x] Cooking ingredients/steps, timer and completion notes
- [x] Native build/tests/design/token/schema checks and screenshot/interaction matrix
- [x] Commit, push, archive, upload and verify all TestFlight groups

Existing web edits are unrelated work and are excluded from this change. Physical-device and two-account checks remain unverified until actually exercised; user previously requested continuation without the phone. Release evidence will distinguish TestFlight distribution from those remaining live checks.

## Implementation details

- Plan retains one selected day. Empty dinner has Choose a meal and Eating out instead; a place can be added using the existing shared dinner title. Future recipes use View recipe, tonight uses Start/Resume cooking, and cooked dinner offers Undo and sharing.
- The iPad Plan column limit is applied per tab, so the outer shell no longer prevents the wide layout from activating. Large accessibility text still reflows into one readable column.
- Draft saved means the atomic local draft write succeeded. Automatic saving is debounced and cannot recreate a discarded or posted draft. Failed comments remain locally visible with retry feedback.
- Comment deep links carry the target comment ID and scroll/highlight it. Like/reply identity, CloudKit record types and reaction wire identifiers stay compatible.
- Household rotation uses an explicit picker and Save/Cancel. Its accessibility label is attached to the actionable button rather than a separate wrapper.
- Cooking preserves the existing frozen session and timer behavior. Timer options are compact; reflection and sharing follow the saved dinner. A failed note save keeps the text and reports the note failure separately.

## Verification

- Native simulator build and signed release archive/export succeeded. Archive is **1.0.1 (43)**; app and widget carry the same build number. Its iPad orientation list contains only Landscape Left and Landscape Right; iPhone retains Portrait and both landscape directions.
- Regression suite: **527 tests, 4 opt-in Calendar skips, 0 failures** (`build/polish-unit-final.xcresult`). Covers identity, household merge, invitations, reactions, notification policy, draft persistence, ledger behavior and the new viewed-activity/deep-link policies.
- Final iPhone interaction suite: **8 passed, 0 failures** (`build/polish-ui-final.xcresult`). Includes both-theme native screen captures, accessibility text, Activity read/clear semantics, post draft recovery, explicit rotation Save/Cancel, dinner-place editing, cooking completion and comment reactions.
- Follow-up visual checks: **3 passed, 0 failures** (`build/polish-final-visuals.xcresult`). Largest-text attachment actions now use the full row; People opens correctly. Official Apple Weather artwork loads and remains visible on green and cream. The full-width Table photo correction was visually checked in both appearances.
- iPadOS 27: **1 passed, 0 failures** (`build/polish-ipad27-final.xcresult`). Both landscape directions, portrait and upside-down physical orientations retain the horizontal interface, and a typed post draft survives rotation with its sheet open. Full-display screenshots are authoritative: XCTest's app-scoped captures can crop incorrectly, and its element frames use physical-screen coordinates. An upright device therefore reports a vertical frame for a horizontal, landscape-locked button. Earlier tests that compared window width/height alone were corrected; no root-controller replacement or rotation overlay ships.
- iPadOS 26.5: **1 passed, 0 failures** (`build/polish-ipad26-verified.xcresult`) on a fresh isolated simulator. Both landscape directions fill the display; holding the device upright centers the same horizontal two-column workspace in Apple’s compatibility mode. A typed draft survives the entire rotation sequence. The older review simulator retained a different windowing state, so it was not used as the final full-display baseline.
- All release gates passed from the clean committed native checkout: design rules for 178 Swift files; 10 native/widget tokens; 31 website tokens in both themes; byte-identical copied timer activity model; 159 deployed CloudKit production fields. Unrelated uncommitted website work remains outside the release.
- Machine-readable test summaries are in `results/`; unmodified native screenshots are in `captures/`. Fixture names, photos, counts and preview weather are test data, not claims about a live household. The interactive design artifact's illustrative states are not a claim that every native account/network combination was exercised.

## Remaining live checks

The user requested continuation without a connected phone or second test account. This release must not be described as proving physical VoiceOver behavior, lock-screen APNs delivery/inline replies, two-account profile-photo/activity synchronization, or household invitation acceptance on two real phones. Previous device evidence remains in the release-check documentation; simulator fixtures are not replacement proof for those account and device boundaries.

Apple documents that iPad windowing controls scene resizing even when a restricted orientation is declared; this app retains native adaptive layouts for those available sizes. See [UIRequiresFullScreen](https://developer.apple.com/documentation/bundleresources/information-property-list/uirequiresfullscreen) and [TN3192](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key).

## Release

**TestFlight 1.0.1 (43) is available to all current Internal and External testers.** Apple processing is `VALID`; both beta states are `IN_BETA_TESTING`. Internal retains access to all builds, and build 43 is explicitly assigned to External. Automatic tester notifications are enabled and the en-US release notes were read back and verified. See `results/distribution.json` for the timestamped Apple API evidence and `TestFlight-notes.txt` for the published notes.

- TestFlight: https://testflight.apple.com/join/2exAQgYs
- Native source: `cf9a663`, follow-up sizing/orientation/accessibility corrections: `192cae5`; build 43 and verification record: `30bac2f`. All are pushed to `origin/main`.
- Preserved signed archive, debug symbols and IPA: `build/release-polish-43/`. The IPA fingerprint in `results/archive.json` matches the uploaded file.
- The temporary release worktree was archived after preserving the signed artifacts. Unrelated website work was left unchanged. No public App Store release was submitted.

This distribution does not change the remaining live-check limitations above.
