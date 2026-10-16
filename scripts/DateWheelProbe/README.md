# Date wheel UI verification

This standalone XCTest UI probe runs against an installed, signed Debug Plated
app. It launches `-plated-design-review`, which uses the memory-only sample store.
It does not edit a real household or send CloudKit changes.

After building/installing the app, run from the repository root:

```sh
xcodebuild -project scripts/DateWheelProbe/Probe.xcodeproj -scheme WheelProbe \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID' \
  -derivedDataPath build/date-wheel-probe -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 test
```

Only this standalone UI runner is unsigned; keep normal Plated app signing and
entitlements. The probe verifies selected-date centering, date taps, slow and
fast flicks, Today, repeat launches and background/foreground. It retains a
screenshot after the gesture sequence and on verification failure. It does
not measure physical haptic feel or replace VoiceOver/device testing.
