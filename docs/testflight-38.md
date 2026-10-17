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
skipped, zero failures** (`build/household-reinvitation-verified.xcresult`).
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

Build 38 is being packaged under the user's existing authorization to commit,
push, upload and distribute to all internal and external testers. Signed-package
verification and App Store Connect availability will be recorded after readback.
