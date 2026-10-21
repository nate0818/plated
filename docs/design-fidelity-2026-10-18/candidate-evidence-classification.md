# Candidate evidence classification

> **October 21 update:** The Xcode first-launch blocker below was resolved and
> fresh native suites ran. See
> [the dated candidate status](continuation-status-2026-10-21.md). The
> October 20 classifications and historical captures below remain scoped to
> their original source and run; they are not current release sign-off.

This is an evidence audit of the isolated, unreleased correction candidate after TestFlight 1.0.1 (45). It does not certify a release. The original approval remains unchanged: 15 screen families, 60 annotations and 36 selectable states; the light/dark mapping has 72 entries. That illustrative inventory is smaller than the complete application inventory required by `docs/release-quality-standard.md`.

## What can be shown in the new comparison

`capture-index.js` is empty at this snapshot. `mapping-plan.json` supplies planned attachment names and originating tests, not a collection of verified images. Its October 20 reconciliation has 70 planned source/test candidate mappings and 2 null push entries. These must not be reported as 70 passes, 70 captured states, or 2 test failures. Newly added candidates remain unrun in this document.

For each adopted native screenshot, retain:

1. Exact originating result bundle, test method, attachment metadata and original exported image hash. Copy an image without altering/cropping its native content; preserve the original separately.
2. App source manifest and the code-bearing app binary hash, plus the actual runtime-loaded path. A current installed bundle hash did not prevent the stale pass3 test-runner problem.
3. Test-source manifest, runner/plugin identity and actual loaded bundle path. Confirm a nonzero intended test count and current-method canary; use the result's final status, not an unfinished console excerpt.
4. Device, OS, orientation/window, appearance, text size, selected state and viewport. The phone/compact/iPad and default/AX comparisons are separate observations.
5. The visible state and content differences actually inspected. A screenshot is proof of its shown render only; label out-of-view elements, actions and persistence as separate evidence. Fixtures do not prove live identity, photos, sync or delivery.
6. A status that distinguishes captured, visually reviewed, interaction passed, live verified, failed and unavailable. None implies the others. A native candidate should not be captioned as fully corrected before those distinctions are shown.

Preserve missing entries with an explicit reason. Do not silently fall back to a different state, theme, device, text size or older build. Any historical comparison image must visibly identify its earlier source/run, not inherit the current-candidate caption. Keep the original approval panel unchanged and disclose the later landscape-only iPad instruction separately.

## Exact-state candidate reconciliation — October 20

| Original mapping | Inspected state / source finding | Permitted treatment |
| --- | --- | --- |
| `table/pending/dark`, `table/pending/light` | Source now has a distinct known-outage state, path-aware foreground recovery and coalescing. `SocialPublicationUITests.testWaitingForConnectionInBothAppearances` emits planned `publication-waiting-dark/light`; cream AX5 is supplemental. | Exact-state source/test candidates, unrun here. Preview network state is overridden to unavailable; it does not prove a real outage, retry or transport. Placeholder-identity recovery completed independent source review and the pass7 app build. Its 38 helper cases passed in host Pass9; iOS integration and actual network recovery remain unrun. |
| `comments/sending/dark`, `comments/sending/light` | `FidelitySupplementalStatesTests.testPendingReplyBothAppearances` now freezes a DEBUG pending reply and emits planned `fidelity-comments-sending-dark/light`. | Source/test candidates, unrun here. A pending reply's displayed Sending label is not a real server-write receipt. Failure/waiting/Retry, AX5 and delivery remain separate checks; never substitute Table post status. |
| `activity/push/dark`, `activity/push/light` | No actual current-candidate phone push capture/delivery check is available. | Keep both null and live-blocked. The original lock-screen panel is a copy concept. In-app fixtures or server configuration cannot demonstrate latency, sound, grouping, badge, delivery or tap destination. |
| `household/invite/dark`, `household/invite/light` | `HouseholdHomeView` now has a real `.sent`-gated inviter receipt; `FidelityInviterReceiptTests.testSentInvitationReceiptBothAppearancesAndSizes` emits planned `fidelity-household-inviter-sent-dark/light` plus AX5 variants. Separate dark fixtures cover resend, accepted and ended; both-theme fixtures cover missing exact membership as unavailable instead of Pending. | Source/test candidates, unrun here. The preview constructs receipt state without real Messages or CloudKit. Actual dismissal-to-receipt sequencing, fresh/old-link behavior, live join/notification and recipient identity remain unverified. Generic fresh contacts cannot establish prior removal, so that explanatory copy is not fabricated. Recipient Rejoin remains separate. |
| `ipad/default/light` | `FidelityIPadMatrixTests.testLightDefault` emits `ipad-matrix-plan-light-default` with XCUIScreen and a paired tree; a pass3 attachment already exists. | Map as a final-source capture candidate, not a missing implementation. Existing pass3 files remain historical and require their own inspection; later layout/copy corrections require a fresh candidate run. Phone/AX screenshots cannot substitute for default light iPad. |

Seven previously null entries now have exact planned test candidates, including the light iPad entry with historical evidence. Only two phone-push entries remain null. This describes the mapping, not complete application coverage, executed tests, visual acceptance or a release score. `capture-index.js` stays empty until images are exported, matched to the final source/run, inspected and explicitly adopted.

The 46 supplemental candidates are listed in `mapping-plan.json`. Six native input methods are authored: four cover multiline growth/cap, caret editing, keyboard/Send geometry, full draft relaunch and typed/menu mentions in both appearances/default/AX5; two additional methods cover typed-query replacement/middle insertion and visible link-only draft restoration in both appearances/default. Cream/default edge tapping is separate. Twenty-nine Foundation-only `CommentEditorStateTests` cases cover token replacement, Unicode ranges, account/zone/post isolation and restoration without adopting legacy or unrelated placeholder drafts. All 29 editor helper cases passed in the exact-source host Pass9 run below. The six native input methods remain unrun here. The view captures draft ownership on entry, observes defaults changes on the main run loop and foreground return, hides the composer on ownership mismatch, and also checks every save/send. Stored original-account drafts are retained. Photo completions now require the current request generation, captured scope, current account and exact picker selection; newer pick/remove/successful local Send/account mismatch invalidates them. Notification recipients use complete names with valid @ boundaries and longest-match precedence. Grapheme-boundary validation precedes every helper traversal or selection replacement. Multiword continuation inspects complete lexical tokens; the authored matrix preserves unrelated “with basil”/“maybe later” prose, completes partial name words, consumes matching-name suffixes and handles a caret immediately after a separator. There is no verified ownership mapping for legacy or placeholder-to-confirmed drafts, so no migration is claimed. The relative four-versus-ten-line height check alone cannot prove four full native lines are visible. These draft UI tests never send comments and do not establish IME, dictation, copy/paste, physical hardware keyboard/VoiceOver, real account switching or actual notification/transport behavior.

The frozen placeholder-identity recovery, editor and note-sending changes completed independent source review. App build pass7 and UI harness Verified7 both succeeded. Host Pass9 covers the bounded helpers specified below; new SwiftData identity and injected CloudKit note-transport tests are compiled but unrun. Earlier builds, unit runs and screenshots do not certify this candidate. See `candidate-source-pass7.json` for the exact 312-file source and binary manifest.

## Existing complete evidence and its limits

### Historical pass3 units

`/Users/natemeadows/Plated/build/Fidelity-Unit-Pass3.xcresult` completed: 576 cases, 4 skipped, 0 failures (572 passed). The log records 13 `TablePostPublicationTests`, 20 `CommentReplyVisibilityTests`, 24 `HouseholdReinvitationTests` including the five added presentation-proof cases, and three `RecipeDurationFilterTests`.

The reply-visibility and reinvitation helper/test files still match `candidate-source-pass3.json`, supporting only their bounded historical logic results. `TablePostPublication.swift` and `TablePostPublicationTests.swift` no longer match pass3 after outage/recovery work; the current test source has 38 methods, not the historical 13. An intermediate 22-case publication source passed the historical host run; all 38 final publication helper cases passed host Pass9 below. The new inviter receipt has seven authored unit cases and four UI journeys with no run claimed here. Only an exact invited seat means Pending; missing/deleted/non-invited membership is unavailable, not inferred waiting or removal. `PlanContextView`, `PostThreadView`, `HouseholdHomeView` and `WeekView` also changed. The historical full run must not certify these new sources or the final app.

The four skipped cases are:

- `CalendarIntegrationTests.testDeniedRemovalPreservesReferenceForRetry`
- `CalendarIntegrationTests.testEventKitCreateUpdateRecreateAndRemove`
- `CalendarIntegrationTests.testMovedCalendarAndDaylightSavingTimeEditsRetainOneEvent`
- `CalendarIntegrationTests.testRemovingAnExternallyDeletedEventClearsItsLocalReference`

They require their own opted-in Calendar runs. A suite with these skips is not a Calendar integration pass.

### Bounded October 20 host logic evidence

`/Users/natemeadows/Plated/build/fidelity-logic-host.log` records a completed macOS host XCTest run: 42 tests, 0 failures (22 publication and 20 reply visibility). `/Users/natemeadows/Plated/build/Fidelity-Logic-Host/source-hashes.json` freezes the unchanged copied source/test versions: `NetworkAvailability.swift`, `TablePostPublication.swift`, `CommentReplyVisibility.swift` and both XCTest files. The separate trailing Swift Testing “0 tests” line does not replace the completed XCTest count.

This is a historical, bounded helper-level result. The publication helper and tests already differ from that manifest after further placeholder-author recovery work; the final source has 38 publication methods. NetworkAvailability and reply-visibility source/test hashes still matched the host manifest at this reconciliation. The final changed helper sources were executed separately in Pass9 below. The 42 passing tests do not establish an iOS application build/suite, native keyboard/layout, real UIKit Messages callbacks, actual path transitions, or live transport and notification behavior.

### Final frozen source — October 20

`candidate-source-pass7.json` records 312 unchanged source inputs before/after app build, source digest `48ff85b3316abca5e8102952f10f0da99f35880e97666c5712b556d0a13c35d6`, app/widget/test-runner binary hashes, SDK/Xcode and commands. Both app `fidelity-app-build-pass7.log` and harness `fidelity-ui-verified7-build.log` end in TEST BUILD SUCCEEDED. The harness has the fresh bundle identity `com.natemeadows.plated.FidelityVerified7`. Neither binary was executed in a new simulator session. The app build retains a pre-existing redundant-await compiler warning in `HouseholdShare.swift:2563`; it is not an execution failure. Both build logs explicitly report the unavailable CoreSimulator service.

`/Users/natemeadows/Plated/build/fidelity-logic-host-pass9.log` completes **87 XCTest cases, zero failures**: 38 publication, 20 reply visibility, and 29 editor/draft/photo cases. Exact copied source/test hashes in `Fidelity-Logic-Host-Pass9/source-hashes.json` match this candidate. This is macOS helper execution only; it does not run the iOS app, SwiftData identity migration, injected note transport, keyboard, photos picker, CloudKit, or notifications. The 14 identity migration/confirmation tests and 18 note-transport tests are authored and compiled, not executed in this pass.

Retain the failed `fidelity-logic-host-final.log` and its `Fidelity-Logic-Host-Final/source-hashes.json`: the invalid-surrogate-selection case crashed with signal 5. The current Character-boundary correction and expanded regressions pass in Pass9. Intermediate Pass7/Pass8 helper logs (84/85 passing cases) predate the final whole-word prose-preservation fix and cannot certify it.

Fresh static checks pass: 182 Swift files against design rules, 10 shared app/widget tokens plus identical timer source, and 159 recorded CloudKit fields. Initial `fidelity-schema-pass7.log` falsely attributed note fields to a nested authorization function. The repaired checker retains the enclosing static writer, validates the exact note constructor/type, and passes `fidelity-schema-pass7-recheck.log`. Three isolated fixtures in `fidelity-schema-extractor-regressions.json` prove the unchanged baseline passes while a new field and a changed record type still fail. The deployed manifest is unchanged; this does not verify the live production schema. Final whitespace checks are clean.

The Mac was rechecked and is locked. Xcode setup still needs administrator authentication; installed CoreSimulator 1171.7.0 is older than required 1174.9.2. The user's approval is recorded, but system authentication has not been completed. Fresh native execution, screenshots, accessibility diagnostics and visual adoption remain blocked. No new image is added to `capture-index.js`.

### Historical official Weather artwork

Completed result: `/Users/natemeadows/Plated/build/Fidelity-Weather-Pass2.xcresult`, three tests, zero failures. Attachment metadata resides in `fidelity-weather-pass2-attachments/manifest.json`.

Visually inspected here:

- Green: `B3CBFA20-1A56-4252-93FA-9558A2DF60DD.png` — downloaded white Apple Weather mark is visible on green.
- Cream: `953A0B34-834A-4528-BDB3-0B4890E43395.png` — downloaded black mark is visible on cream.

Both images also show “Preview weather”; forecast values are simulated. The test explicitly waits for real attribution metadata and the downloaded mark, so the evidence is narrower than a live weather pass but stronger than a placeholder-only preview. The separate cream AX5 attachment `2E7B5759-6067-4896-9121-348744376227.png` exists; this audit has not visually reviewed it. These tests do not tap through the legal link, grant/deny location permission, or verify real forecast retrieval. Recovery copy and hit-target changes postdate these images and still need fresh proof.

### Historical pass3 iPad matrix

Completed result: `/Users/natemeadows/Plated/build/Fidelity-iPad-Matrix-Pass3.xcresult`, four tests, zero failures. The named export contains exactly 32 PNGs and 32 accessibility-tree files. Eight screens—Plan, Table, composer, recipes, recipe detail, groceries, household and cooking—were captured in both themes at default and AX5 text size. The test asserts a route marker and a landscape app window before each `XCUIScreen.main.screenshot()`.

This audit checked file/test/log inventory, not all 32 rendered images. It does not convert the test's completion into a visual pass. The earlier `review-findings.md` has a separate, bounded inspection of four default-dark Plan orientation captures from `Fidelity-iPad-Pass3.xcresult`; preserve that narrower finding under its original source/run.

Use XCUIScreen captures for this iPad evidence. Some app-scoped screenshots in the rotation run were cropped/misoriented and must not be used as proof. Default/AX5 route captures do not establish a narrow/resized window, keyboard interaction, all scroll content, a real physical iPad or retention of every draft/session state.

## Failed, stale and interrupted evidence

- `/Users/natemeadows/Plated/build/fidelity-logic-host-final.log` records an intermediate exact-copy host failure: signal 5 in `testInvalidSelectionIsRejectedWithoutChangingTheDraft`, with a String Character index trap from an interior UTF-16 surrogate offset. The copied `Fidelity-Logic-Host-Final` source and log remain historical failure evidence. The regression is preserved and extended to combining/ZWJ/overflow cases; the revised Character-boundary guard still requires a fresh final run. No partial test count is promoted to a pass.
- `test-runner-provenance.md` documents the pass3 compact harness loading its obsolete plugin from a retired CoreSimulator path. Do not present that run as executing the latest test code. The app image can be considered separately only after app provenance and actual render inspection.
- `Fidelity-Verified-Smoke1.xcresult` executed two current methods: empty Directions passed; comment-input geometry failed (17pt frame against 44pt minimum). The later TextEditor change is the proposed correction and requires fresh native edge-tap, typing, keyboard/AX and persistence proof.
- `/Users/natemeadows/Plated/build/Fidelity-Verified-Phone4.xcresult` and `Fidelity-Verified-Compact4.xcresult` exist without `Info.plist`; the coordinator reports that both runs were interrupted. They have no final suite result to promote to a pass. Preserve partial diagnostics for investigation only.
- Pass6 app/harness logs report TEST BUILD SUCCEEDED, but the source changed afterward for unavailable invitation membership and ongoing placeholder-identity recovery. Those later corrections are covered by the final source review/build and bounded host evidence recorded here; their iOS/native integration remains unrun. Pass7 subsequently built the frozen final source successfully. No pass5/pass6 test count, screenshot review or runtime success is asserted by this document; successful builds do not prove native behavior.

## Release limits remain separate

Both-account invitation/removal/rejoin, avatar/activity propagation, automatic Table comments/reactions, accurate badges and timely phone notifications remain live checks. Physical VoiceOver, minimum-supported iOS 18, in-place upgrade and narrow/resized iPad windows remain explicit obligations unless later evidence establishes them. Simulator snapshots, pure helper tests and historical candidate results do not waive those requirements.

No archive/export, new TestFlight upload, processing completion, tester-group availability or installation on Nate's phone is established by this evidence audit.
