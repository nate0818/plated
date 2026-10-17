# TestFlight 1.0.1 (36)

October 17, 2026. Follow-up to the Plan and household redesign in build 35.

## Cross-account report

The user clarified that the household member's photo and activity appear on
that member's phone but not theirs. Build 35 fixes hidden organizer photos,
name-based avatar/profile lookup and incorrect organizer cook IDs. This does
not establish whether the user's particular records reached their phone.

Two isolated account-identity/store fixtures now exercise production household
serialization, CKAsset decoding, receiving merges and profile/activity readers
in both directions. A cooked dinner also passes through the production plan
record codec; a received Table post retains credit after its author renames.
These tests use local records, not two live iCloud sessions.

Before the fix, guest-to-host passed, while host-to-guest failed: changing
“Alex” to “Alex Rivera” left “Alex” on the receiver. The clone guard compared
the organizer to their own previous name. Build 36 exempts the organizer's
actual account-bound seat from that guard. A separate regression retains
protection against the organizer's name/photo being cloned onto a guest.
Photos and activity passed the delivered-record checks in both directions.

No UI, model or CloudKit schema fields changed from build 35. Its reviewed
screenshots and VoiceOver/large-text interaction evidence remain applicable.

## Verification and distribution

Full native regression passed: **440 executed, 436 passed, four intentional
opt-in Calendar skips, zero failures**. This includes both account-direction
delivery tests, the clone-protection regression and the widget publisher test.
Evidence: `build/household-delivery-before.xcresult` (one reproduced failure),
`build/household-delivery-final.xcresult` (all enabled tests pass).
Design, token, CloudKit-schema and whitespace checks pass. The signed export
passed signature, privacy-manifest, app/widget-version and production entitlement
verification. CloudKit/APNs use Production; WeatherKit is enabled;
`get-task-allow` is false. Native source fingerprints stayed unchanged during
archive. Binary and dSYM UUIDs match: `6B65F7ED-A17C-360C-A178-1C134DE03115`.

Source commit `8547ca0` is pushed to `origin/main`. The retained archive/export is
under `build/releases/36`. IPA SHA-256:
`68222a9c52024a1431a3b73c3d7eebef377d172cdc5b5fbf88a1e5acf7c2341a`.
Apple accepted the 17,461,148-byte IPA with no upload errors at October 17,
16:05 EDT, delivery UUID `f71e0ebc-e226-477d-8537-c81222737c6d`.
**Available to all configured Internal and External testers**, verified October
17 at 16:07 EDT. Apple reports both build states as `IN_BETA_TESTING`; both
groups include build 36, automatic notifications are enabled, and English tester
notes were read back successfully. Build 35 had no individually assigned testers
to carry forward. Public link: https://testflight.apple.com/join/2exAQgYs.
Machine-readable evidence:
[release receipt](testflight-36-release.json).

Builds 34 and 35 remain retained and available; no earlier beta was expired.
If this update causes a critical regression, expire build 36 and use the previous
beta while preparing a repair. No App Store production submission was made.

Live two-account transport and physical WeatherKit remain unverified: the phone
is disconnected and no second test account/device is available. Do not label
this a complete release clearance or a confirmed repair of the user's live data.
