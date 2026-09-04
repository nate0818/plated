# TestFlight build 18 — Cook exit and physical meal lift

- Native source: `bcedb03`
- Version: `0.1.0 (18)`; app and widget both 18
- IPA: `build/releases/18/Plated.ipa`
- SHA-256: `4762a51eccab6a55f4e2d90464b1467073e3a1f139dc60b53f4d44a150bd6330`
- Upload: succeeded September 4, 2026 at 14:50 EDT.
- Delivery UUID and App Store Connect build ID:
  `de035d9d-c112-41c1-a2fe-41834d57cd7f`
- Distribution: VALID; Internal and External both IN_BETA_TESTING.
- Automatic TestFlight tester notification is enabled.

Cook Mode now separates pausing from ending. The down control is labeled
Minimize cooking and preserves the current step, note draft and timer for the
global Resume cooking bar. The visible End control asks for confirmation,
clears that session and its pending timer notification, restores the device's
idle-timer behavior, and returns to the recipe while keeping the meal planned.

Planned meals now use an explicit native item-provider lift. The newer
`draggable` path passed simulator automation but did not reliably begin inside
a Button or SwipeRow on a physical iPhone. The replacement matches the native
path used by recipe-step reordering. Its preview keeps the dish, meal slot and
title together in a compact material card. Week rows, Day detail dates and
Month cells take a persimmon tint, outline and small scale while targeted;
landing retains the existing haptic and occupied-slot swap behavior. The
explicit Move action remains available for accessibility and discovery.

Native XCUITest completed four interaction flows with no failures. It ended a
session from step two, verified Resume disappeared, restarted at step one, and
ended again. It also performed actual one-second holds and drags from the Week
featured card and agenda row, the Day detail card, and the Month agenda card,
then verified the meal at each destination. The
[confirmation](native-build-18/end-cooking.png),
[Week result](native-build-18/week-meal-moved.png),
[Day result](native-build-18/day-meal-moved.png), and
[Month result](native-build-18/month-meal-moved.png) were captured from the
signed Debug app. The [native test source](native-build-18/NativeInteractionChecks.swift)
records the flows. Test content exists only in the explicit DEBUG in-memory
review container.

The Release archive/export, app/widget version checks, App Store Connect
upload validation, all 120 Swift-file design checks, and all 10 shared token
checks passed. Apple marked the uploaded build VALID. Local certificate trust
evaluation of the archive reported `CSSMERR_TP_NOT_TRUSTED`; the exported IPA
was accepted without errors and is in beta testing. Physical-device drag feel
still needs hands-on confirmation from build 18; simulator automation cannot
establish tactile quality.

Public testing link: https://testflight.apple.com/join/2exAQgYs
