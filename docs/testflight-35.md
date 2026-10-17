# TestFlight 1.0.1 (35)

October 17, 2026. Prepared for the user's previously authorized commit, push and
distribution to all configured internal and external TestFlight testers.

## Change

The empty Plan dinner card was tall and left the rest of the page unused. It now
offers compact Plan tonight/Eating out actions, followed by the selected date's
forecast and a seven-day household dinner log. Counts derive from real local and
shared records without counting scheduled meals as cooked or duplicating echoes.
The cook is an explicit role with a face and assignment control, including before
a recipe is chosen. Rotation suggestions are labeled, and choosing a recipe keeps
an explicit unassigned choice. Household rows show photos and recorded seven-day
cooking/sharing activity with profile links.

Identity fixes keep an organizer’s photo visible to members, resolve Table/profile
photos and posts by account ID after a rename, and publish the correct organizer
cook ID when another member plans. No stored model fields or CloudKit schema
changed. Eating-out and cook-assignment saves have narrow rollback and alerts.

## Verification

432 native tests passed; four opt-in Calendar tests skipped. An additional widget
publisher test passed against its actual app-group snapshot. Fourteen Plan/context
and household cases passed on each phone size; two iPad cases passed. The final
typical-phone run passed all 18 cases, including real simulator VoiceOver through
the household rows and all three selected-day regressions. Dark/light and AX5 layouts
were reviewed. Design/token/schema checks passed. Full evidence and limits:
[Plan design record](plan-context-design.md).

Live WeatherKit and Apple attribution rendering on a physical signed device are
not newly verified. The phone is disconnected; the earlier two-account and other
physical-device release gaps still apply. This is a beta update, not an App Store
production submission or a claim of complete release clearance.

## Deployment

Status: **available to Internal and External testers**. Source commit `d59fdac` is
pushed to `origin/main`. App/widget are 1.0.1 (35), production CloudKit/APNs,
get-task-allow=false; signatures and privacy manifests validate, binary/dSYM UUIDs
match. Source fingerprints stayed unchanged during archive. The signed artifact is
retained under `build/releases/35`; see [release receipt](testflight-35-release.json).
Apple reports both beta states as `IN_BETA_TESTING`; both configured groups
include build 35, automatic notifications are enabled, and English tester notes
were read back successfully. Build 34 had no individually assigned testers to
carry forward. Verified October 17 at 15:59 EDT. Public link:
https://testflight.apple.com/join/2exAQgYs.
Build 34's archive/export remain under `build/releases/34`. If dinner planning,
history or weather shows a critical regression, expire build 35 and use retained
build 34 while preparing a fix. Earlier betas will not be expired by this upload.


Apple accepted the 17,460,365-byte IPA with no upload errors at October 17, 2026,
15:57 EDT. Delivery UUID: `13247daa-8cb2-4ddc-879e-19df453b865a`.
IPA SHA-256: `f3142402df5647c31086a6dbc4bea8c902e4cd3a54e37d4c3bdbb7f75e2df1e9`.
Binary/dSYM UUID: `568A9353-9BD2-3E4B-B1FA-5B505B140DD2`.

The user's clarification that the profile appears on the other phone prompted
an additional receive-path regression. It found an organizer rename rejected
by the merge's clone guard; follow-up verification is tracked in
[build 36](testflight-36.md). The already-running build 35 distributor completed
before it could be paused; no build was expired or removed from a tester group.
