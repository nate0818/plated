# TestFlight 1.0.1 (37): household removal

October 17, 2026. The user reported that Remove failed for Alessandra; their
screenshot showed Nate correctly identified as organizer and the generic
“Check your connection” error. This establishes the action reached its failure
path, not which underlying CloudKit/account condition caused it on that phone.

## Corrections

- An empty `userRecordName` no longer hides a valid `participantID`.
- Joined profiles without local identity read their exact shared seat to recover
  an account link. Names and participant-list position never choose an account
  for revocation. A confirmed unlinked saved profile can be removed with explicit
  copy distinguishing that action from account-access revocation. An unavailable
  lookup retains the profile and explains the failure.
- Both sharing steps must finish before the roster disappears. Already-absent
  participants are successful retries; changed share records are fetched again;
  individual CloudKit save results are checked. The organizer remains protected.
- Household and Table People show progress, prevent repeated removal taps and
  report the failed step. The service saves the deletion. A failing local save
  restores the profile and cook assignments without discarding prior edits.
- Removal dialogs retain value snapshots, and animated roster rows guard against
  deleted SwiftData objects. The successful-removal UI test exposed a crash in
  the retained swipe-row content; the row no longer reads the deleted person.
- Preview Table People cannot mint links or call CloudKit. UI removal fixtures
  stay within the memory-only preview boundary.

No model/schema fields changed. No real household member was removed during
verification. The existing authorization covers commit, push and distribution
to all configured TestFlight groups; this is not an App Store submission.

## Verification

Final native suite: **450 executed, 446 passed, four opt-in Calendar skips,
zero failures**, including ten removal workflow regressions. Evidence:
`build/household-removal-final.xcresult`. These tests call the actual
removal service with injected transport results; they do not verify Apple's live
share service. The failed-save regression initially exposed nil cook relationships
after SwiftData rollback; the fixed recovery now passes.

Design/token/schema gates pass (170 Swift files, 159 deployed CloudKit fields).
The SwiftUI static scan reports no high findings; existing fixed-size/motion
review findings remain on these large preexisting screens. The new status/error
content uses scaled text and no new fixed-height container.

All five UI scenarios passed on the isolated iPhone 17 Pro / iOS 27 simulator:
cancel, confirmed-unlinked removal, identity lookup failure, local-save recovery,
and Table People removal at Accessibility XXXL. Evidence:
`build/household-removal-ui-fixed.xcresult` (four passing household cases) and
`build/household-removal-table-ui.xcresult` (passing Table case after correcting
the test's button-label selector). Screenshots and accessibility trees were
inspected. The multiline household notice gained vertical padding after that
review; the final successful-removal check also passed on iPhone SE (3rd gen) /
iOS 26.5 (`build/household-removal-compact-ui.xcresult`). Visual evidence is in
`docs/household-removal-2026-10-17/`.

## Signed release

Source commit: `a8bba2c464d309a5c260290605133577578f79ae`, pushed to `origin/main`.
The signed 1.0.1 (37) archive/export succeeded. Signature trust and integrity,
app/widget build matching, production CloudKit/APNs, WeatherKit entitlement,
sharing/background keys, export compliance, privacy manifests and matching
binary/dSYM UUID all passed. Native source fingerprints stayed unchanged during
the archive. The package is retained in `build/releases/37/`; its SHA-256 and
verification receipt are recorded in `docs/testflight-37-release.json`.

Apple accepted the upload without errors (17,495,315 bytes; delivery/build ID
`77335a29-5a3a-420a-adf4-d25ef291f91a`). At 2026-10-17 21:12:11 UTC the build was
`VALID`, with both internal and external states `IN_BETA_TESTING`. Both
configured groups include build 37; tester notes were read back successfully,
automatic notifications are enabled, and build 36 had no individually assigned
testers to carry forward. Older builds were not expired. Public TestFlight:
https://testflight.apple.com/join/2exAQgYs

Live two-account revocation and the user's exact production-state cause remain
unverified without the connected accounts. No real household member was removed
during this work. The user can update to build 37 and retry the action on their
own household.
