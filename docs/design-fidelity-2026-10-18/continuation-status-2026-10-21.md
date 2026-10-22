# Approved-design candidate status — October 21, 2026

This is a checkpoint for the isolated, **unreleased** candidate at
`/Users/natemeadows/.codex/worktrees/plated-approved-fidelity/Plated` on
`codex/approved-design-fidelity-46`. The approved-design implementation was
committed as `abd64872e107efa9cb0ce64653a6317dc72a3f7c`, followed by the
compact-text photo-control correction in `7b4d56d973f96ee2aba3ac463dcd9b398840cf11`,
and the household photo-label refinement in `afe2f99`; all were pushed. It supersedes the Xcode-setup
blocker in `continuation-status-2026-10-20.md`, not the outstanding coverage in
`acceptance-ledger.md` or `docs/release-quality-standard.md`. Project settings now
say 1.0.1 (46) for the app and widget. Fresh signed archives and IPA exports
were created locally from both `7b4d56d` and the current app-source commit
`afe2f99`. Nothing has been uploaded, processed, or made available to testers.
The later one-line household cover-copy refinement (`Add a household photo` →
`Add photo`) keeps the visible prompt on one line at AX5 while preserving the
full accessible action name.

## Fresh native evidence

| Scope | Result | Evidence and limit |
| --- | --- | --- |
| App unit suite | 719 executed, 4 opt-in Calendar skips, 0 failures on the current candidate | `/Users/natemeadows/Plated/build/Plated-All-Current-20261021.xcresult`. This rerun includes the final Plan accessibility control and Table-thread labels. The four skipped opt-in cases remain separately scoped; permission UI flows were also rerun below. |
| App unit suite after final Plan/photo edits | 719 executed, 4 opt-in Calendar skips, 0 failures | `/Users/natemeadows/Plated/build/Plated-All-After-Photo-Plan-Signed-20261021.xcresult` used the latest simulator app with local signing and CloudKit entitlement. An unsigned first attempt crashed before test bootstrap because its application identifier entitlement was absent; it is not counted as an app failure or a pass. No-account CloudKit log messages in the passing simulator suite are not live sync evidence. |
| iPad landscape route matrix | 4 current-source matrix methods passed | `/Users/natemeadows/Plated/build/iPad-Matrix-Current-20261021.xcresult`; 32 screenshot/tree pairs across eight routes, both appearances, default/AX5. The test tree measured a 1376×1032 landscape app window and the installed Info.plist declares only iPad landscape. XCUIScreen attachments misleadingly serialize as 2064×2752 portrait pixels on this runtime; an independent `simctl io screenshot` measured the display at 2752×2064 and visually showed the landscape two-column Plan. Do not use the portrait-shaped attachments alone as rotation proof. Separate rotation/draft-retention result: `iPad-Rotation-Final-20261021.xcresult`. Narrow/Stage Manager resizing remains unchecked. |
| iPad matrix after Plan/photo edits | All 4 native methods and the separate rotation/draft journey passed on the newer candidate | `/Users/natemeadows/Plated/build/iPad-Matrix-After-Photo-Plan-20261021.xcresult` covers dark/light and default/AX5 after the pinned Plan summary and composer photo-action edits; `iPad-Rotation-After-Plan-Photo-20261021.xcresult` checks portrait/landscape attempts, two-column placement, and unsaved post text through rotation. These do not close narrow-window and physical-device gaps above. |
| iPad matrix and attached-photo controls after final AX5 correction | All 4 matrix methods plus the photo-change/remove interaction passed | `/Users/natemeadows/Plated/build/iPad-Matrix-After-AX5-Photo-Fix-20261021.xcresult` checks dark/light and default/AX5. `/Users/natemeadows/Plated/build/Photo-Controls-IPad-AX5-Landscape-20261021.xcresult` asserts full-row photo buttons, readable stacking, removal, and disabled posting. Its actual native screenshot was inspected. An earlier attempt held the landscape-only iPad physically portrait and could not swipe the controls into view; that failed result is retained separately and the test now starts in landscape. Narrow/resized-window behavior remains open. |
| iPad AX5 matrix after household-copy refinement | One eight-route light/AX5 matrix method passed against explicitly installed app source `afe2f99` | `/Users/natemeadows/Plated/build/IPad-AX5-Correct-App-20261021.xcresult` contains Plan, Table, composer, recipes, detail, groceries, household and cooking captures/trees. The test asserted landscape app-window geometry on every route. The Household screenshot was inspected and shows one-line `Add photo`, readable People/Invite and full member rows. XCUIScreen again serialized portrait-shaped pixels; retain the earlier independent display-orientation proof above, and do not call this capture alone proof of physical display orientation. |
| Empty widgets | Tonight small, Whose Turn small and medium visually inspected; no observed overlap or truncation | `/Users/natemeadows/Plated/build/Widget-Both-Empty-Final-20261021.xcresult`, exported to `Widget-Both-Empty-Final-Export-20261021/`. The small turn prompt is “Assign a cook”; the medium retains “Tap to hand out the week.” Deterministic DEBUG app-group fixture only; real household timeline and device installation remain separate. |
| Widget gallery/tap destinations | Gallery and cookbook, Table, Grocery simulator tap-through passed in prior focused results | `Widget-Gallery-Final-20261021.xcresult` and `Widget-Clean-Tapthrough-20261021.xcresult`. Gallery previews do not prove actual home/lock widgets on a phone. |
| Household pushed header | Bell, settings, return navigation and both appearances passed and were visually inspected | `Household-Header-Capture-Final-20261021.xcresult` and matching export. The separate iPad matrix shows the same bell in its default and AX5 Household captures. |
| Plan selection, leftovers and weather | Focused simulator journeys passed | Large/compact selected-day results; `Leftovers-Compact-Retry-20261021.xcresult`; `Weather-Attribution-26-20261021.xcresult`. Weather used real Apple attribution artwork/metadata with a preview forecast. No live forecast claim. |
| Native VoiceOver simulation | The prior app-source commit's iOS 27 simulator suite finished with 8 executed, 1 explicit input-activation-probe skip, and 0 failures | `/Users/natemeadows/Plated/build/VoiceOver-iOS27-Final-20261021.xcresult` covers Plan dinner/weather/count order, featured dinner and cooking reachability, gathering controls, household/Table headers, profile failure/cancel, recipe failure/discard, and seven-screen reading order. The one-line household copy change after this run needs a fresh focused announcement check; the suite is historical for the current working tree. A physical up/down adjustment and gesture activation remain unverified. |
| Recipe save-failure VoiceOver rerun | Passed on the latest candidate | `VoiceOver-Recipe-Diagnostic-20261021.xcresult` now asserts the failure notice exists immediately after Save, retains a capture of that state, then checks VoiceOver can reach it and that cancel/discard preserves the original recipe. The older broad run intermittently missed the notice in speech; the isolated current-source journey passed. Physical gestures remain unverified. |
| Calendar permission UI | Fresh denied and granted flows passed independently on iOS 27 | `Calendar-Denied-Clean-20261021.xcresult` and `Calendar-Granted-Clean-20261021.xcresult`; Plated's simulator Calendar permission was reset before each run. Denial kept the draft and allowed local-only save; grant completed the event flow. This is simulator proof, not device Calendar proof. |
| Calendar permission in reused simulator | Both native UI paths passed after each test reset Calendar authorization | `Calendar-Isolated-Reset-20261021.xcresult`. The broad suite's older Calendar tests assumed a fresh permission prompt on a simulator that had already authorized Calendar; resetting in `setUp` preserves the prompt and subsequent denied/granted assertions without weakening them. |
| Social notification backend | 21 local Deno tests and function typecheck passed; configuration and worker are present; no device delivery has been exercised | Cached Deno 2.5.4 ran `deno test social.test.ts` (21/21) and `deno check index.ts`; tests cover verified CloudKit actors, recipients, membership, reinvitation, preferences, APNs retry classification and payloads. Read-only inspection of Plated's Supabase project on October 21 found active social Edge Function v3, whose four deployed files exactly match this checkout; configured development/production CloudKit token entries; and active delivery/retention cron jobs (1,440 and 1 successful runs respectively in the prior 24 hours). `social_installations` had **zero active rows** and `social_deliveries` had no rows created in the prior 24 hours. This cannot establish APNs registration, delivery, timing, or deep-link behavior. No credential values were read or copied into the ledger. |
| In-place local recipe upgrade | Passed for one persisted recipe | Exact distributed source `aea845b75ec14978a522ecd682dc9c2722467c28` was compiled as simulator build 45 and installed on a clean iOS 26.2 iPhone 16e. A recipe was created through the real local first-run path, confirmed after relaunch (`Upgrade45-Clean-Seed-20261021.xcresult`), and still opened after installing the candidate build 46 over the existing app without uninstall or erase (`Upgrade46-Clean-After-20261021.xcresult`). This narrow result does not cover other persisted models, drafts, settings, photos, queues or timers. |
| Collect-only accessibility audit | Two concrete Table-thread naming findings corrected; seven contrast findings triaged but not counted as an app-wide accessibility pass | Before: `Compact-Accessibility-Diagnostics-20261021.xcresult` reported an unlabeled post photo and a URL-only link name. After the new labels, `Compact-Accessibility-After-20261021.xcresult` reports neither. [The named contrast triage](accessibility-contrast-triage-2026-10-21.md) maps six targets to actual source color/background pairs above 4.5:1, identifies two sampled offscreen positions, and leaves the one unattributed node open for the fresh visual inventory. Raw probe findings are preserved. |
| Static checks | Passed again after the committed household-copy change | `scripts/check-design` (183 Swift), `scripts/check-tokens --native-only` (10 shared tokens), `scripts/check-schema` (159 recorded fields), and `git diff --check`. The schema check is a manifest check, not a live CloudKit test. |
| Current local release archive/export | Build 46 archive/export succeeded from committed app source `afe2f99`; **not distributed** | `build/Plated-46-afe2f99.xcarchive` and `build/export-46-afe2f99/Plated.ipa` in this checkout; IPA SHA-256 `fcddb74165450f96cf912eb1bf24ac0f5a183650e728f239dc1e3c2b315cdeff`. Exported app and widget both report 1.0.1 (46), minimum iOS 18.0 and `get-task-allow=false`. App has production APNs/CloudKit, WeatherKit, app group, associated domain and communication/time-sensitive notification entitlements; widget has the app group. iPad Info.plist allows only landscape and requires full screen. Strict `codesign --verify --deep --strict` passed separately for app and widget. App UUID `C59D4553-52B1-3D1C-B71E-AB1EFBE499DE` and widget UUID `91128856-72B2-338D-8BB1-6A04AC21B7D9` match their respective archive dSYMs. Both privacy manifests are packaged. No upload or Apple processing receipt exists. |
| Superseded local archive/export | The earlier build-46 export from app source `7b4d56d` is retained only as historical evidence | `build/Plated.xcarchive` and `build/export/Plated.ipa`, SHA-256 `a3b2c730faa55b0566ebd57a97af67b1abc2fc54a1a43c733b3af66f383db944`. It lacks the AX5 household cover refinement and must not be uploaded. |
| Broad phone UI suite | Latest completed compact run: 192 executed, 5 skips, 15 failures; focused triage passed and the exact-current-app complete rerun is in progress | `/Users/natemeadows/Plated/build/Phone-UI-Final-Compact-Portrait-20261021.xcresult` is retained as a failed run. The 15 comprise one Favorites transition timing assertion, three iOS 26 recipe-menu query type mismatches, one household confirmation outside-tap mismatch, seven iOS 26 simulator VoiceOver service errors, one AX5 selected-day assertion matching recent activity, and two reused-simulator widget gallery/cleanup assumptions. Focused evidence below resolves or scopes each; it does not turn this completed run into a pass. A prior rerun at `Phone-UI-Compact-Final-Rerun-20261021.xcresult` was interrupted after 32 methods when the app source changed and is not counted. The new complete run uses `/Users/natemeadows/Plated/build/Phone-UI-Correct-App-Compact-20261021.xcresult` against explicitly installed app source `afe2f99`; it must finish before its result can be counted. The older pre-fix 188-test discovery run and its nine failures remain separately preserved in `phone-ui-current-20261021.log`. |

The broad run also exposed a shared simulator-orientation leak from an iPad
matrix into later phone tests. Targeted portrait reruns now pass for attached
photos, planned-recipe detail, Start cooking, first-run large text, and
Table-to-Household removal; their respective
test launch helpers reset portrait. The attached-photo test additionally found
that the corner-only Remove control was hard to reach on a short landscape
phone. The current candidate places Change photo and Remove photo in a 44-point
action row below the preview; portrait and landscape tap/removal/disabled-post
checks passed in `Phone-Orientation-Connected-20261021.xcresult`. The native
landscape capture was inspected, with the same XCUIScreen pixel-orientation
limitation noted above. A separate landscape Start cooking journey passed
after the test dragged the button fully into the 874×402 window and tapped
its actual center (`Phone-Landscape-Precise-Scroll-20261021.xcresult`). XCTest
had earlier reported an offscreen button as hittable and auto-scrolled its tap
outside the window. The passing journey verifies the cooking screen, not just
the button's existence; before/after captures are retained.
`Phone-Cooking-Connected-Final-20261021.xcresult` is the final focused
portrait recipe-detail and Start cooking rerun.

The compact iPhone AX5 capture in `Photo-Controls-Compact-AX5-20261021.xcresult`
exposed a genuine visual defect despite a passing touch test: side-by-side
“Change photo” and “Remove photo” broke into letter fragments. The composer now
stacks those controls at accessibility text sizes. The strengthened test asserts
full-row widths, vertical ordering, both 44-point targets, removal, and disabled
posting afterward; it passed in
`Photo-Controls-Compact-AX5-After-Fix-20261021.xcresult`. Its new screenshot was
visually inspected and shows complete, readable labels. Connected portrait and
landscape checks passed in `Photo-Connected-After-AX5-Fix-20261021.xcresult`.
The final iPad matrix and attached-photo interaction passed separately as recorded
above. The signed archive was replaced after this source correction and verified
as recorded above.

The first compact full-suite run exposed launch-orientation leakage in
`ApprovedPolishTests`; the two Plan journeys passed with its explicit portrait
reset. Grocery/Favorites still failed its immediate post-tap assertion in the
reused compact simulator. A new iOS 26.2 iPhone 16e and a new iOS 26.2 iPhone SE
both showed the correct Favorites result; the fresh SE capture visibly shows
the non-favorite recipe absent. The strengthened test waits briefly for that
result instead of sampling an in-flight transition. These independent passing
Grocery/Favorites, eating-out, and local/shared/completed Plan results are in
`Grocery-Favorites-Isolated-20261021.xcresult`,
`Grocery-Favorites-iOS26-Diagnostic-20261021.xcresult`,
`Grocery-Favorites-Fresh-Compact-20261021.xcresult`,
`Plan-Eating-Out-Isolated-20261021.xcresult`, and
`Plan-Parity-Portrait-Isolated-20261021.xcresult`. The clean full suite is still
required; no failure was dropped from the preserved logs.

The subsequent 192-test compact baseline finished with 15 failures and 5
skips. Its focused triage is recorded without changing the signed app source:

- The iOS 26 SwiftUI recipe menu exposes “Edit recipe” as a `PopUpButton` where
  the iOS 27 runner had queried a `Button`. A type-independent accessible
  identity query preserved the actual edit/cancel, photo hit-region and keyboard
  checks; all three passed together in
  `Compact-AX-Menu-Focused-20261021.xcresult`.
- The household confirmation is a centered sheet on the compact iOS 26
  simulator. The underlying header bell is dimmed, so it cannot serve as an
  outside-tap target. Tapping unobscured space dismissed it, kept Sam in the
  household, and passed in `Household-Cancel-Compact-Diagnostic-20261021.xcresult`.
- At AX5 the selected breakfast row is a combined accessible button. Full
  XCTest swipes skipped past it; smaller drags placed the complete row between
  the pinned date strip and tab bar. After changing to tomorrow, the meal row
  disappeared as required; a different recent-activity entry still mentioned
  the previous breakfast. The test now distinguishes those meanings and passed
  in `Plan-AX5-Exact-Row-20261021.xcresult`. Both day screenshots and trees were
  inspected, including the earlier failed captures.
- iOS 26's XCTest remote service returned “Unable to enable VoiceOver — remote
  interface does not support this functionality” for seven speech tests. They
  now explicitly skip on that simulator instead of reporting an app failure.
  The iOS 27 native-speech suite subsequently passed seven tests with one
  explicit input-activation-probe skip in `VoiceOver-iOS27-Final-20261021.xcresult`;
  physical VoiceOver remains unverified. A skip is not a speech pass.
- On the reused simulator, the Lock Screen inline picker started with other
  providers and needed scrolling, while multiple earlier Plated test widgets
  remained on Home. The test now finds Plated's inline families and removes
  every test-owned Plated widget before testing Table/Grocery tap-through. Both
  failed widget methods passed on that same reused simulator in
  `Widget-Reused-Sim-Diagnostic-20261021.xcresult`. Its gallery and destination
  screenshots were retained.
- Favorites was correctly filtered in separate fresh iOS 26.2 compact and
  larger phone captures after a short transition wait. The full-suite rerun
  still needs to confirm that corrected timing assertion in sequence.

This triage changes only test instrumentation and this evidence record. The
subsequent household-cover copy edit was separately committed as `afe2f99`
and has its own signed export and hash above.

A fresh AX5 household cover capture exposed the original three-line photo
prompt. The source now uses the shorter visible `Add photo` inside the same
PhotosPicker, retaining the full accessible action name `Add a household photo`.
The focused native journey first ran against a stale installed app despite a
freshly built UI runner; that result is **not** evidence of the change. After
building the Plated app from this worktree and explicitly installing it on
simulator `A8859A6C-579C-4122-9A07-684ED5445057`, the corrected focused
journey passed in `Household-AX5-Correct-App-20261021.xcresult`. Its ordinary
and AX5 screenshots were inspected: the CTA stays on one line, the cover is
shorter, People and Invite remain readable, and the invitation destination
opens. The updated app's household/Table header VoiceOver-control journey also
passed in `Household-VoiceOver-Correct-App-20261021.xcresult` on the iOS 27
simulator. The accessible photo action retained the full label `Add a household
photo` in the exported AX5 hierarchy. The same app binary was installed on compact simulator
`A61A8933-A9A0-4919-844F-0369A224FDFD`; a fresh full UI suite ran
in `Phone-UI-Correct-App-Compact-20261021.xcresult`. That suite subsequently
finished with 192 tests: 178 passed, 12 explicitly skipped, and 2 failed.
`ReleaseKeyboardTests.testRecipeTitleNotesAndDecimalFieldsHaveAWorkingDoneControl`
reached the final return-to-recipe-options assertion after exercising the
title, notes, decimal keyboard and Done controls. Its exported failure hierarchy
shows the recipe detail and its `Recipe options` button present after discarding
the edit, but the requested edit menu was absent. The return interaction is
under focused diagnosis; the full-suite failure is retained. The exact
keyboard/discard journey passed alone both before and after adding a wait
for the edit sheet and alert to close before the single Recipe options tap
(`Keyboard-After-Full-Diagnostic-20261021.xcresult` and
`Keyboard-After-Transition-Guard-20261021.xcresult`). The corrected compact
baseline in `Phone-UI-Baseline-Excluding-Isolated-Upgrade-20261021.xcresult`
finished with 190 tests: 178 passed, 12 explicitly skipped, 0 failed. Its
result is green only for the included simulator checks. The second
failure, `UpgradePersistenceTests.testSeedBuild45Recipe`, explicitly required a
clean simulator with the old build installed; this broad run deliberately used
the reused candidate-app simulator and did not show the first-run `welcome-local`
button. The separate clean build-45-to-46 upgrade journey above remains its
scoped evidence. The rerun excludes this two-method procedure from the reused
simulator through Xcode's `-skip-testing` selector, retaining its separate
clean-upgrade evidence. The first broad run remains failed historical evidence;
the corrected baseline is the current passing simulator result. An earlier full-suite
attempt was stopped after 32 methods when the app-source copy changed; it is
retained as interrupted historical evidence, never as a pass.

The initial AX5 cooking timer snapshot in the prior native matrix visibly
showed two offset `Resume` titles immediately after a tap; a capture 1.2
seconds later was clean. Focused runner tests passed but their code experiments
were mistakenly exercised against the stale installed app. Those unverified
timer source experiments were reverted. The transient remains an open visual
finding, not a confirmed fix or a settled-frame failure.

The current-source iPad light/AX5 matrix passed its eight-route initial-viewport
checks. All eight exported images were visually reviewed at readable scale;
the household cover CTA remains single-line, and no new overlap was observed
in these initial viewports. This does not certify every scrolled section,
secondary control, dark appearance or resized window of the new commit.

The corresponding dark/AX5 eight-route matrix also passed against the
explicitly installed `afe2f99` app in
`/Users/natemeadows/Plated/build/IPad-Dark-AX5-Correct-App-20261021.xcresult`.
All eight initial viewport captures were inspected. The composer actions and
household cover prompt remain readable. Recipes filters stack vertically and
grocery quantities move beneath item names at this size; these are visible
layout tradeoffs, not a claim that every deeper state is approved. The capture
does not close resized-window, scroll-depth, or physical-device checks.

The app/widget debug binaries used for the final empty-widget capture had SHA-256
`edd645c09b5b8c3cd4981864109c08ff51154cfdb67ec3806534b20b2d185117`
and `48fb309d818919f099e8d991235c1983a611b75f9b96568eb74cbf9700c464d3`,
respectively. The final UI runner plugin, after adding the small-widget capture,
had SHA-256 `b8a38873b8041df9be0b35bbeb9a19453dd46efeb14fa22ba5b139b9f70b9732`.
All are unsigned-for-distribution simulator products, not a release export.

## Release gates still open

1. Reconcile and inspect the full current route/state inventory and every original
   approved annotation. The 15 illustrative design families and passing focused
   suites do not cover every active route, error, offline, role and recovery state.
   Read raw accessibility diagnostics and resolve any real findings.
2. The corrected broad phone UI suite passed 178 checks with 12 explicit skips,
   after the failed first run and focused transition repair above. Read the
   skipped-test reasons and keep visual/capture proof separate from behavior.
3. Minimum deployment is iOS 18.0, but installed runtimes are iOS 26.2/26.5/27.0.
   `xcodebuild -downloadPlatform iOS -buildVersion 18.0 -architectureVariant arm64`
   returned “iOS 18.0 (arm64Only) is not available for download.” Minimum-OS
   remains unverified. The single-recipe build-45-to-46 upgrade above is only
   partial coverage of the required representative persisted state.
4. Nate’s paired phone is visible over local network on October 21, but
   `devicectl device info details` still reports **Developer Mode Disabled**. The user
   explicitly asked again on October 21 to continue without the phone. Physical VoiceOver, installed
   widgets, push registration and live notification delivery/timing, and device Calendar remain unverified
   on this candidate. A second real account/device was unavailable, so both-way
   avatar/activity, invitation, Plan, grocery and Table sync is also unverified.
5. Before any TestFlight distribution: finish the release ledger and the clean
   final-source UI suite. The app-source commit and matching signed export are
   recorded above; commit the remaining documentation/test-runner evidence
   without changing app source. Then verify Apple upload, processing
   and access for each authorized internal and external tester group. No upload
   receipt or tester availability exists for this candidate.

No missing check is treated as passed or waived. App Store Connect's latest
build number read back on October 21 was 45; this local build 46 is not on
TestFlight.
