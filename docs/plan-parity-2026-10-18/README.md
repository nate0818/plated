# Plan: approved proposal versus build 43

The user's report was valid. Build 43 included several approved changes but did
not fully implement the Plan proposal. The previous release summary overstated
design completeness. Its passing interaction tests were not a visual parity audit.
Apple's API still reported 43 as latest when this investigation began; the build
installed on the user's phone has not been independently confirmed.

Reference: `docs/design-polish-review-2026-10-18/review.js`, Plan open, planned,
weather/household, and iPad proposals. No changes to the approved reference.

| Approved treatment | Gap in 43 | Correction |
| --- | --- | --- |
| Quiet time-aware greeting and month control | Hi, Nate / generic Calendar | Time-aware greeting and selected month/year, with accessible Calendar label |
| Seven compact dates; today distinct from selection | Fixed widths, edge handles; no separate today cue | Seven fitted tiles at normal phone widths, quieter edges, outline on unselected today |
| One dinner decision and secondary eating-out route | Local open state updated, shared cook-only state still old | Same headline and Choose a meal / Eating out instead on both paths |
| Assigned cook beside practical facts | Shared dinners omitted time/servings | Same compact fact group for local/shared dinners; Assign for an unassigned cook |
| Bounded food imagery | Shared photo ignored matching cookbook image while its own image was unavailable | Use the matching recipe's existing photo as fallback |
| Eating-out state with place action | Plain Add a place plus redundant Edit dinner | A night out, primary Add/change place, secondary Change dinner plan |
| Compact weather unit | Separate heading and old high/low layout | Condition/day/rain grouped beside explicit high/low, preserving official attribution |
| Honest household history | Already renamed and real counts | Retained; no fabricated counts |
| Actor/action rows, secondary event time | Single combined summary; planning events absent | Account-attributed planned/updated events beside recorded cooking/posts, separate time |
| Quiet tomorrow preview | Title-only link | Meal title, cook, available thumbnail, explicit next-day navigation |
| Completed/future next actions | Mostly implemented; shared completion duplicated its status | Retained Start/View/Share semantics and removed repeated shared completion caption |
| Landscape two-column iPad | Implemented | Retained and rechecked after Plan changes |

Production data adaptations: daily weather is explicitly labelled High/Low, not
presented as a current temperature. No “you're caught up” sync claim is inferred
from an empty local activity list. The recent-activity ending states its seven-day
scope. Missing photos remain truthful fallbacks. These are deliberate differences
from illustrative mock data.

Shared eating-out changes use the existing shared record and edit queue. They do
not create a competing local PlannedMeal. Planning activity credits the author or
editor, never the assigned cook, and does not increment cooked-history counts.

## Verification

- **74 logic tests passed, 0 failures**: profile identity, household planning edits,
  and dinner-history rules (`build/plan-parity-final-unit.xcresult`). Includes
  legacy private meals without an author stamp: they belong to the current
  account, never the assigned cook.
- **24 Plan/UI checks passed, 0 failures** (`build/plan-parity-final-ui.xcresult`):
  local/shared/open/completed states in both appearances, weather permission and
  recovery, official Apple attribution on both backgrounds, assignment, failed
  saves, date selection and largest text. These preceded the final compact
  activity-row and private legacy attribution follow-up.
- **iPad orientation check passed** (`build/plan-parity-ipad.xcresult`): all four
  physical orientations retain the horizontal layout, and a typed draft survives
  rotation. Two-column composition was visually inspected. This check preceded
  the final activity timestamp wrapping and next-day accessibility reflow.
- The final activity follow-up initially passed 2 of 3 checks. The largest-text
  check tapped a partly visible actor row whose default tap point was behind the
  bottom navigation. The recording showed Plan remaining open. The test now
  scrolls the tap point above the navigation and asserts the destination. Review
  also caught and fixed timestamp wrapping and the next-day thumbnail squeezing
  “Tomorrow” at largest text.
- **5 final follow-up UI checks passed, 0 failures**
  (`build/plan-parity-activity-verified.xcresult`): ordinary and largest-text
  profile activity, normal and largest-text next-day navigation, and eating-out
  place editing. These use the final source including legacy author attribution,
  timestamp wrapping, the adaptive preview and singular dinner caption. Their
  screenshots were visually inspected.
- The single-dinner history caption now uses singular grammar. No activity or
  count is fabricated from the design mockups.

`results/` contains machine-readable summaries. `captures/` contains unmodified
native test screenshots. Names, photos and preview weather in these captures are
fixtures, not proof of a live household's data. Earlier captures preserve their
actual stage; the final follow-up captures supersede activity and eating-out
caption views.

## Release scope and remaining live checks

Build 44 was archived from a separate clean native checkout. Unrelated
website edits were excluded. Its release gates checked the committed website token
baseline; the working directory's unrelated website palette edits currently
trigger the cross-platform token check and are not part of this native release.

Physical VoiceOver, lock-screen notifications and two-account synchronization
remain unverified in this pass. The user authorized proceeding without the phone.
The simulator profile/photo tests verify local identity handling, not live
CloudKit transport between two accounts. No public App Store release was submitted.

## Released

**TestFlight 1.0.1 (44) is available to all existing Internal and External testers.**
Verified with Apple's API at 2026-10-18 10:36:42 UTC: processing `VALID`, internal
and external states both `IN_BETA_TESTING`. Both groups include build 44; Internal
also retains access to all builds. Automatic tester notifications are enabled.
The published en-US notes were read back and exactly match `TestFlight-notes.txt`.

- [Open TestFlight](https://testflight.apple.com/join/2exAQgYs) and install **44**.
  Installation on the user's disconnected phone has not been verified.
- Native implementation commits: `e8cd43a`, `61e08de`, `575f1f2`.
  Build number, final follow-up test and evidence commit: `48c0ff8`.
  All were pushed to `origin/main` before upload.
- The clean release checkout's native files matched `48c0ff8` exactly. Signed
  archive/export and all release gates succeeded. Both app and widget are build
  44; the exported app declares only the two landscape iPad orientations.
- Preserved archive, debug symbols, exact uploaded IPA and logs:
  `build/release-plan-44/`. Fingerprint and delivery UUID are in
  `results/archive.json`; Apple distribution evidence is in
  `results/distribution.json`.
- The temporary release checkout was archived after artifact preservation. The
  isolated iPad simulator was shut down. Unrelated website edits remain untouched.
