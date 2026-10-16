# Plated website: closer Whipp reference

Local implementation in `web`, 16 October 2026. This replaces the paper app
spread and text-only feature columns from the preceding UX refinement.

## Reference and structure

Reviewed the live [Whipp website](https://www.whipp.app/), including its hero,
early meal gallery, and app walkthrough. The useful reference is its order of
information and the space given to the product: a large app screen beside the
promise, appealing food immediately afterward, and screen-led explanations of
how the app works. Plated keeps its own copy, photography, native UI, fonts,
Editorial green, cream, and coral actions.

The new page has:

1. One prominent, complete recipe-book capture in the hero, with a plain category
   description and a direct household value proposition. The image has a defined
   device frame and sits clear of photography. It opens the four-screen explorer.
2. A four-recipe food gallery immediately afterward. Names and preparation times
   come from `Plated/Support/SampleData.swift`. The gallery becomes a horizontal,
   keyboard-scrollable row at tablet and phone widths.
3. A manual Recipes / Plan / Groceries tour, with one explanation visible at a
   time. It opens on Plan, so the first scroll introduces the core planning and
   cook-assignment behavior instead of repeating the hero's recipe book.
4. A separate, alternating Table scene showing the complete native capture.
   The copy distinguishes shared household planning from deliberate, invite-only
   posting to friends.
5. A clear TestFlight invitation, an optional launch-email disclosure, native FAQ
   disclosures, and a fuller navigable footer.

The page does not copy Whipp's automatic planning, budget, pricing, macro,
subscription, or speed claims. It has no invented testimonials or ratings.
The app preview contains real screen captures, not a simulated working app.

## UX decisions

Applied principles from Jon Yablonski's
[Laws of UX, second edition](https://www.oreilly.com/library/view/laws-of-ux/9781098146955/):

- [Hick's Law](https://lawsofux.com/hicks-law/): one main conversion goal,
  three named tour choices, one explanation at a time, and optional email signup.
- [Fitts's Law](https://lawsofux.com/fittss-law/): 44–56 px navigation, tab,
  dismissal, disclosure, and action targets, with clear spacing.
- [Proximity](https://lawsofux.com/law-of-proximity/): each product explanation
  sits with its screen; meal names and times stay with their photos.
- [Jakob's Law](https://lawsofux.com/jakobs-law/): familiar links, a native dialog,
  standard tab keys, and native disclosures. No scroll hijacking or autoplay.

The category label has no decorative dash or pill. Coral is reserved for primary
actions. Semantic tokens and bundled Newsreader / DM Sans remain aligned with the
native design system. Anchor navigation is immediate; reduced-motion rules still
cover color transitions.

## Assets

All app captures are the unaltered `editorial-*-current.png` files documented in
`web/public/app/README.md`. Recipe photography comes from the existing sample
cookbook assets in `web/public/editorial/`. The generated lifestyle image from an
earlier direction remains unused. The sharing card now uses the recipe-book
capture and the current headline.

## Verification

- Production Next.js build and TypeScript pass.
- Targeted ESLint passes for the changed TSX files and artwork generator.
- `make tokens`: all 31 website roles match both native appearances; widget parity
  and the existing timer-source check also pass.
- Checked document geometry at 320, 390, 800, and 1440 CSS pixels: no page-level
  horizontal overflow; the hero remains two lines. Tour targets are 52 px tall
  on phones and 56 px on larger layouts.
- Tested tour selection, arrow keys, and the screen explorer's arrow navigation,
  Escape dismissal, and focus return. Native dialog presentation isolates the
  background and locks its scrolling.
- Tested FAQ expansion, launch-email disclosure, and browser validation of an
  invalid email. No valid signup was submitted.
- Final production-browser screenshots are stored alongside this note. The local
  server remains running at `http://127.0.0.1:3003/` for the requested click-through.

These checks verify implementation and layout. Comparative comprehension and
conversion performance have not been measured with users.
