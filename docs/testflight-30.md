# TestFlight 1.0.0 (30)

Date: September 24, 2026

## Release evidence

- Built from the current working tree, including its existing uncommitted app
  changes; app and widget both carry version 1.0.0 and build 30.
- Added `PlatedHouseholdGroceryLine.recipeOriginsJSON` as String in CloudKit
  Development and deployed it to Production. The deployment comparison showed
  one modified record type, zero index changes, and zero security-role changes.
  CloudKit Console confirmed successful deployment; the Production record type
  displayed the field. All 154 entries pass `scripts/check-schema`.
- Separately added and deployed `CD_GroceryItem.CD_recipeOriginsData` as Bytes
  for SwiftData's private iCloud mirror, and verified it in Production. The
  schema gate scans hand-written CloudKit writers only, so this persisted-model
  change required an additional schema check. The second deployment also changed
  one record field, with no index or security-role changes.
- Signed Release archive and App Store Connect export succeeded. The exported
  app passed strict signature verification including the widget, uses Production
  CloudKit and APNs entitlements, and has `get-task-allow=false`.
- App and widget packaged privacy manifests pass plist validation;
  `ITSAppUsesNonExemptEncryption=false` is present in the app.
- Prior integrated candidate verification: 366/366 XCTest cases and Release
  analysis passed. No app source changed during this release turn.
- Apple accepted the 12,960,815-byte IPA without upload errors. Delivery UUID:
  `0809ec76-1b31-4ce4-8d4b-33afdb996e50`.
- IPA SHA-256:
  `a5fe1037611fdde8c1e56cba2740e34224357e0400257d76ab460ba95a50203b`.
- Export preserved at `build/releases/30/export/Plated.ipa`; archive at
  `build/Plated.xcarchive`.

Apple processing was `VALID`, and build 30 was submitted for Beta App Review
on September 24 at 09:13:16 UTC. After the profile-to-Household navigation
freeze was reproduced, build 30 was explicitly expired in App Store Connect
on September 24. Its external state is now `EXPIRED`: neither internal nor
external testers can install it, even though the historical External group
relationship remains. Build 29 remains the latest approved external build;
the fixed build 31 is separately awaiting Beta App Review.

Build and review submission ID: `0809ec76-1b31-4ce4-8d4b-33afdb996e50`.
The en-US TestFlight testing notes were saved in App Store Connect, including
the account-deletion limitation. No App Store review was submitted.

## What to test

This beta includes refinements to planning, recipes, shared groceries, Table,
iPad Settings, and accessibility. Test recipe imports and grocery provenance,
household sync, Table posts and reactions, notification links, and widgets.

Table reports and local blocking are available. Blocking hides content locally;
it does not revoke the other person's access to shared content.

Known beta limitation: directory account deletion and automatic Sign in with
Apple revocation still require backend rollout and live verification. Do not
treat that flow as ready for release validation.

## Release tooling

The release script chooses a build above both the local project and latest
uploaded build, checks the schema before bumping, and supplies API-key
authentication to archive and export. The ASC helper requests all current group
builds rather than the default ten and refreshes its JWT before expiry during
long processing waits. Syntax, mocked JWT renewal, design/token, and diff checks
passed.

Public TestFlight link: <https://testflight.apple.com/join/2exAQgYs>.
