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
extended VoiceOver and selected-day run is in progress. Dark/light and AX5 layouts
were reviewed. Design/token/schema checks passed. Full evidence and limits:
[Plan design record](plan-context-design.md).

Live WeatherKit and Apple attribution rendering on a physical signed device are
not newly verified. The phone is disconnected; the earlier two-account and other
physical-device release gaps still apply. This is a beta update, not an App Store
production submission or a claim of complete release clearance.

## Deployment

Status: prepared; archive, upload and distribution results will be recorded here.
Build 34's archive/export remain under `build/releases/34`. If dinner planning,
history or weather shows a critical regression, expire build 35 and use retained
build 34 while preparing a fix. Earlier betas will not be expired by this upload.
