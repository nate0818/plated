# Plated screen feedback dispositions

This ledger maps every screen/state to its written feedback and current outcome. Original feedback remains in `review-notes.json` and the review document. “Discuss” items are captured here as recommendations or explicit dependencies instead of being treated as approved new product scope. The all-screen ZIP prefers updated QA captures when available; unchanged entries retain the original source images.

| ID | Screen/state | Review label | Resolution / QA status |
| --- | --- | --- | --- |
| A01 | Week plan | Change · High | Implemented; no-photo fallback, swipeable dates and picker are captured. Follow-up on Oct 16: moved the date rail into the fixed header so it stays visible as the meal timeline scrolls; verified live in the iOS 26.5 QA simulator. |
| A02 | Month plan | Discuss · Medium | Recommendation: keep the calendar primary and add a few clearly defined planned/cooked/eating-out summaries only after metric definitions are agreed. |
| A03 | Day details | Discuss · Medium | Implemented and verified live on iPhone 17 Pro / iOS 26.5: retains the selected date, meal, cook, and clear back action; the bottom Plan/Recipes/Add/Groceries/Table bar now remains visible while viewing a day. Day cards now include the planned recipe description beneath time and cook details. The latest simulator capture is in the ZIP, overview, and review document. |
| A04 | Plan a night | Keep | No specific note; retained in review set. |
| A05 | Move a meal | Change · Medium | Implemented; the move sheet explains night changes and the swap behavior for uncooked meals. |
| A06 | Recipes | Discuss · Medium | Recommendation: keep source/ownership visible for imported and shared recipes; treat a public catalog as a separately scoped product. |
| A07 | Recipe filters | Discuss · Medium | No specific defect was identified; include in a later recipe shelf critique rather than changing behavior without a target. |
| A08 | Recipe details | Discuss · Medium | Recommendation: show cooking history only from verified household cook events; make ratings optional and household-scoped. |
| A09 | Planned recipe | Discuss · Medium | Recommendation: use deterministic serving scaling and author-provided timings; do not let AI silently alter effort or quantities. |
| A10 | New recipe | Discuss · Medium | Keep prep time optional and editable. Recipe import already extracts recipe content; avoid guessed durations when the source is ambiguous. |
| A11 | Edit recipe | Discuss · Medium | General optimization request; preserve current validated editor behavior pending a concrete usability finding. |
| A12 | Import recipe | Discuss · no written note | No written note; screen retained in the 91-state review set. |
| A13 | Assign recipe to a night | Discuss · Medium | General optimization request; no missing control or task was specified. |
| A14 | Recipe picker | Change · High | Implemented; aligned single-column recipe rows and clear selection affordances are captured. |
| A15 | Share recipe | Change · High | Implemented; recipe preview and distinct share destinations/outcomes are captured. |
| A16 | Cooking without written steps | Discuss · no written note | No written note; screen retained in the 91-state review set. |
| A17 | Groceries | Discuss · Medium | Authenticated server-side Instacart handoff is implemented and tested. CTA stays hidden until the partner key and production approval are configured; no real partner checkout has been verified. |
| A18 | Table feed | Change · High | Implemented; the invite-only feed has Everyone/Household scopes, photo-first cards, author/source/time, plates and comment entry, audience/privacy door, question posts, refresh/retry, edit/delete, and delivery status. Fresh capture checked. It follows small-group conversation patterns; public ranking/follower-growth patterns are intentionally excluded by the product contract. |
| A19 | Discover | Discuss · no written note | No written note; screen retained in the 91-state review set. |
| A20 | Post thread | Change · High | Implemented; the full dish and author open into a threaded conversation with replies, mentions, photo/link comments, draft recovery, plate/save actions, and a composer ready from “Add a comment.” Fresh capture checked. |
| A21 | Create a post | Discuss · Medium | Use the Table feed/thread treatment as Plated’s own social model; avoid copying Instagram patterns that imply public reach. |
| A22 | Edit post | Discuss · no written note | No written note; screen retained in the 91-state review set. |
| A23 | Ask the Table | Discuss · no written note | No written note; screen retained in the 91-state review set. |
| A24 | Table seats | Discuss · Medium | Household seats and Table invitations have separate, explicit membership paths. An Instagram-style follower graph, broad discovery, or recommendation system is not implemented; those change the privacy model and need a product decision. |
| A25 | Activity | Discuss · no written note | No written note; screen retained in the 91-state review set. |
| A26 | My profile | Discuss · Medium | Profile editor supports avatar and household-person banner editing; avatar photo selection remains opt-in. |
| A27 | Other person profile | Discuss · Medium | Recommendation: show relationship counts only when they clarify a real Table/household task; avoid vanity metrics. |
| A28 | Edit profile | Change · High | Implemented; synced person banner, subject-aware framing, crop drag/pinch/zoom/reset; geometry tests and screenshots pass. Direct gestures still need native interaction QA. |
| A29 | Household | Discuss · Medium | Implemented; replaced the front-door metaphor with direct household-sharing copy. |
| A30 | Add household member | Discuss · High | Implemented; role, shareable invite link and add-by-name path are visible in the fresh capture. |
| A31 | Household statistics | Discuss · no written note | Recommendation: use small, auditable household summaries instead of a dense dashboard until people can act on the numbers. |
| A32 | Awards | Discuss · no written note | No written note; screen retained in the 91-state review set. |
| A33 | Settings | Discuss · no written note | No written note; screen retained in the 91-state review set. |
| A34 | Gathering | Change · High | Implemented; event handoff to Calendar is clear and says guests are added there. EventKit cannot set attendees; no public Apple Invites integration surface was found. |
| A35 | Join household failure | Discuss · Medium | Keep the failure state actionable with retry/return paths; avoid changing invitation semantics without a concrete failure case. |
| A36 | Create menu | Discuss · Medium | General optimization request; preserve the existing create menu until a specific friction point is established. |
| A37 | Sign in | Discuss · Medium | Implemented; added a calendar-day motif behind the sign-in artwork and checked the fresh simulator capture. |
| A38 | Profile setup | Discuss · Medium | Implemented; copy tightened and selecting one contact photo is an explicit user action, with a regular photo fallback. |
| A39 | Contacts onboarding | Discuss · Medium | Explicit add-by-name/invitation paths are implemented. Suggested friends are not implemented; any future suggestions should use opt-in contact discovery or an explicit shared-Table context, not upload or expose an address book by default. |
| A40 | Tour tonight | Discuss · Medium | General tour elevation request; treat the four-card walkthrough as one story and keep its steps concise. |
| A41 | Tour plan ahead | Discuss · Medium | General tour optimization request; no individual control or copy defect was named. |
| A42 | Tour recipes | Discuss · Medium | General tour optimization request; no individual control or copy defect was named. |
| A43 | Tour Table | Discuss · Medium | General tour optimization request; no individual control or copy defect was named. |
| A44 | Launch opener | Discuss · Medium | Implemented; updated to “Plan. Shop. Cook. Eat. Together.” and checked the full timed capture. |
| A45 | Cooking ingredients | Discuss · Medium | Cooking view includes a step-aware ingredient reference and an all-ingredients sheet without losing the current step. |
| A46 | Cooking complete | Discuss · Medium | Recommendation: celebrate only verified cook completions; make any award or Table share brief, optional and user initiated. |
| A47 | Groceries by meal | Discuss · no written note | No written note; screen retained in the 91-state review set. |
| A48 | Grocery meal picker | Discuss · Medium | No written note; screen retained in the 91-state review set. |
| A49 | Grocery shopping options | Discuss · Medium | Grocery shopping already supports a selectable seven-day start and meal filter. Labels describe the selected window; Instacart remains gated by partner setup. |
| A50 | Post a question | Change · Medium | Implemented; Ask the Table now states that the post is visible only to Table members. |
| A51 | Award detail | Discuss · Medium | Recommendation: make award detail warm and useful, but tie progress to defined milestones rather than adding empty gamification. |
| A52 | Apple sign in fallback | Discuss · Medium | Keep Apple Sign in as the primary identity path and preserve the on-device continuation fallback; avoid inventing a second credential system. |
| A53 | Plated Plus | Discuss · Medium | Recommendation: leave Plus conversion claims tied to live entitlements and priced benefits; current copy/product status does not justify stronger sales claims. |
| A54 | Prongsby | Discuss · Medium | Implemented; Prongsby routes and promotion are removed while existing message records remain readable. |
| A55 | Cooking with written steps | Discuss · Medium | Ingredients can be opened mid-step without losing place. Multi-dish sequencing is deferred until a clear household cooking model is defined. |
| A56 | Cooking with active timer | Discuss · Medium | Implemented; each timer can mute/unmute its alert and restart using its original duration. Existing sessions decode; two persistence tests pass. |
| A57 | Household settings | Discuss · no written note | No written note; screen retained in the 91-state review set. |
| A58 | Plan calendar picker | Discuss · Medium | The calendar picker is reached from Week/Month date navigation; retain that context and avoid a second unexplained date picker. |
| A59 | Recipe ingredient sheet | Change · Medium | Implemented; servings context, quantity control and pinned Add to groceries action are captured. |
| A60 | Household badge detail | Discuss · Medium | Recommendation: use real household milestones and avoid badges that reward activity for its own sake. |
| A61 | Grocery shopping date | Discuss · Medium | Implemented; grocery header now clears the status bar in embedded navigation. |
| A62 | Activity with updates | Change · Medium | Implemented; empty inbox remains honest and the populated state was checked using six diverse local-only fixture events. |
| W01 | TonightWidget systemSmall | Discuss · Medium | Installed on the QA Home screen with seeded local data; shows “You’re cooking” without the recipe duration, and the household fallback art stays clear of the title and cook line. |
| W02 | TonightWidget systemMedium | Discuss · Medium | Gallery preview checked with seeded data: uses household-themed illustration when no shared banner exists, never dinner photography; a saved household-banner photo still needs its own fixture to verify. No clipping in preview. |
| W03 | TonightWidget systemLarge | Discuss · Medium | Gallery preview checked with seeded data: uses household-themed illustration when no shared banner exists, never dinner photography; a saved household-banner photo still needs its own fixture to verify. No clipping in preview. |
| W04 | TableWidget systemSmall | Discuss · Medium | Populated preview checked; dish, title, and author fit without clipping. Insets and author credit are retained; crowded reaction counts stay out. |
| W05 | TableWidget systemMedium | Discuss · no written note | No written note; screen retained in the 91-state review set. |
| W06 | TableWidget systemLarge | Discuss · no written note | No written note; screen retained in the 91-state review set. |
| W07 | CookbookWidget systemSmall | Discuss · no written note | No written note; screen retained in the 91-state review set. |
| W08 | CookbookWidget systemMedium | Discuss · Medium | Populated gallery preview checked; favorite recipe, photo, and cook time fit. The note “weak” remains a general design reaction without a specific behavior request. |
| W09 | GroceryWidget systemSmall | Discuss · Medium | Populated 17-item preview checked; count, progress, and label fit without clipping. |
| W10 | GroceryWidget systemMedium | Discuss · Medium | Populated 17-item preview checked; count, first four items, and “+ more” fit without clipping. |
| W11 | GroceryWidget systemLarge | Discuss · Medium | Populated 17-item preview checked; nine rows and “+ 8 more” fit without clipping. |
| W12 | CookTurnWidget systemSmall | Discuss · Medium | General style reaction only; no concrete task requested. Keep text legible at system family sizes. |
| W13 | CookTurnWidget systemMedium | Discuss · Medium | General “more fun” request; reserve for a coordinated widget visual design pass. |
| W14 | TonightLock accessoryInline | Discuss · no written note | No written note; screen retained in the 91-state review set. |
| W15 | TonightLock accessoryCircular | Discuss · Medium | General consumer design request across Lock Screen layouts; no specific content change was stated. |
| W16 | TonightLock accessoryRectangular | Discuss · Medium | General consumer design request across Lock Screen layouts; no specific content change was stated. |
| W17 | GroceryLock accessoryInline | Discuss · Medium | General consumer design request across Lock Screen layouts; no specific content change was stated. |
| W18 | GroceryLock accessoryCircular | Discuss · Medium | General consumer design request across Lock Screen layouts; no specific content change was stated. |
| W19 | GroceryLock accessoryRectangular | Discuss · Medium | General consumer design request across Lock Screen layouts; no specific content change was stated. |
| W20 | CookTurnLock accessoryInline | Discuss · Medium | General consumer design request across Lock Screen layouts; no specific content change was stated. |
| W21 | CookTurnLock accessoryCircular | Discuss · Medium | General consumer design request across Lock Screen layouts; no specific content change was stated. |
| W22 | CookTurnLock accessoryRectangular | Discuss · Medium | General consumer design request across Lock Screen layouts; no specific content change was stated. |
| W23 | Cook timer live activity | Discuss · no written note | No written note; screen retained in the 91-state review set. |
| W24 | Cook timer expired | Discuss · no written note | No written note; screen retained in the 91-state review set. |
| W25 | Dynamic Island expanded layout | Discuss · no written note | No written note; screen retained in the 91-state review set. |
| W26 | Dynamic Island compact layout | Discuss · no written note | No written note; screen retained in the 91-state review set. |
| W27 | Dynamic Island minimal layout | Discuss · no written note | No written note; screen retained in the 91-state review set. |
| X01 | Share extension sending | Discuss · Medium | General visual-improvement request; sending state already communicates progress. Revisit animation/branding only with a concrete interaction goal. |
| X02 | Share extension saved | Discuss · Medium | General visual-improvement request; saved state already confirms completion. Preserve that clear success feedback. |
