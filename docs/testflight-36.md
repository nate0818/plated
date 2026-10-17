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
Design, token, CloudKit-schema and whitespace checks pass. Signed archive and
distribution verification are pending; build 35 is already available to both
configured tester groups.

Live two-account transport and physical WeatherKit remain unverified: the phone
is disconnected and no second test account/device is available. Do not label
this a complete release clearance or a confirmed repair of the user's live data.
