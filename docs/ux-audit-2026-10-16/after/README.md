# Remediation evidence

See [the repair ledger](../REPAIRS.md) for the implementation and verification limits. Screens use synthetic in-memory fixtures; times and names are fixture data.

- [Tonight-first Plan, Editorial](final-phone-screens/normal-plan.png)
- [Tonight-first Plan, Light](final-phone-screens/light-week.png)
- [Empty Tonight](final-phone-screens/state-empty-tonight.png)
- [Shared cooking, six servings](final-phone-screens/state-shared-cooking-six.png)
- [Completed Tonight](final-phone-screens/state-tonight-completed.png)
- [Largest-text Plan rows](final-phone-screens/ax-plan-scroll-3.png)
- [Largest-text grocery rows](final-phone-screens/ax-groceries-scrolled.png)
- [Largest-text timer](final-phone-screens/ax-cooking-scrolled.png)
- [Largest-text share preview](final-phone-screens/ax-share.png)
- [Final landscape Groceries](verified-final-screens/final-landscape-groceries.png)
- [Final AX5 thread and typing prompt](verified-final-screens/final-ax-thread.png)
- [Rejected Profile save retains the draft](verified-final-screens/failure-profile-draft-retained.png)
- [iPad Plan](failure-screens/ipad-plan.png)
- [iPad rejected recipe save](ipad-retest-screens/failure-recipe-retained.png)
- [iPad rejected planner save](ipad-retest-screens/failure-planner-no-success-receipt.png)

`verified-screens/` records the earlier visual pass. Its AX row/timer defects prompted another correction; use `final-phone-screens/` for those surfaces. `focused-screens/` records the keyboard failure before the explicit Done action; the app-level landscape capture in that directory is cropped by XCTest, so the final run uses the physical simulator-screen capture. Each named screenshot has a corresponding `-tree.txt` where available. Test-run evidence and the final focused retest are summarized in REPAIRS.md. Reproducible result bundles/raw attachment exports remain local and are ignored by Git.
