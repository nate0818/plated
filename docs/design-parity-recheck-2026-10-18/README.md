# Design implementation recheck — October 18, 2026

The user correctly reported that build 44 did not fully implement the approved proposal. Earlier verification established that actions existed; it did not establish faithful visual implementation. This pass compares native output against the original artifact without changing that artifact to match the code.

Open [the interactive comparison](Design-Implementation-Comparison.html). Choose **Build 44** or **Build 45**, a screen, and an appearance. The right panel is the original approved renderer. The left is an unmodified simulator screenshot. Single-state captures identify their appearance and coverage. Changing the proposal state does not silently substitute an unrelated native state.

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
| Recipe detail | Recipe header, bounded hero, grouped facts and available anchors, checkable ingredients and solid bottom action area | Ingredient toggle and native captures |
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
- Final screen/interactions: `build/DesignRecheck-FinalUI.xcresult` — 10 passed, 1 stale test expectation failed. The failure expected the superseded “Hi, Nate” greeting; the tab-visibility test now checks the actual dinner card and is rerun in the release UI bundle. Comment likes/unlikes, replies, cookbook-save routing, largest-type reactions, grocery Undo and ingredient toggling passed.
- The comment accessibility audit returned no issues for contrast, hit region, sufficient description and text clipping. Its raw report is `comment-accessibility-audit.txt`; this is not a physical VoiceOver result.
- Visual inspection of largest-type Household found words wrapping vertically despite the earlier navigation test passing. People/count and Invite/options now reflow separately. New assertions check the control and heading proportions and exercise Invite.
- Final targeted release UI recheck: `build/DesignRecheck-ReleaseUI.xcresult` — 7 passed, 0 failures. Includes the corrected tab-visibility assertion, largest-type Household/Invite and cooking Pause/Resume, Profile collections, completion notes, Plan eating-out/cook assignment, and selected-day context. Native screenshots were inspected after the tests.
- Final recipe screen: `build/DesignRecheck-RecipeFinal.xcresult` — passed both appearances using a clean simulator build from release source `aea845b`. Visual inspection confirmed that content no longer shows beneath the bottom action area.
- Final iPad recheck: `build/DesignRecheck-iPad-Final.xcresult` — passed both landscape orientations, attempted portrait rotations and draft preservation.
- `scripts/check-design`, `scripts/check-tokens --native-only`, and `scripts/check-schema` passed. Schema check compares source fields with the recorded deployment manifest; it is not a live CloudKit transaction.
- Native release commands now explicitly check app/widget token consistency. The separately redesigned marketing website has its own palette; default `check-tokens --all` still checks it and has not been weakened.

## Limits

These are isolated simulator records, not Nate or Alessandra’s live account data. Live two-account photo/activity transport, physical-device VoiceOver gestures and lock-screen APNs delivery were not reverified in this pass. No simulator result is presented as proof of those services. The comparison covers the approved 15 surfaces; it is not a claim of zero bugs across every app state.

## Release

Build 45 has been archived and exported from clean source `aea845b75ec14978a522ecd682dc9c2722467c28`. The exported app and widget are signed, non-debuggable and both build 45; APNs and CloudKit use Production. The app binary UUID matches its preserved dSYM. Apple accepted the upload with no errors. App Store Connect reports VALID, with Internal and External both IN_BETA_TESTING. Both existing groups include build 45, automatic tester notification is enabled, and the previous build has no individually assigned testers to carry forward. Tester notes were saved and read back successfully. See `release-verification.json` for the exact receipt and check time.

Install/update through [TestFlight](https://testflight.apple.com/join/2exAQgYs); confirm version **1.0.1 (45)**.

Exact archive, export, logs and verification are preserved in `build/release-design-45/`. IPA SHA-256: `b0b0a063bf02b753f69f7a6c8294396cca56250617787f64c7e4e8a71a77da03`.
