# Plated: Your week, well fed.

Implemented homepage direction, October 16, 2026. This supersedes the earlier
website explorations while retaining the approved Editorial system.

## What changed and why

The previous page relied on repeated feature layouts, small app screens, and
large areas of empty green. It communicated a list of features more readily
than a reason to want the product.

The new page leads with dinner and the people around it. A large shared-table
photograph sits beside the promise “Your week, well fed.” An actual recipe-book
capture connects that emotional setting to a tangible product. The next section
shows four meals from the existing sample cookbook. The workflow then explains
Recipes, Plan, and Groceries in three visible steps, with full app captures
available in a native dialog. Household co-editing and invite-only Table sharing
have distinct explanations. TestFlight is the primary action; the launch
waitlist is secondary.

[Whipp’s live website](https://www.whipp.app/) was inspected in the browser,
including its hero and meal presentation. The useful reference was the early
combination of appetite, a clear outcome, and visible product detail. This is
Plated’s own composition, typography, palette, and household story. No outside
designers were contacted or represented as having reviewed the result.

## System and implementation

- Newsreader Roman titles and wordmark; DM Sans reading text and controls.
- Deep green canvas, cream headings, orange primary actions, small sage accents.
- Flat surfaces, fine rules, 4px photography corners, 6px controls.
- Existing food imagery optimized as WebP, with descriptive alternatives.
- Current Plan capture includes the restored Week/Month controls and cream date.
- Native dialog offers Recipes, Plan, Groceries, and Table captures. Buttons,
  arrow keys, explicit close, Escape, focus return, and a live screen label are
  supported. The underlying page is inert while the dialog is modal, and root
  scrolling is locked while it is open.
- Native FAQ disclosures and the existing waitlist endpoint are retained.
- Social card and page metadata use the new headline. Artwork remains generated
  from bundled fonts, the live palette, and the actual Plan capture.
- No fabricated customer testimonials, app ratings, catalog sizes, or outcomes.

## Image provenance

The shared-table brand photograph was created with the **built-in image
generation tool**. It is illustrative brand imagery, not a customer photograph
or an app screenshot. Product UI comes exclusively from real Plated captures.

- Original: `shared-table-original.png` in this directory.
- Optimized website asset: `web/public/editorial/shared-table.webp`.
- Recipe photography: existing `design/salmon-plate.jpg`, `design/pizza.jpg`,
  `design/poke.jpg`, and `design/pancakes.jpg`.
- Recipe names and total times: `Plated/Support/SampleData.swift`.
- Full generation prompt: [shared-table-prompt.txt](shared-table-prompt.txt).

## Verification

- `npm run build` passes, including TypeScript and static prerendering.
- Targeted ESLint passes for the homepage, app viewer, phone screenshots,
  waitlist, root layout, and artwork generator.
- `git diff --check -- web` passes.
- `make design tokens` passes: 153 Swift files checked, ten shared tokens
  consistent, and CookTimerActivity identical across targets. An initial widget
  fill mismatch disappeared when the concurrent native palette update completed;
  no native files were changed for this website pass.
- Browser layout inspected at CSS widths 320, 390, 800, and desktop sizes, with
  no horizontal page overflow. Mobile heading scale and narrow preview widths
  were refined; tablet preview alignment uses equal-height grid rows.
- All four screenshot choices, arrow navigation, close, Escape, and focus return
  were exercised. The native dialog exposes its controls to accessibility.
- FAQ expansion and invalid-email rejection verified without sending an email
  address to the waitlist service.
- Final screenshot gallery images verified loaded. The four small food images
  load eagerly so they are ready when the visitor reaches the next section.
- Browser viewport and capture timeouts interrupted the final capture session;
  it recovered and the verified captures below were saved. No production
  deployment, new waitlist record, or native app upload was performed.

## Captures

- [Desktop hero](desktop.jpg)
- [Full page](full-page.jpg)
- [Mobile hero](mobile.jpg)
- [Complete mobile page](mobile-full-page.jpg)

These are browser captures, not image-generated website mockups. Their pixel
dimensions reflect the in-app browser’s viewport and display scale. Preview
servers were stopped after verification.
