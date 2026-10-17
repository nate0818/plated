# TestFlight 1.0.1 (38): reinvitations and profile delivery

October 17, 2026. The user confirmed that Alessandra saw “invited you” and
“removed you” after opening a NEW invitation sent after removal. Code inspection
confirmed that creating an invitation never superseded the raw account block.
The same review found stale profile publication and queue-acknowledgement races,
and zone readers skipping failed individual records before advancing tokens.
These are confirmed code defects, not proof of the exact production transport
failure on the two phones.

## Corrections

- Fresh household links receive an organizer-published capability before a ready
  link leaves the app. Old links stay blocked; a later removal invalidates prior
  capabilities. Acceptance, interrupted seat setup, repeated opens, identity
  fallbacks, pending removals and changed-record failures are covered.
- All invitation headings, explanations and actions derive from one state.
  Blocked access offers no Join claim or name prompt. Interrupted joins say
  “Finish joining”; own links do not invite the organizer to join themself.
- Role/rotation edits preserve linked personal fields in the fetched record.
  Same-account device updates and intentional profile clearing are supported,
  while pending local edits remain protected. An empty account ID on an invited
  seat no longer discards the joining person's own name, bio or photo. Profile
  adoption must save before it queues uploads or announces success; failure
  restores the original profiles, invitation state and cook assignments. Joining
  drains completed adoption immediately instead of parking until dismissal.
- Upload acknowledgements remove only the revision sent. The seat fingerprint
  acknowledges the serialized content, not a newer edit made during the await.
- Household and Table readers fail a page on any individual record failure.
  The next pull retries it. A one-time complete reread recovers records older
  readers skipped, and locally protected own profiles are republished when an
  older household write overwrote them.
- Access edits persist per device and replay against fetched server state.
  Upgrade migration inspects the previously persisted queue before new edits.
  Delayed acceptance cannot supersede a concurrent revocation.

No CloudKit schema/model fields changed. New grant metadata uses the deployed
string-list field. Both phones need build 38 and a newly generated invitation;
older clients deliberately continue to refuse a revoked account. This is the
app's existing bearer-invitation model, not a change to CloudKit's public-share
permission model. No real household membership was changed during verification.

## Verification

Full native suite: **474 executed, 470 passed, four optional Calendar checks
skipped, zero failures** (`build/household-reinvitation-final-verified.xcresult`).
Transport failures are injected; these tests exercise production codecs,
publication policy, merge, queue and activity projections without live accounts.
The failed-adoption regression initially exposed SwiftData retaining a joined
state after rollback; the explicit transaction restore and retry now pass.
The two-store photo/activity delivery tests pass in both directions. They do
not establish live multi-account delivery.

Five actual invitation-sheet UI scenarios pass on iPhone 17 Pro / iOS 27:
fresh invitation, blocked link, blocked link at Accessibility XXXL, interrupted
setup and own link (`build/household-invitation-ui.xcresult`). Screenshots and
accessibility trees are exported to `docs/household-reinvitation-2026-10-17/`.
Visual review shortened the blocked heading to “New invitation needed” to
reduce unnecessary scrolling at the largest text size. All five scenarios
then passed again with the final copy on iPhone SE (3rd gen) / iOS 26.5,
including the largest Dynamic Type setting and a reachable Close action
(`build/household-invitation-compact-ui.xcresult`). Final screenshots and trees
are in the `compact/` subdirectory. The final adoption transaction change has
no view/layout changes; it is covered by the complete native rerun above.

Design, shared-token and deployed-schema gates pass: 172 Swift files and
159 recorded CloudKit fields. The phone is disconnected and a second test
account is unavailable. Real two-account remove/reinvite, photo delivery and
activity delivery remain a release-verification limitation; no “zero bugs” or
100% live verification claim is made.

## Distribution

Source commit: `8299509fc0b3347ffaf4ab808bd8f1e901e1f6d5`, pushed to
`origin/main`. The final signed archive/export passed with unchanged native
source fingerprints, matching app/widget versions, production CloudKit/APNs,
WeatherKit, sharing/background keys, privacy manifests, signature trust/integrity
and matching binary/dSYM UUID. The package is retained in `build/releases/38/`.
An earlier packaging pass surfaced a main-actor callback annotation warning;
that was corrected, the full native suite rerun, and the final archive rebuilt
before any upload.

Apple accepted the final 17,547,995-byte upload with no errors. Delivery/build
ID: `400ca973-8ee0-4316-8784-992e6e6c0096`. At
`2026-10-17T21:48:22.790097+00:00`, processing was `VALID` and both internal
and external states were `IN_BETA_TESTING`. Both configured tester groups include
build 38. Tester notes were read back successfully, automatic notifications are
enabled, and build 37 had no individually assigned testers to carry forward.
Older builds were not expired. The signed-package hashes and complete availability
receipt are in `docs/testflight-38-release.json`.

TestFlight: https://testflight.apple.com/join/2exAQgYs

## Remaining live account check

Use two real iCloud accounts on build 38 or newer. Generate a new invitation,
accept it, then confirm the joining person's photo and profile on the organizer's
phone. Edit the photo and bio on the member's phone; confirm the organizer sees
the change after refresh and relaunch. Mark a newly shared household dinner
cooked, then share a dish at the Table and confirm the member's 7-day activity
on the other phone. Personal history from before joining remains private.
Remove the member, confirm the previous link is refused, issue a new invitation,
rejoin, and repeat removal to confirm the prior reinvitation no longer works.
These live steps have NOT been run by this agent; disconnected hardware and the
unavailable second account remain the constraint.
