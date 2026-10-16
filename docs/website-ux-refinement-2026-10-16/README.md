# Plated website: clarity and product presentation

October 16, 2026. Current local implementation in `web/`, superseding the
previous website explorations.

## Value proposition

Plated helps a household share the work of dinner: one recipe book, meal plan,
and grocery list, with a cook assigned to a meal. The homepage leads with
“Dinner, planned together” and immediately names those three shared tools.

[Whipp's live site](https://www.whipp.app/) was inspected again in the browser.
Its marketing makes a specific promise about rapidly producing a meal plan
around budget and preferences. Plated's earlier headline described a mood more
than a job. This revision focuses on household collaboration, which the real
Plated captures and implementation support. This is a positioning and design
assessment, not evidence of better conversion or comprehension than Whipp.

## Design critique and response

| Finding | Severity | Final change |
| --- | --- | --- |
| The line and uppercase label above the headline add decoration without useful information. | Minor | Removed the label and line entirely. |
| A small, tilted phone over a detailed photograph obscures the product. | Major | Upright Recipes and Plan captures sit together on the existing paper palette, with no overlap. Each opens a full screen viewer. |
| Repeated slogans and competing sections delay the household proposition. | Major | Shortened the page to the product promise, three concrete jobs, own-recipe imagery, questions, and the same TestFlight action. |
| The recipe gallery can suggest a content subscription rather than the user's cookbook. | Moderate | Existing recipe photographs illustrate a clearly identified sample cookbook alongside an explanation of bringing one's own recipes. |
| Tiny descriptions and repeated metadata add effort. | Moderate | Reading text is generally 15–18px; useful captions are 12–13px. Removed decorative numbering, repeated category labels, and the oversized footer. |
| A visible waitlist competes with trying the app. | Moderate | Native disclosure reveals launch-email signup only when requested. |

The deep green default, Newsreader, DM Sans, exact orange primary action,
flat surfaces, and near-square photo corners remain. Paper is deliberately
scoped to the product spread; it does not change the app captures or the default
appearance elsewhere. The current page uses actual app captures and existing
recipe photos. The generated shared-table image from the earlier exploration
is no longer referenced by the homepage.

## Laws of UX decisions

Reference: Jon Yablonski's
[Laws of UX, second edition](https://www.oreilly.com/library/view/laws-of-ux/9781098146955/)
and the author's accompanying explanations.

| Principle | Application |
| --- | --- |
| [Hick's Law](https://lawsofux.com/hicks-law/) | One main conversion goal: try Plated through TestFlight. Launch signup and extra product screens are progressively disclosed. |
| [Fitts's Law](https://lawsofux.com/fittss-law/) | Navigation has 44px targets; the main CTA has a 52px minimum height. Viewer controls and close targets are 48px, with space between them. Entire app captures are clickable. |
| [Law of Proximity](https://lawsofux.com/law-of-proximity/) | Product captures share a single defined area. CTA and availability sit together. Recipe photography is separate from app UI. |
| [Jakob's Law](https://lawsofux.com/jakobs-law/) | Familiar links, buttons, native disclosure controls, and a native modal dialog. There are no custom gestures to discover. |

These principles inform the decisions; they are not a substitute for observing
people use the page. No outside designers were contacted or represented as
having reviewed it.

## Verification

- `npm run build` passes, including TypeScript and prerendering.
- Targeted ESLint passes for the homepage, app viewer, root layout, and artwork
  generator. `git diff --check -- web` passes.
- Browser layouts checked at CSS widths 320, 390, 800, and 1440 with no
  horizontal page overflow.
- Recipes, Plan, Groceries, and Table selections verified. Arrow navigation,
  explicit close, Escape, and return of focus to the opening button verified.
- Viewer buttons checked at 320px; controls remain within the dialog and have
  48px heights. The underlying page is inert while the dialog is open.
- Privacy FAQ expands. Launch signup is initially hidden; opening it exposes
  its labelled email input. Invalid email is rejected by native validation.
  No valid address was submitted and no waitlist record was created.
- Calculated contrast: cream on deep green 14.93:1; secondary text on deep green
  8.42:1; primary button label 5.49:1; paper text 12.09:1.
- Hero images load eagerly. Recipe photo wrappers reserve their aspect ratio;
  all visible gallery images were loaded before the full-page captures.
- Social image regenerated and visually inspected with the current headline
  and actual Plan capture. Page, social, and tab metadata agree.
- Final local production response verified as HTTP 200. A fresh working browser
  tab was opened after the dev-server restart left an old tab on a network-error
  page. The production preview remains running for the user's requested review.
- No deployment or native-app changes were made in this website pass.

## Captures

- [Desktop](desktop.jpg)
- [Full page](full-page.jpg)
- [Mobile](mobile.jpg)
- [Complete mobile page](mobile-full-page.jpg)

These are browser captures. Their raster dimensions reflect the browser's
viewport and display scale, rather than new image-generated site mockups.
