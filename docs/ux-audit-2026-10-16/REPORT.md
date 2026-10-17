# Plated UX/UI audit — 16 October 2026

> Historical pre-repair assessment. See [REPAIRS.md](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/REPAIRS.md) for the subsequently authorized implementation and current verification.

**Assessment: not ready for UX sign-off.** The audit found visible layout failures, inaccessible controls, lost draft content, misleading outcomes and inconsistent shared-household behavior. The visual identity is coherent, but several basic interactions do not yet honor what their labels promise.

**26 findings: 10 P1, 14 P2, 2 P3.** Finding 26 addresses the opening screen’s hierarchy, added after the user supplied qualitative feedback. Findings 01–08 and 25 cover visible/accessibility defects; 09–18 cover lost work and inconsistent outcomes.

Baseline: native app at commit `f8707a1`, current working tree. The existing website changes are outside this audit. No production code was changed. Testing uses isolated simulators and the app’s in-memory preview fixtures; no live household posts, invitations or messages were sent.

This report distinguishes **rendered evidence**, **interaction evidence**, and **source-confirmed branches**. A branch proven in code is not described as reproduced against live iCloud. An audit cannot honestly certify every combination of device, network, permissions, account membership and data as “100% flawless.” The coverage ledger records the boundaries and the remaining device scenarios explicitly.

A selection of captured defects is shown below; the first and last use default text size, the middle two use the largest accessibility size.

![Captured layout defects](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/key-findings.jpg)

Browse the [evidence index](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/EVIDENCE.md) for the full capture sets and interaction results.

## Priority and evidence

- **P1:** fix before UX sign-off; blocks access, loses work, misrepresents sharing, or produces conflicting plans.
- **P2:** significant friction, accessibility or state integrity defect; fix before broad release.
- **P3:** consistency improvement with a usable workaround.
- **Rendered:** screenshot inspected, with an accessibility tree where available.
- **Interaction:** exercised through XCUITest against the installed native build.
- **Source:** exact implementation establishes the failure; its external or exceptional trigger was not injected.

## Findings

### 01 · P1 · Plan rows grow beyond the screen at accessibility text sizes

**Evidence: screenshots, accessibility hierarchy and source; iPhone SE, largest accessibility text.** A Saturday meal row is 717.5pt high, but its title is placed at x=785.5 with a width of 0 on a 375pt screen. Tuesday’s title is at x=892. The photograph grows to match the text height; this steals more text width, causing more wrapping and an even larger photograph. This is a layout feedback loop, not simply a long dish name.

[Scrolled screenshots](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/review-1-1.jpg) · [Accessibility tree](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/screens/ax-plan-tree.txt) · [PlanPhotoStackLayout](/Users/natemeadows/Plated/Plated/Views/Components/PlanFilledMealStack.swift:97).

**Fix:** bound artwork independently of text, and use a vertical or text-first row at accessibility sizes. **Acceptance:** every day, meal name and cook remains inside the viewport and readable at all Dynamic Type sizes, including long names, on 375pt width. Test filled and empty rows independently. Principle: accessible reflow and meaningful visual hierarchy.

### 02 · P1 · Table’s fixed introductory layout breaks large text and landscape

**Evidence: rendered, largest accessibility size.** “Private to your Table” starts above its own panel, overlapping “The Table”; “People” extends underneath the audience selector. The panel reports y=181…355.5, while its title begins at y=137.5 and People extends to y=399.3. The fixed outer vertical arrangement compresses content that requires more height. At normal text size in 667×375pt landscape, the feed begins at y=270 and the tab bar begins around y=313.5, leaving only about 43.5pt of unobscured feed; the first post shows its author but no content. [Landscape screen](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/screens/landscape-screen-table.png).

[Screen](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/screens/ax-table.png) · [Table layout](/Users/natemeadows/Plated/Plated/Views/TableFeedView.swift:420) · [Privacy panel](/Users/natemeadows/Plated/Plated/Views/TableFeedView.swift:809).

**Fix:** put introductory/context content in the scrolling region or give it its full intrinsic height; retain a compact accessible scope control. **Acceptance:** privacy, People, audience selection and the first post never overlap and all remain reachable. Principle: common-region grouping and accessibility.

### 03 · P2 · Edit Profile’s Cancel overlaps its title

**Evidence: rendered.** At the largest text size, the centered two-line “Edit profile” and leading Cancel occupy the same ZStack. The overlap occurs before any editing.

[Screen](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/screens/ax-edit-profile.png) · [Header](/Users/natemeadows/Plated/Plated/Views/PersonProfileView.swift:661).

**Fix:** use a real navigation/toolbar layout or separate rows at large text. **Acceptance:** the title, Cancel and Save have separate space in portrait, landscape and keyboard states. Principle: Fitts’s Law and clear hierarchy.

### 04 · P2 · Table post header breaks ordinary words at normal text size

**Evidence: rendered, default text on iPhone SE.** “Pancake Dinner” becomes “Panca / ke / Dinner” and the author is reduced to “Sam…”. Back, avatar, title, Save, overflow and account all compete in one horizontal row. The comment input is also reduced to “Add a comm…”. At the largest text size, the title breaks into a narrow vertical column and the author/action labels become ellipses; the captured header consumes a substantial portion of the screen.

[Screen](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/screens/21-thread.png) · [Header](/Users/natemeadows/Plated/Plated/Views/PostThreadView.swift:298) · [Composer](/Users/natemeadows/Plated/Plated/Views/PostThreadView.swift:979).

**Fix:** place author/title on a dedicated line; move secondary commands into the menu. Collapse attachment options when the composer is idle or place them on a separate row. **Acceptance:** ordinary names and dish titles remain intelligible at default size; entering a comment gets useful width. Principles: Hick’s Law, proximity, prioritization.

### 05 · P2 · Cooking chrome overwhelms the recipe at large text

**Evidence: rendered.** “Cooking together” truncates to “Co / o…”, the recipe to “Panc…”, and Finish cooking becomes a 150.5pt-high button. The scroll viewport is only 243pt high; the first view shows only “This” from the instructions after the metadata and progress bar. Timer controls lie many scrolls below.

[Screen](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/screens/ax-cooking.png) · [Cooking layout](/Users/natemeadows/Plated/Plated/Views/CookingFocusView.swift:77).

**Fix:** use compact, reflowing session controls; prioritize the instruction and active timer. Keep large text readable rather than globally shrinking it. **Acceptance:** session identity is readable, instructions get the majority of usable height, and the timer and step actions remain easy to reach. Principle: Fitts’s Law and task-focused hierarchy.

### 06 · P2 · Groceries opens on configuration with no shopping items visible

**Evidence: rendered, default text on iPhone SE.** The first viewport contains title, date range, scope, pantry explanation, aisle-order control, footer and tabs—but none of the 17 items. A pricing panel appears before the actual aisles when scrolling, even when its estimate is unavailable. The main task is buried under setup. Landscape also opens with no items visible: most of the view is the title and pinned shopping summary. [Landscape screen](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/screens/landscape-screen-groceries.png).

[Screen](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/screens/03-groceries.png) · [Ordering](/Users/natemeadows/Plated/Plated/Views/GrocerySheet.swift:158) · [Estimate inputs](/Users/natemeadows/Plated/Plated/Views/GrocerySheet.swift:259).

**Fix:** default to the shopping list with a compact scope summary; disclose dates, pantry, aisle ordering and prices through an options panel. Only elevate an estimate when useful data exists. **Acceptance:** a populated list exposes checkable items immediately on the smallest supported phone. Principles: Hick’s Law and progressive disclosure.

### 07 · P1 · Segmented choices lose their individual accessibility names

**Evidence: accessibility trees and source.** Week and Month both expose “Calendar view”; Next 7 days and Pick meals both expose “Grocery scope”; Your Table and Household both expose “Table audience”. Selected state alone does not identify the other choice. A container label is propagated onto the child buttons.

[Plan labels](/Users/natemeadows/Plated/Plated/Views/WeekView.swift:594) · [Grocery labels](/Users/natemeadows/Plated/Plated/Views/GrocerySheet.swift:876) · [Table labels](/Users/natemeadows/Plated/Plated/Views/TableFeedView.swift:938) · [Observed tree](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/screens/03-groceries-tree.txt).

**Fix:** keep each button’s option name, expose group context separately, and retain selected traits. **Acceptance:** VoiceOver announces “Week, selected” and “Month”, with equivalent distinct names for the other groups. Principle: accessible name/role/value and recognition.

### 08 · P2 · Enabled comment attachment controls are too faint in Light mode

**Evidence: source and measured token contrast.** The inactive-looking mention/photo/link icons are enabled controls. `inkFaint` (#A5AD9A) on `canvas` (#FAF9F4) gives **2.20:1**, below the 3:1 non-text contrast benchmark. These controls have no visible text alternative. Dark mode’s equivalent is 3.98:1.

[Controls](/Users/natemeadows/Plated/Plated/Views/PostThreadView.swift:979) · [Measured ratios](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/contrast.json).

**Fix:** use the accessible secondary/active icon color; reserve faint styling for decoration or truly disabled controls. **Acceptance:** all enabled icon-only controls meet at least 3:1 against their actual backgrounds in both appearances. [WCAG non-text contrast explanation](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html).

### 09 · P1 · Editing an existing recipe has no unsaved-work protection

**Evidence: reproduced interaction on iPad, plus source.** Appended “ UX AUDIT” to an existing recipe title, tapped Cancel, and reopened Edit. No discard choice appeared and the original title returned. [Before Cancel](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/screens/recipe-edit-unsaved-value.png) · [Reopened](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/screens/recipe-edit-reopened-original-value.png). `hasDraftContent` is explicitly false whenever `editing != nil`. Both Cancel and interactive sheet dismissal use this predicate. New recipes receive protection, but changes to a saved recipe can be discarded immediately.

[Dirty-state predicate](/Users/natemeadows/Plated/Plated/Views/NewRecipeView.swift:566) · [Dismissal guard](/Users/natemeadows/Plated/Plated/Views/NewRecipeView.swift:489).

**Fix:** compare editable state against an initial snapshot for both new and existing recipes; provide Keep editing/Discard, or persist a clearly identified draft. **Acceptance:** title, ingredients, steps, photo and metadata edits survive accidental dismissal or trigger an explicit discard choice. Principle: user control and error recovery.

### 10 · P1 · “Save draft” loses the Table post’s photo

**Evidence: source.** The composer’s Save draft choice serializes text, options, tags and destination but deliberately omits `photoData`. Reopening restores those other values without the image. The dialog does not disclose this loss.

[Save-draft choice](/Users/natemeadows/Plated/Plated/Views/TableComposerSheet.swift:207) · [Draft serialization](/Users/natemeadows/Plated/Plated/Views/TableComposerSheet.swift:558).

**Fix:** save a managed draft image file and its reference with the draft; retain it until successful posting or explicit discard. **Acceptance:** a photo-only and photo-plus-caption draft reopen with their exact selected photo after dismissal and relaunch. Principle: consistency and preservation of work.

### 11 · P1 · Alternative planning routes ignore shared household occupancy

**Evidence: source.** The regular recipe planner checks `PlanLedger` before placing dinner. Move Meal checks only local `PlannedMeal` rows, and a new recipe’s “Save and plan…” shortcut also finds an open night using only local rows. A night already planned by another household member can therefore be presented as available through these alternate doors.

[Move occupancy](/Users/natemeadows/Plated/Plated/Views/MoveMealSheet.swift:30) · [New-recipe shortcut](/Users/natemeadows/Plated/Plated/Views/NewRecipeView.swift:1048) · [Existing shared check](/Users/natemeadows/Plated/Plated/Views/CookbookView.swift:2351).

**Fix:** centralize occupancy/authority checks and revalidate immediately before committing. **Acceptance:** a remote occupied night is consistently blocked or explicitly resolved in move, drag, picker and save-and-plan routes; no duplicate dinners. Live two-account verification remains required. Principle: consistency and error prevention.

### 12 · P1 · “Start cooking” can take the user to another planning action

**Evidence: local action reproduced on iPad; future/shared branches confirmed in source.** Tapping Plan’s Start cooking opened recipe detail, where another Start cooking button was still required. [Before](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/screens/local-start-cooking-before.png) · [After](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/screens/local-start-cooking-opens-detail.png). A future meal leads to “Change this night”. A shared meal passes no remote meal context, so recipe detail offers “Plan a night” rather than starting that shared dinner; shared serving context is also lost.

[Local button](/Users/natemeadows/Plated/Plated/Views/WeekView.swift:478) · [Shared button](/Users/natemeadows/Plated/Plated/Views/WeekView.swift:568) · [Destination](/Users/natemeadows/Plated/Plated/Views/WeekView.swift:208) · [Detail action rules](/Users/natemeadows/Plated/Plated/Views/CookbookView.swift:1436).

**Fix:** carry the selected meal’s identity, authority, servings and date into a cooking intent; either start/resume directly or label a detail-only route “View recipe”. **Acceptance:** every Start cooking command enters the intended recipe session without replanning it. Principle: Jakob’s Law and action-label consistency.

### 13 · P1 · Sharing a recipe to the Table omits the actual recipe

**Evidence: source.** The share preview promises “Ingredients and method”. `RecipeShare.post` creates a Table post from only title, summary and photo. The Table save flow prefills those same fields, so another person cannot obtain the promised ingredients and steps from this shortcut.

[Promise](/Users/natemeadows/Plated/Plated/Views/Components/RecipeShareSheet.swift:154) · [Payload](/Users/natemeadows/Plated/Plated/Services/RecipeShare.swift:50) · [Save-from-Table](/Users/natemeadows/Plated/Plated/Views/TableFeedView.swift:588).

**Fix:** include a durable recipe snapshot or resolvable recipe attachment and round-trip all promised fields; otherwise relabel the action as sharing a dish photo, with accurate preview copy. **Acceptance:** another invited user can save the shared recipe with ingredients, quantities, servings and method intact. Principle: consistency between promise and outcome.

### 14 · P1 · Share-to-Table claims success without a valid multi-Table destination

**Evidence: source.** The shortcut immediately shows “Saved to your Table” and says it will appear as it syncs. It never offers destination selection. `TableShare.publish` refuses an unassigned new post when multiple writable Tables exist, so waiting does not resolve the missing choice.

[Immediate confirmation](/Users/natemeadows/Plated/Plated/Views/Components/RecipeShareSheet.swift:61) · [Publication guard](/Users/natemeadows/Plated/Plated/Services/TableShare.swift:678).

**Fix:** use the same destination resolution as the normal composer; distinguish Saved locally, Waiting to upload, Shared and Needs a Table. **Acceptance:** zero/one/multiple destination states have a truthful outcome and a visible recovery path. Principle: system-status visibility; timely feedback must remain truthful.

### 15 · P2 · Removed groceries have no recovery, and manual items silently age out

**Evidence: source.** Removing a manual item deletes it; removing a generated ingredient marks it dismissed for the household and hides it. The existing Undo only reverses check-off. Separately, manual items outside the rolling seven-day horizon are hidden even if still unbought, without an expiry explanation.

[Removal](/Users/natemeadows/Plated/Plated/Views/GrocerySheet.swift:517) · [Visibility window](/Users/natemeadows/Plated/Plated/Views/GrocerySheet.swift:87) · [Check-off undo](/Users/natemeadows/Plated/Plated/Views/GrocerySheet.swift:345).

**Fix:** provide a remove undo and a discoverable hidden-items restore; keep outstanding manual items until explicitly completed/removed or make their scope visible. **Acceptance:** an accidental removal is reversible, including on another household phone, and an unbought extra does not unexpectedly disappear after a week. Principle: error recovery and persistence expectations.

### 16 · P2 · Gathering drafts and calendar retries do not preserve what the form shows

**Evidence: source.** Gathering has no dirty-draft dismissal guard. After a Calendar failure, `savedGathering` is reused but edited title, time, location and guest count are not applied to it. Inputs remain editable, and the action has no in-progress state. The UI also claims the gathering is saved without checking a local save outcome.

[Form and dismissal](/Users/natemeadows/Plated/Plated/Views/PlanNightSheet.swift:1679) · [Retry/save](/Users/natemeadows/Plated/Plated/Views/PlanNightSheet.swift:1813) · [Calendar service](/Users/natemeadows/Plated/Plated/Services/CalendarSync.swift:32).

**Fix:** preserve a draft; save locally with an acknowledged result; reapply form edits on retry; expose Calendar permission/error details and prevent repeated in-flight actions. **Acceptance:** dismiss/reopen preserves work, and changing the time after a denied/failed Calendar attempt updates the final event. Principle: recovery, visibility and consistent form behavior.

### 17 · P2 · Several Save/confirmation flows ignore persistence failure

**Evidence: source; storage failure not injected.** Edit Profile checks only the name result, ignores failures saving photo/banner/bio/preferences, clears its draft and closes. PlateAssign shows “Plated for…” and dismisses without checking a durable save. Post Edit ignores its initial `Persist.save` result and can close an unpublished post as though editing succeeded.

[Profile commit](/Users/natemeadows/Plated/Plated/Views/PersonProfileView.swift:795) · [Profile helpers](/Users/natemeadows/Plated/Plated/Views/PersonProfileView.swift:900) · [Planner commit](/Users/natemeadows/Plated/Plated/Views/CookbookView.swift:2363) · [Post edit](/Users/natemeadows/Plated/Plated/Views/PostEditSheet.swift:151).

**Fix:** make each user action one checked local commit; retain the form and draft on failure, and distinguish local persistence from remote synchronization. **Acceptance:** injected disk/store failures never erase the draft or show a success receipt. Principle: truthful feedback and transactional user actions.

### 18 · P1 · Discard after a failed recipe replacement does not restore the original

**Evidence: source; storage failure not injected.** Import → Update existing mutates the live recipe and replaces its ingredients before attempting a save. If saving fails, Discard deletes a pending new recipe only; it does not undo the existing recipe’s mutations. A later context save can persist the supposedly discarded replacement.

[Mutation before commit](/Users/natemeadows/Plated/Plated/Views/RecipeImportSheet.swift:862) · [Discard](/Users/natemeadows/Plated/Plated/Views/RecipeImportSheet.swift:120).

**Fix:** stage the replacement independently and atomically apply it, or restore a complete snapshot on cancel/failure. Avoid a context-wide rollback that discards unrelated work. **Acceptance:** failure → Discard leaves the original recipe, ingredients, source and history unchanged. Principle: user control and error recovery.

### 19 · P2 · A stale widget reports an empty plan rather than uncertainty

**Evidence: source.** After midnight, `aged` retains rolled day rows but clears `tonight`. The Tonight widget then says “Nothing plated yet”, even when the rolled first day is marked planned. After seven days, missing grocery data is also rendered as “Nothing to shop for”. These are claims of absence, not merely stale data.

[Snapshot aging](/Users/natemeadows/Plated/PlatedWidgets/PlatedWidgets.swift:117) · [Tonight empty copy](/Users/natemeadows/Plated/PlatedWidgets/TonightWidget.swift:246) · [Grocery fallback](/Users/natemeadows/Plated/PlatedWidgets/GroceryWidget.swift:49).

**Fix:** represent unknown/stale distinctly, show last-update context, and open the app to refresh. **Acceptance:** clock rollover and delayed refresh never claim “nothing” when the stored data only establishes uncertainty. Principle: visibility and trustworthy status.

### 20 · P2 · Household statistics and sharing awards make unsupported claims

**Evidence: source.** Household “Dinners” counts any past dinner even without `cookedAt`, unlike personal awards. It only queries local meals. “Saved elsewhere” and “Passed around” claim that other people saved your recipe, but their ledger increments on this device when this user saves a Table post, keyed to its author. It is not an inbound save-receipt system.

[Dinner metric](/Users/natemeadows/Plated/Plated/Views/HouseholdStatsView.swift:110) · [Household badge](/Users/natemeadows/Plated/Plated/Views/HouseholdStatsView.swift:148) · [Personal award](/Users/natemeadows/Plated/Plated/Support/Awards.swift:133) · [Local ledger](/Users/natemeadows/Plated/Plated/Support/Awards.swift:329) · [Save increment](/Users/natemeadows/Plated/Plated/Views/TableFeedView.swift:1669).

**Fix:** define whether a number means planned, elapsed or explicitly cooked; include shared authority correctly. Rename local-save metrics or implement real inbound receipts before claiming social proof. **Acceptance:** missing meals, uncooked past meals and another account’s saves produce accurate counts and badges. Principle: truthful feedback and consistent concepts.

### 21 · P3 · Reselecting a tab does not honor “Return to the top”

**Evidence: reproduced interaction, screenshot comparison and source.** Each selected tab advertises Return to the top, but the handlers clear pushed destinations without resetting the root ScrollView. The recipe grid remains at its previous scroll offset. [Before reselecting](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/screens/recipes-scrolled.png) · [After reselecting](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/screens/recipes-reselected.png).

[Promised action](/Users/natemeadows/Plated/Plated/Views/MainShellView.swift:950) · [Recipe handler](/Users/natemeadows/Plated/Plated/Views/CookbookView.swift:431) · [Grocery handler](/Users/natemeadows/Plated/Plated/Views/GrocerySheet.swift:216).

**Fix:** implement root scroll-to-top on reselection and pop where appropriate, or accurately describe a deliberately different behavior. **Acceptance:** repeated selected-tab taps have predictable, consistent results in all four tabs. Principle: Jakob’s Law.

### 22 · P2 · Household cook-day targets fall below the product’s 44pt target

**Evidence: source geometry.** Seven columns with six 6pt gaps and 48pt page gutters leave approximately 41.6pt per day on a 375pt screen. The cells do not independently enforce 44pt width. The grocery price fields also use a 42pt minimum height.

[Cook grid](/Users/natemeadows/Plated/Plated/Views/HouseholdHomeView.swift:1306) · [Price fields](/Users/natemeadows/Plated/Plated/Views/GrocerySheet.swift:306).

**Fix:** use a horizontally scrolling 44pt minimum grid, reduce spacing/gutters only where appropriate, or reflow; increase editable-field targets. **Acceptance:** adjacent actionable targets meet Plated’s 44×44pt design requirement without overlap. This is an Apple/product target, not a claim that WCAG 2.1 AA universally mandates 44pt. Principle: Fitts’s Law.

### 23 · P2 · Household joining can be dismissed while the switch continues

**Evidence: source; live membership switch not exercised.** The join sheet hides its Cancel button while joining but only disables interactive dismissal after seat candidates exist. Before that, a swipe can close the sheet while the asynchronous join/switch continues. A user can lose visibility of a consequential operation and its outcome.

[Dismissal guard](/Users/natemeadows/Plated/Plated/Views/JoinHouseholdSheet.swift:90) · [Joining state](/Users/natemeadows/Plated/Plated/Views/JoinHouseholdSheet.swift:376).

**Fix:** prevent dismissal while the irreversible portion is in flight, or support real cancellation and a persistent operation result. **Acceptance:** slow-network joins and household switches always retain visible progress, failure and completion. Principle: user control and system-status visibility.

### 24 · P3 · Featured widget content opens generic tabs

**Evidence: source.** Cookbook and Table widgets display a particular recipe/post but use generic cookbook/Table URLs. Tapping the item starts a search for the content the user already chose.

[Cookbook URL](/Users/natemeadows/Plated/PlatedWidgets/CookbookWidget.swift:34) · [Table URL](/Users/natemeadows/Plated/PlatedWidgets/TableWidget.swift:30).

**Fix:** include stable item identities in snapshots/deep links and handle deleted/unavailable content with a useful fallback. **Acceptance:** tapping a featured item opens that item. Principle: continuity and recognition rather than recall.

### 25 · P2 · Large-text sheet and profile layouts truncate essential context

**Evidence: rendered at the largest accessibility size on iPhone SE, plus source.** The share title becomes “Choose where it…”, the people sheet becomes “People a…”, and the profile masthead becomes “Your…”. The gathering date loses everything after “Sunday,…”; Guests breaks into “Guest / s”, and Calendar into “Calenda / r”. The profile’s household label and content filters also lose usable width. These are ordinary built-in labels, not unusually long user content.

[Large-text evidence](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/review-3-1.jpg) · [Share header](/Users/natemeadows/Plated/Plated/Views/Components/RecipeShareSheet.swift:37) · [People header](/Users/natemeadows/Plated/Plated/Views/TableSeatsSheet.swift:130) · [Profile masthead](/Users/natemeadows/Plated/Plated/Views/PersonProfileView.swift:385) · [Gathering form](/Users/natemeadows/Plated/Plated/Views/PlanNightSheet.swift:1679).

**Fix:** adopt a shared adaptive header with unrestricted meaningful title wrapping, and move form labels above controls when horizontal space is insufficient. Reflow profile cards/filters and reduce decorative space before reducing content space. **Acceptance:** every sheet identifies its purpose and selected date, and every built-in label remains understandable at all supported text sizes; no mid-word wrapping or ellipsis that removes the distinguishing words. Principle: recognition, proximity and accessible reflow.

### 26 · P2 · Plan opens with calendar mechanics before establishing the main task

**Evidence: user-supplied qualitative feedback, corroborated by the default screenshot and source. Added after the initial audit; this was not independently identified in its first 25 findings.** The feedback describes feeling dropped into a calendar, too much text, weak grouping and uncertainty about where to look. This is one reported experience, not a usability-study result. It applies to arriving at Plan; the separate new-user flow initially opens the empty cookbook.

The existing “At home, tonight.” heading already introduces the day, but the visual order is wordmark/actions → large editorial heading → date → Week/Month and date controls → seven-day strip → Tonight label → large photograph → meal name → cook/servings → primary action. On the captured 375×667pt phone, the name and action are below the first viewport. Multiple labels communicate date context while the meal’s identity and next action arrive late. This supports a hierarchy/grouping diagnosis; the greeting itself is a proposed improvement, not a proven solution.

[Default Plan screen](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/evidence/screens/01-plan.png) · [Root ordering](/Users/natemeadows/Plated/Plated/Views/WeekView.swift:159) · [Featured meal ordering](/Users/natemeadows/Plated/Plated/Views/WeekView.swift:442) · [Current heading](/Users/natemeadows/Plated/Plated/Views/WeekView.swift:675).

**Recommended direction:** keep Plan as one of the four destinations, but make its initial view lead with tonight. Replace the current large introductory heading with a compact personal greeting such as “Hi Nate”, using the real profile name and a neutral fallback. Group Tonight, meal name, bounded photo, cook/time information and one primary action into one clear region. Put a quieter “Coming up” section beneath it and provide a discoverable Calendar entry for deliberate date planning. Greeting copy must replace existing introductory text rather than add another stacked heading. Use spacing and a subtle boundary for the main meal region; avoid giving every item equal card emphasis.

For an empty night, the same primary region should say “What’s for dinner?” and offer Plan tonight. For an active session it should offer Resume cooking; after completion it should accurately show the cooked state. Calendar selection must still clearly identify dates other than today and provide a route back to tonight. Essential status or failure messages must remain visible.

This direction intentionally revisits the current [design specification](/Users/natemeadows/Plated/DESIGN.md:85), which pins calendar controls above tonight. It is a proposed design change, not an implementation change or a claim that the current code violates that rule.

**Acceptance:** at default text size on the smallest supported phone, a populated opening view exposes the meal identity and primary action without scrolling. At accessibility sizes the same reading order remains intact with usable scrolling. Run a brief first-impression/task test: can participants identify what is happening tonight, who is cooking and what they can do next; can they then find another date? Verify empty, planned, shared, cooking and completed states. Preserve access to deliberate planning while removing the need to interpret calendar controls before understanding dinner.

Principles: [common region](https://lawsofux.com/law-of-common-region/) supports clear grouping; [Hick’s Law](https://lawsofux.com/hicks-law/) supports reducing competing initial choices. These explain the proposed direction; testing must establish whether it improves this app’s experience.

## What is already working

The fresh app/widget build and design-token checks passed. Four first-run interaction tests passed, covering local entry, manual recipe creation, pasted recipe import/review/save, adding ingredients, opening the planner, Cancel and invalid invitation handling. Welcome and first-recipe actions remain reachable at the largest accessibility text size. The regular recipe planner already has a remote-occupancy guard; pending Table publication and several sharing errors are represented explicitly. These are patterns to reuse across the inconsistent shortcuts.

The standard text palettes are healthy: secondary text is 5.44:1 in Light and 8.42:1 in Editorial; the primary-action label is 5.49:1. The light-mode enabled attachment icons are the specific contrast exception recorded above. Normal-size iPad screenshots give the main screens useful space; they do not clear split-screen or large-type tablet states.

## Design direction

Preserve the editorial type, warm surfaces, consistent palette and four-tab structure. The audit does not justify a wholesale visual redesign. It does justify clearer opening-screen hierarchy (finding 26), a shared adaptive header pattern, a consistent draft lifecycle, a common planning-occupancy service and one honest action-result model.

The strongest visual improvements are structural: protect content width; move low-frequency setup away from the main task; let large text reflow instead of compressing it; reserve pinned space for controls necessary now. Enlarging every piece independently is not equivalent to making a screen accessible.

## Apply the Laws of UX carefully

This audit uses Jon Yablonski’s author-maintained framework associated with O’Reilly’s [Laws of UX](https://lawsofux.com/book/), alongside Apple’s native interface guidance and accessibility standards. These principles guide diagnosis; they do not prove a product defect or replace user testing.

| Principle | Applied to Plated |
|---|---|
| [Fitts’s Law](https://lawsofux.com/fittss-law/) | Separate reachable controls; protect targets and usable content space in cooking, cook-day assignment and compact headers. |
| [Hick’s Law](https://lawsofux.com/hicks-law/) | Disclose grocery setup and secondary post controls when needed; keep the immediate task obvious. |
| [Jakob’s Law](https://lawsofux.com/jakobs-law/) | Preserve familiar save, discard, tab and deep-link expectations; make Start cooking perform the named action. |
| Common region and proximity | Text must stay inside the panel that explains it; grouped controls must retain readable individual names. |
| Doherty threshold / responsive feedback | Acknowledge work promptly with real saving/uploading/error states; speed is not a reason to fabricate success. No latency benchmark was measured here. |
| Peak-end rule | Ending editing, importing, posting or cooking must leave the user with a correct, recoverable outcome. |
| Aesthetic-usability effect | A coherent visual style can mask broken behavior; the screenshots and state audit test the behavior separately. |

[Apple’s design tips](https://developer.apple.com/design/tips/) inform native readability and interaction targets. Contrast assessment uses underlying color values rather than antialiased screenshot pixels. This is an engineering accessibility audit, not a formal WCAG conformance certification.

## Fix order and release gate

1. Establish a clear tonight-first hierarchy for Plan, then repair Plan, Table, Profile, sheet headers and Cooking reflow; remove duplicate accessibility labels. Recheck normal/AX1/AX5, short/tall phone and iPad widths.
2. Preserve existing-recipe edits and complete Table drafts; make import replacement transactional.
3. Unify local/shared planning rules and the cooking intent. Round-trip recipe sharing and resolve Table destinations before promising publication.
4. Make save/retry/undo behavior truthful across Profile, Gathering, posts and groceries.
5. Correct widget freshness, social metrics, tab reselection and remaining target/contrast issues.

For each fix, use the acceptance condition in its finding. A release gate should also exercise the outstanding real-device/multi-account scenarios in [COVERAGE.md](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/COVERAGE.md). Do not mark a screen passed solely because it builds or its screenshot hook launches.
