# Native UX audit artifacts

Read [REPORT.md](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/REPORT.md) for prioritized findings and acceptance criteria. Read [COVERAGE.md](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/COVERAGE.md) for exactly which routes/states were rendered, exercised, source-reviewed or remain outstanding.

The `UIAudit` project is an **audit-only harness**, separate from the app’s production project and normal tests. Survey success means capture completed, not that the screen passed its UX review. Accessibility diagnostics deliberately collect issues rather than failing on each issue. Failed targeting probes are retained as transparent evidence of test limitations; they are not product regression tests.

Use a separate simulator and the in-memory preview flags. Do not replace them with live data or use the harness to send real invitations/posts.

Example focused visual run (substitute the isolated simulator ID):

```sh
xcodebuild -project docs/ux-audit-2026-10-16/UIAudit/Probe.xcodeproj \
  -scheme UIAudit -destination 'platform=iOS Simulator,id=SIMULATOR_ID' \
  -derivedDataPath build/ux-audit-probe -parallel-testing-enabled NO \
  -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO ARCHS=arm64 \
  -only-testing:UIAudit/SurveyTests \
  -resultBundlePath /tmp/plated-ux-survey.xcresult test
```

Install a fresh `Plated.app` built from the current source on that simulator first. The source build used `-derivedDataPath build/ux-audit`.

`read_source.py` prints original source line numbers while omitting blank/comment-only lines. `extract_screens.py` makes readable copies of exported Xcode attachments and contact sheets; it uses the bundled Python runtime with Pillow. Original per-run manifests map screenshots to tests, devices and times.

The baseline report is historical. The authorized implementation and verification are documented in [REPAIRS.md](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/REPAIRS.md), with new evidence under `after/`. Use `RepairTests` and `FailureRepairTests` for remediation checks; older audit probes may intentionally assert pre-repair behavior. Build the app with simulator signing (`CODE_SIGN_IDENTITY=- ARCHS=arm64`) so its CloudKit and app-group entitlements are present. The standalone UI runner can remain unsigned.
