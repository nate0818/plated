# Household verification on Nate's and Alessandra's phones

Updated October 18, 2026. This is a verification procedure, not a record of a pass.
The earlier version used pull-to-refresh in its main steps and obsolete “Dish”
composer copy. Refresh-dependent delivery does not meet the current requirement.

Use the same current candidate on BOTH phones; record the version/build installed
in TestFlight on each. Keep both online for the foreground checks. Record the time
of each change and when it appears on the other phone. Do not refresh, relaunch or
switch tabs just to make an event arrive during the automatic-delivery check.

A two-minute observation window can help diagnose missing events; it is not a
promise, an acceptable latency target or permission to mark delayed delivery as
timely. Record the actual delay. Unavailable accounts/devices mean blocked checks.

## 1. Confirm the household without removing anyone

Open Profile → Household. Both phones should show Meadows, Nate as organizer and
Alessandra as a joined member. Each person is “You” only on their own phone. There
should be one row per person, with no contradictory pending/removed membership.

If Alessandra is already joined, do not remove/rejoin merely to repeat this test.
Existing membership can verify photos, posts and activity. Removal/reinvitation
regressions belong in an authorized disposable test membership, without disrupting
the working household. Existing authorization for that test scope remains valid.

Only if she has not successfully joined: Nate creates a fresh invitation from the
current candidate and Alessandra opens that exact link. Record loading, acceptance
and completion on both phones. An older link and a genuinely new invitation after
removal are separate cases: a revoked old link must not invalidate a new invitation.
The sheet must describe its actual state without simultaneously inviting and
rejecting the person. Capture any error instead of repeatedly issuing invitations.

## 2. Verify the in-app join event automatically

For a new acceptance, keep Nate's Activity screen open before Alessandra accepts.
Expect one contextual household-joined event without pulling to refresh. Check the
bell/unread count and that opening the event reaches the correct household. Further
foreground updates must not duplicate it. Test the currently visible bell/feed in a
separate case; manually opening Activity is not proof its badge updated automatically.

An old membership does not establish a new join notification. Do not manufacture a
removal merely to trigger one. Banner permission, Focus and sounds are separate from
in-app activity; a missing bell row is not explained by denied banner permission.

## 3. Verify profile/photo delivery in each direction

On Alessandra's phone, open her own Edit profile. Confirm her intended photo and
append a reversible marker such as “Sync A” to her bio, then Save. On Nate's phone,
observe her already-open profile: the bio and avatar must update automatically.
Separately check the Household People row and post/comment avatars. They should
represent the same person and photo. Never assign her photo manually on Nate's phone.

Repeat Nate → Alessandra with “Sync N.” After automatic delivery is recorded, leave
and reopen Plated to check persistence. Remove the temporary markers and verify the
cleanup also arrives automatically. Use consented temporary photo changes only when
needed to test replacement, and restore them afterward.

Record “bio arrived, photo missing” separately from neither arriving. Missing media,
identity association, publication and receipt are different failure paths.

## 4. Verify posts, comments and reactions without gestures

Create an authorized temporary general post from the Table composer, with distinctive
text such as “Sync check — Alessandra.” Choose the shared household Table if an
audience choice appears. Observe Nate's already-open feed without pulling to refresh.
Check exact author, avatar, text/photo, audience and delivery status. Repeat the other
direction; seeing one's own local post is not proof of sharing.

Comment and reply on the other person's post; react and unreact to both the post and
a comment. Observe the open thread/feed and Activity separately. Verify the actual
comment, reply target, reaction identity/count, contextual notification and badge;
no duplicates or fabricated counts. The same changes must remain after relaunch.
Record and clean up test content through normal supported actions after verification.

## 5. Verify dinner attribution and household data

Use an actual shared household dinner. Confirm the assigned cook, mark it cooked
only when done, and observe the other phone automatically. Credit the correct person
once. Eating out is not a cooked dinner. Repeat with the other person's next dinner;
do not fabricate history to raise a counter. Check the UI's stated period/scope when
comparing counts; personal history from before joining can legitimately differ.

Exercise a reversible grocery add/check/Undo and a Plan edit in both directions.
Verify their final values, not just a notification. After the online pass, repeat
appropriate temporary changes offline and reconnect; drafts/queued edits must survive,
converge without duplicates and show truthful pending/error states. Record conflicts.

## 6. Verify phone notifications separately

Record each phone's Plated notification permission/preferences and relevant Focus
state. Put the receiving app in the background and lock the phone. Send a comment
or reply from the other phone. Observe arrival time, actor, object/excerpt, sound and
badge according to preferences. Tap it and verify the exact post/comment destination.
Repeat in the other direction and check that opening does not duplicate the event.

Test foreground presentation, background/locked delivery and cold-launch routing as
distinct scenarios. Test a join alert only with an authorized new acceptance; do
not remove an existing member for convenience. An APNs acceptance or an in-app row
appearing later does not prove the phone displayed a notification.

## If anything fails

Record both builds, role/account direction, send/arrival times, network/app state,
and exact UI outcome. Capture corresponding screens. Mark required-refresh behavior
as a failure even if the content later arrives. After capturing that failure, a
single pull-to-refresh or the existing iCloud recovery action can be a diagnostic;
record it as recovery, not a passed automatic-sync check.

Do not reinstall, leave the household, or remove/reinvite in a troubleshooting loop.
Continue independent safe checks, preserve the failed case, fix the cause, and rerun
the same scenario. Keep unavailable cases blocked and report them explicitly.

Automated codec, queue, merge and notification tests cannot establish that these two
real phones exchanged their records or displayed their alerts. Record actual results
in the candidate's [release evidence ledger](release-quality-standard.md).
