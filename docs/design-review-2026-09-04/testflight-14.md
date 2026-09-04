# TestFlight build 14 — redesign and development-data cleanup

- App: Plated, `com.natemeadows.plated`
- Version: `0.1.0 (14)`; widget build also `14`
- Native source commit: `c4e5df1`
- Artifact: `build/releases/14/Plated.ipa`
- SHA-256: `f101bf8bd417a1e9d8f69bc85572ecea15e848a72a6c9007c16f7fde397946fb`
- Upload: succeeded September 4, 2026 at 13:29 EDT.
- Delivery UUID: `42988b42-9a8c-4ec7-a180-b3b4b92774bd`
- Distribution: VALID; Internal and External both IN_BETA_TESTING.
- App Store Connect build ID: `42988b42-9a8c-4ec7-a180-b3b4b92774bd`
- Tester notification: accepted September 4, 2026 at 13:32 EDT.
- Notification ID: `050a881b-349f-4a5b-89f0-250f4f023a20`

The exact legacy development post by Prime, titled Schema probe and captioned
Written to teach CloudKit the type., is excluded from feed, profiles, people,
counts and widgets. The original SwiftData primer's exact post signature is
also recognized. Cleanup runs at launch, foreground, and Table refresh. Shared
posts are removed from their original CloudKit record and zone before deleting
the cached model and its comments. Network failures retain a hidden row for
retry. A cloud replay remains hidden and is cleaned up again. Real people named
Prime and similarly titled posts are preserved. No CloudKit fields were added.

The earlier primer falsely reported cleanup success even when retraction
failed; it now reports the actual result. DEBUG-only schema setup remains
separate from the in-memory design-review fixtures.

Eight [native in-memory regression checks](schema-probe-cleanup-tests.log) passed: exact matching, offline
retention, record/zone targeting, cached deletion, comment cascade, idempotence,
replay suppression, and replay cleanup. Signed Debug build and Release archive
and export succeeded. The exported IPA passed strict recursive signature
verification, and app/widget versions both equal 14. The design check passed
for 118 Swift files and all 10 shared widget tokens matched.

The cloud calls in the cleanup tests were controlled responses. This does not
establish deletion from Nate's signed-in iPhone or from the Production database.
After updating and opening the app, the real cleanup uses that user's CloudKit
access; a network or permission failure stays pending and retries on refresh.

The major-redesign announcement is included at the top of the TestFlight notes.
Apple's Build Beta Notifications API targets all eligible assigned testers and
controls the push wording. API acceptance is not per-device delivery evidence.
The request and accepted response are retained in `build/releases/14/beta-notification.json`.

Public testing link: https://testflight.apple.com/join/2exAQgYs

Instacart partner configuration, Production CloudKit verification for the earlier
optional grocery/thread fields, cross-account sync, and physical-device behavior
remain outstanding as disclosed in the TestFlight notes. Native redesign scope
and screenshots are recorded in [native-build-12.md](native-build-12.md).
