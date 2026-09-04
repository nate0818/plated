# TestFlight build 13 — native redesign

- App: Plated, `com.natemeadows.plated`
- Version: `0.1.0 (13)`; widget build also `13`
- Native source commit: `fdbb3f5` (includes the redesign in `94de2d2`)
- Artifact: `build/releases/13/Plated.ipa`
- SHA-256: `a8dc9395ef38112b8040be7434cbc0f080ce13431b09c067056c3ac938a858c9`
- Distribution: Apple processing VALID; Internal and External both IN_BETA_TESTING.

The Release archive and export succeeded, and strict recursive signature
verification passed for the exported IPA. No CloudKit model fields were added.
The native screens and UI flow evidence are in [native-build-12.md](native-build-12.md).
The build 13 Household scope check passed on the simulator, including the legacy
full-name/short-name case and exclusion of a non-household post.

App Store Connect build ID: `6dd31047-f059-49de-980b-3cc8df40c8d1`.
Both Internal and External groups include this build. Build 14 follows with the
targeted schema-probe cleanup; see [its release record](testflight-14.md).

The public testing link is https://testflight.apple.com/join/2exAQgYs.
Instacart partner configuration and Production CloudKit verification of the
previous build's optional grocery/thread fields remain outstanding. Physical
device, VoiceOver, Contacts, and cross-account sync checks are not established
by simulator tests. These limitations are also included in TestFlight notes.
