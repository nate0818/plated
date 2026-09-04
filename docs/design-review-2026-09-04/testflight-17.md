# TestFlight build 17 — Account and Settings

- Native source: `a35ef67`
- Version: `0.1.0 (17)`; app and widget both 17
- IPA: `build/releases/17/Plated.ipa`
- SHA-256: `73313b48c28df1184553a4b36fddcba9baeba0b52b24787e2838fe88cfa6cbd8`
- Upload: succeeded September 4, 2026 at 14:21 EDT.
- Delivery UUID: `0be45eda-f019-43bb-b0c4-083e41aa3114`
- Distribution: VALID; Internal and External both IN_BETA_TESTING.
- App Store Connect build ID: `0be45eda-f019-43bb-b0c4-083e41aa3114`
- External includes build 17; Internal has access to all eligible builds.

The avatar now opens a dedicated Account hub instead of dropping somebody
into their social profile and leaving administration behind a gear. Four named
rows make Edit profile, Settings, Your household and View your Table profile
immediately visible. Each row explains what is inside. The account identity
card keeps the current photo, name, role and bio together without duplicating
the full social profile.

Settings opens at full height and has a visible Done action. Edit profile has
an explicit Cancel action alongside Save profile. Its Contact-photo path is a
full-width labeled control, and the copy explains Apple's photo limitation in
terms of what the person can do. The social profile remains intact as its own
destination and Back returns to Account.

Native XCUITest opened Account from Plan, Recipes, Groceries and Table. It
verified all four hub actions are visible and hittable, opened Settings and
checked Done and Appearance, opened Edit profile and checked Cancel, Save and
Contact photo, then entered and returned from the Table profile. The
[Account](native-build-17/account.png), [Settings](native-build-17/settings.png),
and [Edit profile](native-build-17/edit-profile.png) screenshots were inspected.
The [native test source](native-build-17/NativeAccountChecks.swift) records the
flow. Test content exists only in the explicit DEBUG in-memory review container.

The signed Debug build, Release archive/export, app/widget version checks and
strict recursive signature verification passed. All 120 Swift files pass the
design check, and all 10 app/widget tokens match. Physical-device Contacts and
VoiceOver behavior remain to be verified. Earlier beta limitations remain in
the TestFlight notes.

Public testing link: https://testflight.apple.com/join/2exAQgYs
