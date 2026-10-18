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

Validation and release results will be recorded here after completion. Real-device
notification delivery and two-account synchronization remain separate unverified
checks; this work does not claim otherwise.
