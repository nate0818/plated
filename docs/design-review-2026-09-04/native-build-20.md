# Native design audit — build 20

Build 20 closes the Account hierarchy and action-label failures visible in
build 19, and verifies the surrounding product paths that make Account useful.

## What changed

- Account now opens as a personal control center from every main destination.
  Its identity hero uses the shorter `Profile` and `Edit` actions, with the
  fuller social-profile meaning retained for accessibility.
- Primary action, tab, chip, and segmented-control labels have an explicit
  one-line contract through `plActionLabel()`. The design checker enforces that
  contract on custom capsule buttons so the original two-line CTA cannot
  return unnoticed.
- Household and Settings use full-width, descriptive surfaces. Decorative
  chevrons and diagonal arrows were removed from Account and awards; the whole
  surface responds to touch and carries the transition.
- Account and awards reflow earlier for Dynamic Type. At Extra Extra Large,
  Profile and Edit stack at full width and remain single-line controls.
- Tapping outside a presented sheet consumes the dismissing tap, preventing it
  from activating the control underneath.
- The Plan date runway is lazy, keeping month-scale navigation responsive and
  avoiding an eager two-year accessibility tree. Week, Day, and Month meal
  cards retain native hold-and-drag movement with highlighted destinations and
  landing feedback.
- Recipe steps have a dedicated long-hold handle with lift, live target tint,
  depth, continuous tracking, and haptics. When the keyboard leaves only one
  step visible, Move up and Move down sit directly above it and preserve the
  caret instead of pretending a hidden row is a valid drop target.
- Recipe intake now routes each Add Recipe entry through the same import and
  manual-entry experience. Serving selection and Plan carry the chosen yield
  into the planned night.

## Native evidence

The [standard Account](native-build-20/account-default.png) and
[Extra Extra Large Account](native-build-20/account-xxl.png) captures show the
single-line action contract and arrow-free destination cards. The paired
[standard Settings](native-build-20/settings-default.png) and
[Extra Extra Large Settings](native-build-20/settings-xxl.png) captures cover
the next level of the flow.

Interaction evidence includes Table notifications before and after reading,
recipe steps before and after a physical hold-and-drag, the focused-step
keyboard controls, and both featured and agenda meal movement. The complete
[native regression source](native-build-20/NativeCTARegressionChecks.swift) is
stored beside those captures.

Fifteen native UI flows passed across the final simulator build: Account from
all four tabs, Settings depth and appearance, Extra Extra Large layout, awards,
Table notifications, recipe step reordering and persistence, serving changes,
week/day/month meal dragging, month navigation, recipe editing, cooking
start/resume/finish, explicit cooking cancellation, household scope, and dark
appearance. The signed simulator build compiled successfully, all 125 Swift
files passed the design-contract scan, and `git diff --check` reported no
whitespace errors.

Native automation verifies behavior and visible layout. The final tactile feel
of the lift, haptics, and opener motion still requires a physical-device pass.
