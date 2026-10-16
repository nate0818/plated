# Editorial consistency and date-wheel verification

October 16, 2026. Standard SwiftUI profile: precise, quiet native behavior with
the selected deep green Editorial identity, cream selections and original orange
primary actions. Local implementation; no deployment or TestFlight upload.

## Experience contract

The primary task is choosing a dinner date by touch, direct tap, calendar, Today,
keyboard or an accessible action. WeekView owns the committed date. The wheel
owns a transient preview and its idle/scrubbing/navigating interaction value.
Native scrolling owns velocity and deceleration. The dinner content updates once
the wheel rests, keeping expensive plan updates out of the continuous gesture.

The wheel uses native centered snapping on iOS 26, with a bounded native fallback
on iOS 18. Initial positioning and resizing follow the actual scroll viewport.
Final commits read geometry from the native phase-change context, avoiding a
preceding-frame position. Taps and Today interrupt previous motion. Backgrounding
cancels a transient scrub; stale deceleration cannot override a new date.

Native `.sensoryFeedback(.selection)` fires on meaningful crossed days and date
choices. Feedback is coalesced within 45 ms during fast flings. Initial layout and
programmatic alignment are silent. Reduce Motion removes programmatic travel.
The selected date has an adjustable accessibility action; day/week/Today actions
and keyboard arrows supplement dragging. No glass or ambient effects were added.

## Reconciled design work

Read **Create Plated UI screen review doc** and **Refresh Plated's website**.
The other chat's darker grocery panels and capsule Table rail are preserved.
`EditorialSegments` now owns the moving cream selection for Week/Month, Grocery
scope and Table audience. Shared chips, day-detail dates, remote dates, award
filters and appearance choices now follow the same roles. Complex appearance
previews use a cream boundary/checkmark rather than inverted content. Remaining
green accents identify small supporting controls or semantic status.

Native surfaces were quieted and mirrored in widgets and website CSS. The
website's authentication/error surfaces, selected controls and primary actions
now follow the same palette. Public app images are unaltered captures of the
current native build; browser and sharing artwork were regenerated from them.
The website composition from the other chat is retained.

`make tokens` now checks 31 shared website roles in both appearances, in addition
to the existing 10 widget roles and Live Activity type parity. This catches
future divergence across concurrent app and website work.

## Evidence

- Signed Plated simulator build and 388 behavior tests passed. Six new wheel
  tests cover silent touch-down, feedback coalescing, one-time settling,
  programmatic interruption, cancellation and invalid/overscrolled geometry.
  Log: `/tmp/plated-wheel-final-tests.log`. Subsequent adapter corrections were
  built and exercised by the UI probe below.
- Saved standalone [UI probe](../../scripts/DateWheelProbe/README.md): **2 tests
  passed** on iOS 26.5, simulator `03D915E3-518F-4AC4-B1A1-EDBBC4CCE2DC`.
  Verified launch centering, date tap centering, slow/fast flicks, Today,
  three repeat launches and background/foreground. The tests exposed initial
  lazy-layout positioning, skipped tracking phases, and stale final geometry;
  those issues were corrected before the final passing run.
  Log: `/tmp/plated-wheel-final-ui-verification.log`.
- `make design tokens`, `git diff --check`, website production build and ESLint
  passed. Logs: `/tmp/plated-web-final-build.log`, `/tmp/plated-web-final-lint.log`.
- Actual captures inspected: [Plan](plan-current.png), [Recipes](recipes-current.png),
  [Groceries](groceries-current.png), [Table](table-current.png),
  [iPad Plan](plan-ipad-current.png), [AX5 Plan](plan-ax5-current.png).
  Simulator text size was restored afterward.
- Browser inspection verified deep green `rgb(25,28,23)`, cream
  `rgb(237,240,230)` selection, and primary orange `rgb(255,90,60)` with dark text.
  No horizontal overflow at measured 1600 and 390 CSS-pixel widths. The product
  dialog's selection and Escape dismissal worked. Error-route colors were
  checked. Authentication correctly showed its unavailable state; authenticated
  console content could not be exercised without its environment configuration.
  [Desktop](website-current.png) and [mobile](website-mobile-current.png) captures
  use the production build and current native imagery.
- [Static audit](consistency-static-audit.txt): 146 files, 3 high, 441 medium,
  7 low heuristic findings. The high findings are existing persistent UUID
  creation in services and a valid TimelineView animation schedule, not new
  transient view identity or an unscoped animation. New wheel warnings concern
  its bounded GeometryReader and fixed chrome dimensions, checked in the
  captured phone, iPad and AX5 layouts.

## Quality limits

Provisional Apple Fidelity assessment: **84/100** — platform 14/15, structure
13/15, semantics 13/15, continuity 17/20, motion 13/15, accessibility 6/10,
implementation 8/10. Multiple corrective passes and real gesture tests improved
the result, but missing assistive-technology/device evidence caps the score.
This is not an Apple endorsement or a claim of completed release qualification.

Physical Taptic Engine feel, a full VoiceOver/keyboard walkthrough, actual
system Reduce Motion/Increase Contrast operation, iOS 18 fallback runtime,
smallest-device coverage and Instruments frame-time profiling remain unverified.
Reduced-effects and accessibility code paths are implemented; screenshots and
simulator feedback cannot establish their complete real-device experience.

Main implementation: `Theme.swift`, `DateWheelInteraction.swift`,
`PlanDateStrip.swift`, `EditorialSegments.swift`, the affected native consumers,
widget palette, `web/app/globals.css`, web console/error CSS, current image
mapping, shared design guidance, and `scripts/check-tokens`.
