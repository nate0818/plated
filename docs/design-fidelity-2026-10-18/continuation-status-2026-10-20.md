# Continuation status — October 20, 2026

Later addition: [Eat leftovers change and verification](leftovers-2026-10-20.md). Its source manifest supersedes pass 7 for the current candidate.

The approved-design correction candidate is implemented in the isolated worktree and has fresh source/build/helper evidence. **It is not visually signed off or released.** Distributed TestFlight 1.0.1 (45) has not been replaced by this work.

## Exact candidate

- Worktree: `/Users/natemeadows/.codex/worktrees/plated-approved-fidelity/Plated`.
- Base commit: `fc87ad199364019c1ed19c18c6ac24cc0d9b1eb5`; changes remain uncommitted.
- Source: 312 inputs frozen before and checked unchanged after the app build. Digest: `48ff85b3316abca5e8102952f10f0da99f35880e97666c5712b556d0a13c35d6`.
- [Source and binary manifest](candidate-source-pass7.json); [annotation acceptance ledger](acceptance-ledger.md); [evidence classification](candidate-evidence-classification.md).
- Original approval hashes are unchanged: 15 families, 60 annotations, 36 states / 72 appearance mappings. The mapping has 70 planned captures, two live-push gaps, and 46 supplemental candidates. These are plans, not passes. The original illustration is not the entire release screen/state inventory.
- App/widget metadata remains 1.0.1 (45) in this Debug simulator candidate. This modified local binary must not be confused with the distributed build carrying that number.

## Additional defects corrected during this continuation

- Saved Table posts have explicit waiting/sending/failure/acknowledged states and one-shot foreground recovery. Overlapping attempts do not discard another post's retry or duplicate a successful send. Destination and placeholder-author confirmation remain scoped to the original account.
- Comment input is a native multiline editor with a full intended touch area. Mentions insert at the caret, replace the active query, preserve unrelated prose and match exact recipients. The tests reproduced and corrected an invalid Unicode-selection crash, duplicate/suffix mentions, prose consumption and Sam/Samantha notification collisions.
- Reply drafts restore visible link/photo controls and are scoped by account, zone and post. Account changes hide the composer and block save/send. Delayed photo selections cannot overwrite a newer selection or a subsequent draft. Old unscoped and unresolved-placeholder drafts remain stored but are not automatically restored under a different account; no ownership-safe migration is claimed.
- Comment sends/retries/deletions capture the initiating actor, pin the destination and verify actual CloudKit identity around asynchronous operations. A switched account cannot acknowledge the old attempt or enqueue its notification. Existing own-comment/own-post moderation retains the original author. A server save already in flight cannot be recalled; live account-switch behavior still needs proof.
- Invitation receipts require actual sent completion and exact seat state. A missing/deleted seat reports unavailable membership rather than falsely saying Pending. Real Messages sheet handoff and two-account acceptance remain unverified.
- The schema extractor now retains the enclosing static writer across a nested authorization helper. The production deployment manifest was not modified; negative fixtures still reject genuinely new fields/types.

## Verification completed for this source

| Check | Result | Evidence / limit |
| --- | --- | --- |
| App and app-test compilation | Passed | `build/fidelity-app-build-pass7.log`; Debug simulator build-for-testing only, not execution. |
| Fresh UI runner compilation | Passed | `build/fidelity-ui-verified7-build.log`; unique `FidelityVerified7` identity, no runtime-loaded path yet. |
| Exact-source host helpers | 87 passed, zero failed | `build/fidelity-logic-host-pass9.log`: 38 publication + 20 reply visibility + 29 editor. macOS helper execution only. |
| Independent source review | No remaining concrete blocker found in changed editor, recovery, identity and note paths | Not an assurance that no bugs remain, or live-account validation. |
| Design/token/schema/whitespace checks | Passed | 182 Swift files, 10 shared tokens, timer equality, 159 recorded fields. Initial checker failure and three regression fixtures are retained. |
| Failed-case retention | Preserved | Unicode signal-5 log and exact source snapshot; final regression passes. Old stale/interrupted native runs remain excluded. |

The app compiler reports one pre-existing redundant `await` at `HouseholdShare.swift:2563`. No new compiler error remains. Both build logs report simulator service unavailability; a successful build does not override that diagnostic.

## Still required

1. Unlock the Mac and finish Xcode's administrator-authenticated setup. CoreSimulator 1171.7.0 is installed; Xcode requires 1174.9.2. Approval was already granted; the missing step is the macOS authentication itself.
2. Run the fresh-runner canary, verify actual loaded app/plugin paths, then execute the iOS baseline and relevant regression suites. The new 14 identity and 18 note-transport cases are compiled but unrun. Calendar opt-in tests require their own run.
3. Capture and inspect this exact native candidate against the immutable approval in both appearances, phone sizes, default/AX text sizes and supported landscape iPad states. Reconcile the complete release screen/state inventory, not only the 72 illustrative mappings. Confirm keyboard, scrolling, cancellation, persistence, relaunch, narrow windows and rotation attempts. `capture-index.js` remains empty.
4. Verify physical VoiceOver, real account invitations/removal/rejoin, avatars/activity, comment/reaction propagation and contextual phone notifications. Phone-free continuation is authorized; it is not a waiver or a pass. Minimum iOS 18, in-place upgrade and narrow/resized iPad verification also remain outstanding.
5. Only after the release gates: commit/push the intended source, create and inspect the signed production archive/export, validate versions/capabilities/symbols, upload and verify processing and every authorized tester group's access. No new archive, commit, push or TestFlight upload was made in this continuation.

Build logs above live under `/Users/natemeadows/Plated/build/`. The macOS host suite and its copied source manifest are in `Fidelity-Logic-Host-Pass9/` there. Historical test counts and screenshots are separately identified in the evidence classification and do not certify the current candidate.
