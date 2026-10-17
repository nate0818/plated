# TestFlight 1.0.1 (39): household join notices and profile recovery

October 17, 2026. Nate reported that he had no in-app notice for Alessandra joining and her avatar still differed across phones. Installed versions and the exact live-account exchange were not observable here. The following are confirmed code paths, not a claim to have reproduced the two real accounts.

## Changes

- The household digest previously returned no notices for every full-zone read. Household Home and People recovery explicitly request such reads. A recent unannounced acceptance can now reach the organizer’s bell during replay (36-hour recovery window), including when share standings already promoted the invited row before the profile record arrived.
- Join keys include the seat/invitation rather than only the account, so removal followed by a fresh invitation is a new event. Seen keys plus existing bell rows prevent repeat delivery. Legacy notices stay quiet on recovery unless a newer invitation is evidenced. A joining phone does not announce old housemates; revoked cached seats do not generate recovery notices. Recipe history stays quiet during join recovery without suppressing an already-announced member’s later recipe activity.
- Household notice deduplication keys are remembered only after the bell save succeeds.
- A same-version household record can now hydrate another linked person’s missing personal fields without reapplying household role/rotation fields. Own profiles and pending edits retain their existing protection. The own-profile clearing check also recognizes participant-only identity. The first build-39 household pull performs one complete reread to trigger repair.
- Refresh from iCloud previously inferred departure whenever no person was newly inserted, including a normal refresh of existing members. It no longer claims departure or opens a reinvitation automatically. Failed reads report failure; successful reads acknowledge refresh or the actual pending invitation.

No CloudKit model/schema changes. No real household membership was modified. Website-copy work in docs/website-copy-2026-10-17 was left untouched.

## Verification

485 tests executed: 481 passed, four optional Calendar checks skipped, zero failures. Final bundle: build/household-join-notices-39-verified.xcresult. Log: /tmp/plated-39-verified-native-tests.log. Tests include production merge → digest → bell persistence, replay, duplicate prevention after key-book reset, participant-only identities, rejoin keys, legacy notice migration, revoked seats, recipe activity, same-version profile recovery and identity mismatch protection.

Design, native/widget/web token and deployed schema checks passed (172 Swift files; 159 CloudKit fields). No new layout or permission flow was introduced. Physical two-account delivery remains unverified; the test sequence is in household-two-phone-check.md. Personal dinners before joining intentionally remain private, so verification compares new activity increments rather than lifetime totals.

## Distribution

Packaging and App Store Connect availability are recorded in testflight-39-release.json after upload. Both configured tester groups and any individually assigned testers on build 38 are to receive this build. Older builds are retained.
