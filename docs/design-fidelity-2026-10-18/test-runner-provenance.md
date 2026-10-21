# UI test runner provenance — October 18, 2026

## Finding

The pass3 compact UI run executed an obsolete XCTest bundle from a retired CoreSimulator installation. The correct freshly built bundle was installed on disk, but that was not the bundle XCTest loaded. A matching built/installed SHA therefore did not prove runtime provenance.

This diagnosis was read-only. No app, simulator, cache, build setting or active test session was changed by the investigating subtask. The coordinator subsequently created the isolated replacement harness described below.

## Exact evidence

The build log `/Users/natemeadows/Plated/build/fidelity-ui-build-pass3.log` records a successful build-for-testing at approximately 08:06. Both architecture compile commands and `UIAudit.SwiftFileList` reference the isolated worktree:

`/Users/natemeadows/.codex/worktrees/plated-approved-fidelity/Plated/docs/ux-audit-2026-10-16/UIAudit/Tests`

The linked plugin contains the new DesignFidelity methods in **both arm64 and x86_64**. Its Objective-C method list also includes them. A wrong architecture slice or duplicate source class did not explain the discrepancy.

Built plugin:

`/Users/natemeadows/Plated/build/Fidelity-UI/Build/Products/Debug-iphonesimulator/UIAudit-Runner.app/PlugIns/UIAudit.xctest/UIAudit`

- SHA-256: `bf59f8623e4cb3fc80bdb520830689c98678e355e61d280da95d9625af5cd2d4`
- arm64 UUID: `04A75626-564D-3CBB-83C2-1F51E37F0CCB`
- x86_64 UUID: `61D64AA5-859F-3AFA-83B4-032F67190C97`
- Modification time: October 18, 2026, 08:06:06 local.

The current compact installation was at:

`/Users/natemeadows/Library/Developer/CoreSimulator/Devices/A61A8933-A9A0-4919-844F-0369A224FDFD/data/Containers/Bundle/Application/8303B78E-CA2E-441D-AD50-A4A9B6045141/UIAudit-Runner.app/PlugIns/UIAudit.xctest/UIAudit`

The current larger-phone installation was independently hashed and matched the built plugin:

`/Users/natemeadows/Library/Developer/CoreSimulator/Devices/6F47F1FD-52AE-4C35-8D2F-BFE1A52A332F/data/Containers/Bundle/Application/2D912342-8A10-4CF0-A06E-62EEFAC59159/UIAudit-Runner.app/PlugIns/UIAudit.xctest/UIAudit`

However, the compact XCTest session diagnostic states at **08:07:07.451** that it loaded its test bundle from:

`/Users/natemeadows/Library/Developer/CoreSimulator/Devices/A61A8933-A9A0-4919-844F-0369A224FDFD/data/Library/Caches/com.apple.containermanagerd/Dead/temp.mZ4GOT/A271510F-A842-4C68-974E-01A12F44782A/UIAudit-Runner.app/PlugIns/UIAudit.xctest/`

Both “Loading test bundle at” and the active configuration's `testBundleURL` name this retired path. They appear at lines 144 and 150 of the diagnostic retained during the run:

`/Users/natemeadows/Plated/build/Fidelity-Compact-Pass3.xcresult/Staging/1_Test/Diagnostics/UIAudit-5EB6BD76-7D51-464B-B359-C622C3B516A4-Configuration-Test Scheme Action-Iteration-1/UIAudit-F4A2B50B-E66D-4B30-9361-BD8ED01ABEDF/Session-UIAudit-2026-10-18_080705-PWYHRA.log`

Xcode can relocate these diagnostics when finalizing the result bundle; use the result bundle's diagnostic export if its temporary Staging path has disappeared.

The executable at the recorded Dead path still existed when inspected:

- SHA-256: `ff318d795dbf1e9f0bdcaa9f5551dd3dce81f970bccb967273c91241f057ea45`
- arm64 UUID: `3A4D0D90-E073-39E1-BD08-6EABA1CD9F34`
- x86_64 UUID: `5BB44941-3A87-3DC3-B4EE-CEA8DF2B0C24`
- It lacks both `testCommentInputPaddingAcceptsFocus` and `testEmptyRecipeDirectionsAreExplicitAndReachable`, which exist in the current built plugin.

This directly explains why `/Users/natemeadows/Plated/build/fidelity-compact-pass3.log` omitted new methods, reported obsolete source line numbers, and attempted the old “Add photo” selector even though the current source says “Photo.” The exact failure established here is a stale runtime test-bundle URL pointing to a retired installation. The evidence does not isolate which internal Apple component retained that URL, or prove that signing alone caused it.

## App provenance checked separately

During the replacement canary, compact app PID 34221 mapped the launcher and debug library from the current app container, not a Dead path:

`/Users/natemeadows/Library/Developer/CoreSimulator/Devices/A61A8933-A9A0-4919-844F-0369A224FDFD/data/Containers/Bundle/Application/C4D7303A-9A42-4152-A8E5-8B7BD04E0A37/Plated.app/`

Read-only `lsof` showed both loaded paths. Their hashes matched `/Users/natemeadows/Plated/build/Fidelity-App/Build/Products/Debug-iphonesimulator/Plated.app/` exactly:

- `Plated`: `b6e1941042ad404bc93caf00e3bfd0d83f794f611f37b7535599699b2ad09470`
- `Plated.debug.dylib`: `772d0104a18e9959c925cf568275bee33ca873618d477d2551bad79649d11065`

Thus the new canary's comment-input failure was not explained by a stale app installation. These hashes identify the inspected pass3 app only; subsequent app corrections require a new manifest.

## Replacement harness and canary outcome

The coordinator used all of the following to invalidate the old runner identity without deleting app data or disrupting unrelated simulator sessions:

1. Fresh derived data at `build/Fidelity-UI-Verified`.
2. A unique test product bundle identifier, `com.natemeadows.plated.FidelityVerified`.
3. Ad-hoc signing of the simulator test harness.
4. An explicit newly generated `.xctestrun` for test-without-building.
5. A bounded run of two newly added methods before any broader matrix.

The combination successfully executed the new methods. This establishes that the replacement harness ran the current tests; it does not establish which individual invalidation step was sufficient.

Evidence:

- `/Users/natemeadows/Plated/build/fidelity-verified-smoke1.log`
- `/Users/natemeadows/Plated/build/Fidelity-Verified-Smoke1.xcresult`

Outcome: **2 tests executed, 1 failure**.

- `testEmptyRecipeDirectionsAreExplicitAndReachable` passed in both appearances, including tapping Directions and reaching the explicit no-steps message.
- `testCommentInputPaddingAcceptsFocus` executed the current method and failed at its current line 151: the native text field accessibility frame was 17 points high versus the required 44. The test stopped at that assertion; padded-edge focus was not verified in this run.

The coordinator is correcting that input and building a new app candidate. This document does not claim the correction passed. Old pass3 harness results must not count as execution of the current test sources. Retain their artifacts as evidence labelled with the stale runner; any useful app screenshots require separate provenance and visual review.

## Required source and binary labels for subsequent runs

Before each verification batch, retain a manifest containing:

- Commit, worktree path, dirty diff/source digest, and hashes of relevant app and test source files.
- Exact build and test commands, configuration, build time, Xcode/SDK versions, destination identifier, runtime OS and architecture.
- App version/build plus hashes and UUIDs for the app launcher and actual code-bearing debug library when present.
- Test bundle ID, runner/plugin hashes and UUIDs, explicit `.xctestrun` path and digest, and the selected test names.
- The **runtime-loaded** app and test-bundle paths from process mappings/XCTest diagnostics, compared with the manifest. Installed-container hashes alone are insufficient.
- A canary present only in the intended test revision, with an explicit assertion that the expected nonzero test count executed. A selection that runs zero tests is not a pass.
- Result bundle and screenshot/AX-tree paths tied to this manifest, with implementation, visual review, interaction execution, and live-account/device checks labelled separately.

Record any source change after the manifest as a new candidate boundary. Do not silently reuse previous binary or test results for that change. Keep harness-only and app-only rebuilds separately identified so it is clear which executable changed and which evidence remains applicable.
