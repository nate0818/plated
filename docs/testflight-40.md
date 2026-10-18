# TestFlight 1.0.1 (40): household and Table controls

The household settings glyph was too small and visually attached to the surname, the household bell differed from other headers, and the Table People chip's surface was vertically compressed. Household settings is now a separate 44-point control alongside Activity, with a wrapping title below. The Table heading is more compact, its People control has proper padding, and the audience card retains native button semantics. Household now uses the shared paper/deep-green canvas.

The audience subtitle now opens the authoritative People list instead of presenting a membership count derived from historical activity. No CloudKit data model or membership operations changed. The build-39 invitation/profile/activity repairs remain included; two-phone delivery is still a separate live-account verification.

Detailed findings, screenshot evidence, test matrix, and limitations: [header-controls-2026-10-17/README.md](header-controls-2026-10-17/README.md).

## Verification

Plated suite: 485 total; 481 passed, four optional Calendar tests skipped, zero failures (`build/header-controls-40-unit.xcresult`). Design, native/widget/web tokens, and 159 recorded deployed CloudKit fields pass their checks.

Header UI matrix: 22/22 passed across compact iPhone, iPhone 17 Pro, and iPad, including VoiceOver speech. Light/dark and largest-text captures were reviewed. Physical activation and live two-account delivery were not repeated. Distribution is recorded in testflight-40-release.json after Apple processing.

## Distribution

Source commit: bab8b62b18099a70f03c8c5cee39d55705b71622. Apple accepted the 17,539,071-byte upload without errors. Signature, production entitlement, privacy-manifest, dSYM and unchanged-source checks passed. At 2026-10-18T00:37:37.195217+00:00, build 40 was VALID with both internal and external states IN_BETA_TESTING. Internal and External both include build 40, automatic tester notifications are enabled, and the tester notes were read back successfully. Build 39 had no individual testers to carry forward. Older builds remain available. The package is retained in build/releases/40; the full receipt is testflight-40-release.json.

TestFlight: https://testflight.apple.com/join/2exAQgYs
