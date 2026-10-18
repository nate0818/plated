# Household and Table header repair

October 17, 2026. The user supplied real-device crops showing the Table audience button and household heading. These were missed in the earlier visual audit. The changes below address the reported controls; they do not certify every app state or live two-account delivery.

## Findings and corrections

1. **Household settings looked like a stray mark beside the surname.** It was an 11-point slider glyph inside the entire title button. The title also shrank to 60% of its intended size to accommodate controls. Settings is now a separate 44 × 44 button in the utility row, using an 18-point symbol and a clear accessibility label. The name occupies its own row and wraps. Named households open settings without automatically focusing the name field; unnamed households retain that shortcut.
2. **Household and Table bells did not match.** The household used a 36-point control with a 15-point symbol; Table used 44/18. Both now use 44/18, and the shared default is 44.
3. **The People chip's surface was shorter than its label.** Its minimum-height frame was outside its background. Vertical padding and a 44-point minimum now precede the surface and border.
4. **Table chrome crowded out the feed.** Its heading now uses the display token with tighter surrounding spacing. Other tab mastheads retain their existing layout.
5. **“Just you for now” asserted membership from the wrong data.** The count came from a reaction denominator that includes historical post authors. The card now says “See who can view posts” and opens the authoritative People view.
6. **Household used the system background.** An ornamental gradient did not establish a base canvas, so the screen fell back to white/black rather than paper/deep green. It now explicitly uses the shared canvas token.
7. **The audience card lost button semantics.** A wrapping accessibility element outside its background was exposed as an `Other` element while the actual nested button had a different label. The surface now belongs to the button label, and its name, hint, and identifier attach to the native Button.

No membership operations, CloudKit data/model/schema changes, or real-account resets were performed. The profile/invitation/activity fixes shipped in build 39 remain intact. Concurrent website work is outside this native-app change.

## Verification

Standard profile from Design SwiftUI Interfaces. Tests use isolated simulators and the app's in-memory design-review fixtures. No screenshots of the user's private household are committed here.

- Plated native suite: 481 passed, four opt-in Calendar tests skipped, zero failures; `build/header-controls-40-unit.xcresult`.
- Header UI matrix: 22/22 passed, zero skipped. SE (iOS 26.5): 7; iPhone 17 Pro (iOS 27.0): 8 including actual VoiceOver speech; iPad Pro 11-inch M5 (iOS 26.5): 7. Bundles: `build/header-controls-{se,pro,ipad}-final.xcresult`. Machine-readable devices/results are in `ui-results.json`.
- Header test paths include Settings → Back → Activity → Back → Settings, Table → People, light/dark, long household names, and the largest accessibility text size. They assert control bounds, alignment, title wrapping, and the actual destination.
- Accessibility audits cover contrast, target region, description, and clipping for the modified headers. Full-screen findings are retained in attachments rather than silently treated as header failures or as proof of a clean full screen.
- `make design tokens` passes: 172 Swift files, 10 shared widget/native tokens, 31 website/native palette tokens, matching timer-activity copies.
- Static skill audit: 164 files; three high, 448 medium, seven low heuristic matches. The three high matches are persistent invitation/log IDs and a throttled TimelineView, not transient view identity or unscoped animation. The header's fixed control frames are intentional tap targets.

An initial unsigned simulator build crashed when Settings initialized CloudKit. The normally signed simulator build with its CloudKit entitlements resolves that harness problem; the failed bundle is retained separately. A subsequent failed Table query exposed the real semantic wrapping issue described above, which was corrected before final testing.

## Limits

Actual simulator VoiceOver traversal confirmed Settings, Notifications, and People as buttons and Meadows as a heading; the transcript is `voiceover-header-speech.txt`. No new physical-device double-tap, active-call safe-area capture, iOS 18 runtime, keyboard/pointer, right-to-left, reduced-effects, or live multi-account check was collected for this header change. The user disconnected the phone. No custom animation was added; no Instruments frame-rate claim is made. Existing press feedback already respects Reduce Motion.

Provisional skill rubric: platform fidelity 13/15; information architecture/layout 13/15; semantics/visual system 14/15; interaction correctness 17/20; motion/material craft 12/15; accessibility/adaptation 7/10; implementation/performance 8/10. Total 84/100, capped by unverified reduced-effects and physical input paths. This is an evidence-limited assessment of the modified headers, not an app-wide score. Test pass counts do not establish a flawless app.

### Additional audit output triage

The compact-phone audit also reports a small hit area for “Sun + Sat.” That is a noninteractive schedule status Text, not a control (HouseholdHomeView member row); the adjacent profile and menu are separate buttons. Table's contrast reports identify elements in the retained, hidden Plan tab (for example “Salmon Night” and date labels), not pixels visible in the Table screenshot. These raw reports are retained in this folder. They do not establish contrast failures in the modified headers, and they are not silently counted as a clean full-screen audit.

The iPad audit additionally flags two weekday cells below the header. Their label uses inkSecondary (#606958) on canvas (#FAF9F4), a calculated token contrast of 5.44:1. The screenshot shows the label intact. These remain recorded automated findings; no pixel-perfect contrast claim is made for the separate rota component.
