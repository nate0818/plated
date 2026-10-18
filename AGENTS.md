# Plated: standing quality requirements

## Nate's explicit instruction — October 18, 2026

> Every detail matters. You need to be explicit and thorough to not miss anything.
> Everything must be checked every single time so we don't keep running into
> issues like this. I can't be the only person that's catching these issues and bugs.

Treat this as a standing project requirement. Own defect discovery and verification;
do not make Nate the primary QA reviewer or ask him to enumerate issues that can be
found by inspecting the app. A plausible implementation, successful build, passing
interaction test, or uploaded binary is not proof of a polished, working experience.

## Before implementing

- Read `DESIGN.md`, the relevant product contracts, and the latest applicable user
  approval. Use the original approved design as the reference; do not revise a
  proposal or expected result merely to match incomplete code.
- Identify every affected screen, state, navigation path, role, and shared-component
  use site. Include loading, empty, error, offline, pending, success, and recovery
  states. Check connected workflows, not just the reported element.
- Convert approved annotations and reported defects into explicit acceptance
  criteria. An illustrative screen is not the complete application inventory.
- Preserve concurrent/unrelated work. Record the exact source and build being
  verified so an older installation cannot be mistaken for the revised app.

## Before calling work complete

- Inspect actual native renders against the approved reference, element by element:
  hierarchy, typography, spacing, alignment, sizing, colors/contrast, artwork,
  attribution, controls, copy, states, safe areas, keyboard, scrolling, and reflow.
- Exercise actions and transitions, including cancellation, retries, failure,
  persistence, relaunch, and return navigation. Verify the resulting data/state,
  not just that a button was tapped or a screenshot was captured.
- Check both appearances, compact and larger iPhones, default and accessibility
  text sizes, minimum-supported and current shipping OS versions, and supported
  iPad layouts. Include an in-place upgrade from the previous distributed build.
  iPad is landscape-only per Nate's request;
  also check rotation attempts and narrow/resized windows without losing drafts.
- Read accessibility diagnostics. Some audit probes collect findings without
  failing: a green capture run does not mean the visual or accessibility review
  passed. Physical VoiceOver and live account/network behavior need their own proof.
- Fix discrepancies, retest the affected behavior and its connected paths, and
  retain evidence. Do not weaken assertions just to obtain a pass; an obsolete
  assertion needs a documented product reason and a meaningful replacement.
- Report implementation, visual review, interaction tests, and live verification
  separately. Never convert unavailable, skipped, source-only, or historical checks
  into passes, or describe the product as bug-free/100% verified.

## Every app release

Follow [`docs/release-quality-standard.md`](docs/release-quality-standard.md).
Reconcile the full current screen/state inventory, run the release baseline and
available regression suites, visually review the rendered inventory, and record a
fresh coverage ledger. Do not silently omit a screen because it was unchanged.
Maintain extra coverage for every previously reported defect.

Verify the exact signed export, app/widget versions, production capabilities,
symbols, upload receipt, processing state, and access for every authorized tester
group. Upload success is not tester availability or proof of installation on a phone.

If a required check is unavailable, continue all independent authorized work and
state exactly what remains unverified. Do not infer a waiver from silence or an old
test. Preserve the scope of any explicit user-approved exception without requesting
the same permission again. Never describe an exception as verification.

This instruction-only change does not constitute a new app audit or release.
Routine non-release work still requires checks appropriate to its actual changes;
do not run unrelated app tests merely to validate documentation.
