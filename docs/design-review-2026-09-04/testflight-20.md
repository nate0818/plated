# TestFlight build 20 — interaction and Account polish

- Native source: `27c3c49ea5d1bb3a87a6008fadd96ff4ed8950cb`
- Version: `0.1.0 (20)`; app and widget both 20
- IPA: `build/releases/20/Plated.ipa`
- SHA-256: `e22126d90fb6cb8d57758ee36c0b1108991aa6fc842a2c331f622269f7376afd`
- Upload: succeeded September 4, 2026 at 17:42 EDT.
- Delivery UUID and App Store Connect build ID:
  `96312f91-e4ee-4e21-8af4-37437f9e75d1`
- Distribution: VALID; Internal and External both IN_BETA_TESTING.
- Automatic TestFlight tester notification is enabled.

Build 20 removes decorative chevrons and diagonal arrows from Account and
awards. Account destinations now behave as rich, fully pressable surfaces with
clear pressed states and purposeful transitions. The identity hero uses the
short, single-line `Profile` and `Edit` actions. At larger Dynamic Type sizes,
those actions stack at full width instead of wrapping. Household and Settings
are full-width descriptive destinations, which gives both paths enough context
without visual navigation clutter.

The same one-line action contract now applies across the app's primary buttons,
chips, tabs and segmented controls. A repository design check catches custom
capsule buttons that omit the contract. The [standard Account](native-build-20/account-default.png)
and [Extra Extra Large Account](native-build-20/account-xxl.png) captures show
the final hierarchy; the corresponding [Settings](native-build-20/settings-default.png)
and [large-text Settings](native-build-20/settings-xxl.png) captures verify the
next level of the experience.

The bottom tray now uses custom kitchen-object icons with contextual state and
motion. Plan, Recipes, Groceries and Table each have their own selected state;
the grocery basket visibly fills, gently responds to a repeated tap and empties
when the user leaves. Reduce Motion displays the same state changes without the
animated sequence.

Planner meals can be lifted and moved between Week, Day and Month destinations.
Valid dates highlight during the gesture, and the landing uses haptic feedback.
Recipe steps lift from a dedicated handle with live destination tint, depth and
haptic ticks; order persists after Save and is discarded after Cancel. When the
keyboard obscures valid drop targets, explicit Move up and Move down controls
preserve the editing caret. Cook Mode includes a visible End action that clears
the active session after confirmation.

Fifteen native UI flows passed across normal and Extra Extra Large text, light
and dark appearance, Account and Settings from all tabs, awards, Table
notifications, recipe editing and step reorder persistence, serving changes,
Week/Day/Month meal movement, household scope, and cooking start, resume,
finish and cancellation. All 125 Swift files pass the design-contract scan; all
10 app/widget tokens match. The signed Release archive exported successfully,
and App Store Connect accepted the IPA without errors.

The release evidence is preserved in `build/releases/20`, including the IPA,
source commit, version numbers, code-signing report, SHA-256 digest and exact App
Store Connect response. Physical-device review remains appropriate for the
subjective feel of the haptics and long-hold lift.

Public testing link: https://testflight.apple.com/join/2exAQgYs
