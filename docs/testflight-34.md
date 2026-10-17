# TestFlight 1.0.1 (34)

Date: October 17, 2026

Status: **available to Internal and External TestFlight testers**. Apple processing is `VALID`; both internal and external states are `IN_BETA_TESTING`. Automatic tester notification is enabled and the en-US testing notes were saved and read back. The user explicitly requested committing and pushing all current changes and distributing the beta to all testers, including external testers, after being told about the remaining release-verification gaps. An App Store production release was not requested.

## Changes

Plan opens around today’s dinner with a greeting and clearer grouping. The date row selects the only day displayed below it. The broader audit repairs cover recipe/gathering drafts and failure recovery, shared plan and cooking state, groceries, Table, profile editing, accessibility, and widget content/layout.

Additional release checks repaired stale Calendar references after external event deletion, missing keyboard-dismissal controls in gathering/recipe fields, and profile errors that VoiceOver did not consistently announce.

The commit also retains the workspace’s website/admin release evidence, Android scope notes, and email-signature artifact, as requested by “everything.” These artifacts do not deploy a website or backend during this beta release.

## Verification and limits

- Native regression suite: 418 passed, 4 intentional opt-in skips, zero failed. All four Calendar cases passed separately.
- Widget provider/date-boundary tests: 6 passed.
- Targeted gathering, recipe and profile VoiceOver journeys passed; compact keyboard and draft recovery checks passed.
- Design rules, token parity and CloudKit schema comparison passed.
- Full evidence and outstanding device/account gates: [release verification](ux-audit-2026-10-16/release/README.md), [disconnected-phone checks](ux-audit-2026-10-16/release/PHONE_DISCONNECTED.md).
- The phone remains disconnected; latest repairs were not installed directly on it.
- Existing automatic Sign in with Apple revocation/account-deletion verification remains open, as recorded in the quality audit.

## CloudKit gate repair

The release gate initially flagged `record.cookedAt`. The existing deployment manifest already records `planRecord.cookedAt`. `TableShare.planRecord` and `PlanShare.record` both construct `PlatedHouseholdPlan`; this is a second writer of the same deployed field, not a new record field. The gate now compares those two writers together and fails closed if their record-type mapping changes. The deployment manifest was not changed and no schema was deployed.

Mutation checks passed: the legitimate second writer is accepted; a new undeployed field, a changed editor record type, and a missing cookedAt deployment entry are all rejected. A fresh live schema export was unavailable because no CloudKit management token is configured; the existing manifest remains the deployment evidence, with the same documented limitation as before.

## Tester distribution

Both configured groups have access: Internal through its all-builds setting, External through an explicitly verified build-34 membership. External distribution is already `IN_BETA_TESTING`; no further beta-review wait is outstanding. Automatic tester notifications are enabled. Build 33 had no individual tester assignments outside the groups to carry forward. Tester notes are in [testflight-34-notes.txt](testflight-34-notes.txt).

Public link: <https://testflight.apple.com/join/2exAQgYs>.

## Source and upload

All current source/documentation changes were committed as `4f0219ba522b2c2da16d601ce7497c70e3ed25c2` and pushed to `origin/main` before upload. Apple accepted the 17,303,549-byte IPA with no errors; delivery UUID `cabe9bff-6dde-44ea-8771-38ce5f0dc781`.

## Signed artifact

- App and widget: **1.0.1 (34)**; production CloudKit/APNs, `get-task-allow=false`.
- Deep/strict signature verification passed; packaged privacy manifests parse; sharing/background capabilities and export-compliance key are present.
- Binary and dSYM UUID: `314461D6-1EE3-3DCF-90B9-96A022DE89A6`.
- IPA SHA-256: `4e7d81532b39c1689b0b6517e429ccf2fa4e9ac7553eccadd0e7b1cfdd0210de`.
- Build 34 archive/export and previous build 33 are preserved under `build/releases/`.
- App source fingerprints remained unchanged during the archive, apart from the intended build-number bump.
- Machine-readable artifact and distribution verification: [testflight-34-release.json](testflight-34-release.json).

Build 33 remains available; this upload does not expire earlier betas. If a critical regression is confirmed, the rollback is to expire build 34 in TestFlight and direct testers to the retained approved build while preparing a fix. No App Store production submission is part of this release.

Distribution was read back from App Store Connect at 2026-10-17T16:26:51.043094+00:00. The source commit remains `4f0219b`; the final documentation-only commit records the observed distribution result.
