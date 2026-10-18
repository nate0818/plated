# Social activity delivery: October 17 investigation

Status: foreground fixes implemented and tested; reliable social phone
alerts remain a release blocker. This is not a completed end-to-end fix.

## Report

Nate could not see Alessandra's comment or dish reaction, or their activity
notifications, until pulling down to refresh. Comments and household joins
also did not produce timely phone notifications.

## Confirmed findings and changes

1. There was no ongoing foreground reader. Scene activation alone could
   skip a read for sixty seconds. `ForegroundSync` now owns one cancellable
   loop, reads immediately on activation, and waits five seconds after each
   completed read on social/household screens and fifteen seconds elsewhere.
   Failure delays increase to sixty seconds; backgrounding stops scheduling.
   All reads still go through `TablePull` to prevent cursor races. Slow
   networks add to those intervals; this is a fallback, not a realtime SLA.
2. `TableShare` silently treated failed reads as successful empty results
   and erased cursors on every error. It now reports failure, logs the
   failure, and preserves cursors on transient errors. Only expiration or
   confirmed zone deletion resets them.
3. The Table's failed-write queue dropped comments and reactions after
   twenty attempts, despite receiving only a Boolean failure from the
   transport. It now retains them, backs off up to five minutes, and sends
   one attempt per key at a time. A new edit resets its delay; an older
   completion cannot discard the new intent. Existing queue JSON remains
   readable.
4. CloudKit subscription failures were discarded. Creation/verification now
   logs outcomes, retries failures while active, and rechecks after an
   iCloud account change. Successful checks are cached for six hours.
5. The background callback's task-group timeout still waited for a
   cancellation-insensitive CloudKit child. A separate one-shot deadline
   now completes the OS callback even while the shared read remains in
   flight. A successful empty read reports `noData` rather than `newData`.
6. Social notice keys were remembered before saving the bell rows. Keys are
   now remembered only after a successful save, matching the household path.
7. APNs device registration cached only token/time. The cache now includes
   a digest of the directory session and APNs environment, and failed
   registration retries during foreground maintenance. Credentials are not
   written to defaults.
8. A completed remote merge made the Table view initiate another full
   refresh, including refresh haptics. That observer now updates connection
   state; the central reader already merged the models and ledgers.

Bulk household publishing and subscription/device maintenance do not run on
every five-second tick. Incoming activity is read before bulk publishing.
Preview-backed launches remain excluded from the live reader.

## Phone notification gap: still open

The deployed Supabase functions were inspected read-only. `invite` is an
invitation nudge; there is no deployed comment, reaction, or accepted-invite
delivery function. Eight device registrations exist (six production, two
sandbox), which demonstrates registration data, not delivery. The
announcement delivery table has no receipt rows. No artificial alerts were
sent to Nate, Alessandra, or other testers.

Social phone alerts currently require a silent CloudKit push, an app wake,
a successful fetch/merge, and then a local notification. Apple explicitly
does not guarantee background delivery:
[Pushing background updates](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app).
The client repairs improve this path but cannot turn it into reliable
visible server push.

Simply substituting record-based alerts is insufficient:
[CKQuerySubscription](https://developer.apple.com/documentation/cloudkit/ckquerysubscription)
works in private/public databases, not the shared database used by household
members. A generic shared-database alert cannot name the comment and would
also announce housekeeping and unrelated changes. Neither workaround is
implemented.

The remaining implementation needs recipient-authorized event delivery:

- Generate a durable event after the underlying comment/reaction/join is
  confirmed. Preserve a stable event ID across network retries.
- Resolve the actual post owner, reply recipient, or household organizer;
  verify current membership and removal/reinvitation generation. A client
  supplied recipient ID or CloudKit ID alone is not server authorization.
- Deliver a visible APNs alert without requiring the recipient app to wake.
  Use the same event identity for the bell, badge, deep link, and duplicate
  suppression when CloudKit later merges the change.
- Enforce recipient preferences, blocks, muted posts, quiet hours, expiry,
  and no self-notifications. Group reactions; do not sound on every plate.
- Persist delivery attempts and retry transient APNs errors. Record Apple
  acceptance separately from observed device delivery. Handle stale tokens,
  account changes, and sign-out bindings.

No new server delivery path or schema was deployed by this change. Build 40
remains the distributed beta; these fixes are not an announcement that
social lock-screen delivery is complete.

## Verification

- Full native suite: 495 tests, 491 passed, four optional Calendar tests
  skipped, zero failures. Final result: `build/social-delivery-commit.xcresult`.
- Ten added regressions exercise the production foreground loop, cancellation
  during an uncooperative read, retry timing, one-shot background callbacks,
  CloudKit cursor policy, queue retention/old JSON decoding, registration
  cache identity, and notification save failure/retry.
- Design/token checks and all 159 recorded CloudKit fields pass. No wire
  fields changed.
- No physical two-account timing, lock-screen, or force-quit test was run.
  Nate's phone is disconnected. Simulator results do not cover APNs delivery.

## Two-phone release gate

After the server-delivery gap is implemented, use two separate real iCloud
accounts on the candidate build. Record sender save time, receiver update
time, event ID, and actual phone alert time for each case:

1. Keep Nate's post open; Alessandra comments and plates it. Confirm the
   thread/count/bell update automatically without a refresh and without a
   redundant foreground banner over the open thread. Reverse the roles.
2. Repeat while the recipient is on Plan, on the home screen, locked, and
   force-quit. A phone alert must deep-link to the correct post; reopening
   must not create a second bell entry or banner.
3. Accept a new household invitation after removal. Confirm the organizer's
   join notice, new avatar, roster, and current membership epoch on both
   phones. An old invitation must not restore access.
4. Comment offline, reconnect, and background the sender. Confirm the comment
   and its single notification eventually arrive. Repeat with a reaction
   changed before sending, and with an APNs transient failure.
5. Check a muted post, notification category off, blocked person, quiet hours,
   system notifications off, and Focus. In-app activity and system alerts
   must follow their separate settings. Never bypass system notification
   controls to meet a timing target.
6. Remove a member and change/sign out of an account. Confirm no private
   activity goes to the departed member or previous account's device binding.

Target normal-network observations: foreground updates within five seconds
and visible direct-comment/join alerts within ten seconds. Measure these;
the poll interval and APNs acceptance alone cannot establish either target.
