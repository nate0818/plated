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

Signed distribution verification is pending. Live two-account revocation and
the user's exact production-state cause remain unverified without the connected
accounts. Do not claim that Alessandra has already been removed.
