# Native redesign — TestFlight build 12

## Scope

This release implements the design direction in SwiftUI. The HTML prototype is
not the application binary. Build 11 shipped only part of the direction; this
release changes the actual screens and navigation.

- Four primary destinations: Plan, Recipes, Groceries, and Table, with profile access.
- Original tomato orange, warm canvas, stronger supporting text, consistent display type,
  rounded recipe photography, selected-state icons, and system glass navigation.
- Photo-led selected dinner, smaller date numerals, week/month views and calendar jump.
  Existing agenda swipes, night menus, long holds, and meal/step rearranging remain.
- Visible recipe search, All/Favorites/Weeknight/Saved filters, and aligned photo cards.
- Recipe editing, serving scaling, a graphical planning calendar, cook/yield selection,
  and explicit Start/Resume cooking.
- Cooking snapshots the instructions, ingredients, and servings. Position and notes
  persist locally; minimizing exposes a resume control across tabs. Finishing records
  the cooked meal, saves notes, clears the session/timer, and shows confirmation.
  Legacy sessions acquire snapshots when resumed. Starting another recipe asks before
  replacing the active session.
- Full-screen groceries, week/meal selection, meal picker, ingredient provenance,
  shopping progress, and manual extras visible in meal mode.
- My Table/Household scopes, post/thread navigation, and profile tabs for dishes,
  conversations, and the owner's private saved recipes.

## Native verification

Signed Debug simulator build succeeded on iPhone 17 Pro / iOS 26.2. The design
rule check passed for 117 Swift files and all 10 shared widget tokens matched.
XCUITest verified navigation through all four destinations, visible search,
week/meal controls and meal picker, Table scopes, and profile tabs. Native
light/dark screenshots were inspected. The initial cooking test was obstructed
by the simulator lock screen; the rerun activated the app and passed.

The cooking test edited a real in-memory recipe through the editor, added and
saved two steps, started cooking, inspected ingredients, advanced to step two,
minimized, changed to Groceries, resumed on step two, finished, and verified
both the success state and removal of the resume control. The month calendar
was also opened and captured. These checks use `-plated-design-review`, which
selects an isolated in-memory store and never seeds a signed-in user's data.
The companion NativeFlowChecks.swift records the external XCUITest harness.

Release archive/export is being finalized; distribution status is recorded in
implementation-status.md after confirmation from App Store Connect.

## Remaining external verification

No new CloudKit schema fields are introduced here. Verification of build 11's
optional grocery/thread fields in Production remains outstanding because
CloudKit Console access requires Apple Account sign-in. Cross-account and
physical-device interactions are not established by simulator tests.

Instacart's authenticated handoff is retained, but its production partner key
is still missing. A real shopping link and checkout are not verified. This
release does not claim otherwise. Contact photo selection needs the user's
permission; Sign in with Apple does not supply an account photo automatically.
