# Build 48 candidate: October 22 correction

This is a candidate-quality record, not an assertion that phone alerts work.
Build 48 was subsequently verified available to both TestFlight groups; see
[the distribution record](../testflight-48.md). The
reference is the original approved October 18 design review; Nate's installed
build-47 screenshots are the defect evidence. The candidate starts from
`8907f0b` on `codex/approved-design-fidelity-46` in an isolated worktree.
The [49-row screen/state inventory](screen-state-inventory.md) records both
freshly checked routes and explicit gaps for this incremental beta.

## Changed criteria and evidence

| State | Required result | Evidence | Status |
| --- | --- | --- | --- |
| Compact iPhone, open dinner, Light and Editorial | Dinner decision and cook remain clear; live Apple Weather mark and both seven-day counts/labels fit above bottom tabs | [Cream](captures/plan-open-cream-weather-history.png), [Editorial](captures/plan-open-editorial-weather-history.png), focused native UI assertion | Simulator pass; real forecast/device not checked |
| Plan date selection | Only the selected date's meals appear below the date row; Choose a meal and Eating out are distinct, reachable actions | PlanContext and SelectedDayPlan native UI suites: 22 passed, 0 issues, `Test-UIAudit-2026.10.22_16-24-36--0400.xcresult` | Simulator pass; live shared meal unverified |
| Accepted Table guest before first post | Feed acknowledges an accepted friend and does not suggest inviting someone to an already occupied Table; People uses the same identity filter | TableAudience unit test and native Table entry test | Source/unit pass; live two-account check unavailable |
| Phone alert setup failure | Retry shows progress and a specific outcome; a stale receipt for a different APNs token/account cannot claim this phone is connected; in-app fallback is not suppressed for an unconfirmed device | App logic suite and Settings capture [unregistered fixture](captures/settings-alert-status-cream.png) | Source/simulator pass only; production registration remains broken |

## Known limits

The production notification service previously returned HTTP 403 for phone
registration and had no confirmed installation. The deployed service logs
only a finite rejection code. A later server-only version 6 accepts Apple's
documented privacy-protected caller identity shape; its focused tests and
deployment read-back are in [the release record](../testflight-48.md). No new
phone attempt has verified registration after that change. No push delivery,
current invitation acceptance, or two-way profile/photo/activity sync is
claimed. Physical VoiceOver, the installed
widget, and real Calendar permission behavior remain separate device checks.

The captures use an isolated iPhone 17 Pro simulator on iOS 26.2 with review
fixtures; `Preview weather` marks sample forecast values. The official Apple
Weather artwork in those captures was fetched from WeatherKit, not drawn as a
counterfeit. The camera/photo and household data are fixtures, not Nate's or
Alessandra's accounts. Unchanged screens and the full release inventory have
not yet been recaptured for this candidate. A passing focused test is not full
design acceptance.

## Current check ledger

| Check | Candidate and environment | Result | Limit |
| --- | --- | --- | --- |
| App logic | Candidate source, signed iOS 26.2 simulator, `Test-Plated-2026.10.22_16-14-49--0400.xcresult` | 717 passed, 4 skipped, 0 issues | The skipped tests require live Calendar permission |
| Plan selected day and weather/history | Candidate source, iPhone 17 Pro, Light and Editorial, `Test-UIAudit-2026.10.22_16-24-36--0400.xcresult` | 22 passed, 0 issues | Fixture weather values; actual WeatherKit attribution fetched |
| Table entry and accepted share guest | Candidate source, `TableAudienceTests` and native Table entry | Passed | No two-account CloudKit acceptance or latency proof |
| Design rules, native tokens, schema manifest, diff whitespace | Candidate source | Passed (183 Swift files, 10 shared tokens, 159 recorded fields) | Schema manifest is not live CloudKit data |
| Approved screen matrix | Candidate source, iPhone 17 Pro iOS 26.2, `Test-UIAudit-2026.10.22_16-30-15--0400.xcresult` | 16 passed, 1 expected iPad-only skip, 0 failures | Major proposal routes in both appearances; captured screens still require visual judgement, and untouched variants remain separate |
| iPad landscape Plan | Candidate source, iPad Pro 13-inch iPadOS 27.0, `Test-UIAudit-2026.10.22_16-36-46--0400.xcresult` | 1 passed, 0 failures | Landscape, attempted portrait rotation, two-column Plan and draft preservation in the simulator; split windows not checked |
| Current-OS compact Plan | Candidate source, iPhone 18 Pro iOS 27.0, `Test-UIAudit-2026.10.22_16-38-04--0400.xcresult`, [native capture](captures/plan-open-cream-ios27.png) | 1 passed, 0 failures; visually inspected | Open dinner with official Weather artwork and visible dinner-history labels; fixture forecast values |
| Automated accessibility diagnostics | Candidate source, iPhone 17 Pro iOS 26.2, `Test-UIAudit-2026.10.22_16-38-28--0400.xcresult`; raw [Plan](accessibility-plan.txt), [Groceries](accessibility-groceries.txt), [thread](accessibility-thread.txt) reports | Capture test passed; Groceries returned no issues; Plan and thread each returned one contrast finding | Findings reviewed below; this is not physical VoiceOver proof |
| Real device, two accounts, actual phone push | No connected authorized test session | Not verified | Previously observed registration 403 remains unresolved |

The route/state inventory in `docs/ux-audit-2026-10-16/COVERAGE.md` is historical;
its unexercised variants are not promoted to current passes. This candidate has
fresh evidence only for the rows above and the screenshots linked here. The
remaining inventory must be completed before claiming a full release sign-off.

The Plan diagnostic targets the accessible `Salmon Night` button node whose
reported 334×206-point region includes its photo; the actual visible heading
uses `ink` on `fill` (10.68:1 in Light). The thread diagnostic targets the
`1 hr. ago` label at y=787.8, below its scroll view's visible bottom at
y=775.7; the actual caption color `inkSecondary` on `canvas` measures 5.39:1.
Neither finding establishes low-contrast visible text. The raw reports are
retained rather than silently treating this collect-only probe as a clean pass.
