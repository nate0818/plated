# Independent Plan fidelity findings

Reference: unchanged `docs/design-polish-review-2026-10-18/review.js`, `review.css`, and the original standalone review rendered in the browser. Compared with build 45 PNGs under `docs/design-parity-recheck-2026-10-18/after/` and source at `fc87ad1`. This is a source correction report, **not a pass for the revised native output**. No build or UI test was run by this reviewer.

## Evidence inspected

Native: `polish-plan-open-dark`, `polish-plan-dark`, `polish-plan-light`, `polish-plan-eating-out`, `plan-parity-cooked-dark`, `plan-parity-context`, `plan-parity-future`, `polish-plan-AX5`, `polish-ipad-display-3`. Browser-rendered original proposals: open, planned, context. Original proposal CSS/renderer also read for iPad and all Plan variants.

At the proposal's 402-point logical width, browser DOM measurement gives: card x20, width362; content x38,width326; open card y242.84,height290.37; open heading y286.78,height68.65; primary y426.22,height48; planned card y242.84,height437.84; planned title y304.83,height29.70; photo y346.52,height164; cook row y526.51,height38.79; facts y581.31,height17.39; primary y614.69,height48. Native screenshot coordinates are approximate (pixel inspection), not instrumented native frame measurements.

## Confirmed discrepancies and source corrections

1. **Open dinner line composition differed.** Approved `What sounds good` / `tonight?`; build45 `What sounds` / `good tonight?`. Same nominal 33-point size did not establish the approved arrangement. `WeekView.unplannedDinnerTitle` now uses the approved break at ordinary sizes, natural reflow at accessibility sizes, and an unchanged spoken label. Local and remote open dinner paths both use it.
2. **Planned date/title block had an extra 12-point vertical gap.** Native title/photo/CTA were approximately 13–19 points lower than the proposal while outer card top was within roughly4points. The outer featured stack now groups its date/options and title without that redundant gap; open date-to-title keeps10points. Primary48 and photo geometry remain intact pending new capture comparison.
3. **Cook avatar32 vs approved36.** Both resolved and fallback cook identity now use36; identity and assignment remain separate from authorship.
4. **Facts had13-point type/20-point interitem spacing vs approved12/12.** Corrected both; Change servings remains a44-point action.
5. **Completed dinner had blue Undo and no filled confirmation.** Actual build45 screenshot shows iOS-blue Undo, a bare confirmation line, and outlined Share. Local and shared confirmation now use a compact raised surface, checkmark, sage Undo, and date-aware Cooked tonight/Dinner cooked. The root agent owns the global secondary-button fill correction. Persistence and shared Undo error handling unchanged.
6. **Date tile geometry/weight differed.** Native flexible tiles were about50wide, weekday12 medium, date23 medium and an outline around unselected Today. Proposal tiles45×65, weekday11 regular, date23 regular, and a2-point underline for Today. Date tiles now match those values (slightly narrower at compact width to preserve seven visible targets). Dinner dots and selection/VoiceOver semantics retained.
7. **Fixed62-point date viewport clipped at accessibility sizes.** Visible in `polish-plan-AX5.png`. Viewport now measures a hidden label under the same chrome environment, with minimum65, instead of cutting off growing contents. Needs runtime AX check; not yet proven.
8. **History period was loud uppercase microcopy.** Proposal Last7days is12-point sentence case. Corrected that and labels/explanation13→12, inner gaps16→12. Counts stay actual recorded dinners; zero history remains explanatory prose.
9. **Weather allocation differed.** Native icon allocated44 with16gap; proposal32 with10gap. Corrected. Native High78°F occupied the headline and Low61°F a second line; now a compact degree value with explicit High/Low pair beneath, matching the approved information arrangement. The data remains a daily high, and the pair and VoiceOver state that fact; it is not a new observed-current-temperature feature. The real official mark/link remain; preview does not counterfeit Apple attribution.
10. **Household activity did not implement compact actor/action rows.** Build45 gave every person a36-point avatar, standalone15-point name, separate13-point action and third time line, plus an extra period footer. Proposal uses28-point avatar and12-point actor+action on one flow, with secondary day/time. Corrected the anatomy, preserved live photo/identity lookup, one profile action, pending invitations, and actual activity. Restored the small Household chevron and removed the unapproved period footer.
11. **Tomorrow preview was larger than approved.** Native thumbnail52 vs42 and separate meal/cook lines. Corrected42 and combined caption; wraps naturally, retains whole-row44+ tap target and date-selection behavior.
12. **iPad columns were not the approved proportion.** Native context was fixed340 (roughlyone third of the wide composition), with a disproportionately broad meal. Proposal1.12fr/.88fr and26-point gap. Wide composition now preserves56:44 with26gap, rail max465 instead of500. Landscape-only, the existing800breakpoint and one-column AX behavior preserved. Actual new landscape and narrow-window renders must be inspected.

## Shared/systemic issues sent to root

- Global palette values differed from the approved CSS; source token equality only proved native/widget consistency, not design parity.
- Global SecondaryActionStyle outlined controls while approved secondary controls are raised fills.
- Browser computed tab font is15px because `.app button { font: inherit }` overrides the low-specificity10px rule. Match the rendered proposal, not an isolated declaration. Native used13.
- The serif fallback/fixed-optical-size suspicion was **disproved** by root's CoreText check. Native resolves the font and automatic optical sizing. Identical Newsreader TTF SHA256 was also verified. Do not claim the wrapping issue came from a missing font.
- AX5 hero in build45 turns into several single-word lines and a detached question mark, displacing every task control. The shared semantic title scaling is owned by root; do not cap meaningful title text to conceal this problem.
- Prior review accepted palette/font/layout discrepancies generically as “native adaptations” instead of measuring visible result against the actual approval.

## Remaining gaps and required native checks

- Added the compact selected-dinner summary when the measured card bottom passes behind the measured pinned date rail. Both positions are tagged with the selected day and cleared on date change. The pill is in narrow-screen context only; it is absent while the meal remains visible, on wide iPad, and for an empty/being-removed dinner. Pending shared changes say Waiting to sync. No scroll delay or guessed offset is used. Fresh native scrolling and date-change regression checks are still required.
- The original context proposal ends with You're caught up. Current code does not have a reliable positive freshness signal. Do not fabricate that claim; source this state from actual sync completion or leave the implementation gap explicit.
- iPad Tomorrow preview is now below the main column, with the approved View day label,42-point thumbnail and420-point bounded width. This final change still requires native landscape inspection.
- Native weather loading, permission, denied, failed/retry, outside-range, official attribution in both appearances; local/shared/pending/removed/custom dinner; long cook/meal titles; future and cooked states; rotate/narrowiPad; AX date top/bottom bounds; Undo persistence and rollback; return navigation and date-selection after scrolling still require fresh exercise.
- `plan-parity-future.png` is a scrolled context image with weather partly behind the pinned date rail, not evidence of the approved future dinner card or View recipe CTA. Its old use as future-state design proof is invalid.
- Captures use fake forecast and fixture household records. Missing official mark there and different actor/dinner/count values are data differences, not proof that live Apple artwork, household photo transport or two-account activity passed.


## Follow-up from the first revised native captures

Inspected all six actual 402-point renders in `build/fidelity-initial-named` in the main checkout: `fidelity-plan-open-dark/light`, `fidelity-plan-out-dark/light`, and `polish-plan-dark/light`, including their accessibility frame trees. The new open headline has the approved two lines, with a66-point native text frame. Planned title y311 versus proposal y304.83 is substantially explained by the native62-point safe area versus the mock56-point status region; this is not evidence of a remaining seven-point content-gap defect.

The captures still exposed these source defects, now corrected in `WeekView.swift` after that build:

- Open/eating-out microdate used the abbreviated planned-meal format. It now uses the full weekday/month, e.g. Tonight · Sunday, October18. A planned dinner retains the short month, and tomorrow explicitly says Tomorrow. Other unplanned dates use the full date once, without duplicating the weekday.
- Eating out retained a44-point ellipsis row, added No cooking needed, and centered Change dinner plan. Its header now omits that menu, matches the approved description Dinner out is on the plan, uses12-point description type, and left-aligns Change dinner plan. Title plus description form the existing day-detail button, so its compact title is not a33-point-only hit area. The approved7-point heading/description and16-point description/primary gaps are explicit. Secondary actions retain44-point native targets, rather than the mock's36-point minimum.
- Operations are preserved through the existing paths: Change dinner plan opens PlanNightSheet, which keeps editing/removal; the heading opens DayDetailView, whose local dinner actions retain Change, Move and Remove. Existing meal dragging remains. Pending/shared removal still withholds actions and never gains the settled dining-out description. These paths are source-traced, not newly interaction-verified.
- AX frames for Eating out instead, Change dinner plan and Change servings were only16–17points tall despite outer44-point layout frames. Text-action sizing and rectangular content shapes now live inside the Button label. The same correction covers Undo and Edit dinner. New stable identifiers are `plan-eating-out-action` and `plan-change-dinner-action`.

`git diff --check` passes after these edits. No build or test was run by this reviewer. Root's preceding unit run predates these final corrections; it cannot verify them. Fresh native checks must confirm: both appearances, full-date wrapping at compact and AX sizes, eating-out card geometry, ≥44-point accessibility/button bounds, off-text taps near the label edges, Edit/Move/Remove from local and shared day paths, tomorrow's label/action, and date changes after the context summary appears. Live Apple attribution and sync freshness remain separate from fixture captures.


## Additional approved states: source frozen for native verification

Added `FidelityAdditionalStatesTests.swift` with green/cream captures and real UI journeys for: future Plan reached via Tomorrow (full title/photo/action in viewport, selected date, correct View recipe destination and return); empty recorded history; forecast unavailable/retry with the failed fixture retaining the meal; Under30 collection and reset; checked asparagus and Undo; and joined member profile reached from the household roster, with View household navigation. The future test explicitly refuses to repair the old scroll position by swiping down before capturing.

Recipe filtering exposed a missing product state rather than a missing screenshot. The library only had Weeknight (30 minutes or less). At root's authorization, added Under30min as a separate collection (>0 and <30), retained Weeknight's boundary, showed the active non-favorites collection in the first rail position with a clear-filter hint, and added the actual matching count. Existing sample data has five matching recipes, not the illustrative proposal's three. `RecipeDurationFilterTests.swift` covers unknown0 and29/30/31-minute boundaries, preserved Weeknight behavior, and clearing. Product edits are limited to RecipeFilter, the library grid footer, and collection rail; recipe-detail work is untouched.

These new tests have not run. No simulator was launched by this reviewer. Fixture retries deliberately remain failures and do not prove live recovery; member imagery/activity is seeded, not multi-account sync evidence. No additional fixture or product flag was invented for the new captures.
