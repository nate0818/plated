# TestFlight build 19 — Account depth, awards and recipe intake

- Native source: `1dab6f4`
- Version: `0.1.0 (19)`; app and widget both 19
- IPA: `build/releases/19/Plated.ipa`
- SHA-256: `d5ff9d207533011e0baa8146e69df7692c3e2f7e845655cb38a5f33e7a33374c`
- Upload: succeeded September 4, 2026 at 16:21 EDT.
- Delivery UUID and App Store Connect build ID:
  `7e9e286a-0e93-4f24-ad2b-996de920444d`
- Distribution: VALID; Internal and External both IN_BETA_TESTING.
- Automatic TestFlight tester notification is enabled.

Account is now a personal control center rather than a menu hidden behind the
social profile. The identity hero keeps View profile and Edit visible. Large
Household and Settings destinations explain their contents; a live status card
summarizes iCloud, reminders and appearance. Settings has grouped identity,
appearance, planning, household, permission, privacy, tour and account controls
with a persistent Done action. The layout was reviewed at normal and
accessibility text sizes, and the wordmark now stays intact at the largest iOS
Dynamic Type size.

Awards add twelve permanent kitchen achievements across planning, cooking,
cookbook building, Table participation and household milestones. Earned awards
never expire. Kitchen levels turn accumulated points into a personal story
without a leaderboard or punitive daily streak. Account shows the current level
and featured badges; a person's Table profile shows earned badges publicly and
keeps unfinished progress private. The gallery supports All, Earned and In
progress views, concrete progress, earned dates and a detail sheet that explains
how each badge is earned. The [gallery](native-build-19/awards-gallery.png) and
[award detail](native-build-19/award-detail.png) were inspected in the native
simulator.

Recipe intake now accepts a pasted website link, keeps source attribution,
surfaces fields worth checking and handles likely duplicates without silently
creating copies. Editable servings and timing use direct controls in the review
step. The source for an iOS Share extension is retained in the repository, but
its target is not embedded in build 19 because Apple has not provisioned the
new `com.natemeadows.plated.share` App ID on this Mac. In-app paste and website
import are included in this release.

Native UI tests passed the Account and Settings accessibility layout and the
complete Awards flow from Account through gallery, badge card and detail. The
[Account](native-build-19/account-accessibility.png),
[Settings](native-build-19/settings-accessibility.png), gallery and detail
captures are preserved with the [test source](native-build-19/NativeAccountAwardsChecks.swift).
All 124 Swift files pass the design rules and all 10 app/widget tokens match.
The signed Release archive and export succeeded. App Store Connect accepted the
IPA without errors and reports build 19 VALID and IN_BETA_TESTING for External.
Local certificate trust evaluation still reports `CSSMERR_TP_NOT_TRUSTED`; the
exported IPA was accepted by Apple. Physical-device badge motion, VoiceOver and
Contact-photo behavior still need hands-on confirmation.

Public testing link: https://testflight.apple.com/join/2exAQgYs
