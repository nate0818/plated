# First-run concepts — 16 October 2026

Option B was selected and implemented. See [implementation and verification](implementation/README.md).

Exploratory boards generated using the built-in image generation tool. Not implemented screens or production icon assets.

## Direction
- Compare the custom serving plate with the custom editorial P. The plate still risks reading as a progress indicator; refine before selection.
- Launch matches the destination canvas and exits when ready, without a timed logo interstitial.
- Welcome offers Apple sign-in or local use and explains the sharing requirement.
- Enter the real Recipes empty state with Add your first recipe as the primary action, Plan a night as secondary, and an invitation route.
- Preserve incoming invitation destinations through authentication and bypass generic setup.
- Reuse an available name; defer photos and request missing identity when needed for collaboration.
- Import, scan, or manually enter a recipe. Review imported details before saving. The board omits this intermediate review screen.
- After a successful save, open actual recipe detail with Plan a night and Add to Groceries. No celebration interstitial.
- Preserve input on import/save failure, show retry, and never show saved confirmation before success.
- Ask for contacts, notifications, or invitations only when relevant. Saving or cooking never publishes to Table.

## Production refinements
Use actual Newsreader and DM Sans and flat semantic colors. Generated artwork approximates these. Remove the generated em dash in empty-state copy; use a plain saved confirmation rather than the illustrated pill. Use real recipe data, not the illustrative pasta ingredients. Validate small screen, iPad, Dynamic Type, accessibility, and all loading/failure states when implementing.

## Files
- icon-study.png
- first-run-study.png
- prompts.json: exact generation prompts
