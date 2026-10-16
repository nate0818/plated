# Editorial implementation

[Current design and wheel verification](consistency-and-wheel.md)

[Plan](plan-current.png) · [Recipes](recipes-current.png) · [Groceries](groceries-current.png) · [Table](table-current.png) · [iPad](plan-ipad-current.png) · [Website](website-current.png)

Earlier light/dark captures below are historical evidence, not the selected
default or current selection treatment.

October 16, 2026. User-selected Editorial direction, with original Plated orange
primary CTAs added in the follow-up. Standard SwiftUI profile. Existing local,
household, sharing, permission, timer and navigation ownership contracts remain.

## What changed

- Bundled Newsreader and DM Sans in the app and widget extension, including SIL
  OFL licenses. Removed Gabarito and Plus Jakarta Sans binaries and migrated the
  native font APIs to editorial/sans role names. Cap matching uses the new metrics.
- Replaced the cream/brown/tomato system with Editorial paper, green-black ink,
  olive supporting states and small rectangular controls. Orange has its own
  primary-action token and dark foreground; it is not the selection color.
- Replaced illustrated floating navigation and the center Add disc with four
  plainly labeled SF Symbol destinations. Header Add retains the existing
  create flow and guards repeated/busy presentations. Reselect behavior and
  accessibility identifiers are retained.
- Reworked mastheads, wordmark, shared actions, artwork corners, option rows,
  chips, secondary controls and surface elevation. Theme/font changes propagate
  through every native screen; custom controls in root screens and Settings
  were migrated alongside them.
- Plan keeps the date wheel and Week/Month controls visible above dinner. Week,
  month and drag behavior remain available. Recipe search and adaptive grids
  remain visible and use the new type system.
- Removed the timed illustrated opener in favor of an app-readiness lockup.
  Sign-in uses a photographic welcome; setup/tour backgrounds are static paper.
- Widgets register both new font families and mirror the checked palette. The
  share-extension source adopts paper, serif status type and an orange Done action.
- Replaced DESIGN.md and design/design-system.md. Historical specs are explicitly
  retired. The design checker now recognizes rectangular compact controls too.

## Validation

Signed Plated Debug arm64 simulator build and all **372 existing tests passed**
on iOS 26.5, Plated-QA-Sandbox (03D915E3-518F-4AC4-B1A1-EDBBC4CCE2DC).
Both new font binaries are present in the built app. `make design tokens` and
`git diff --check` pass. No services, schemas or stored identity hex values were
migrated for the redesign.

Measured token contrast ratios (WCAG luminance formula, opaque surfaces):

| Pair | Ratio |
| --- | ---: |
| Orange primary / dark text, light | 5.49:1 |
| Orange primary / dark text, dark | 5.49:1 |
| Supporting ink / paper, light | 5.44:1 |
| Supporting ink / paper, dark | 8.42:1 |
| Olive selection / label, light | 7.90:1 |
| Olive selection / label, dark | 9.20:1 |

The static scanner reports 3 high, 432 medium and 7 low review signals across
142 files. High signals include persistent service UUID construction and a valid
TimelineView schedule, not confirmed transient view identity or unscoped
animation bugs. Full output is retained in static-audit.txt. Existing application
sync/retry work and unrelated interaction patterns were not rewritten merely to
clear heuristic scanner counts.

Fresh Plan and Recipes iPhone captures and the three-column iPad recipe grid
have been inspected. Additional captures and verification limits follow below.

## Scope and limits

The native app and widgets build together. The share-extension source is not an
active target in the current Xcode project, so its updated UIKit presentation has
not been built or exercised here. The website has unrelated uncommitted work and
was not restyled in this native-app request. System-owned pickers and Apple
sign-in retain system UI. No deployment or TestFlight upload was performed.

Screenshots establish the captured viewport only. Full VoiceOver, Switch Control,
keyboard operation, physical-device integrations, interrupted gestures and
Instruments performance remain unverified; no claim of complete platform quality
or 90-point fidelity is made from the build and screenshot evidence.


## Accessibility follow-up and provisional assessment

The first AX5 captures (retained as before-fix evidence) exposed oversized editorial mastheads. The masthead now
uses concise location labels (Plan/Recipes) with the heading scale at accessible
sizes. Plan uses a shorter date, and its task restores the selected dinner anchor
after text reflow. Recipe search glyphs remain compact while content scales.
The passing 372-test run includes those accessibility fixes. A subsequent build
checks final icon, widget identity-tone and print styling adjustments.

Provisional fidelity assessment: **79/100**, limited by incomplete interaction,
assistive-technology and full visual-matrix evidence. Category scores: platform
13/15; layout 12/15; semantics 13/15; interaction continuity 15/20; motion/materials
12/15; accessibility 6/10; implementation 8/10. This is an evidence-limited
assessment, not release sign-off. The AX5 issue prompted a corrective pass; full
VoiceOver and device checks are still needed to lift that cap.

`changed-native-files.txt` lists files changed by this Editorial pass relative to
the workspace at its start, separately from existing uncommitted work.


Final signed simulator build passed after the final widget/icon/print styling
adjustments. The contrast values and primary CTA treatment remain unchanged.

Fresh captures cover all four roots in light appearance, Plan in dark, the iPad
three-column recipe grid, and Plan/Recipes at AX5. Before-fix AX5 screenshots are
retained; corrected captures use `-fixed` in the filename. The corrected Plan
opens at its selected dinner after text reflow. Content remains vertically
scrollable; these captures do not prove complete assistive-technology operation.

A newly added nutrition field from concurrent workspace work contained an em-dash
placeholder. This pass changed only that placeholder to "Optional" so the shared
design checker remains green, preserving the surrounding feature work.

Corrected AX5 Plan and Recipes captures were visually inspected: masthead labels
fit, recipe search keeps compact glyphs, the recipe grid is one column, and the
selected Plan dinner is at the scroll's opening position. Simulator settings were
restored to light appearance and normal text after the check.


## Correction: match the selected green appearance

The selected Editorial concept was viewed in its deep green appearance
(`#191C17`), with cream text (`#EDF0E6`). The first implementation inherited
System appearance as its default, so a Light-mode phone showed the optional
paper palette. That was a mismatch with the user's selected presentation.

Editorial is now the default app appearance, independent of the phone's theme.
Fresh and previously automatic-theme installs adopt it once. Explicit Light
choices are retained; later manual selections are never reset by the migration.
The launch asset is deep green in both device appearances. Settings names the
green option Editorial and its preview uses the current palette. The app and
settings share the same default and fallback. Primary CTAs use the exact original
orange `#FF5A3C` in both appearances, with dark labels.

Six behavior tests cover the selected color scheme, fresh installs, upgrading
an automatic default, preserving Light, later System choices and invalid old
preferences. Verification and a fresh capture follow below.


The first verification attempt also exposed an invalid mixed fixed/flexible
SwiftUI frame overload in concurrent grocery-budget edits. It was corrected to
separate width and minimum-height modifiers, preserving the surrounding work.

The retry exposed a missing explicit return in the grocery aisle grouping
getter after concurrent aisle-order edits. That compile error was corrected
without changing the grouping behavior.

### Green-default verification

- Signed simulator test run passed: **382 tests, zero failures**, including all
  six appearance migration tests. Log: `/tmp/plated-green-appearance-tests-final.log`.
- `make design tokens` passed across 151 Swift files, with no widget token drift.
- `git diff --check` passed.
- Captured and visually inspected Plan, Recipes, Groceries and Table while
  `simctl ui … appearance` reported **light**. The app's stored appearance was
  **dark**, adopted by the Editorial migration, with no appearance launch override.
- The Groceries capture exposed an uncovered bottom padding strip. Its canvas
  background now includes that padding and the safe area. A final signed build
  passed after this layout-only correction (`/tmp/plated-green-final-build.log`),
  and the Groceries screenshot was refreshed and inspected.

Current green-default captures:
[Plan](plan-green-default.png), [Recipes](recipes-green-default.png),
[Groceries](groceries-green-default.png), [Table](table-green-default.png).
These are actual simulator captures using the memory-only review fixture.
Earlier `-light` images document the mismatch and are not the selected default.
The previous limits on device, assistive-technology and performance evidence
still apply. No TestFlight upload or deployment was performed.

## Restore the date wheel

The date wheel is once again visible at the top of Plan whenever Week is
selected. The collapse toggle and its state were removed. Week/Month, Choose a
date and Today are immediately available, and the existing date selection,
scrolling, haptics, accessibility actions and meal-drop behavior are retained.
The deep green appearance and orange primary actions are unchanged.

The signed simulator build passed (`/tmp/plated-date-wheel-build.log`), as did
`make design tokens` and `git diff --check`. The regular-size screen was captured
and visually inspected: [Plan with date wheel](plan-date-wheel-restored.png).
The wheel and its controls also fit at AX5 in
[the accessibility-size capture](plan-date-wheel-ax5.png). Normal simulator text
size was restored afterward. This visual check does not replace assistive-tool
or gesture testing.

## Align date selections with the parallel grocery design update

The user rejected the pale green day selection and pointed to the other design
chat. Read-only inspection of **Create Plated UI screen review doc** confirmed
the grocery panel had already adopted a darker surface and cream selected
controls. **Refresh Plated's website** was active on the Editorial migration.

The custom week wheel and month grid now use the same `ink` fill and `canvas`
labels as the existing choice controls. Meal markers invert with the selected
date. Their geometry, selection state, accessible selected trait, haptics and
date behavior are unchanged. Shared design guidance now specifies cream
selections and keeps olive to small supporting accents.

`make design tokens`, `git diff --check` and the signed simulator build passed
(`/tmp/plated-cream-selection-build.log`). Actual sample-data captures were
visually inspected: [Week](plan-cream-date-selection.png) and
[Month](month-cream-date-selection.png). This appearance-only correction did
not add tests or rerun the behavior suite.
