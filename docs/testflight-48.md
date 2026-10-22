# TestFlight 1.0.1 (48) — October 22, 2026

Build 48 is an incremental beta for the compact Plan layout, accepted Table
audience visibility, and clearer phone-alert connection status. It is **not** a
claim that phone notifications now deliver: the last production registration
attempt returned HTTP 403, and no new real-device attempt has verified the
diagnostic service. The exact candidate is source commit `2d2de4c85c8623fc3769c1be56185dc0ce32600e`
on pushed branch `codex/approved-design-fidelity-46`; the working tree was
clean at archive and export.

## Source and native checks

The [candidate evidence and coverage ledger](quality-2026-10-22/README.md)
links the rendered Plan and Settings captures and names the still-unverified
states. The app logic run passed 717 tests, with four Calendar-permission tests
skipped. The final connected Plan/selected-day suite passed 22 tests; the
approved-design matrix passed 16 with one iPad-only skip on iPhone; the same
iPad case passed on iPadOS 27. The compact Plan check also passed on an iOS 27
iPhone. The automated accessibility probe's raw findings and interpretations
are retained in the ledger. These are simulator and fixture results, not a
two-account or physical VoiceOver result. The final copy-only Settings
revision and build-number bump were compiled in the Release archive after the
broad app logic and approved-screen runs; focused current-OS Plan and final
Settings captures use the revised code.

Static design, native token, schema-manifest and whitespace checks passed.
The recorded schema manifest is not a live CloudKit transaction. The production
`social` Edge Function is ACTIVE at version 5, logging only bounded error codes
for future diagnosis; successful registration or APNs delivery remains unverified.

## Exact signed package

- Archive: `build/Plated.xcarchive`; export: `build/export/Plated.ipa` in the
  isolated worktree. IPA size: 18,687,245 bytes. SHA-256:
  `a35cdfd7db1b73abf9235214ade9f87d91256aef20af54ab35d374741d96a8d3`.
- Exported app and widget both report **1.0.1 (48)**. App and widget binary UUIDs
  match their respective preserved dSYMs. Both privacy manifests are present.
- Exported app entitlements include production APNs and CloudKit, WeatherKit,
  Apple sign-in, associated domain, communication/time-sensitive notifications,
  and the app group. The widget has the app group. Both have
  `get-task-allow=false`. The app declares iPad landscape only, iPhone portrait
  plus landscape, minimum iOS 18.0, and no non-exempt encryption.
- Xcode's Release archive and cloud-signed export succeeded. The embedded app
  provisioning profile's CMS signature verified, and it expires September 2,
  2027. Local `codesign --verify --strict` reports `CSSMERR_TP_NOT_TRUSTED` for
  this IPA **and** an older accepted Plated IPA on this Mac; local trust-chain
  verification is therefore unconfirmed. Apple processing state is recorded
  below separately. The archive emitted the same two nonfatal Swift warnings
  recorded for build 47.

## Upload and access

Apple accepted the exact IPA upload with no transport errors; delivery UUID
`be748f41-641f-48d5-acbb-462106f96b10`. App Store Connect processed build
48 as `VALID`. It reports `IN_BETA_TESTING` for Internal and External, with
Internal's all-build access and explicit build-48 membership in External.
There are zero individually assigned build testers outside those groups.
The External [TestFlight public link](https://testflight.apple.com/join/2exAQgYs)
serves this group. The exact en-US [tester notes](testflight-48-notes.txt)
were saved and read back before External distribution. These checks establish
tester access, not installation on Nate's phone.

## Unverified behavior

No fresh phone registration, push banner, background/terminated delivery,
new-invitation acceptance, two-way photo/activity sync, physical VoiceOver,
installed widget, device Calendar permission, previous-TestFlight in-place
upgrade, or iOS 18 runtime behavior was established. Nate explicitly
authorized proceeding with this beta without the phone or a second account;
that exception does not turn these checks into passes.

At the October 22 service check, the latest real registration attempts had
returned `403 cloud_identity_unavailable` before the phone could be registered.
The production database still held zero active installations, queued social
events, and deliveries. This narrows the next investigation to Apple's caller
identity response or its interpretation; it does not establish which one is
wrong. The new Settings result explains that alerts are unavailable and keeps
in-app Activity available, but it is not a notification transport repair.

Settings still contains a dense list of notification categories; the compact
Phone alerts status removes the oversized connection block but is not a full
Settings polish pass. The [coverage ledger](quality-2026-10-22/screen-state-inventory.md)
retains the other unreviewed routes and states explicitly.
