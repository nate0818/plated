# Design implementation recheck — October 18, 2026

The user correctly reported that build 44 did not fully implement the approved proposal. Earlier verification established that actions existed; it did not establish faithful visual implementation. This pass compares native output against the original artifact without changing that artifact to match the code.

Open [the interactive comparison](Design-Implementation-Comparison.html). Choose **Build 44** or **Revised working build**, a screen, and an appearance. The right panel is the original approved renderer. The left is an unmodified simulator screenshot. Single-state captures identify their appearance and coverage. Changing the proposal state does not silently substitute an unrelated native state.

## What was actually missing

| Surface | Correction | Evidence |
| --- | --- | --- |
| Shared framing | 20-point page margins, 12-point cards, 8-point control corners; explicit 20/27/32/33 editorial scales; readable tab labels | Native green/cream screen matrix |
| Plan | Regular editorial dinner headline, bounded 2:1 photography, smaller cook identity; selected-day model, primary/secondary actions preserved | Open, eating out, local/shared, cook-only, cooked and future cases |
| Weather/history | Compact forecast, recorded household counts and real activity preserved | Context and largest-type next-day checks; preview weather labelled honestly |
| Table | Underline filters and quieter bookmark affordance | Green/cream feed captures; actual media proportions retained |
| Create | Left-aligned title, editorial action rows, content-sized sheet | Green/cream captures |
| Composer | Editorial writing prompt, compact attachment pills, full-width accessibility controls | Draft recovery and largest-type attachment interaction |
| Thread | Caption above actions, clear comment order, compact nested replies, rounded composer; remove orphaned deleted comments without deleting their data | Reaction/reply tests and green/cream captures |
| Activity | Unread count beside Mark all read, remove redundant New header | Mark-all-read test; existing grouped reactions and deep links retained |
| Household | Single-row title and gear, bounded cover, smaller unframed people list, compact Invite, verified recent activity | Rotation selection/cancel/save, standard/largest-type captures |
| Profile | Posts / dinners cooked / recipes added; Posts / Recipes / Saved; own-only private collection; smaller milestones, household link below content, household/role identity | Attribution/privacy/count tests; collection navigation and native captures |
| Recipes | Editorial tile titles, compact source/time line, underline tabs and Collections | Library screenshots and filter interaction |
| Recipe detail | Recipe header, bounded hero, grouped facts and available anchors, checkable ingredients | Ingredient toggle and native captures |
| Groceries | Compact date range, solid quick-add field, simpler item/quantity/provenance rows, export in overflow, compact progress and Undo | Quick add/check/Undo test and standard/largest-type captures |
| Cooking | Checkable frozen ingredient list, direct Pause/Resume, persisted paused duration, serialized alert cancellation, completion notes after finishing | Timer/state tests, finish flow, native screenshots |
| iPad | Bounded meal beside context, landscape-only | Both landscape orientations and attempted portrait rotations; typed draft survives |

## Native adaptations and sample differences

- iPad is landscape-only as requested after the original portrait proposal. The original portrait design is deliberately preserved for comparison.
- System status bars, sheet presentation, safe areas and SF Symbols differ from HTML artwork. Controls retain at least 44-point targets and accessibility reflow.
- Native text uses the app’s bundled fonts and semantic colors; the proposal approximates the palette/font rendering in a browser. Original orange is preserved in both appearances.
- Native data remains authoritative: zero histories are not fabricated, no photo is invented, legacy post titles remain visible, optional recipe sections only appear when present, and paused timers retain their real remaining time.
- A daily forecast is labelled High/Low rather than being presented as an observed current temperature. Fake-weather screenshots say Preview weather rather than displaying a counterfeit official attribution.
- “You’re caught up” is not asserted without a reliable sync freshness signal. Existing activity recency and empty states remain explicit.
- Recipe-detail ingredient ticks last for that viewing session. Cooking-mode ticks and paused timers persist in the cooking ledger.
- Navigation shortcuts, tagging, polls, attachments, recipe scaling, grocery export, member management and safety/reporting actions remain reachable. This is not a reduction of those workflows to the illustrative mock data.

## Verification

- Baseline: `build/DesignRecheck-Before.xcresult` — 4 UI tests, 0 failures.
- Revised interaction/state matrix: `build/DesignRecheck-After.xcresult` — 11 passed, 1 expected iPad-only skip on iPhone, 0 failures.
- Regression tests: `build/DesignRecheck-Unit.xcresult` — 50 passed, 0 failures. Includes persisted timer pause, legacy decoding, delayed alarm add/cancel ordering, profile account identity/private recipes, lifetime dinner counts, dinner history, grocery writing, reactions and activity reads.
- iPad: `build/DesignRecheck-iPad.xcresult` — landscape composition and rotation/draft preservation passed.
- Final UI recheck and release status are recorded below when complete.
- `scripts/check-design`, `scripts/check-tokens --native-only`, and `scripts/check-schema` passed. Schema check compares source fields with the recorded deployment manifest; it is not a live CloudKit transaction.
- Native release commands now explicitly check app/widget token consistency. The separately redesigned marketing website has its own palette; default `check-tokens --all` still checks it and has not been weakened.

## Limits

These are isolated simulator records, not Nate or Alessandra’s live account data. Live two-account photo/activity transport, physical-device VoiceOver gestures and lock-screen APNs delivery were not reverified in this pass. No simulator result is presented as proof of those services. The comparison covers the approved 15 surfaces; it is not a claim of zero bugs across every app state.

## Release

Build 45 is prepared locally. Upload/distribution is not yet confirmed.
