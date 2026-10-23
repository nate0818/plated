# Build 49 evidence — October 23, 2026

App source: `d2fc3fb3b02bc784c5dc4ac5129b99b520d7386f`, version **1.0.1 (49)**,
branch `codex/approved-design-fidelity-46`. Documentation/test-expectation follow-ups
do not change the signed app. The original October 18 proposal remains the design
reference; its JS SHA-256 is `cb45d1f300a0719674ad9ea87db7044789365d7b545133b377557ee156df5d6b`.
The later landscape-only iPad and leftovers instructions remain applicable.

## Corrections and proof

- CloudKit caller identity accepts Apple's direct identity or strict single-user
  envelope. Token rotation follows Apple's SDK response headers. Privacy-protected
  participant identities are supported; conflicting identities fail closed.
- Confirmed posts/questions, comments/replies, likes/votes and joins enter the
  durable verified delivery pipeline. Post saves notify only after CloudKit saves
  successfully. The server independently verifies identity, actual record author,
  root/share and accepted membership; clients cannot choose recipients or copy.
  Old edits cannot replay as new posts. Shared-zone default-owner metadata does
  not establish a guest's identity. Account switches clear prior work.
- Transient authentication errors retain queued work; expired sessions offer Apple
  sign-in. Notification recovery uses a real 44-point label target. The Activity
  banner now says “Get Table notifications” and opens Settings.
- Plan's pinned summary previously caused a geometry feedback loop at one scroll
  boundary. Measuring the entire occluding header fixes it. Both appearances and
  compact phone scroll paths pass afterward.
- iPad cooking is constrained to the existing 760-point readable width. The cook
  picker shows its full weekday between Cancel and Save cook.

## Executed checks

Bundles are retained under `/Users/natemeadows/Plated/build/`.

| Check | Bundle | Observed result and scope |
| --- | --- | --- |
| App baseline | `Release49-Logic.xcresult` | 718 passed, 4 Calendar opt-in skips, zero failures. Pre-final corrections; affected tests rerun below. |
| Durable queue/publication final source | `Release49-PostPush.xcresult` | 45 passed, zero failures (7 queue, 38 publication). |
| Backend final source | `supabase/functions/social/social.test.ts` | 32 passed; `deno check index.ts` passed. Includes token sequencing, recipients, blocked/muted/category rules, old/spoofed posts, joins, retries and APNs payload. |
| Approved phone matrix + leftovers | `Release49-Approved.xcresult` | 23 passed, one iPad-only skip, zero failures. Major approved routes, both appearances, AX5, draft recovery, seven leftovers cases. |
| iPad matrix/orientation | `Release49-IPad.xcresult` | 3 passed; both appearances, landscape/rotation attempt and draft preservation. |
| Final iPad cooking | `Release49-FinalIPad3.xcresult` | Width, pause, minimize, Back, resume and paused timer persistence passed. Full-display simctl capture inspected; XCTest's application crop was incorrect on this rotated simulator. |
| Compact extra states/invitations | `Release49-Compact.xcresult` | 10 passed; future date assertion failed because it expected visual abbreviated copy rather than the intentional full spoken date. |
| Compact meaningful retest | `Release49-CompactRetest.xcresult` | 2 passed: selected future date/action/return and pinned context both appearances. Full spoken date assertion retained. |
| Final notification/scroll/reply/photo checks | `Release49-Regression.xcresult` | 5 passed; Settings route and 44-point action, cooking return path, pinned summary, reply target/cancel, photo removal after rotation attempt. |
| Current OS launch/publication | `Release49-CurrentOS.xcresult` | 9 passed: local onboarding, paste/manual save, invitation validation, AX5 and five publication states. |
| Final draft and planned detail flows | `Release49-FinalFlows.xcresult` | Draft/recipe paths passed; two picker assertions still expected old title/copy. Updated expectations preserve all Save/Cancel assertions; final picker result below. |
| Final cook picker | `Release49-CookPickerFinal.xcresult` | 2 passed, zero failures. Both appearances; full weekday title, explicit Save/Cancel and persistence verified. |
| Static checks | release scripts | 183 Swift design files, 10 shared native tokens, copied Live Activity tokens, 159 recorded CloudKit fields, diff whitespace passed. Manifest check is not live schema/transaction proof. |

Early failures are retained: the 17-point notification action was corrected; the
new cooking test initially searched for a root resume strip while still on recipe
detail, then was corrected to navigate Back and verify paused state after resume.
A first photo-removal attempt and reply-target attempt failed in the run disrupted
by the Plan hang; both passed isolated without changing their assertions or app
implementation. The portrait-shaped capture after a physical rotation attempt is
not proof of a landscape composer layout. Original failures are not counted as
clean runs. Capture timing may retain a transient timer-label animation.

## Actual visual review

Inspected the native approved phone matrix, AX5 states, iPad matrix and 78 additional
native state captures. Review included typography, hierarchy, wrapping, controls,
spacing, safe areas, captions, actor/recipient context, recovery copy and real
interaction results. Screens use isolated fixtures; sample weather explicitly says
Preview weather. Fixture avatars are not real cross-account profile proof.

Selected final evidence:

- [Plan context, Light](captures/fidelity-context-recorded-household-light.png)
- [Plan context, Editorial](captures/fidelity-context-recorded-household-dark.png)
- [Activity, Light](captures/notifications-activity-light.png) and [Editorial](captures/notifications-activity-dark.png)
- [Notification settings, Light](captures/notifications-settings-light.png) and [Editorial](captures/notifications-settings-dark.png)
- [Photo composer](captures/fidelity-composer-photo-light.png)
- [Reply target and keyboard](captures/fidelity-comments-replying-light.png)
- [Fresh invitation after removal](captures/fidelity-invitation-rejoin-light.png)
- [iPad cooking full display](captures/cooking-ipad-light.png)

The [route/state ledger](screen-state-inventory.md) retains all 49 prior inventory
rows, with specific fresh evidence and open combinations. Neither these captures
nor the passing slices establish complete coverage of every route/state/device.

## Production service and security

`social` **v10 ACTIVE**, deployment SHA-256
`caf1d4fa3646bb643d2b1c9bd2fe6e5464a1903465b5defe7c7c2e3a76f8aa0b`.
All four deployed TypeScript files read back exactly matching the local source.
Existing custom session/worker authentication is retained; no anonymous event path
was added. Six `social_*` tables have RLS enabled and no SELECT grants to anon or
authenticated roles. Credentials and short-lived Apple proofs were not logged.
The delivery cron is active every minute, with 60 successful scheduler executions
in the inspected hour; 15 recent pg_net HTTP responses were 200 with no timeout.
This establishes worker availability, not delivery to an actual phone.

The production service still had **zero active verified installations** at the
inspection. No fresh real-device registration or APNs delivery was observed after
these fixes. This is an explicit remaining validation gap, not a passed end-to-end
phone test. Peer photos, membership and automatic activity latency also require
actual account sessions. No real household was mutated as disposable test data.

## Remaining limits and release exception

Nate explicitly instructed continuing without the phone and distributing without
waiting on live checks. Physical VoiceOver, installed widgets/Live Activities,
Calendar permission, two-account sync and actual background/terminated push remain
unverified. iOS 18 and a previous-TestFlight in-place upgrade were not available in
this run. Resized iPad windows, all motion variants and the unexercised ledger rows
remain open. These exceptions are not passes, and this beta is not a bug-free or
App Store approval claim. Existing baseline accessibility findings remain in the
October 22 raw reports; no fresh full automated accessibility audit is claimed.

See `../testflight-49.md` for the signed package, upload and actual tester access.
