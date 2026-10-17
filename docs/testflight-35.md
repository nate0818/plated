# TestFlight 1.0.1 (35)

October 17, 2026. Prepared for the user's previously authorized commit, push and
distribution to all configured internal and external TestFlight testers.

## Change

The empty Plan dinner card was tall and left the rest of the page unused. It now
offers compact Plan tonight/Eating out actions, followed by the selected date's
forecast and a seven-day household dinner log. Counts derive from real local and
shared records without counting scheduled meals as cooked or duplicating echoes.
No stored model fields or CloudKit schema changed. The eating-out shortcut has
narrow rollback and an alert on failed save.

## Verification

423 native tests passed; four opt-in Calendar tests skipped. Ten typical-phone
UI/VoiceOver/selected-day checks, six compact-phone context checks, and two final
save-success/failure checks passed. Dark/light, AX5 and iPad screenshots were
reviewed. Design/token/schema checks passed. Full evidence and limits:
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
