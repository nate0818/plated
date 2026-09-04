# Plated: UX and UI design review

**Current design direction:** [Original Plated orange, unified app experience, and production acceptance criteria](product-design-direction.md). This supersedes the earlier palette exploration below.
September 4, 2026

**The strongest next version of Plated is a calm, personal kitchen companion: decide what to eat, know what to buy, cook with confidence, and share the result with your people.** The product already has recognizable ingredients. It needs a clearer hierarchy of jobs, a more coherent interaction model, and substantially less visual furniture.

My recommendation is a significant refinement of the product architecture and visual grammar. Keep the name, the warmth, the food, the private Table, and the expressive typography. Reconsider the universal plus, the Home tab, the heavily framed plan rows, the mandatory circular recipe shelf, and the number of decisions between an intention and dinner.

This is a design recommendation, not a set of implemented app changes.

The [follow-up recipe workflow review](recipe-workflow-review.md) examines editing, servings, grocery reconciliation, and the frontend/data contracts in greater depth. It also identifies limitations of the initial visual concept.

## What I examined

- The installed simulator app, version 0.1.0, build 9.0, on an iPhone 17 Pro running iOS 26.2, at 402 × 874 logical points.
- Rendered screens at default and extra-extra-large text sizes, plus additional layouts recorded in the accompanying evidence directory.
- The current SwiftUI screens, shared components, typography and color tokens, routing, onboarding, planning, recipe import, cooking, shopping, household controls, Table, profiles, notifications, and widget implementations.
- `DESIGN.md`, `docs/open-decisions.md`, and older design specifications. The older specifications contain directions that differ from today's app; I treated them as historical context.
- Current Apple design guidance and W3C contrast guidance for the platform and accessibility recommendations.

The repository was clean when I began, at commit `34da5bc`. Screenshots are evidence from the installed build; source findings refer to the current checkout. I did not establish that the installed binary exactly matches this commit. Where that distinction matters, I describe the evidence separately. Existing simulator content includes fixtures; a solid orange post photo and mismatched sample recipe photos are not sufficient evidence of production image failures.

This is an expert review, not a study with representative users. I did not validate cross-account sharing, physical-device haptics, camera/scanner behavior, push delivery, or real-world cooking ergonomics. Proposed task-time targets below are validation criteria, not measured results.

## The six decisions with the highest payoff

| Priority | Decision | Why it matters |
|---|---|---|
| P0 | Make household sharing and assignment promises match the actual data model | People need to know whether their partner can see the plan or has been told to cook. |
| P1 | Organize navigation around **Plan · Recipes · Groceries · Table** | Shopping is a recurring task. Household administration can live behind a consistent avatar entry. |
| P1 | Make an open dinner row open dinner selection, across its entire tappable area | The current split target makes a simple job depend on exactly where the finger lands. |
| P1 | Make tonight actionable, with a direct route into the recipe and cooking | A prominent answer should also offer the obvious next step. |
| P1 | Put recipe search directly on the shelf and simplify meal selection | The current filter sheet hides results behind a large set of controls. |
| P1 | Reduce borders, shadows, nested containers, and crowded header controls | Visual restraint needs fewer competing objects, not just quieter colors. |

P0 means a trust or product-contract issue. P1 means a core workflow or pervasive design issue. P2 means a valuable refinement after the core flow works. P3 means finishing craft. These are priorities, not estimates of engineering effort.

## What to preserve

The warm ink on white has personality without overwhelming food. Gabarito and Plus Jakarta Sans are a recognizable pairing. A small private Table is a stronger proposition than a generic food feed. A dinner linked to a recipe, its servings, and its cook is the right underlying object. Source-aware recipe saving, contextual reminders, and widgets can reduce real work.

The codebase also already contains useful foundations: semantic tokens, a type scale, reduced-motion handling, selected-state accessibility traits, explicit loading/empty/error states on several surfaces, measured sheet sizing, and matched navigation transitions. Preserve and finish these systems. Do not replace them with a new collection of unrelated components.

## 1. Resolve the product promise before polishing its presentation

### 1.1 A shared Table is not yet a shared household plan — P0

The current store uses the account's automatic CloudKit mirror. The onboarding tour explicitly documents that the week reaches the same person's devices, while the Table has a shared zone. Yet the visible Contacts onboarding says **“Nobody sees your plan or your recipes unless you invite them,”** which implies that inviting someone grants access to the plan and recipes. That boundary needs to be explicit. The dormant Plated+ screen makes stronger shared-plan promises, but `PlatedPlus.gatingEnabled` is false, so those claims are a future reactivation issue rather than a currently visible paywall finding.

**Recommendation:** make real shared planning a foundational product milestone. Until it exists, show an accurate, compact boundary such as “Your plan syncs across your devices. Table posts are shared with invitees.” The exact placement should be the household setup, relevant assignment UI, and account status, rather than a warning repeated everywhere.

When shared planning is implemented, design the whole contract: who can edit, who can view groceries, whether a guest can see the plan, what happens offline, what happens when two people change the same dinner, and what happens after someone leaves. Prototype these states before making the promise.

Evidence: [store configuration](../../Plated/Support/PlatedStore.swift#L33), [tour's sharing boundary](../../Plated/Views/Onboarding/TourView.swift#L19), [visible Contacts copy](../../Plated/Views/Onboarding/ContactsView.swift#L88), [dormant Plated+ claims](../../Plated/Views/PersonProfileView.swift#L976).

### 1.2 Assignment needs an understandable social contract — P1

The household cook grid says that nobody is notified. Tapping a weekday cycles through people. Elsewhere a name is presented as tonight's cook. A household can read that as agreement, although the app has only recorded an assignment.

**Recommendation:** tap the cook to open a named person picker, with “Unassigned” and a visible explanation of whether that person can see the change. If requests and acceptance are introduced, distinguish “Assigned,” “Requested,” and “Accepted” only when backed by real events. Avoid a task-management approval ceremony for every meal; use explicit requests where the household needs them.

### 1.3 Define household membership and Table invitations separately — P1

The Table has “Everyone” and “Household,” stacked avatars, a host avatar, and a separate seats sheet. Home has another people list. The user has to infer which group gets which information.

**Recommendation:** one people-management surface with two plainly named sections: “Household” and “Table guests.” Each section should state what members can access. Invitations should state the scope before the invitation is sent. “Everyone” in a private feed should become “All at your Table” if a scope filter is actually necessary.

### 1.4 Avoid a purchase-shaped preview — before reactivation

The dormant Plated+ implementation labels a button “Start Plated+ · $2.99/mo,” then says no payment is taken and activates a preview flag. The explanatory line is helpful, but the main action and its result disagree. Gating is disabled and this entry is parked; this is a source review finding to resolve before exposing it.

**Recommendation:** while this is a preview, use “Try the Plated+ preview” and move hypothetical pricing out of the committing button. Before a real paid launch, define the entitlement and supported collaboration features, then provide the complete purchase, restore, renewal, cancellation, and failure experience. The paid value should be demonstrated in the product before an upgrade screen asks someone to trust it.

## 2. Navigation: give each recurring job a stable home

### Recommended structure

| Destination | Its primary job | Secondary access |
|---|---|---|
| **Plan** | Decide dinner, see tonight, manage the week | Calendar, cook assignment, gatherings, history |
| **Recipes** | Find, save, and reuse dishes | Import, collections, recipe editing |
| **Groceries** | Add, review, and shop a dependable list | Plan range, pantry review, export/share |
| **Table** | Share meals and respond to your people | Guests, activity, polls |
| **Avatar** | Household and personal administration | People, cook rotation, preferences, account, subscription |

This is the preferred concept, not a change to make without validating actual shopping frequency. A lower-scope alternative is to retain today's four destinations while adding a clearly labeled, persistent grocery entry. I would test the four-job version first.

### 2.1 Retire the universal plus as the dominant control — P1

The tomato plus is the strongest persistent affordance on every screen, but it opens three different creation jobs. It does not directly plan a dinner. On a recipe page it competes with “Plan it.”

**Recommendation:** use contextual creation: “Add recipe” on Recipes, “Post” on Table, “Add item” on Groceries, and direct empty-night actions on Plan. Place “Ask the Table” alongside posting within the Table. If a global shortcut survives, make it secondary and ensure its behavior is predictable.

### 2.2 Preserve each destination's place — P1

The installed app loses recipe context when changing tabs: a selected Dinner filter resets, and an open recipe returns to the library root after visiting another tab. The source switches between separate view branches, with navigation and filter state owned locally by each screen. A recipe, search, or day should remain where the user left it after checking another destination.

**Recommendation:** persist a navigation stack, scroll position, and filter state for each tab. Reselecting the current tab can return to its root; changing tabs should preserve context. Verify recipe → groceries → recipe and search → Table → search explicitly.

Evidence: [shell and state ownership](../../Plated/Views/MainShellView.swift#L115), [recipe filter state](../../Plated/Views/CookbookView.swift#L160).

### 2.3 Stop treating tab changes as back-stack navigation — P2

The shell records tab history and attaches a left-edge back gesture. This makes an edge swipe potentially mean “previous tab” as well as “previous page.”

**Recommendation:** keep back navigation within the current destination. Tab changes should be explicit. Prefer the system navigation and tab primitives unless a custom behavior solves a demonstrated problem.

### 2.4 Finish the floating bar as a functional layer — P1

Screenshots show content visible beside and beneath the pill, with the recipe CTA stacked above it. The bar's broad shadow and the content's own shadows accumulate. Removing one row's shadow will not resolve the overall layering.

**Recommendation:** use a consistent system-managed safe area and scroll-edge treatment; account for the bar once. Keep glass on navigation and controls and opaque surfaces behind reading content. Inspect actual lower content, the keyboard, presented sheets, and landscape together. Apple's material guidance treats glass as a distinct functional layer above content: [Materials](https://developer.apple.com/design/human-interface-guidelines/materials).

## 3. Plan: orient the household, then make dinner easy

### 3.1 Rebuild the header around one useful title — P1

“Your week,” the date range, a basket, a bell with a badge, a progress ring, and a host portrait compete across one narrow line. The ring's bare “2” needs interpretation. “HOST” adds hierarchy without helping someone decide dinner.

**Recommendation:** use a small date context and one clear masthead, with one avatar or overflow destination. Put a labeled “2 nights planned” summary alongside the week control, if the household finds that useful. Move groceries to its destination and activity into the Table/account entry. Remove the host caption from everyday chrome.

### 3.2 Keep tonight important; make its prominence functional — P1

Tonight is already the strongest content on Plan. Preserve that. The current tall centered card spends much of its area on an abstract plate and still requires opening a day page to reach the recipe.

**Recommendation:** show the real photo when present, the full dish name, the cook, duration when known, and one context-aware action. Suggested states:

| State | Primary action | Supporting information |
|---|---|---|
| No dinner, recipes available | Choose dinner | A few useful candidates |
| No dinner, no recipes | Add your first recipe | Paste a link or write a dish name |
| Recipe planned for tonight | Start cooking / Open recipe | Cook, servings, duration |
| Already cooking | Continue cooking | Current step and active timer |
| Marked cooked | Add a note | Optional post to Table |
| Eating out / leftovers | Change plan | Show the actual plan, without a cooking CTA |

“Start cooking” should open the existing scrollable recipe in a useful posture. It should not force a separate card deck, require every step to be checked, or trap the user in a mode.

### 3.3 Give an empty night one obvious action — P1

Observed: the plus inside an empty night opens planning; the rest of the row opens a day with “Add a meal,” which then asks for a meal slot. These are different routes inside a row that visually reads as one object.

**Recommendation:** in the dinner-focused Plan list, the whole empty row should open dinner selection. Expose “Day details” as a separate, secondary affordance. Preserve other meal types there. Keep the accessible equivalent equally direct.

Evidence: [split target in the empty row](../../Plated/Views/WeekView.swift#L499), screenshots `17-plan-night` and `17b-meal-menu`.

### 3.4 Replace four weeks of equally framed rows with a clear time model — P1

The current list presents this week's remaining nights and then three more complete weeks. As empty rows accumulate, the screen becomes a long set of unfilled containers. Earlier dates sit above the initial scroll position, so “Your week” does not immediately show the shape of the full week.

**Recommendation:** retain a compact, explicit seven-day overview. Show tonight and the next few dinners below it. Offer “Next week” or a week picker for longer planning, and a clear history entry. Do not require the household to discover that history is above the initial scroll position.

### 3.5 Use a quieter row anatomy — P1

Each row currently contains an outer card, a raised date tile, a circular dish, sometimes an overlapping avatar, and several text weights. The nested elevation makes the date furniture surprisingly loud.

**Recommendation:** use one aligned date column, one food thumbnail, a two-line text group, and a trailing action only when needed. Separate most rows with space or a fine rule. Reserve a container for the active selection or meaningful grouping. Target roughly 72–88 pt at default size, growing naturally with content; do not force that height at large text sizes.

### 3.6 Broaden what counts as a valid dinner — P2

“Eating out” is available; an equally quick path for leftovers, takeaway, a named simple meal, or a night away would reduce pressure to manufacture recipes.

**Recommendation:** add “Quick plan” with a small, stable set of options. Distinguish an intentionally open night from an undecided night. Avoid framing every blank day as an incomplete obligation.

### 3.7 Make month view discoverable without rotating — P2

The month is selected by compact vertical size class. A user with rotation lock can miss it entirely.

**Recommendation:** provide an explicit Week / Month choice, remember it, and adapt its layout to orientation. Landscape is a layout opportunity, not the only navigation mechanism. Keep dates reachable in six-row months rather than shrinking day contents until they become illegible.

## 4. Choosing a meal: show food before showing a menu of methods

### 4.1 Replace the six-option planning gateway with a useful picker — P1

The night sheet offers Pick for me, Choose a recipe, Add a recipe, Eating out, Ask the Table, and Plan a gathering. It is orderly, but the user must select a method before seeing any dinner.

**Recommendation:** open a picker titled “Dinner for Monday, Sep 7.” Put search and a few relevant recipes first. Keep quick-plan alternatives visible beneath the candidates or in a compact secondary menu. Put gatherings and polls where they are needed, rather than making them equal first-step choices every night.

### 4.2 Make suggestions inspectable before they change the plan — P1

“Pick for me” currently takes the top ranked recipe, writes it into the plan, assigns a cook, and dismisses the sheet. The recommendation can be helpful, but the household cannot inspect the choice first.

**Recommendation:** show one recommended dish, a concrete reason such as “25 minutes” or “You haven't cooked this recently,” and “Use this” / “Another idea.” An optional “Surprise me” shortcut can commit immediately if that is explicit and offers undo. Do not assert a dietary or weather match without supporting data.

### 4.3 Make assignment and servings explicit at the right moment — P1

A meal should show its day, slot, servings, and proposed cook together before commitment. Changing an existing dish should preserve the household's chosen cook and servings unless they deliberately change them; the current `plate` path reassigns both from defaults.

**Recommendation:** a compact confirmation area with editable values, then “Add to Monday.” A successful addition returns to the affected date and offers “Undo.” For planning several nights, keep the picker open and advance the date deliberately.

Evidence: [planning actions](../../Plated/Views/PlanNightSheet.swift#L240).

## 5. Recipes: make finding something as good as looking at it

### 5.1 Promote search to the main screen — P1

Search is inside a sheet alongside meal, genre, source, and six sort choices. The results are behind that sheet. The interaction is particularly indirect when the person already knows the dish or ingredient they want.

**Recommendation:** a visible search field on the shelf, with results updating in place. Put sorting behind a concise menu and advanced filters behind a filter button. Active filters should be removable directly above results. Useful quick filters could include Favorites and Under 30 minutes; their usefulness should be tested against real libraries.

### 5.2 Reconsider circular crops as a mandatory library rule — P1

The circular shelf is recognizable, but it crops food aggressively and gives photos and abstract placeholders very different visual weight. Tall food, pans, recipe cards, and full-table photos do not naturally fit a circle.

**Recommendation:** test two directions using the same content:

1. **Editorial shelf, preferred:** 4:3 or gently rounded rectangular photographs, left-aligned names, one concise metadata line. Keep circular dishes for small planning thumbnails and the brand's special moments.
2. **Refined plate shelf:** retain circles, make crop positioning adjustable, reduce shadow spread, use consistent diameters, and align text baselines. This is less disruptive but less flexible.

Neither direction should misrepresent a placeholder as a photo of the recipe. Give recipes without photos a compact, intentional typographic or simple illustrative treatment; a large animated colored disc should not dominate because a photo is missing.

### 5.3 Make recipe identity stronger than metadata — P2

At default size, shelf titles are small and the metadata uses much of the remaining width. Taxonomy values mix effort, equipment, format, and judgments: “Quick & Easy,” “Grill,” “Bowls,” “Healthy,” and “Kids' Pick.”

**Recommendation:** larger recipe names with reliable wrapping; show time plus one useful attribute. Put full categorization in details. Consider separating meal type, preparation method, and household collection instead of treating unlike categories as peers. Avoid an unqualified “Healthy” label as an inferred fact.

### 5.4 Simplify favorites, pins, saves, and collections — P2

The current system offers favorites, pinned ordering, imported/saved source, and “most loved.” That is a lot of organization vocabulary before collections exist.

**Recommendation:** make Favorite mean “we want this again.” Use a small number of user-named collections if research supports them. If pins remain, render a distinct Pinned section so “A to Z” does not appear incorrectly sorted. Source should describe provenance, rather than competing with personal organization.

### 5.5 Keep attribution specific — P2

Show “From Riley's Table,” the originating website, or “Added by you” when those facts exist. A recipe saved from a post should preserve the author and source relationship as structured data. Avoid an invented byline inferred from arbitrary tags.

## 6. Recipe detail and cooking: serve two moments well

### 6.1 Give browsing and cooking different emphases — P1

The current detail page has a large image, title, three-column facts, ingredients, steps, and a fixed action. Useful cooking behavior already exists: selecting a step collapses the hero, enlarges quantities, remembers the cursor, and offers timers.

**Recommendation:** preserve that capability and make it discoverable. Browsing should answer “Do I want to make this?” Cooking should answer “What do I do next?” A direct Start / Continue cooking action should move to the steps and make ingredients easy to revisit, without replacing the whole recipe with mandatory paging.

### 6.2 Do not let the CTA compete with the global bar — P1

The detail screenshot stacks “Plan it” above the persistent tomato plus and four tabs. Both bars consume the bottom of a screen whose reading content is long.

**Recommendation:** one contextual bottom action at a time. A library recipe offers Plan; tonight's recipe offers Start or Continue; completion becomes available in the cooking context. A deliberate cooking focus may simplify navigation while keeping Back/Close and ingredient access obvious. This is an intentional revision of the current always-visible shell.

### 6.3 Remove empty metric furniture — P2

“Effort: Not set” occupies one-third of the facts row in the observed recipe. Servings then appear again immediately above ingredients.

**Recommendation:** render only known facts. Put the editable servings control beside ingredients, and use one concise duration line rather than a rigid three-cell dashboard. Missing effort should not look like unfinished homework.

### 6.4 Bring quantities into the reading line — P2

Ingredient names and quantities sit far apart. During cooking the eye repeatedly travels across the screen to match them.

**Recommendation:** test “2 tbsp butter” or a narrow quantity column immediately beside the ingredient. Use tabular numerals only where alignment is helpful. Preserve ranges and qualifiers such as “to taste.” Preserve the existing decision to avoid meaningless ingredient checkboxes; quantities and clear step context are more useful.

### 6.5 Finish interruptions and timers — P1

Keep the current absolute timer end time and session recovery. Give the active timer an accessible, named surface, state whether it can alert, and make cancellation explicit. A future multi-dish timer should name the recipe and step. Validate interruption, backgrounding, Low Power Mode, screen lock, and returning to another recipe on a physical phone.

### 6.6 Make completion warm and optional — P2

After “Cooked,” offer a small note and an optional photo post. Keep planning, cooking completion, and publishing as separate facts. A person should be able to cook dinner successfully without posting, earning badges, or answering a questionnaire.

## 7. Grocery design deserves its own focused pass

### 7.1 Make shopping the primary job — P1

The observed grocery sheet opens halfway up the screen and shows four items above two large export controls. The dominant action is “Send 13 items to Reminders.” It makes Plated feel like a handoff utility while its own shopping list gets a small viewport.

**Recommendation:** a full-height grocery destination with a legible list, an always-reachable add field, and a compact “More” menu for export and ordering. If most users deliberately shop in Reminders, test that as a separate product strategy rather than giving both models equal weight.

### 7.2 State the shopping range precisely — P1

The sheet says “This week,” but the builder selects the next seven days from today. The Plan header uses a calendar week. On a Friday these are materially different sets of dinners.

**Recommendation:** show the actual date range, for example “Sep 4–10 · 5 meals,” and let people choose which planned meals feed the list. Use the same range vocabulary everywhere.

Evidence: [grocery aggregation window](../../Plated/Services/GroceryListBuilder.swift#L17), [grocery header](../../Plated/Views/GrocerySheet.swift#L54).

### 7.3 Protect the list from surprising disappearance and stale checks — P1

Manual rows are shown only within a rolling age window. Automatic rows carry checked/dismissed status by ingredient name and unit. That can make an old “bought” state difficult to distinguish from a newly required quantity of the same item.

**Recommendation:** manual items remain until checked, removed, or deliberately cleared. Define an explicit shopping session or carry-forward rule. When newly added meals require more of something already checked, show the additional amount and reopen the need visibly. This requires state design, not just row styling.

Evidence: [manual horizon](../../Plated/Views/GrocerySheet.swift#L31), [state carry-forward](../../Plated/Services/GroceryListBuilder.swift#L35).

### 7.4 Make the list explain itself — P2

Show quantity near the name and reveal the source dishes on expansion. The model already records `originTitle`, but the visible row does not use it. Keep aisle grouping and manual additions. Add a compact review for pantry assumptions; omitting a staple should be a known preference, not a silent claim that it is in the cupboard.

### 7.5 Design checking for fingers, motion, and recovery — P2

Use the whole row as the target, with a clearly visible check boundary. Keep checked items in place briefly or collapse them in an explicit Purchased section; do not make neighboring items jump under an ongoing tap. Provide undo after removal and a clear count of remaining items. Keep the quantity legible outdoors and at larger text sizes.

### 7.6 Keep the integration language honest — P2

“Copy list and open Instacart” accurately describes the current action. Preserve that honesty. Put it in the secondary action menu, and retain useful receipt/error feedback for Reminders. Never replace it with “Order groceries” unless a real order is created.

## 8. Import and editing: make the first recipe feel easy

### 8.1 Lead with the source choice and immediate result — P1

The import screen is dominated by a large empty text area. The user sees Paste, Scan, Photos, Read it, and Write it out, without a strong visual distinction between importing a link and pasting recipe text.

**Recommendation:** start with “Paste a recipe link or text,” one clear field, and a contextual import action. Keep Scan, Photo, and Write manually as alternate entrances. Do not inspect the clipboard proactively. Once the person supplies content, show useful progress and then a review of what was extracted.

### 8.2 Show import uncertainty in the review — P1

Preserve the original text and source link. Mark missing title, missing steps, unparsed quantities, and narrowed ranges as review items. The existing parser can reduce “2–3 cloves” to 2; that difference should be visible before saving. Let the user correct a particular field without starting the whole import again.

### 8.3 Put the recipe before its optional administration — P1

The manual editor begins with a large photo well, an additional photo affordance, name, summary, preparation time, cooking time, servings, and categorization before ingredients and steps.

**Recommendation:** start with name, ingredients, and method. Put an optional photo alongside the name or in a smaller attachment row. Follow with servings and time; collapse extra photos, meal/category labels, effort, and notes into “More details.” Import and manual entry should converge on the same review/editor structure.

### 8.4 Saving to the library should not silently add shopping — P1

`addToGroceries` defaults to true in the editor. Saving a recipe is often collecting an idea, not committing to buy its ingredients.

**Recommendation:** grocery additions follow an explicit plan or explicit “Add ingredients to groceries” action. Make “Save recipe,” “Plan meal,” and “Buy ingredients” separate outcomes with useful shortcuts between them. Preserve bulk paste for ingredients and steps; it saves real typing.

### 8.5 Treat drafts as valuable work — P2

The editor and import flow have discard protections; finish that system across the post and poll composers. Persist meaningful drafts through app interruption and navigation. “Discard” should discard; a dismissal should not unexpectedly erase a long recipe. Explain validation beside the missing field, and make the save button's unavailable state understandable.

## 9. Table: keep the intimacy, improve the clarity

### 9.1 Give the Table its name back — P1

In the recorded fixture with five people, the title truncates to “The T…” at default size and “The…” at extra-extra-large. Search, activity, stacked avatars, and a host portrait crowd it out.

**Recommendation:** title plus one membership/account affordance. Put the actual audience in a short secondary line. Move discovery out of this header. The complete title and privacy context should survive long names, more members, and larger text sizes.

### 9.2 Do not use a search icon to mean discovery — P1

The magnifying glass opens Discover, a different content scope, rather than searching the private Table.

**Recommendation:** reserve search for searching the current scope. If discovery survives, name it explicitly and place it in Recipes as an inspiration source with visible provenance. The public/private boundary should never be a surprise after tapping a familiar icon.

### 9.3 Refine feed anatomy and reduce redundant controls — P2

Use a consistent order: author and time, photo, dish name, caption, compact reactions, comments. Preserve the photograph's aspect ratio within practical bounds. Repeating the author's name immediately beneath an already labeled post can often be removed. Test whether a permanent “Add a comment” row is useful on every post in such a small feed; one clear comments entry may be enough.

The orange photo in the simulator is a fixture, not a diagnosed loading bug. For actual loading and missing-photo states, use a bounded placeholder and a retry affordance only when a fetch failed.

### 9.4 Clarify reaction vocabulary — P2

The plate reaction is ownable, but a newcomer may not infer it instantly. Keep an accessible “React” or “Give a plate” label, and use a light first-use explanation. Keep the count absent at zero. Reserve Chef's kiss for a clear, supported event and avoid suggesting food quality is a popularity contest.

### 9.5 Make saving and planning a shared dish different actions — P2

A bookmarked post, a copied recipe, and a planned meal should not collapse into one vague “Save.” Label the result: “Save recipe” or “Save post.” After saving a complete recipe, a secondary “Plan this” continuation can be useful. Incomplete dish posts should not silently become recipes that appear ready to cook.

### 9.6 Strengthen posting and discussion states — P1

Keep camera/library access, caption editing, photo preview, and cancellation. Show the receiving audience beside Post. Preserve drafts and distinguish “Posting,” “Posted,” and “Couldn't post.” Display replies in context with an obvious exit from reply mode, without filling the composer with permanent controls for every possible attachment. Do not let a pending post look delivered indefinitely.

## 10. Household, profiles, and stats: spend space on useful relationships

### 10.1 Replace the empty cover-photo monument — P1

Home opens with a large dashed “Add a photo” banner, then numeric stats, then people. On a household without a cover image, the least useful setup task occupies the most useful space.

**Recommendation:** a compact household identity row, people and roles, then cook schedule. A cover photo can be a personal customization, but should not dominate an unconfigured screen. Apply the same principle to personal profiles.

### 10.2 Make cook rotation a readable schedule — P1

Give each day a full name and current cook in a list or a selected-day panel. Tapping chooses a person from a list instead of cycling invisibly. Explain automatic rotation once, with a preview of who will receive upcoming open nights. Respect opt-outs and unavailability rather than implying least-count assignment is always fair.

### 10.3 Distinguish planned dinners from cooked dinners — P0

The Home summary counts `meals.count` as “Dinners,” while the detailed stats count cooked dinner slots. In the recorded fixture, Home shows 5 Dinners and the stats page shows 0 Dinners. Those can both reflect different facts, but the identical label makes the app look wrong.

**Recommendation:** use explicit terms: “Meals planned” and “Dinners cooked,” with the same range and definition wherever repeated. Count meal slots correctly. A metric deserves space only when the definition is both useful and defensible.

### 10.4 Remove unsupported social proof — P0

The existing open-decisions document identifies “Saved by others” as a local counter that cannot measure saves on another household's device. The current stats screen still uses the label.

**Recommendation:** remove that metric and any badge derived from the unsupported claim until the real event is available. Do not simply make it prettier. If a personal saved-recipes count is useful, give it that precise label.

Evidence: [stats definitions](../../Plated/Views/HouseholdStatsView.swift#L239), [recorded unresolved decision](../open-decisions.md#L49).

### 10.5 Reframe stats as household memory — P2

Six counters and a badge grid make the surface feel gamified, particularly when much of it is zero. More emotionally meaningful content would be a dish cooked again, a favorite from last month, or an actual photo from a good dinner.

**Recommendation:** make useful history primary and badges optional. Hide empty social counters from everyday profiles. Celebrate a milestone once and let it become part of the history, rather than maintaining an achievement dashboard as a household's public face.

### 10.6 Simplify settings anatomy — P2

Settings uses separately outlined cards containing icons, title, explanatory paragraphs, and controls. This spends a lot of vertical space and can squeeze the actual input, as the household-name row demonstrates.

**Recommendation:** grouped native-style rows with short labels, trailing controls, and section-level explanations. Open longer edits on their own page. Put account/sync status where it can be found, but keep transient failures attached to the affected task as well.

## 11. Onboarding: reach a useful dinner sooner

### 11.1 Replace the sequence of introductions with one first success — P1

The route is opener → Apple sign-in → profile → contacts → four-panel tour → app. Individual screens are friendly, but the combined sequence postpones the first useful action.

**Recommendation:** establish necessary identity, then help the person plan tonight or save a recipe. Let them add a photo, invite people, choose regular cook nights, and take a tour later. Existing “Not now” and Skip options are helpful; make the overall path shorter rather than relying on people to skip repeatedly.

An invited guest should see who invited them and what accepting grants, then arrive at that Table. They should not be walked through unrelated host setup first.

### 11.2 Align the illustration language with the mature product — P2

The sign-in screen uses floating emoji faces and food chips. The main product leans on restrained typography and food photography. These feel like different levels of maturity.

**Recommendation:** one art-directed composition of food and people, preferably using the same framing and type language as the real product. Keep motion purposeful and brief. A small brand opener can be delightful; do not make returning users wait through it to check dinner.

### 11.3 Make authentication failure a visible local state — P0

The sign-in implementation allows a non-cancel authentication failure to continue locally. That can be a good resilience choice, but the person is not told the difference.

**Recommendation:** continue with a clear local-mode receipt and a recoverable sign-in entry. Keep local planning available; gate shared actions with an explanation of what is needed. Never let a failed sign-in look like a successful authenticated session.

## 12. The visual system: precise changes, not another coat of styling

### Typography

- **Keep the two font families.** Use Gabarito for major headings and important dish names; Jakarta for reading, controls, and metadata. A new font is a lower-value change than fixing hierarchy.
- **Raise core reading comfort.** Test a 16–17 pt default body and 13–14 pt supporting text; retain 11–12 pt only for genuinely secondary, compact metadata. The current scale has 11, 12, and 13 pt steps before its 15 pt body, so too much of the app can end up below comfortable reading size.
- **Reduce simultaneous boldness.** One major heading, one section weight, and a quieter supporting voice. Repeated bold titles, bold tiny labels, bold pill contents, and bold numbers flatten the hierarchy.
- **Use fewer all-caps eyebrows.** Keep them when they clarify time or section. Remove redundant pairings such as a tiny label that simply restates the title below it.
- **Wrap useful text before shrinking it.** Protect dish names, screen titles, and permission scope. Adaptive header composition should happen before truncation, not only at accessibility categories.
- **Use native, scalable symbol sizing for content icons.** The existing cap-matching helpers have no call sites; do not describe the app as optically matched until those pairs are measured in use.

### Color and contrast

The following ratios were recalculated from the current light-mode tokens using relative luminance. They describe color pairs, not a full WCAG certification of the native app.

| Pair | Ratio | Design implication |
|---|---:|---|
| `inkSecondary` on white canvas | 4.63:1 | Clears 4.5:1, with limited headroom. |
| `inkSecondary` on `fill` | 4.11:1 | Insufficient for normal-size text under the 4.5:1 benchmark. |
| `inkSecondary` on `chipFill` | 4.25:1 | Same issue; evaluate actual use, not the token alone. |
| White on tomato | 3.10:1 | Do not treat this as a universal text-button pairing. Small text needs a stronger pair. |
| Tomato initials on tomato tint | 2.73:1 | Improve identity lettering. |
| Basil initials on basil tint | 2.87:1 | Improve identity lettering. |
| Amber initials on mango tint | 2.98:1 | Improve identity lettering. |
| `hairline` on white | 1.19:1 | Suitable as subtle decoration; not a sufficient sole boundary for an essential control. |

**Recommendation:** use ink initials on colored avatar tints. Keep the tint as identity decoration and the letter readable. Introduce semantic action-text and success-text colors with adequate contrast instead of using raw tomato/basil for every colored word. Aim for 4.5:1 for normal reading text on its actual surface; treat large text separately and do not equate SwiftUI point values mechanically with CSS point sizes. Disabled controls are a standards exception, although their purpose should still be understandable. [W3C contrast guidance](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html).

A warmer canvas is an option, not the core recommendation. If used, keep it very subtle and retest every secondary text and surface pair. The current white canvas can support an excellent result.

### Space, shape, and elevation

- Establish a spacing ladder: 4, 8, 12, 16, 24, 32. Use 20–24 pt page gutters as a starting point, with smaller insets only for genuinely edge-oriented content.
- Align titles, search, image edges, section headings, and row text to deliberate shared lines. Do not align an outer card while its inner content drifts.
- Remove most list-row shadows. A date nested inside a card should not appear to float above a floating row above the page.
- Keep elevation for elements that actually overlap: a sheet, an active drag, navigation chrome, or a focused overlay.
- Use a small radius family with a purpose. Avoid slightly different radii that create no meaningful distinction.
- Replace “circles are always dishes” with a more flexible rule: circles are a recognizable accent and compact identity shape; photographs keep a composition suited to their content.
- Give missing-photo states less area. A missing image is not more important than ingredients, people, or dinner selection.

### Motion, sound, and touch

- Keep the existing named springs and reduced-motion handling. Audit the resulting motion on device rather than introducing new effects at each call site.
- Use one short confirmation for a committed meal or completed action. Avoid indefinite ambient animation on routine screens if it competes with reading or spends energy without helping the task.
- Move focus with the task: after planning, show the affected night; after an error, keep the user at the field; after dismissal, restore the originating control.
- Keep haptic semantics consistent across import/save, favorite/pin, assignment, and removal. Feel the final vocabulary on a phone before standardizing it.
- Preserve matched transitions where they clarify origin, but do not require every utility page and settings transition to zoom. Continuity can also come from consistent placement and preserved context.

## 13. Small details that determine whether the app feels finished

| Detail | Recommendation |
|---|---|
| Dates | Include month/day when ambiguity is possible; honor locale and first weekday. Do not depend on “Monday” alone across long planning ranges. |
| Weather | Offer only supported facts. Use the person's temperature unit; hide unavailable readings cleanly. Ask for location in context. |
| Long names | Test long dishes, household names, people names, and translated strings with realistic content. |
| Empty states | State why it is empty and offer the most useful next action. Distinguish no items, no filter results, unavailable data, and all completed. |
| Loading | Reserve space; avoid blank flashes. For longer waits, add a concise status and recovery path instead of an indefinite unlabeled spinner. |
| Errors | Keep the user's input. Say what failed, whether it saved locally, and what Retry will do. |
| Primary buttons | Consistent height and label grammar; progress should not change the button's width or make the layout jump. |
| Secondary controls | Do not outline every action. Use text or an ordinary toolbar control when the grouping is already clear. |
| Input fields | Persistent labels for meaningful fields; readable placeholder text; correct keyboard and return-key behavior. |
| Quantity editing | Preserve ranges, fractions, units, and qualifiers. Do not imply precision that was not supplied. |
| Shopping toggles | State checked/unchecked audibly, not just visually. Whole-row hit areas should not collide with remove or edit actions. |
| Selection | Use a selected trait and a second visual cue, not color alone. |
| Badges | A real unread count, an earned milestone, or no badge. Remove unexplained zeroes from social surfaces. |
| Destructive actions | Place them in predictable menus; confirm consequential deletions and offer undo for routine reversible changes. |
| Drafts | Recover edits after interruption, including image choice and partially entered recipe steps. |
| Image crops | Let the user choose a focal point when a crop discards important content; keep the source original. |
| Image states | Keep loading, missing, no photo chosen, and failed download visually distinct. |
| Photo controls | Use a stable scrim that remains legible on light photos and in dark appearance. |
| Reduced transparency | Navigation remains distinct from food behind it. Do not depend on blur alone. |
| Large type | Reflow headers early; switch recipe grids to fewer columns; keep the sheet's final action reachable. |
| Focus and VoiceOver | Validate spoken order, custom actions, selected state, navigation return, and modal boundaries on-device. Source labels are a good start, not a completed audit. |
| Rotation | Keep the user's selected date and task; do not reset a recipe or form when the geometry changes. |
| Widgets | Match the app's dinner name, cook, status, and fallback art; deep-link to the relevant dinner/list rather than merely the tab when possible. |
| App icon | Keep the established wordmark; explore layered artwork for supported system appearances as a finishing step. |
| Notifications | Separate social updates from meal reminders. Open the exact relevant object. Do not infer delivery or acknowledgment from local writes. |
| Account transitions | Explain whether the device's existing recipes and household remain after sign-out; that scope is part of user trust. |

## 14. Directions I would deliberately avoid

- A wholesale rebrand before fixing the core flows.
- More bright accent colors, gradients, badges, or floating controls as a substitute for hierarchy.
- A new generic dashboard with arbitrary scores.
- Expanding Discover into a social network before the small private Table works beautifully.
- Bringing the parked Prongsby assistant back as permanent floating chrome. If useful suggestions return, place them at the decision they help with and explain the recommendation.
- Making every user upload a photo, invite contacts, or learn the whole app before planning dinner.
- Adding compulsory ingredient checks or a step-by-step deck that makes ingredients difficult to revisit.
- Automatically hiding genuine errors to preserve a “calm” visual style.

## 15. Deliberate revisions to the existing design rules

These recommendations reconsider several current rules. They should be discussed and documented as product/design decisions, not introduced as accidental exceptions in individual screens.

| Current direction | Proposed revision |
|---|---|
| The plus is the permanent tomato element | One primary action appropriate to the current task; contextual creation. |
| Circles for dishes/planning, rectangles for moments/feed | Preserve circles as an identity accent; allow recipe photos a useful composition. |
| Peers always share container treatment | Peers share interaction semantics and alignment; not every row needs its own container. |
| Every detail opens with a zoom | Use zoom when source continuity helps; standard transitions for utility navigation. |
| Grocery belongs only to the week | Treat shopping as a recurring destination, while keeping its relationship to planned meals explicit. |
| Cooking posture has no explicit entry | Offer a discoverable Start/Continue action while retaining the scrollable, interruption-friendly recipe. |
| A spinner has no words | Brief loading can remain silent; long waits need understandable status and recovery. |

## 16. A practical implementation order

### First: repair trust and remove ambiguity

Resolve sharing copy, planned-versus-cooked counts, unsupported save metrics, local sign-in state, and shopping-range wording. Correct the truncated Table header and lost recipe context after tab changes. Give the empty dinner row one primary outcome. Resolve the Plated+ preview contract before reactivating that feature. These changes improve trust before a visual overhaul.

### Second: prototype the core loop as one experience

Prototype Plan → Choose dinner → Assign → Groceries → Cook → Optional post. Compare the proposed four-job navigation against today's structure. Use real household recipes, including dishes without photos and meals without a full recipe. Test with both the person who plans and the person who receives the plan.

### Third: build the shared visual and interaction system

Implement the header, navigation, search, meal row, recipe tile, action bar, form row, state messages, and token corrections together. A component system should specify behavior as well as appearance: loading, selected, disabled, error, focus, long content, and large text.

### Fourth: finish secondary surfaces and physical-device craft

Bring imports, profiles, people management, settings, stats, discovery, and widgets into the new system. Validate dark appearance, motion, keyboard transitions, haptics, permissions, real sharing, and offline recovery. Update `DESIGN.md` and retire superseded specifications so later work follows one coherent direction.

## 17. How to know the redesign is better

Use the existing app as a baseline and compare both designs on the same tasks. These are proposed acceptance criteria, not claims about measured performance:

- A returning user identifies tonight's dish and cook within about two seconds.
- A known saved recipe can be found without opening a filter sheet.
- An empty dinner row reaches actual recipe choices in one tap.
- A planned dinner reaches the usable recipe in one tap from its main action.
- Groceries is available in one deliberate navigation action and opens with most of the screen devoted to shopping.
- Switching tabs preserves the user's place, draft, or active cooking context.
- Users can explain who can see a plan, a Table post, and an invitation before committing each action.
- Adding or changing a meal produces an understandable grocery update; unchecked manual items do not silently expire.
- The smallest supported phone, default text, extra-extra-large text, accessibility text, light/dark appearance, and landscape all preserve essential content and actions.
- A recipe with no photo, unknown duration, long title, many ingredients, and incomplete imported steps still looks intentional and remains usable.

Observe wrong turns, backtracking, hesitation, accidental actions, and recovery. A more attractive screenshot is useful evidence of visual improvement; smoother completion of the household's real tasks is the evidence that the redesign worked.

## Source and evidence index

- [Design contract](../../DESIGN.md)
- [Recorded open decisions](../open-decisions.md)
- [Theme and components](../../Plated/Support/Theme.swift)
- [Typography](../../Plated/Support/BrandFonts.swift)
- [Navigation shell](../../Plated/Views/MainShellView.swift)
- [Plan](../../Plated/Views/WeekView.swift)
- [Tonight card](../../Plated/Views/Components/TonightCard.swift)
- [Day detail](../../Plated/Views/DayDetailView.swift)
- [Meal planning](../../Plated/Views/PlanNightSheet.swift)
- [Recipe shelf, picker, and detail](../../Plated/Views/CookbookView.swift)
- [Recipe editor](../../Plated/Views/NewRecipeView.swift)
- [Recipe import](../../Plated/Views/RecipeImportSheet.swift)
- [Groceries](../../Plated/Views/GrocerySheet.swift)
- [Grocery aggregation](../../Plated/Services/GroceryListBuilder.swift)
- [Table](../../Plated/Views/TableFeedView.swift)
- [Household](../../Plated/Views/HouseholdHomeView.swift)
- [Profiles, settings, and Plated+](../../Plated/Views/PersonProfileView.swift)
- [Stats](../../Plated/Views/HouseholdStatsView.swift)
- [Apple: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Apple: Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
- [W3C: Understanding contrast minimum](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)

Screenshot coverage and any additional interaction findings are documented in the [evidence notes](evidence.md).
