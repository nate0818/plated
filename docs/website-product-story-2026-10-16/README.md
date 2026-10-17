# Plated product story refinement — October 16, 2026

This revision addresses the six browser comments following the motion pass.

- The hero opens on Plan with an actual 18-second app recording. The clock reads
  8:18 throughout. Play/Pause is available; offscreen and background playback
  stop. Reduced Motion shows a Plan poster until playback is explicitly chosen.
- The masthead P artwork is 36 px instead of 56 px. The wordmark is 34 px.
- The recipe conveyor is replaced by a layered personal recipe collection with
  a finite reveal. It uses existing food photos, without ratings, names or
  invented sharing activity.
- Gallery, walkthrough and FAQ copy describe your own recipes and recipes shared
  by friends. The preloaded/sample cookbook claim is removed. Supporting native
  implementation: `TableFeedView.swift` has Save to cookbook and Save controls;
  `RecipeImportSheet.swift` supports links and adding a recipe.
- Desktop: the phone and step navigation stay sticky; the right-hand story
  scrolls. An IntersectionObserver selects Plan, Recipes or Groceries. Buttons
  also navigate directly to steps. Three native stills load before transitions.
- Mobile: each step has its own inline capture, so no tall phone traps the
  viewport. Content remains present without scroll-dependent hiding.

The 8:18 captures and recording are documented in `web/public/app/README.md`.
The QA app was restored to Editorial appearance and Plan, and the clock override
was cleared. Native source code and user content were not modified.

Validation and browser proof are recorded with this revision’s screenshots.
The live local preview is http://127.0.0.1:3003/; no deployment was requested.

## Verification

- Production build and TypeScript passed.
- Targeted ESLint passed for the six changed TSX files.
- `make tokens` passed native/widget parity and all 31 website colour roles.
- Browser widths 320, 390, 800 and 1120 px stayed within the viewport.
- Production MP4 loaded with duration 18 seconds and played automatically.
  The Pause control paused it; offscreen playback also stopped.
- Page Down advanced Plan to Recipes while the left rail stayed pinned at
  112 px. Direct step navigation selected the matching native screen.
- Enlarged-screen dialog arrow navigation and Escape/focus return passed.
- No browser console errors were captured in the production preview.
- Reduced Motion fallback is implemented in CSS and video setup; the host OS
  preference was not changed for this check.

`hero-start.jpg`, `hero.jpg`, `recipes.jpg` and `walkthrough.jpg` are browser proof from the
production build. The recording advances, so a hero still may show Recipes
after its opening Plan scene.
