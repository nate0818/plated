# Plan and Household literal approval corrections

Reference: the unchanged October 18 approval renderer, `docs/design-polish-review-2026-10-18/review.js` (`weather`, `household`, and `ipad`). Reviewed against the current `DESIGN.md`; older design specifications do not supersede this approval.

## Corrections

- **Forecast unavailable:** restored the exact heading “Forecast unavailable” and body “Your dinner plan is still available.” with the approved decorative weather symbol. The existing “Try again” action still invokes the same forecast refresh. Loading, denied permission, permission request, past-date, out-of-range and live-attribution branches are unchanged. The message wraps rather than truncates.
- **Choose a cook:** added “Choose someone. Changes apply after saving.” above the choices and changed the commit label to “Save cook”. Cancel still discards the tentative choice, and saving still uses the existing validation, persistence, rollback and error handling. The standing-rotation explanation remains visible.
- **Wide Tomorrow preview:** appended the positive stored planned-meal serving count beside the existing actor line. It uses the same local meal or shared ledger entry already chosen for the preview, never the recipe’s default or an invented fallback. Unknown/non-positive values are omitted, and empty nights retain “No dinner planned”. The phone layout, selected-day navigation and wide/narrow layout switch are unchanged.

## Coverage changes and evidence limits

- `ApprovedPolishTests.testHouseholdRotationRequiresExplicitSave`: query now uses “Save cook”; added an exact instruction assertion. Both cancellation and saved-result assertions remain.
- `FidelitySupplementalStatesTests.testDarkRotationPickerCancelsWithoutSaving`: updated the save-control query and added the exact instruction assertion. Cancellation still must preserve the original rotation.
- `FidelityAdditionalStatesTests.testForecastUnavailableAndRetryKeepTheDinnerBothAppearances`: exact body updated and heading asserted. The retry, retained dinner, absent weather/attribution, and enabled recovery assertions remain.

All six changed Swift files parse successfully with `swiftc -frontend -parse`; `git diff --check` passes. These are source checks, not native-render or interaction passes. The already-running pass 4 binary predates these corrections. Fresh app/UI builds and native captures are required before marking them visually or interactively verified. The wide preview also needs a fresh iPad assertion/capture of the stored serving count.
