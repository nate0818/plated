# TestFlight 1.0.1 (46) — October 21, 2026

Build 46 is available to the existing Internal and External TestFlight groups.
[Install or update through TestFlight](https://testflight.apple.com/join/2exAQgYs)
and check that the installed app reports **1.0.1 (46)**. Group availability
does not prove installation on any particular phone.

The app source is `afe2f99` on `codex/approved-design-fidelity-46`; the later
`eae5bd4` commit records test and release evidence without changing app code.
The signed app/widget export is `build/export-46-afe2f99/Plated.ipa` in the
isolated checkout, SHA-256
`fcddb74165450f96cf912eb1bf24ac0f5a183650e728f239dc1e3c2b315cdeff`.
Apple accepted upload delivery `c4da9151-e417-4814-b3d3-93a30c0eb823`.
App Store Connect read-back shows build 46 `VALID`, Internal and External
`IN_BETA_TESTING`, Internal all-build access, and explicit External membership.
Automatic tester notification is enabled; tester notes were saved and read
back. Build 46 has no individually assigned testers outside those groups.

The corrected compact-iPhone simulator baseline passed 178 tests, skipped 12
for documented environment/opt-in reasons, and failed none. The two old-build
upgrade methods require a separate clean-simulator sequence; the one-recipe
build-45-to-46 upgrade was checked there. Focused iPad,
household, widget, Calendar and simulator VoiceOver checks are recorded in the
[candidate evidence](design-fidelity-2026-10-18/continuation-status-2026-10-21.md).
Nate explicitly asked to distribute this beta without waiting for live checks.
Physical VoiceOver, installed widgets, device Calendar, push delivery/timing,
and both-way household/profile/Table sync on two real accounts remain
**unverified**. The full route/state visual ledger, iOS 18 runtime, and broader
in-place upgrade coverage also remain open. None is counted as a pass.
