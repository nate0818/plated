# Historical header assertions and the current route

`HeaderControlTests.checkHousehold` was written for the former hidden fifth-tab Household page. It expects a household-local bell and a title below that control row. Current `MainShellView.handleDebugLaunchFlags` explicitly maps the historical `-plated-tab home` spelling to a pushed Household destination from Plan. The only production `HouseholdHomeView` use sites are WeekView and PersonProfileView, both with `embedded: true`; that form intentionally omits the duplicate local bell. The original approved Household proposal uses Back, title and separate Settings in one compact row at normal text sizes.

Therefore the three historical `testHousehold*` methods in HeaderControlTests describe an obsolete destination/geometry, rather than the current approved product. They remain intact as historical source. Their results must not be counted as passes for the current candidate, nor should their former header be reintroduced to satisfy them.

The replacement `DesignFidelityTests.testApprovedPushedHouseholdHeaderAndActivityRoute` retains concrete checks: title, separate aligned Back/Settings, 44-point targets, no overlap, Settings destination/name field, return navigation, dismissal back to Plan, Activity from the real shell and return to dinner. Both appearances are selected. Largest-text and long-name current-route coverage still needs execution/reconciliation before a full release baseline. Existing Table header and accessibility diagnostics remain applicable separately; a harness-wide green claim is not made here.

This is a documented product reason and replacement-coverage reference, not a skipped-test pass. Native verification is pending on the final binary.
