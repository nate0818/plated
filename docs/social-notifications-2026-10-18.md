# Social phone notifications — 18 October 2026

Build 41 adds visible APNs delivery for comments, direct replies with a parent
comment ID, reactions to posts/comments, question votes, and accepted household
or Table invitations. This addresses the transport gap behind activity appearing
only after pull-to-refresh. It does not establish a measured delivery guarantee.

## Implementation

- The app records confirmed CloudKit writes in a durable, per-device outbox.
  Failed requests retry; later edits replace queued work without stale replies
  erasing the replacement. A household seat is attributed to its claimant,
  even when the original invitation was authored by the organizer.
- The server verifies a fresh native Apple web token, reads the actual record,
  related post/comment, root and CKShare, and derives recipients from accepted
  membership. It rejects claimed-author mismatches, removed members, foreign
  roots and cross-post reply targets. Native web tokens are never stored/logged
  and rotate on each Apple response.
- A transactional queue persists before acknowledgement. Delivery leases,
  exponential retries, token invalidation checks and a one-minute worker recover
  transient failure independently of either phone. APNs acceptance is not proof
  that iOS displayed an alert.
- Comments/replies are active; reactions are passive. Category switches, mutes,
  blocks, notification permission and local quiet hours are respected. A direct
  reply can pass a thread mute. No self-alerts or replay of old activity on first
  device registration.
- Atomic routing chooses the local fallback or server for an event/device.
  Outages retain local fallback availability; duplicates remain possible during
  an ambiguous transport failure, and APNs itself is not exactly-once delivery.
- Visible pushes also request a refresh. Opening the alert pulls before routing;
  inline replies preserve the parent comment. Known read receipts clear remote
  alerts, but a missing CloudKit row does not prematurely clear an arriving one.
- Existing foreground polling and CloudKit wake-ups still populate the feed and
  activity list. New posts, legacy name-only mentions/replies, planning and recipe
  activity continue through the existing local notification path.

## Deployed backend

Project: `dyvrksooelbkzkprqlhk`. Function: `social`, version 3, active.
Artifact hash: `242828f93441445a4587af0e11fe4e936c1fd2263f7253b1705b250d77426a7f`.
Development and Production API tokens are configured in service-only storage
with Nate's explicit approval and restricted to the project's domain.
The retry secret is in Supabase Vault. No credentials are committed.

Migrations:

- `20261018073249_social_notifications.sql`
- `20261018074214_social_notification_worker.sql`

All social tables have RLS and no public/anon/authenticated grants. Only the
service role calls queue functions. Requests authenticate a directory session;
the worker uses a separate secret. Security advisor's no-policy INFO notices
are intentional for these service-only tables. The existing unrelated leaked
password protection warning remains unchanged ([Supabase guidance](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)).

## Verification evidence

- Native suite: 522 executed, four opt-in Calendar integration skips, zero failures.
  `build/social-notifications-release41-unit.xcresult` is the final run.
- Deno: 21 tests passed, zero failures; endpoint type check passed with committed
  dependency lockfile. Tests cover actual verification/policy functions and APNs
  payload/classification, using injected CloudKit responses.
- Transactional SQL checks executed against the deployed functions and rolled
  back: grants, enqueue idempotency, leases, retries, cancellation, removal,
  token/account rebinding and local-versus-server routing.
- No-session, forged-session and forged-worker endpoint probes returned 401.
- Scheduled worker returned HTTP 200 with `processed: 0`; no genuine customer
  events were manufactured or alerts sent for this test.
- Design, shared tokens, CloudKit schema, plist lint, privacy page lint and diff
  whitespace checks passed. No new CloudKit schema fields.

The first added native test run exposed test identity leakage into another suite;
the fixture now restores its identity/defaults. That failed run is not release
evidence. A later review caught and fixed organizer-authored invitation seats
being excluded from the notification queue; the regression uses that real case.

## What Nate and Alessandra need to verify

Do not remove or reinvite a working household just to test notifications.

1. Both install build 41 or later in TestFlight and open Plated while online.
   Leave it open briefly to register. Both must be signed into Apple/iCloud and
   Plated's directory. Enable iOS notifications and Plated's Household and Table
   activity; for the timing check, exclude Plated from Scheduled Summary and
   temporarily disable Focus. These are test conditions, not normal-use rules.
2. Nate backgrounds Plated and locks his phone. Alessandra writes a new comment
   on Nate's post. Record send and alert times. Expect one named notification
   with the comment excerpt, without Nate refreshing/opening the app first.
3. Nate taps it. Expect the correct thread, visible comment and accurate unread
   count. Reply from the notification and verify the reply reaches Alessandra
   with the correct parent. Repeat with roles reversed.
4. Like a post, then a comment. Expect the count/reaction to appear automatically
   on the other phone and a passive notification (Notification Centre, no sound).
   Unlike/re-like must not produce an alert storm. Self-reactions stay silent.
5. Keep the thread open on the recipient phone and add a comment from the other.
   Expect automatic content update and no redundant banner over that thread.
   Mute it: ordinary comments stay quiet; direct replies remain allowed. Test
   the category switch and unmute afterward.
6. On a genuine new household invitation, accept it on the second account.
   Expect one organizer notification and matching membership/profile on both
   phones. A fresh invitation after removal must not show the old removal copy.
   Profile photos and cross-account activity sync still need this real check;
   notification transport does not itself repair photo data.
7. Briefly take the sender offline, write a comment, restore connectivity and
   reopen Plated. Expect one eventual delivery. Record a case with the recipient
   offline too, then verify content and alert after reconnection.

If any step fails, collect build numbers, approximate time and timezone, which
phone sent/received, foreground/background state, and a screenshot. Do not send
Apple tokens. Server delivery counts/reasons can distinguish registration,
CloudKit verification, queued retry and APNs acceptance from presentation issues.

## Remaining release gates

Nate explicitly asked to continue without the phone. Native web-auth round-trip,
real APNs lock-screen presentation, inline reply from iOS, foreground suppression,
two-account latency, invite acceptance and profile propagation are **not verified**.
Automated tests do not replace these checks. This is a TestFlight candidate.

The bundled privacy manifest and policy sources reflect selected shared content,
membership, interaction and delivery metadata processing. App Store Connect's
privacy answers and the public privacy URL must match before a public App Store
release; see `app-store-privacy-disclosures.md`. Website edits outside the privacy
page belong to another task and are excluded from this notification commit.

TestFlight upload/distribution status is recorded below after Apple processing.
