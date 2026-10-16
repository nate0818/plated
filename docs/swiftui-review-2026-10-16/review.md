# Plated SwiftUI experience review

October 16, 2026. Profile: standard. Preserve the warm palette, photographs, four destinations, explicit sharing audiences, and existing navigation ownership.

## Experience contract

The primary task is moving dinner from recipe capture through planning, shopping, cooking and intentional sharing. The emotional target is calm coordination. iPhone and iPad are supported from iOS 18; the installed toolchain is Xcode 27. Existing tab roots retain their local navigation state. Tasks remain sheets; focused destinations hide the root tray. Model and sync behavior are outside this visual pass.

Three structural directions were considered: replacing the shell with a system tab view, introducing an iPad sidebar, or improving the current shared components. This pass chooses shared components because a navigation replacement must preserve existing reselect, deep-link, draft and cooking-resume contracts and requires dedicated interaction verification.

## Findings and implementation

| Surface | Finding | Change |
| --- | --- | --- |
| All shared pressable controls | Press scaling continued with Reduce Motion | Read the SwiftUI environment and retain opacity feedback without scale |
| Primary actions | Fixed single-line treatment shrank important labels at accessibility sizes | Allow multiline labels, vertical growth and explicit capsule hit shapes |
| Secondary commit actions | Disabled actions retained enabled ink styling | Use disabled fill and supporting-text colors, suppress pressed scaling |
| Busy primary actions | Guard blocked repeated work but did not expose disabled semantics | Disable while busy and provide an accessible progress value |
| Root tray | Material lacked explicit reduced-transparency or increased-contrast fallback | Opaque canvas with a supporting-ink outline |
| Root tray | Capped labels had no large-content viewing alternative | Native large-content viewer with destination symbols and labels |
| Add control | Quarter-turn persisted with Reduce Motion | Keep the glyph static under that setting |
| Filter chips | Selection depended on color visually | Add a checkmark under Differentiate Without Color |
| Onboarding | Decorative timelines continued while inactive | Pause the sign-in, atmosphere and drifting-food timelines when inactive |
| Sign-in | Entrance zoom persisted with Reduce Motion | Retain opacity entrance without zoom |

Shared changes flow into planning, recipe, grocery, Table, profile, household, settings, and task surfaces wherever those components are used. This is a shared-system implementation, not an assertion that every individual screen has been redesigned or verified.

## Review coverage

Source inspection covered the shell, design tokens, reusable components, recipe grid behavior, grocery accessibility branches, cooking controls, Table audience/actions, and onboarding. The existing 91-image overview was inspected for overall hierarchy only; its reduced resolution is insufficient for a current visual sign-off. Existing recipe grids already switch to one column for accessibility sizes; grocery options already reflow. These were preserved.

The static scanner initially reported 6 high, 459 medium and 7 low signals across 143 files. These are review prompts, not confirmed bugs: the high animation matches include valid TimelineView schedules, and service UUID creation must be distinguished from transient view identity. No blanket replacement was made.

## Validation and remaining work

- Repository design checker and widget token parity checker pass after the changes.
- Deliberate design exception: primary action capsules can wrap at accessibility sizes rather than shrinking. Regular-size labels remain one line.
- Build, simulator captures and tests are recorded below when completed.
- Full visual matrix, VoiceOver interaction, keyboard focus, rapid navigation, physical-device verification and Instruments remain required before a platform-wide quality claim.
- No numerical fidelity score is assigned until build and visual evidence are collected; this review does not claim the 90-point target.
- Web and installed widget layouts were not redesigned. Widget token parity remains intact.

## Files edited by this pass

- `Plated/Support/Theme.swift`
- `Plated/Views/MainShellView.swift`
- `Plated/Views/Components/DesignComponents.swift`
- `Plated/Views/Onboarding/SignInView.swift`
- `Plated/Views/Onboarding/TourIllustrations.swift`

These files contained existing uncommitted work before the review. Changes were applied in place without restoring or replacing that work.

### Collected verification

Xcode 27 / Swift 6.4: `Plated` Debug, generic iOS Simulator arm64 build succeeded. The signed test run on Plated-QA-Sandbox (iOS 26.5, 03D915E3-518F-4AC4-B1A1-EDBBC4CCE2DC) passed **372 tests with zero failures**. The first unsigned test launch failed because CloudKit requires the app's application-identifier entitlement; rerunning with the project's configured signing resolved it. No product logic was changed to bypass that requirement.

The settled Plan capture (`plan.png`) was visually inspected: title, calendar, meal photograph, cooking action and four-destination tray are visible with no clipping at the captured regular text size. This is a viewport check, not proof of navigation or VoiceOver behavior.

Additional settled regular-type light captures: `recipes.png`, `groceries.png`, and `table.png`. Recipes retains its two-column photo grid and visible search. Groceries retains readable item provenance, shopping choices and separated export/tray surfaces. Table retains its compact audience entry and feed card actions. These screenshots were inspected; no current dark, iPad or accessibility-size screenshots are included.

## Design-system follow-up

Updated `DESIGN.md` and added `design/design-system.md` as the current token and
component reference. Marked the old build sheet as historical and linked the
historical specification to the current system. Added `Spacing` and
`ControlMetrics`, adopted them in shared action pills and minimum-target
behavior, and extended the floating-control opaque fallback to increased
contrast. Added service-free Light, Dark, AX5 and host-accessibility preview
definitions to `DesignComponents.swift`.

Verification after these changes: the signed Plated Debug build and all 372
existing tests passed on the iOS 26.5 QA simulator; design and widget parity
checks passed. Preview definitions compile. The gallery itself has not been
rendered or interactively reviewed in Xcode. The SDK's read-only accessibility
environment values require configuring the host settings for the accessibility
preview; they are not injected by the gallery.
