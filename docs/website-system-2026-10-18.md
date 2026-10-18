# Plated website system

The new homepage is now the local `/` route. `/direction` is a noindex alias
for reviewing the same `MarketingHome` component.

## Shared design

- Global roles: paper `#F7F6F0`, forest `#25362A`, sage `#E7ECDC`, coral `#FF5A3C`.
- DM Sans headings and body text; Newsreader for the wordmark.
- `SiteFrame` owns public navigation, skip links, footer, and Apple badge.
- Consistent controls, focus rings, 44px minimum targets, and reduced motion.
- Desktop wheel/trackpad input eases through Lenis 1.3.27. The engine loads
  only with a fine pointer and without reduced motion. Its frame
  loop runs only during movement; touch and keyboard scrolling stay native.
- Same-page anchors share the easing, CSS scroll margins, URL history, and
  focus handoff. App-preview dialogs stop page inertia and scroll natively.
- App previews move at different depths on desktop; page backgrounds stay
  still. Motion tears down on route, pointer, and reduced-motion changes.

## Coverage

The homepage, early-access form, household and Table invitations, privacy
article, 404, and page-error fallback share this design. Authentication and
the admin workspace use the same palette, typography, panels, and controls.
Sharing artwork uses the new homepage palette and headline.

The privacy page retains its data-handling and retention disclosures. Its
headings, terminology, introduction, and presentation were updated.
Authentication, invitation URLs, request storage, and TestFlight behavior
remain unchanged.

## Verification

- Production build, TypeScript, and targeted ESLint checks pass.
- Public routes checked at 320, 390, 760, 815, and 1280 CSS pixels: no page or
  heading overflow, with the same paper canvas and sans-serif headings.
- The real missing-page route returns HTTP 404.
- Home links, preview enlargement, access navigation, and privacy section
  links checked without submitting requests or sending invitations.
- Wheel easing observed during input and returning to idle, including a
  narrow desktop pane. Section links land below the header and move focus.
  Same-page Back/Forward restoration and native Page Down checked.
- Enlarged previews scroll internally while the document stays locked;
  Escape closes the preview and returns focus to its trigger.
- The 390px layout has no horizontal overflow or desktop depth transforms.
  At 815 × 600, the 492px showcase and both devices remain in frame.
- Admin styles compile. Its local URL redirects to the configured production
  origin, so authenticated console views were not visually tested.

Prepared locally for review; no production deployment has been made.
