# TestFlight build 16 — Native hold and drag

- Native source: `ad8227d`
- Version: `0.1.0 (16)`; app and widget both 16
- IPA: `build/releases/16/Plated.ipa`
- SHA-256: `7397e5ad91bca5fe852186d5ead17fc1b6c265849d1e53a93b05f168f51c2202`
- Upload: succeeded September 4, 2026 at 14:02 EDT.
- Delivery UUID: `f7549e62-6273-4700-883f-c05fde3fde0b`
- Distribution: VALID; Internal and External both IN_BETA_TESTING.
- App Store Connect build ID: `f7549e62-6273-4700-883f-c05fde3fde0b`
- External includes build 16; Internal has access to all eligible builds.

Recipe steps now use native drag-and-drop from their numbered grip or unfocused
text. Focused text keeps native selection, and the grip works with the keyboard
open. A completed drop changes the draft; Save commits the order and Cancel
discards it. Step fields have explicit accessible names. Move up/down actions
and keyboard controls remain available.

Week's featured dinner and agenda cards, Month cards, and day-detail cards lift
and drop onto dates. Day detail now keeps a date strip visible while its meals
scroll. Same-slot occupants swap rather than disappear; recipes, cooks, servings
and grocery identities travel with the original meal. Cooked meals and past
destinations are protected. Existing swipe actions remain, and day detail adds
an explicit Move action. Menus that competed for the card's hold gesture were
removed from the drag surface; their editing/moving alternatives remain visible.

The native checks caught an additional defect: a cropped image's hit area
extended outside its visible card and intercepted Week's date targets. Artwork
and the featured card now constrain hit testing to their layout bounds.

Four native XCUITest flows passed with actual one-second press-and-drag gestures:

1. Move a recipe step from first to last, save and reopen, drag its text back,
   cancel and reopen, then reorder with the keyboard open using the grip.
2. Drag Week's featured dinner onto an occupied date, verify the swap, and drag
   an agenda card onto another agenda row to swap back.
3. Move breakfast from day detail onto another date, preserving its dinner.
4. Move a Month meal card onto a calendar date.

Nine isolated model checks passed for swaps, identity, servings/cook/recipe
preservation, meal-slot isolation, stable payloads, cooked/past protections and
unrelated payload rejection. The [native test source](native-build-16/NativeDragChecks.swift)
and [before](native-build-16/steps-before.png)/[after](native-build-16/steps-after.png)
screenshots record the checks. [Week](native-build-16/featured-meal-moved.png),
[day](native-build-16/day-meal-moved.png), and [Month](native-build-16/month-meal-moved.png)
screenshots were also inspected. Test data exists only in the explicit DEBUG
in-memory design-review container; it never enters a user's persistent store.

The signed Debug build, Release archive/export, app/widget version checks and
strict recursive signature verification passed. All 120 Swift files pass the
design check, and all 10 app/widget tokens match. Physical-device drag behavior
and cross-account synchronization are not established by simulator tests.
Earlier beta limitations remain in the TestFlight notes.

Public testing link: https://testflight.apple.com/join/2exAQgYs
