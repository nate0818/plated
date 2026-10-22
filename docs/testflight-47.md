# TestFlight 1.0.1 (47) — October 21, 2026

Build 47 is available to the existing Internal and External TestFlight groups.
[Install or update through TestFlight](https://testflight.apple.com/join/2exAQgYs)
and confirm the installed app reports **1.0.1 (47)**. Build 47 contains the
approved Plan design already present in build 46 and the
Table invitation/phone-alert repairs in app-source commit `12b7e02`. This is a
beta release with explicit live-verification gaps. **TestFlight availability
does not prove that a particular iPhone installed build 47.**

## What changed

- A Table-only invitation that was accepted no longer depends solely on a
  one-time CloudKit change cursor. The host retries the exact pending claim,
  settles its Invited row, and records an Activity item. An acceptance recovered
  days later appears in Activity without a misleading days-late phone banner.
- People at your Table refreshes after a remote change and on foregrounding.
  A failed iCloud read is shown as a retryable failure rather than an empty
  guest list. The intended contact name is labeled as the invitation recipient,
  because a share link can be forwarded and its user cannot be inferred from
  the address to which the message was sent.
- The phone-alert server now uses Apple's documented CloudKit caller-identity
  endpoint. Existing Apple sign-ins can renew their identity proof in Settings
  without signing out. Settings distinguishes an enabled preference from a
  confirmed device registration, and Activity directs an unregistered phone
  to that setup.
- At the largest accessibility text size, the selected Plan day's date is
  compact, and the primary meal action appears before the cook row. Normal
  text size keeps the approved hierarchy.

## Evidence and boundaries

| Area | Fresh result on this candidate | Limit |
| --- | --- | --- |
| App logic | The complete current app suite passed 717, skipped 4 opt-in Calendar integration cases, and failed 0 on iOS 26.2 iPhone 17 Pro simulator (`/private/tmp/Plated-All-47-20261021.xcresult`). The earlier focused `TableNewsTests` and `SocialPushTests` run passed 59 (`/private/tmp/Plated-Social-Repair-20261021.xcresult`). | Mock/isolated CloudKit data, not a real accepted invitation. The four Calendar skips are not counted as passes. |
| Server logic | 22 Deno tests passed; `deno check index.ts` passed. The corrected `social` Edge Function v4 was deployed and read back. | No phone has registered against it or received a live delivery during this check. |
| Native interaction | The accessibility Plan action test passed (action visible and opens meal choices); two Table People opening tests passed at normal and AX5 text (`/private/tmp/Plated-AX5-Plan-Repair-20261021.xcresult`, `/private/tmp/Plated-Table-People-Repair-20261021.xcresult`). | Preview fixtures; not the user’s household or a live Table share. |
| Native visual | Inspected the current-source [Plan light](testflight-47-captures/plan-default-light.png), [Plan dark](testflight-47-captures/plan-default-dark.png), [Plan AX5 light](testflight-47-captures/plan-AX5-light.png), [Table People light](testflight-47-captures/table-people-default-light.png), and [Table People AX5 light](testflight-47-captures/table-people-AX5-light.png) on the simulator. The normal Plan shows greeting, selected day, meal choice, cook, weather, and household history; AX5 retains the meal action in the initial viewport. | Other build-47 screen/state combinations were not freshly visually inspected. Build-46 evidence does not become a build-47 pass. |
| Static release checks | `scripts/check-design`, `scripts/check-tokens --native-only`, `scripts/check-schema`, and `git diff --check` passed. | The schema script checks a recorded manifest, not a live CloudKit round trip. |

At the final server read, `social_installations`, `social_events`, and
`social_deliveries` each contained **zero rows**. No live phone registration or
delivery is being claimed.

Physical VoiceOver, installed widgets, device Calendar, background/terminated
APNs delivery and timing, an actual old invitation's CloudKit claim, both-way
profile/photo/activity sync, iOS 18.0, broader in-place upgrade, and the full
screen/state visual inventory remain **unverified**. Nate explicitly authorized
continuing this beta without the phone and without a second test account; these
checks have not been converted into passes. Source review, tests, Apple
processing, group access, and installation on a phone are separate facts.

## Signed artifact and distribution

Signed archive: `build/Plated-47-12b7e02.xcarchive`; signed export:
`build/export-47-12b7e02/Plated.ipa`, SHA-256
`c219a4e072054ba05eb367cea6345fb13df21f1531ceb3204fbb263b52fd025c`.
App and widget both report 1.0.1 (47). Strict signature checks passed; app
and widget dSYM UUIDs match their exported binaries. The app has production
APNs/CloudKit, WeatherKit, Apple sign-in, shared app group, associated domain,
notification capabilities, and `get-task-allow=false`. The widget has the
shared app group and `get-task-allow=false`. Both privacy manifests are
packaged; minimum iOS is 18.0; the signed iPad app declares landscape only
and full-screen. The archive build emitted two pre-existing diagnostic
warnings (an unnecessary `await` in `HouseholdShare`, and a constant DEBUG
condition in `Directory`); no build or export error remained.

Apple accepted the exact IPA upload, delivery UUID
`9e866228-bd56-425c-9442-63c550eb13b7`. The build processed as `VALID`.
App Store Connect read-back shows `IN_BETA_TESTING` for Internal and External,
Internal all-build access, explicit build-47 membership in External, automatic
tester notifications enabled, and the exact [en-US tester notes](testflight-47-notes.txt)
saved and read back. Neither build 46 nor 47 has individually assigned testers
outside those groups. The public link above is active for the External group.
No phone installation was observed.
