# Plated UI review implementation plan

This plan turns the feedback on review screens A01–A62, W01–W27 and X01–X02 into an ordered set of design and product work. The review recorded written feedback on 70 of 91 entries. Eleven were marked “Change”; eight were marked high priority: A01, A14, A15, A18, A20, A28, A30 and A34. “Discuss” items are treated as design questions or discovery work rather than decisions already made.

Progress: The 11 comments marked “Change” now have direct implementation work or an explicit product/API disposition. A01’s swipeable date strip, calendar picker and no-photo fallback are implemented; the date rail now stays pinned while the plan timeline scrolls. A05’s move sheet now explains when un-cooked meals will switch dates. A14 uses aligned single-column recipe rows; A15 previews its recipe and clarifies destinations/outcomes; both are captured. A18’s Table composer and A20’s thread have fresh captures. A28 has a distinct synced household-person banner, subject-aware starting framing and a full-height drag/pinch/zoom/reset crop editor; the edit/crop screenshots are checked and BannerFocus geometry is covered by tests, while direct simulator gesture QA remains open. A34 saves the event to Apple Calendar and says guests must be added there; EventKit does not allow Plated to set attendees, and no public Apple Invites integration surface was found in Apple’s developer documentation. A50’s question composer now makes its private Table audience explicit. A56’s cooking timer can be muted and restarted at the same duration; A59’s serving-aware ingredients sheet and A61’s embedded Groceries clearance are captured. A62 preserves an honest empty activity state and its populated feed is checked with varied local-only review fixtures. A38 uses concise photo setup copy and an opt-in single-contact photo picker; A29 replaces the household-photo metaphor; A37’s calendar motif and A44’s new tagline are captured. Tonight widgets now name the cook without repeating recipe duration and use the household banner photo when available; W04/W09–W11 layout fixes are in source. Prongsby has no user-facing route and its existing message data remains readable. The signed iPhone 17 Pro/iOS 26.5 simulator suite passes all 371 tests. Fresh visual captures now check A01/A05/A14/A15/A18/A20/A28/A30/A34/A37/A38/A44/A50/A54/A56/A59/A61/A62. W04 and W09–W11 still need an installed-family visual check; direct A28 drag/pinch verification remains unavailable while native UI automation reports that the Mac is locked.

## Working principles

- Make the next useful action clear, reduce avoidable user input, and keep layouts calm and aligned.
- Use Apple platform conventions where they improve clarity, accessibility or familiarity. Explore translucency and motion in context; do not add effects at the expense of contrast or legibility.
- Treat Instagram and Reddit as quality references for social usability and content richness. Define Plated’s own table-centered interaction model instead of copying another product’s screens.
- Keep planning, shopping, cooking and household coordination connected, while making each screen understandable on its own.
- Preserve a no-photo path for meals and people. Test empty images, long names, large text, dark appearance, narrow widths and failure states as part of each affected feature.

## Phase 1: high-priority screens and visible defects

Implementation and focused captures are complete for the Change notes and the eight high-priority screens. The row descriptions record the original design target; the progress summary and disposition ledger record completed work and remaining QA.

| Screens | Work | Done when |
| --- | --- | --- |
| A01 Week plan | Rework the date selector as a clear, tactile day/week control and keep it pinned above the scrolling plan. Explore a rounded or rotating treatment and restrained system materials. Define a graceful meal-image fallback. | Date changes are easy to discover and operate; current and selected dates are obvious; the date rail remains visible while the meal timeline scrolls; VoiceOver and large text work; missing meal photography still looks intentional. |
| A14 Recipe picker | Establish a consistent row layout with aligned image crops, left-aligned text and clear hierarchy. Reduce crowding. | Rows share a baseline and image treatment; long titles wrap cleanly; selection is obvious; the primary action remains easy to find. |
| A15 Share recipe | Redesign the share flow around recipient, destination and outcome. | The user can tell what will be shared, with whom, and whether it succeeded; cancel and retry paths are clear. |
| A18 Table feed, A20 Post thread | Redesign feed and thread hierarchy, media, identity, replies and reactions as one coherent social experience. | Posts are easy to scan; author and household context are clear; opening and returning from a thread preserves context; loading, empty and error states are designed. |
| A28 Edit profile | Improve avatar and banner selection, crop/position controls and save feedback. | Both images can be previewed and adjusted before saving; replacing or removing an image is clear; failures do not discard the current profile. |
| A30 Add household member | Make invitations feel direct and understandable, with invitation status and recovery. | The user understands who is invited, how the invite is delivered, and whether it is pending, accepted or expired. |
| A34 Gathering | Improve event setup and assess Apple Calendar and Apple Invites handoffs. | Date, attendees and event details are easy to review; the user knows what gets added or shared; calendar authorization and unavailable-app cases are handled. Verify supported Apple APIs before committing to an Invites-specific integration. |

Also address concrete defects surfaced in review: fix the grocery header/logo overlap on A61; inspect and correct clipping in W04 and grocery widgets W09–W11; remove Prongsby (A54) from navigation, deep links, launch routes and promotional surfaces. Keep existing message records readable for compatibility, and confirm there is no user-facing route to the parked screen.

## Other explicit changes and screen-level checks

| Screen | Outcome | Evidence or remaining check |
| --- | --- | --- |
| A05 Move a meal | Added plain guidance for changing nights and swapping an uncooked dinner. | `qa-captures/A05-move-meal.png` |
| A50 Post a question | Added the private Table audience cue to the question/poll composer. | `qa-captures/A50-post-question.png` |
| A62 Activity | Kept the genuinely empty inbox copy and verified the populated feed with diverse local fixture rows. | `qa-captures/A62-activity.png`; no synthetic rows are written to a real account. |
| W01 Tonight widget | Replaced cooking-duration text with who is cooking. | Widget extension build passed; refreshed family rendering is pending. |
| W02–W03 Tonight imagery | Prefer the household’s shared banner photo; use the meal artwork when the household has not chosen a photo. | App-group snapshot wiring builds; refreshed family rendering is pending. |
| A37 Sign in | Added the requested calendar-day motif behind the floating food and people illustration. | `qa-captures/A37-sign-in-calendar.png`; date card is visible in the fresh simulator image. |
| A44 Launch opener | Updated the line to “Plan. Shop. Cook. Eat. Together.” | `qa-captures/A44-launch-opener.png`; full line is visible in the timed capture. |
| A56 Cooking timer | Added per-timer mute/unmute and restart at the original duration; the restarted countdown and Live Activity share the new end time. Old sessions still decode without the optional fields. | `qa-captures/A56-cooking-timer-controls.png`; two persistence regression tests and the 371-test suite pass. |
| A17 Instacart | The authenticated edge-function handoff and list shaping are implemented; the in-app entry remains hidden until an Instacart partner key is configured and a production partner link is verified. | Ten handler tests pass. Instacart’s developer platform generates a Marketplace shopping-list link for user store selection and checkout; partner access and production approval remain external gates. See [Create a shopping list page](https://docs.instacart.com/developer_platform_api/api/products/create_shopping_list_page) and [Get started](https://docs.instacart.com/developer_platform_api/get_started/overview/). |

The other “Discuss” notes are discovery prompts rather than single, specified changes. The phase tables below preserve the proposed product decisions and the questions that require product direction (catalog, Instacart, social graph, rewards, Plus, calendar, and integrations) rather than implementing speculative features.

## Phase 2: improve core planning, recipes and cooking flows

| Screens | Work | Done when |
| --- | --- | --- |
| A02 Month plan | Explore a month view that pairs the calendar with useful planning and cooking summaries. | Planned, cooked and eating-out counts have clear definitions and time ranges; the calendar remains the main way to navigate. Prototype before committing to a dense analytics dashboard. |
| A03 Day details, A05 Move a meal, A07 Recipe filters, A10 New recipe, A11 Edit recipe, A13 Assign recipe | Review each flow for hierarchy, navigation consistency and unnecessary steps. | The user can understand the selected meal/recipe and complete the main task without losing context; bottom navigation behavior is intentional and consistent. |
| A06 Recipes, A08 Recipe details, A09 Planned recipe, A12 Import recipe | Define how owned, imported, shared and catalog recipes differ. Add source/owner details where needed; explore cooking history and household ratings. | Users can identify recipe provenance and what they may edit; history and ratings use real household data with clear empty states. Treat a broad public catalog as a separate product decision. |
| A17 Groceries, A47–A49 Grocery sheets | Clarify whether planning is date-based or meal-based and let users choose a meaningful start date. Explore an Instacart handoff as a separate integration. | The shopping window follows the chosen date and meal selection; labels describe exactly what is included; the user can review the list before leaving Plated. |
| A45, A55 Cooking; A56 active timer | Ingredients open from a cooking step without losing place; timer now has a per-timer alert mute and same-duration restart. Multi-dish sequencing remains a product question because the current cook session is scoped to one recipe. | Timer mute/restart persistence is tested and visible in a fresh A56 capture. Ingredients have an existing sheet. Multi-dish scheduling needs a clear household model before implementation. |
| A46 Cooking complete, A51 Award detail, A60 Badge detail | Explore a completion moment with an optional award or share-to-Table action. | Celebration is brief, dismissible and tied to an actual accomplishment; sharing is always user initiated. |

## Phase 3: social, onboarding and household product questions

These notes ask whether the experience is optimized but do not specify a single solution. The ledger records safe recommendations; broader product changes should follow focused direction and evidence.

- **Table membership and discovery (A24, A26–A27, A30, A38–A39):** Define following, household membership, suggested people and invitations as distinct relationships. Decide which counts and profile images help users; do not expose contact-derived information without clear consent and privacy review. Test profile avatar and banner editing as part of A28.
- **Posting (A21–A23, A25):** Review post creation, question composition, activity and empty states alongside the Phase 1 feed/thread model. Preserve drafts and make audience and visibility understandable.
- **Onboarding and sign-in (A37–A44, A52):** The sign-in calendar motif, photo setup copy/contact-photo choice, and “Plan. Shop. Cook. Eat. Together.” tagline are implemented and captured. Keep Apple sign-in plus the local continuation path; review the tour as one short story before broad changes.
- **Analytics and monetization (A31–A33, A53):** Decide which household stats and awards help people plan or cook together. Test a clearer Plus value proposition before changing conversion surfaces.
- **Gatherings and Apple support (A34–A36):** Keep the Phase 1 gathering redesign separate from investigation into specific system APIs and permissions.

## Phase 4: widgets, Lock Screen and share extension

- **Tonight widgets (W01–W03, W14–W16):** W01 now says who is cooking; W02–W03 prefer the household banner with meal art fallback. Installed-family verification remains.
- **Grocery widgets (W09–W11, W17–W19):** Source insets are fixed for W09–W11; verify each installed size, then consider count/list hierarchy improvements.
- **Cookbook, Table and turn widgets (W04–W08, W12–W13, W20–W22):** Align content and agree on what each surface is for. Explore warmer, more engaging treatments without adding detail that is hard to read at small sizes.
- **Live timer and Dynamic Island (W23–W27):** Verify live, paused and expired states, including the timer controls decided in Phase 2. Review the layout within actual system presentation after source previews are stable.
- **Share extension (X01–X02):** Improve progress, success and retry feedback so saving a recipe is clear and reassuring.

## Validation and remaining work

The signed iPhone 17 Pro / iOS 26.5 simulator suite passes 371 tests. `make design tokens` passes for all 151 Swift files, all 10 shared widget tokens, and the duplicated timer activity source. Ten Instacart edge-function tests pass. The refreshed ZIP has exactly 91 images and passes its archive integrity check; fresh app captures cover 18 updated screens.

Direct A28 drag/pinch and installed widget family visual checks remain because the native UI automation host reports that the Mac is locked. The original captures also do not cover every dialog, failure permutation, iPad layout, dark appearance or larger accessibility size, so this pass does not claim exhaustive device-matrix QA. Instacart still needs a configured partner key, production access and an end-to-end checkout before the hidden CTA can be enabled.

Discuss notes have a recommendation and rationale in `feedback-dispositions.md`. They are product directions, not silent feature commitments. The remaining decisions concern analytics definitions, recipe provenance/catalog scope, ratings, public discovery, multi-dish sequencing, awards, Plus value, and longer-term widget styling.
