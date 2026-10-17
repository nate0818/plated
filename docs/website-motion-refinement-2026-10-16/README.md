# Website browser-comment refinements

16 October 2026. Implements the six comments on the local Plated website.
The previous static-layout checkpoint is in `website-whipp-reference-2026-10-16`.

## Changes

1. Removed the visible “Explore the app” label and expand glyph from all three
   screen presentations. The images still open the accessible enlarged preview.
2. The existing “The meal planner for your household” eyebrow is the only H1.
   Its DM Sans face, 14 px desktop / 13 px phone size, colour, weight, and line
   height remain unchanged. The large display statement is an H2 with its own
   visual class, so heading semantics do not change its appearance.
3. Added the approved custom P to the masthead and footer lockups. Browser and
   touch icons are derived from that same native asset instead of a font glyph.
4. Replaced the hero's dark capture with an unaltered capture of the real recipe
   book in Light appearance. It keeps the food-led screen and creates a strong
   contrast against the Editorial page. A short, finite entrance, slight settled
   angle, and a soft device shadow add depth. The hero does not float endlessly.
5. Replaced the four-card static strip with two counter-flowing food rows. Their
   seven unique recipes, names, times, and photographs come from SampleData and
   the existing design assets. Motion has a visible pause/play control, pauses
   on hover and keyboard entry, and stops offscreen or in a background tab.
   Keyboard focus gives each row a stationary, natively scrollable track.
   Resuming resets any manual scroll offset before motion begins again.
6. Added Apple's unmodified black App Store badge in the footer. The configured
   listing returned HTTP 404 during this pass, so the badge is explicitly labelled
   as coming soon and is not an active broken link. The working conversion path
   remains TestFlight. The badge component supports linking once availability is
   verified.

The manual product tour also has a brief screen transition. Reduce Motion removes
all entrance and looping animation, removes visual loop copies, and leaves two
static rows that can be scrolled normally. Repeated visual cards are hidden from
assistive technology in either mode. Marketing depth is scoped to the hero
artwork; native app colours and flat surfaces are not changed.

## Sources

- Current identity: `Plated/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, copied
  intact to `web/public/brand/plated-mark.png`.
- Light hero: `web/public/app/editorial-recipes-light-current.png`, captured from
  the running sample household on Plated-QA-Sandbox / iOS 26.5, app 1.0.1 (32).
  The QA app was returned to Editorial appearance and Plan after capture.
- Added food conversions: `design/skewers.jpg`, `design/veggie.jpg`, and
  `design/plates.jpg`. No new generated food or reconstructed app UI is used.
- [Apple's badge guidelines](https://developer.apple.com/app-store/marketing/guidelines/)
  and its badge service. See `web/public/brand/README.md` for the exact artwork URL.

## Verification

- Browser geometry checked at 320, 390, 800, and 1120 CSS pixels: one H1, unchanged
  eyebrow sizing, two-line display headline, two food rows, no page overflow.
- Observed both animation directions running; pause stops both tracks, and play
  resumes them. Keyboard arrows scroll a stationary row. Leaving the gallery
  stops its motion.
- The official badge loads locally at 50 px height with its coming-soon status.
  It is unlinked while the listing is unavailable.
- Reduced Motion fallback is defined in each motion component and the shared
  stylesheet. The user's OS preference was not changed for testing.
- Production build, TypeScript, targeted ESLint, and token checks are recorded
  in the task's tool results. No native source files or data services were changed.

The local preview remains running on `http://127.0.0.1:3003/` for click-through.
Screenshots saved alongside this note show the final production rendering.
