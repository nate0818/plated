# First-run UI verification

Runs against an installed Debug Plated app. The `-plated-review-onboarding`
launch flag uses an empty in-memory cookbook and bypasses live-store repairs.
It does not reset a real household. Use an isolated simulator.

```sh
xcodebuild -project scripts/FirstRunProbe/Probe.xcodeproj -scheme FirstRunProbe \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID' \
  -derivedDataPath build/first-run-probe -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 test
```

Exercises local welcome, paste/review/save/detail/planning, manual entry,
cancellation, invalid invitation links, and accessibility-size reachability.
Screenshots are kept as XCTest attachments. Real Apple sign-in, successful
CloudKit joining, and camera scanning require a signed-in physical device.
