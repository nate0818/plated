# Approved polish implementation

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
- [ ] Native build/tests/design/token/schema checks and screenshot/interaction matrix
- [ ] Commit, push, archive, upload and verify all TestFlight groups

Existing web edits are unrelated work and are excluded from this change. Physical-device and two-account checks remain unverified until actually exercised; user previously requested continuation without the phone. Release evidence will distinguish TestFlight distribution from those remaining live checks.

## Implementation details

- Plan retains one selected day. Empty dinner has Choose a meal and Eating out instead; a place can be added using the existing shared dinner title. Future recipes use View recipe, tonight uses Start/Resume cooking, and cooked dinner offers Undo and sharing.
- The iPad Plan column limit is applied per tab, so the outer shell no longer prevents the wide layout from activating. Large accessibility text still reflows into one readable column.
- Draft saved means the atomic local draft write succeeded. Automatic saving is debounced and cannot recreate a discarded or posted draft. Failed comments remain locally visible with retry feedback.
- Comment deep links carry the target comment ID and scroll/highlight it. Like/reply identity, CloudKit record types and reaction wire identifiers stay compatible.
- Household rotation uses an explicit picker and Save/Cancel. Its accessibility label is attached to the actionable button rather than a separate wrapper.
- Cooking preserves the existing frozen session and timer behavior. Timer options are compact; reflection and sharing follow the saved dinner. A failed note save keeps the text and reports the note failure separately.

## Verification in progress

- Native build succeeded, including simulator app and extensions.
- Native regression suite: **527 tests, 4 opt-in Calendar skips, 0 failures** (`build/polish-unit-final.xcresult`). Tests cover identity, household merge, invitations, reactions, notification policy, draft persistence, ledger behavior and the new viewed-activity policy/deep-link parsing.
- Design gate: 178 Swift files checked; passed. Schema gate: 159 production fields checked; passed. Native/widget tokens match. Unrelated uncommitted website palette edits make the combined website-token gate fail in this working directory; release gates will run from the clean committed native checkout.
- Initial iPhone UI pass verified dark/light screen matrix, accessibility text, draft recovery, Activity read controls, cooking completion, comment interactions, and Apple Weather attribution in both themes. Two failures were addressed: a stale Eating out test label and the actual rotation accessibility wrapper. Final interaction/capture pass is pending.
- iPad orientation/layout assertions passed on iPadOS 26.5. Full-display geometry is being rechecked because app-scoped screenshots can misrepresent a letterboxed scene after simulator rotation.

## Remaining live checks

The user requested continuation without a connected phone or second test account. This release must not be described as proving physical VoiceOver behavior, lock-screen APNs delivery/inline replies, two-account profile-photo/activity synchronization, or household invitation acceptance on two real phones. Previous device evidence remains in the release-check documentation; simulator fixtures are not replacement proof for those account and device boundaries.

Apple documents that iPad windowing controls scene resizing even when a restricted orientation is declared; this app retains native adaptive layouts for those available sizes. See [UIRequiresFullScreen](https://developer.apple.com/documentation/bundleresources/information-property-list/uirequiresfullscreen) and [TN3192](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key).
