# TestFlight 1.0.1 (49) — October 23, 2026

## Distribution

Apple reports **VALID**, **IN_BETA_TESTING** internally and externally.
Both authorized groups, **Internal** and **External**, explicitly include build 49.
Automatic tester notification is enabled. Release notes were read back exactly.
No individually assigned testers were returned. This establishes tester access,
not installation on any particular phone.

[External TestFlight](https://testflight.apple.com/join/2exAQgYs)

[Final API receipt](quality-2026-10-23/distribution.json)

## Exact signed package

- App source: `d2fc3fb3b02bc784c5dc4ac5129b99b520d7386f`.
- App and widget: **1.0.1 (49)**; minimum iOS 18.
- Upload receipt/build ID: `2386a645-47cc-4da8-adbc-9a3ae145810a`.
- IPA SHA-256: `27e18c819441bf774f18c57e81dcd90f75f9a9125c158e5556074d9574841b08`.
- App/widget strict signature checks passed; binary and dSYM UUIDs match.
- Production APNs/CloudKit entitlements, privacy manifests, app group and landscape-only iPad orientations checked in the export.
- [Package verification](quality-2026-10-23/signed-package.json).

## Changes and evidence

Fixes the Plan pinned-summary scrolling loop, refines iPad cooking and explicit
cook selection, and improves notification authentication/recovery. Confirmed new
posts/questions now enter the verified server delivery path alongside social
interactions. Production social service v10 matches the tested source.

[Native captures, test outcomes and limitations](quality-2026-10-23/README.md)

[Full retained route/state ledger](quality-2026-10-23/screen-state-inventory.md)

## Unverified behavior

Distributed under Nate's explicit instruction to continue without a phone and not
wait for live checks. Actual phone registration/APNs delivery, two-account sync,
physical VoiceOver, installed widgets/Live Activities and Calendar permission were
not freshly verified. The production service had zero active verified installations
at inspection. iOS 18, an in-place upgrade from the prior TestFlight build, resized
iPad windows and remaining inventory combinations remain open. Simulator/backend
passes do not prove these behaviors. This is a beta release, not a claim of complete
feature verification, zero defects or App Store approval.
