# TestFlight build 15 — Table notification bell

- Native source: `7ccb83b`
- Version: `0.1.0 (15)`; app and widget both 15
- IPA: `build/releases/15/Plated.ipa`
- SHA-256: `ab142850e978d9d0bac4806ffcc1f2e790022dffd13e09db325384db02579301`
- Upload: succeeded September 4, 2026 at 13:42 EDT.
- Delivery UUID: `9c647023-1254-4f97-bb48-b37041433760`
- Distribution: VALID; Internal and External both IN_BETA_TESTING.
- App Store Connect build ID: `9c647023-1254-4f97-bb48-b37041433760`
- External includes build 15; Internal has access to all eligible builds.

The Table's top bar now contains Notifications, Create and Profile. Its title
has a full-width row so the controls do not compress it. The shared bell
uses a filled symbol and numeric badge for unread notifications, an outline
when caught up, a 44-point tap target, and an accessible name and full unread
count. Both Table scopes open the existing Activity destination. Leaving
Activity marks updates read as before and now explicitly saves that state.

Native XCUITest passed: bell discoverability as a button, 12 unread updates
with a visual 9+ badge, header placement, Create/Profile availability, switching
to Household, opening Activity, returning, and clearing the unread value.
The initial check caught and led to correction of the button accessibility
trait. A subsequent harness assertion selected the inactive Plan tab's profile
control; the passing check resolves the visible profile control.

The [unread](native-build-15/table-unread.png) and
[read](native-build-15/table-read.png) screenshots were inspected. The test's
notifications exist only in the explicit DEBUG in-memory design-review path;
they are never seeded into a user's persistent store or a Release build.
The [native flow checks](native-build-15/NativeFlowChecks.swift) record the test.

Signed Debug build, Release archive/export and exported IPA strict recursive
signature verification passed. All 118 Swift files pass the design check;
all 10 app/widget tokens match. The simulator remains open on the Table.

This refines the entry point to the existing notification feed. It does not
add a new APNs delivery backend or establish physical-device VoiceOver and
cross-account notification delivery. Prior beta limitations remain disclosed
in the TestFlight notes. Build 14's targeted schema-probe cleanup is retained.

Public testing link: https://testflight.apple.com/join/2exAQgYs
