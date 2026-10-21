# Approved-design candidate status — October 21, 2026

This is a checkpoint for the isolated, **unreleased** candidate at
`/Users/natemeadows/.codex/worktrees/plated-approved-fidelity/Plated` on
`codex/approved-design-fidelity-46`. The approved-design implementation was
committed as `abd64872e107efa9cb0ce64653a6317dc72a3f7c`, followed by the
compact-text photo-control correction in `7b4d56d973f96ee2aba3ac463dcd9b398840cf11`;
both commits were pushed. It supersedes the Xcode-setup
blocker in `continuation-status-2026-10-20.md`, not the outstanding coverage in
`acceptance-ledger.md` or `docs/release-quality-standard.md`. Project settings now
say 1.0.1 (46) for the app and widget. A fresh signed archive and IPA export
were created locally from the final app-source commit `7b4d56d`.
Nothing has been uploaded,
processed, or made available to testers.

## Fresh native evidence

| Scope | Result | Evidence and limit |
| --- | --- | --- |
| App unit suite | 719 executed, 4 opt-in Calendar skips, 0 failures on the current candidate | `/Users/natemeadows/Plated/build/Plated-All-Current-20261021.xcresult`. This rerun includes the final Plan accessibility control and Table-thread labels. The four skipped opt-in cases remain separately scoped; permission UI flows were also rerun below. |
| App unit suite after final Plan/photo edits | 719 executed, 4 opt-in Calendar skips, 0 failures | `/Users/natemeadows/Plated/build/Plated-All-After-Photo-Plan-Signed-20261021.xcresult` used the latest simulator app with local signing and CloudKit entitlement. An unsigned first attempt crashed before test bootstrap because its application identifier entitlement was absent; it is not counted as an app failure or a pass. No-account CloudKit log messages in the passing simulator suite are not live sync evidence. |
| iPad landscape route matrix | 4 current-source matrix methods passed | `/Users/natemeadows/Plated/build/iPad-Matrix-Current-20261021.xcresult`; 32 screenshot/tree pairs across eight routes, both appearances, default/AX5. The test tree measured a 1376×1032 landscape app window and the installed Info.plist declares only iPad landscape. XCUIScreen attachments misleadingly serialize as 2064×2752 portrait pixels on this runtime; an independent `simctl io screenshot` measured the display at 2752×2064 and visually showed the landscape two-column Plan. Do not use the portrait-shaped attachments alone as rotation proof. Separate rotation/draft-retention result: `iPad-Rotation-Final-20261021.xcresult`. Narrow/Stage Manager resizing remains unchecked. |
| iPad matrix after Plan/photo edits | All 4 native methods and the separate rotation/draft journey passed on the newer candidate | `/Users/natemeadows/Plated/build/iPad-Matrix-After-Photo-Plan-20261021.xcresult` covers dark/light and default/AX5 after the pinned Plan summary and composer photo-action edits; `iPad-Rotation-After-Plan-Photo-20261021.xcresult` checks portrait/landscape attempts, two-column placement, and unsaved post text through rotation. These do not close narrow-window and physical-device gaps above. |
| iPad matrix and attached-photo controls after final AX5 correction | All 4 matrix methods plus the photo-change/remove interaction passed | `/Users/natemeadows/Plated/build/iPad-Matrix-After-AX5-Photo-Fix-20261021.xcresult` checks dark/light and default/AX5. `/Users/natemeadows/Plated/build/Photo-Controls-IPad-AX5-Landscape-20261021.xcresult` asserts full-row photo buttons, readable stacking, removal, and disabled posting. Its actual native screenshot was inspected. An earlier attempt held the landscape-only iPad physically portrait and could not swipe the controls into view; that failed result is retained separately and the test now starts in landscape. Narrow/resized-window behavior remains open. |
| Empty widgets | Tonight small, Whose Turn small and medium visually inspected; no observed overlap or truncation | `/Users/natemeadows/Plated/build/Widget-Both-Empty-Final-20261021.xcresult`, exported to `Widget-Both-Empty-Final-Export-20261021/`. The small turn prompt is “Assign a cook”; the medium retains “Tap to hand out the week.” Deterministic DEBUG app-group fixture only; real household timeline and device installation remain separate. |
| Widget gallery/tap destinations | Gallery and cookbook, Table, Grocery simulator tap-through passed in prior focused results | `Widget-Gallery-Final-20261021.xcresult` and `Widget-Clean-Tapthrough-20261021.xcresult`. Gallery previews do not prove actual home/lock widgets on a phone. |
| Household pushed header | Bell, settings, return navigation and both appearances passed and were visually inspected | `Household-Header-Capture-Final-20261021.xcresult` and matching export. The separate iPad matrix shows the same bell in its default and AX5 Household captures. |
| Plan selection, leftovers and weather | Focused simulator journeys passed | Large/compact selected-day results; `Leftovers-Compact-Retry-20261021.xcresult`; `Weather-Attribution-26-20261021.xcresult`. Weather used real Apple attribution artwork/metadata with a preview forecast. No live forecast claim. |
| Native VoiceOver simulation | Current-source iOS 27 Plan dinner and context reading order, seven-screen traversal, recipe save-failure/discard, and household/Table header controls passed in focused results | `Plan-VoiceOver-Final-20261021.xcresult`, `Plan-Context-VoiceOver-Actor-20261021.xcresult`, `VoiceOver-Recipe-Root-Final-20261021.xcresult`, and earlier header result. VoiceOver announces the selected date as adjustable and moves on to dinner without changing days during reading. A physical up/down adjustment and gesture activation remain unverified. |
| Recipe save-failure VoiceOver rerun | Passed on the latest candidate | `VoiceOver-Recipe-Diagnostic-20261021.xcresult` now asserts the failure notice exists immediately after Save, retains a capture of that state, then checks VoiceOver can reach it and that cancel/discard preserves the original recipe. The older broad run intermittently missed the notice in speech; the isolated current-source journey passed. Physical gestures remain unverified. |
| Calendar permission UI | Fresh denied and granted flows passed independently on iOS 27 | `Calendar-Denied-Clean-20261021.xcresult` and `Calendar-Granted-Clean-20261021.xcresult`; Plated's simulator Calendar permission was reset before each run. Denial kept the draft and allowed local-only save; grant completed the event flow. This is simulator proof, not device Calendar proof. |
| Calendar permission in reused simulator | Both native UI paths passed after each test reset Calendar authorization | `Calendar-Isolated-Reset-20261021.xcresult`. The broad suite's older Calendar tests assumed a fresh permission prompt on a simulator that had already authorized Calendar; resetting in `setUp` preserves the prompt and subsequent denied/granted assertions without weakening them. |
| Social notification backend | 21 local Deno tests and function typecheck passed; configuration and worker are present; no device delivery has been exercised | Cached Deno 2.5.4 ran `deno test social.test.ts` (21/21) and `deno check index.ts`; tests cover verified CloudKit actors, recipients, membership, reinvitation, preferences, APNs retry classification and payloads. Read-only inspection of Plated's Supabase project on October 21 found active social Edge Function v3, whose four deployed files exactly match this checkout; configured development/production CloudKit token entries; and active delivery/retention cron jobs (1,440 and 1 successful runs respectively in the prior 24 hours). `social_installations` had **zero active rows** and `social_deliveries` had no rows created in the prior 24 hours. This cannot establish APNs registration, delivery, timing, or deep-link behavior. No credential values were read or copied into the ledger. |
| In-place local recipe upgrade | Passed for one persisted recipe | Exact distributed source `aea845b75ec14978a522ecd682dc9c2722467c28` was compiled as simulator build 45 and installed on a clean iOS 26.2 iPhone 16e. A recipe was created through the real local first-run path, confirmed after relaunch (`Upgrade45-Clean-Seed-20261021.xcresult`), and still opened after installing the candidate build 46 over the existing app without uninstall or erase (`Upgrade46-Clean-After-20261021.xcresult`). This narrow result does not cover other persisted models, drafts, settings, photos, queues or timers. |
| Collect-only accessibility audit | Two concrete Table-thread naming findings corrected; contrast flags remain under manual review | Before: `Compact-Accessibility-Diagnostics-20261021.xcresult` reported an unlabeled post photo and a URL-only link name. After the new labels, `Compact-Accessibility-After-20261021.xcresult` reports neither. The audit still flags contrast for named Plan/Grocery/Thread nodes plus one unattributed comment node; those are not silently treated as passes. The visually inspected cream Plan and Editorial thread use high-contrast text/token pairs; complete pixel-level triage is pending. |
| Static checks | Passed after the final Plan accessibility source change | `scripts/check-design` (183 Swift), `scripts/check-tokens --native-only` (10 shared tokens), `scripts/check-schema` (159 recorded fields), and `git diff --check`. The schema check is a manifest check, not a live CloudKit test. |
| Local release archive/export | Build 46 archive/export succeeded and signed correctly from app-source commit `7b4d56d`; **not distributed** | `build/Plated.xcarchive` and `build/export/Plated.ipa` in this checkout; IPA SHA-256 `a3b2c730faa55b0566ebd57a97af67b1abc2fc54a1a43c733b3af66f383db944`. Exported app and widget both report 1.0.1 (46), minimum iOS 18.0 and `get-task-allow=false`. App has production APNs/CloudKit, WeatherKit, app group, associated domain and communication/time-sensitive notification entitlements; widget has the app group. iPad Info.plist allows only landscape and requires full screen. Strict `codesign --verify --deep --strict` passed for app and widget. App UUID `47BFA64E-4B9E-3286-9652-D982113CD8B1` and widget UUID `91128856-72B2-338D-8BB1-6A04AC21B7D9` match their respective dSYMs. Both privacy manifests are packaged. No upload or Apple processing receipt exists. |
| Broad phone UI suite | Older discovery run finished: 188 executed, 5 skips, 9 failures. A clean final-source full compact run is in progress | `/Users/natemeadows/Plated/build/phone-ui-current-20261021.log` used the pre-fix app/runner. Its nine failures comprise the real pinned Plan scroll defect, five orientation-leaked paths, two Calendar permission-state paths and one intermittent VoiceOver failure notice. Each has an isolated corrected-source passing retest, but these do not turn the old full run into a pass. The pinned Plan fix and connected date-selection/Tomorrow journeys passed (`Plan-Context-Sticky-Fix2-20261021.xcresult`, `Plan-Context-Connected-20261021.xcresult`). The first post-fix compact run also inherited landscape from an earlier simulator test; it was stopped, preserved as discovery evidence, and restarted with a portrait-reset runner at `/Users/natemeadows/Plated/build/phone-ui-final-compact-portrait-20261021.log`. |

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
2. Finish the broad phone UI suite and any failure repairs, then verify the changed
   paths again. A screenshot/capture pass and a behavioral pass are distinct.
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
