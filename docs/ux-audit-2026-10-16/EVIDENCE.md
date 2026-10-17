# Evidence index

The audit has **26 findings: 10 P1, 14 P2 and 2 P3**. Read the [report](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/REPORT.md) for findings, source references and acceptance checks. Read the [coverage ledger](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/COVERAGE.md) for unexercised states.

Finding 26 was added after the user supplied feedback about Plan’s arrival experience. The existing screenshot and source corroborate the hierarchy problem; no additional usability participants or implementation tests were run for that recommendation.

There are 112 named screenshot PNGs, including five superseded or misdirected captures retained for traceability. This is a count of captures, **not 112 distinct screens or 112 UX passes**. Accessibility trees accompany most screenshots. Export manifests retain the original test attachment names.

## Visual evidence

| Set | Contents |
|---|---|
| [Selected defects](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/key-findings.jpg) | Default thread and groceries; largest-text Table and Plan |
| [Default screens 1](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/default-contact-1.jpg), [2](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/default-contact-2.jpg) | Main roots, creation, editing, planning, social and onboarding routes |
| [Initial large-text survey](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/accessibility-contact-1.jpg) | Accessibility Dynamic Type on core routes |
| [Plan scrolling](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/review-1-1.jpg) | Artwork expansion and offscreen meal names |
| [Additional routes](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/review-2-1.jpg), [household controls](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/review-2-2.jpg) | Month, ingredients, sharing, statistics, crop, filters, planner and household |
| [Additional large-text routes](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/review-3-1.jpg) | Month, share, gathering, people, profile and thread, including scrolled states |
| [Light appearance](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/review-4-1.jpg) | Four roots and scrolled content. Bottom row contains superseded app-only landscape captures; use the full-screen images below. |
| [iPad survey](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/ipad-contact.jpg) | Nine normal-text tablet surfaces |
| [First-run flow](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/first-run-contact-1.jpg) | Welcome, empty cookbook, add/import, saved recipe and planner |
| [Interaction comparisons](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/review-5-1.jpg) | Tab reselection, local Start cooking, and existing-recipe edit loss |
| Full-screen landscape: [Plan/Month](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/screens/landscape-screen-week.png), [Recipes](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/screens/landscape-screen-cookbook.png), [Groceries](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/screens/landscape-screen-groceries.png), [Table](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/screens/landscape-screen-table.png) | Settled rotation at 667×375pt, normal text |

## Run results

| Run | Outcome | Meaning |
|---|---|---|
| Native app/widget build | Succeeded | Build validation, not UX sign-off |
| Design/token checks | Passed | 159 Swift files checked; does not establish accessible runtime layouts |
| `survey` | 6/6 completed | Four first-run interaction tests and two visual capture loops |
| `deep-survey` | 5/6 completed | Additional routes, accessibility diagnostics, light/large text, initial landscape and reselection; recipe input targeting failed |
| `focused` | 1/3 completed | Plan scroll capture succeeded; recipe and cooking targeting failed |
| `ipad-survey` | 1/1 completed | Nine tablet screenshots captured |
| `photo-hit` | 1/1 completed | Coordinate tap focused a field that reported non-hittable; suspected photo interference rejected |
| `visual-confirmation` | 4/4 completed | Repeated additional routes, large text/light, tab reselection and Plan scrolling |
| `interaction-confirmation` | 2/2 completed | Reproduced existing-recipe Cancel loss and local Start cooking opening detail |
| `landscape-confirmation` | 1/1 completed | Correct full-screen rotation captures of all four roots |

The interaction-confirmation assertions intentionally verify the **current defective behavior** to establish the report's evidence. They are audit probes, not desired-behavior regression tests. A future fix should reverse the relevant assertions. Early targeting failures are not counted as product failures.

Apple's automated accessibility diagnostics reported 45 candidate issues across three routes. Several concern underlying hidden tabs, occluded text or noninteractive progress indicators. They were reviewed rather than copied into a defect count. Visually confirmed clipping and independently measured icon contrast are documented in the report. Manual VoiceOver testing remains outstanding.

Successful `.xcresult` bundles, logs and exported attachments remain local. The two failed runs' large partial diagnostic bundles were removed after all attachments were exported and verified. Their logs, manifests and screenshot evidence remain. Test harness files are separate from the production Xcode project.

No native production files were modified. The audit used isolated simulators with in-memory fixtures and did not send live posts, invitations or messages.
