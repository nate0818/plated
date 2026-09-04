# Plated design review: evidence and coverage

Captured September 4, 2026 from the installed simulator app, version 0.1.0 build 9.0. Device: iPhone 17 Pro, iOS 26.2; 402 × 874 logical points. Source review used repository commit `34da5bc`; the installed binary was not proven to match that commit exactly.

The screenshots contain existing sample content. Orange placeholder photography and recipe/photo mismatches are fixture limitations; they were not treated as production failures. No posts, invitations, purchases, or recipe edits were submitted. Simulator appearance and text size were restored to their original settings: light and extra-extra-large.

## Main rendered surfaces

| Surface | Default text size | Extra-extra-large or dark |
|---|---|---|
| Plan | [Plan](screens/06-plan-default.png), [day](screens/07-day-default.png) | [Large text](screens/01-plan-xxl.png), [dark](screens/30-plan-dark.png) |
| Recipes | [Library](screens/09-recipes-default.png), [filters](screens/10-search-default.png) | [Large text](screens/03-recipes-xxl.png), [dark](screens/31-recipes-dark.png) |
| Recipe | [Detail](screens/11-recipe-default.png), [ingredients](screens/12-recipe-ingredients.png) | [Dark detail](screens/36-recipe-before-switch.png) |
| Table | [Feed](screens/13-table-default.png), [Discover](screens/14-discover-default.png) | [Large text](screens/02-table-xxl.png), [dark](screens/32-table-dark.png) |
| Household | [Home](screens/15-household-default.png), [settings](screens/16-settings-default.png) | [Large text](screens/04-home-xxl.png), [dark](screens/33-household-dark.png) |
| Groceries | [Shopping sheet](screens/08-groceries-default.png) | — |
| Creation | [Import](screens/19-import.png), [recipe editor](screens/20-editor.png) | [Global creation sheet](screens/05-create-xxl.png) |
| Planning | [Empty day](screens/17-plan-night.png), [meal-slot menu](screens/17b-meal-menu.png) | — |
| People | [Seats](screens/22-seats.png), [profile](screens/23-profile.png), [profile setup](screens/24-profile-setup.png) | — |
| Onboarding | [Contacts](screens/25-contacts.png), [tour](screens/26-tour.png), [sign-in](screens/27-sign-in.png) | — |
| Statistics | [Stats](screens/21-stats.png) | — |

## Interaction findings

**Recipe filters reset on tab changes.** The Dinner filter was visibly selected, then another destination was opened, then Recipes was revisited. The selected filter was gone. Compare [before](screens/34-filter-selected.png) with [after](screens/35-filter-return.png).

**Open recipes lose their place on tab changes.** A recipe detail was opened, another destination visited, then Recipes revisited. The library root appeared instead of the recipe. Compare [before](screens/36-recipe-before-switch.png) with [after](screens/37-recipe-return.png).

**Empty-night tap behavior depends on the target.** The row body opened a day screen, where adding a meal presented meal slots. The plus affordance has a more direct dinner-planning path in source. The recommendation is to make the primary dinner row consistently open dinner selection.

**The Table title is truncated in both tested text sizes.** The header competes with Discover, activity, stacked people, and the host avatar. This is visible in both light and dark captures.

**The household dinner count and stats dinner count use different meanings.** Home showed five “Dinners” while Stats showed zero. Source inspection shows planned meals and cooked dinner slots respectively. This is a labeling issue; the two counts should not be described identically.

**Contacts onboarding implies broader sharing than the current data boundary.** The captured copy refers to plan and recipe visibility after inviting someone. Source inspection distinguishes personal CloudKit mirroring from the shared Table. The review recommends clarifying that distinction and making shared planning a deliberate product milestone. Cross-account behavior was not independently tested.

## Coverage limits

- Rotation commands did not yield a rendered month or landscape view. Captures named `28-month-landscape.png` and `29-month-bottom.png` are still portrait Plan captures. They are retained as an audit trail, not evidence of the month design. Month recommendations derive from source and require a separate rendered check.
- Plated+ gating and Prongsby are disabled in source. Suggestions about them are future reactivation considerations, not current visible-screen defects.
- Cooking state and timer behavior, widgets, import normalization, offline state, notification behavior, and persistence boundaries received source review. Their complete runtime behavior was not exhaustively exercised.
- This was not a VoiceOver audit or representative-user study. Contrast calculations use source token values; proposed target sizes and task times are acceptance criteria rather than measured results.

## Visual concept

The accompanying interactive concept illustrates Plan, Recipes, Groceries, Table, dinner selection, and cooking with sample content. It is a design proposal, not an implemented SwiftUI change or a connected service. Search, recipe filters, grocery check-off, manual grocery entry, and local planning interactions are exploratory controls. Import, invitations, publishing, and exports are previews only.

The current/proposed comparison changes sample content as well as layout, so it is useful for composition and hierarchy rather than a controlled usability comparison. Validate the design with the same real household content before implementation.
