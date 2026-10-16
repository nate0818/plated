# Editorial website implementation

This replaces the earlier website direction with the approved Editorial system
in `DESIGN.md` and `design/design-system.md`.

## System mapping

| Role | Website implementation |
| --- | --- |
| Default room | Deep green canvas, cream ink, sage supporting actions |
| Titles and wordmark | Bundled Newsreader Roman, regular weight; capitalized Plated without a dot |
| Reading and controls | Bundled DM Sans, emphasis capped at semibold |
| Primary commits | Original orange, dark labels, 6px rectangular corners |
| Content | Flat fields, fine rules, 4px photo corners, no decorative shadows |
| Product explorer | Four accessible tabs with selection rules and real screenshots |
| Waitlist | Rectangular input/action, native validation, busy state, quiet success |

The Plan, Recipes, Groceries, and Table screenshots come from the actual
`docs/editorial-2026-10-16/*-green-default.png` captures, with the sample
household. New asset URLs prevent old optimized screenshots from being reused.

Public privacy and invitation pages inherit the new fonts and deep green
palette. The private console and illustrated 404 are explicitly scoped to the
system's paper palette so existing white utility/artwork surfaces remain readable.
The invitation action adopts the rectangular primary treatment.

Browser icons and the sharing card use the Editorial identity. Their reproducible
generator reads the current CSS tokens, fonts, and Plan capture. Full variable
font binaries and SIL licenses are bundled for browser rendering; static artwork
uses their default Regular outlines because Satori's font reader cannot parse
the variable metadata in these particular binaries.

## Verification

- Production `npm run build` passes, including TypeScript and prerendering.
- Homepage inspected at CSS widths of 320, 390, 800, and 1440 pixels with no
  horizontal page overflow.
- All four selectors display the corresponding copy and Editorial app capture.
- Arrow-key and End selection verified. Tab moves into the selected panel.
- FAQ expansion and invalid-email validation verified without submitting an
  address to the production waitlist.
- Privacy and invitation pages checked for cream-on-green text; the illustrated
  404 verified with its paper palette.
- The browser blocked the private console URL, so that route's scoped palette
  was checked in source rather than represented as visually verified.
- `git diff --check -- web` passes.
- Repository `make design tokens` passes, including widget token consistency.

`desktop.jpg`, `mobile.jpg`, and `full-page.jpg` are local production captures.
The full-page capture includes the food photo after its lazy loading completed.
No deployment or native-app upload was performed.
