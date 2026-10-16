# TestFlight 1.0.1 (31)

Date: September 24, 2026

Status: 1.0.1 (31) uploaded and processed successfully (`VALID`), available for
internal testing (`IN_BETA_TESTING`), added to External, and submitted for Beta
App Review (`WAITING_FOR_BETA_REVIEW`). External availability awaits Apple.

## Profile and household navigation fix

The user reported repeated exits when opening Household or Edit profile from
their profile; their installed build has not yet been confirmed. The Household path reproduced as an unresponsive
app in the simulator, including when starting from the real Plan avatar rather
than a launch shortcut. Edit profile opened successfully in the initial seeded
reproduction, so that report is not independently reproduced as the same crash.

Sampling the hung process showed the main thread continuously updating SwiftUI
navigation and rebuilding both profile and household content. Temporary
`Self._printChanges()` tracing reported thousands of `@self changed` updates.
Changing Boolean destinations to a single enum, switching the household entry
to a direct navigation link, and isolating dismiss environment readers did not
resolve the reproduced freeze.

The fix adds an argument-only Equatable boundary to each destination:

- `PersonProfileView` compares the person's name, color, and persistent member
  identifier before constructing its query-backed content.
- `HouseholdHomeView` compares its embedded/pushed mode before constructing its
  query-backed content.

The paired boundaries prevent unchanged navigation inputs from repeatedly
recreating query-backed content during navigation reconciliation. Profile-only
isolation stopped the profile's repeated updates, but the household continued
looping; adding the household boundary resolved the exact reproduction. Queries,
state, app preferences, and environment subscriptions remain inside the content
views so live data can still update them. Temporary tracing is removed from the
candidate.

## Deleted roster snapshots

Profile identity, roster counts, and award seat reads now use the existing
`members.readable` guard. The editor also applies it before selecting the current
member for initial values, draft storage, and saves. This prevents reading
stored properties on a seat deleted while a query still retains its previous
snapshot. This is defensive coverage of a separate concrete lifetime hazard;
it is not presented as the confirmed cause of the user's report.

Two regression tests were added to `HouseholdMemberQuerySnapshotTests` in
`PlatedTests/HouseholdMemberTests.swift`, using a retained real in-memory
SwiftData container:

- `testEditorFindsLiveSelfBehindDeletedSeatInQuerySnapshot` retains a fetched
  snapshot, deletes a preceding seat, and checks live-self lookup both before
  and after saving the deletion.
- `testProfileIdentityLookupExcludesDeletedSelfFromQuerySnapshot` deletes the
  current member and checks that guarded ID, name, and self lookups safely
  exclude it while retaining the companion.

The full XCTest suite passed: 368 passed, zero failed, zero skipped, and zero
runtime warnings, confirmed with `xcresulttool` against
`build/profile-crash-tests.xcresult`. This includes both new snapshot tests.
Release gates also passed: 154 CloudKit schema entries, design checks across
151 Swift files, and 10 shared design tokens.

## Manual UI evidence

The final candidate completed this sequence on the signed simulator build
without freezing:

1. Open Plan's actual avatar, then Profile, Household, and Household settings.
2. Go back, open the own-profile row, enter Household again, and go back.
3. Open Edit profile, rename the seeded owner to `Nate Verify`, and save.
4. Return to Household and verify the updated person row and cook schedule.
5. Return to the original profile and verify the new name there as well.
6. Reopen Edit profile and verify that the saved name is retained.

The live name changes verify that the equality boundaries preserve model
updates across nested destinations. The changed name belongs only to the
simulator fixture.

An earlier unsigned simulator build threw a CloudKit exception when opening
Settings. Rebuilding with the project's default simulator signing resolved
that separate verification setup issue; no app code change was made for it.

## Rollout and limits

The candidate is version 1.0.1, build 31. Build 30 was submitted under the
1.0.0 beta version but was explicitly expired on September 24 after the
navigation freeze was reproduced; it can no longer be installed by testers.
Build 29 remains the latest approved external build until Apple approves 31.
The separate 1.0.1 beta version allowed a separate review submission for this
fix. Build 31 uploaded
successfully at 05:44:50 EDT and is now processed. App Store Connect confirms
version 1.0.1, build 31, Internal `IN_BETA_TESTING`, External
`WAITING_FOR_BETA_REVIEW`, and automatic tester notification enabled. The
public link remains <https://testflight.apple.com/join/2exAQgYs>.
The review submission was recorded at 05:47:15 EDT. The en-US tester notes
were saved and read back successfully, including the targeted navigation/edit
checks and the existing account-deletion beta limitation.

No physical-device verification has been completed for this candidate, and no
device crash log from build 30 was available to match the user's exits to the
reproduced simulator freeze. External beta approval is not an App Store
release, and no App Store submission was created.

## Signed artifact

- App and widget: 1.0.1 (31).
- Archive and export preserved under `build/releases/31/`.
- App binary and dSYM UUID: `39181A96-0114-3AE8-8191-EB9D5572DC73`.
- Exported app passes deep, strict code-signature verification.
- CloudKit and APNs entitlements are Production; `get-task-allow` is false.
- IPA SHA-256: `541e96da95495fb1cb9183011f40dccd74d2e13c7880bfe5551c053591b64d3a`.
- Upload delivery UUID: `ef84d207-ab95-43c9-a897-12d29c424408`.
- App Store Connect build/review ID: `ef84d207-ab95-43c9-a897-12d29c424408`.
- Build 30's archive, dSYMs, and original export are preserved under
  `build/releases/30/`.

The account-deletion backend and automatic Sign in with Apple revocation
limitations recorded for build 30 remain outside this navigation fix.
