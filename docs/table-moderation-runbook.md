# Runbook: Table safety reports

**Owner:** Plated release owner / privacy inbox operator  
**Frequency:** Check at least daily while any public build is distributed, and
on every new report  
**Last updated:** September 23, 2026  
**Last production drill:** Not yet completed

## Purpose

Triage reports sent from Plated's private, invite-only Table; help the reporter
contain unwanted contact immediately; and produce a prompt, privacy-preserving
response. The release owner must complete a two-account drill before App Store
submission and record it in the history below.

This runbook does not imply access Plated does not have. Table posts, comments
and photos live in participants' CloudKit shares. The developer cannot browse,
retrieve or remotely delete that content from an admin console. A report email
therefore contains a selected reason and opaque references, never the reported
text, name or photo. Containment currently consists of the reporter's local
Block control, an organizer removing a participant from the Table share, and
authors or post owners using the deletion controls available to them.

## Service standard

- Acknowledge every valid report within 24 hours, including weekends while a
  public build is distributed.
- Review credible threats, stalking, doxxing, sexual exploitation, or danger to
  a child as soon as the inbox is checked; do not wait for the normal queue.
- Give the reporter an actionable containment step in the first response.
- Resolve ordinary spam or conduct reports, or explain the remaining limitation
  and next owner, within 48 hours.
- Never promise remote content removal, account suspension, or law-enforcement
  action that has not actually occurred.

If these response times cannot be staffed, pause external distribution rather
than claiming a moderation capability that is not operating.

## Prerequisites

- [ ] Access to `privacy@getplated.food` with multi-factor authentication.
- [ ] A current release build for reproducing the Report, Block, Unblock and
      Table-participant removal paths.
- [ ] Access to the release owner for product decisions and to qualified legal
      counsel for credible illegal-content or safety escalation.
- [ ] A mailbox label or equivalent queue for `New`, `Waiting on reporter`,
      `Escalated` and `Closed`. Keep the email thread as the case record; do not
      copy personal details into an ad hoc spreadsheet.

## Procedure

### Step 1: Validate and timestamp intake

Open the message addressed to `privacy@getplated.food`. A report created by the
app should have a subject beginning `Plated Table report` and a body containing:

```text
Reason
Content type
Content reference
Author reference
Optional Table reference
Report reference
```

Record the received time using the mailbox timestamp and move it to `New`.
Treat forwarded messages and free-form complaints as reports too, but never ask
the sender to reproduce objectionable material merely to fit the template.

**Expected result:** the report has a unique mail thread and a first-response
deadline no later than 24 hours after receipt.

**If it fails:** if the sender address or references are missing, reply on the
same thread asking only for the minimum context needed to identify the incident.
Do not ask for passwords, Apple IDs, contact lists, private CloudKit exports, or
unredacted household data.

### Step 2: Send immediate containment guidance

The first reply must be human, brief and specific. Tell the reporter:

1. On the reported post or comment, open the more-actions menu and choose
   **Block** to hide that person's Table posts, comments, activity, widgets and
   future local notifications on this device.
2. If they organize the Table, open **Table › People**, open the person's more
   menu and choose **Remove from Table** to revoke that participant's share
   access. Household members are removed with **Remove from household**.
3. They can review or reverse a local block under **Table › People › Blocked
   people › Unblock**.
4. If anyone is in immediate danger, contact local emergency services. Plated
   support is not an emergency channel.

Do not say that Block removes content for other participants: it is a private,
device-local filter. Do not say that removing a participant deletes existing
posts: it revokes share participation, while content deletion remains subject
to CloudKit ownership and the controls below.

**Expected result:** the reporter can stop seeing the person immediately and,
when they are the organizer, revoke the person's Table access.

**If it fails:** ask which control is missing, the installed Plated version,
device model and iOS version. Do not request screenshots containing private
content unless the reporter chooses to provide a redacted one.

### Step 3: Classify severity without collecting the content

Use the reporter's reason and their own short description:

| Severity | Examples | Target action |
|---|---|---|
| Critical | Credible imminent violence, stalking with immediate danger, child sexual exploitation | Alert the release owner immediately; obtain qualified legal advice; do not request or redistribute illegal imagery |
| High | Threats, targeted harassment, hate, doxxing, non-consensual sexual material | Same-day human review and containment follow-up |
| Standard | Spam, misleading posts, unwanted contact, other conduct | Acknowledge within 24 hours and resolve within 48 hours |

The opaque author reference is a correlation aid, not proof of identity. A
legacy reference based on a display name can be ambiguous. Never identify or
accuse a person from the reference alone.

**Expected result:** the thread has one severity and one named next action.

**If it fails:** choose the higher severity until a human review resolves the
ambiguity.

### Step 4: Apply the available content and membership remedy

Tell the appropriate participant which in-app action is available:

- An author can delete their own post.
- An author can delete their own comment; the owner of a post can also delete a
  comment on that post.
- A Table organizer can remove a Table guest from **Table › People**.
- A household owner can remove a joined household member, which revokes both
  household and Table participation. This is intentionally durable and should
  not be presented as a temporary mute.
- Any reader can keep the reported author locally blocked even when no one with
  CloudKit authority agrees to delete the record.

Support cannot perform these CloudKit mutations on the person's behalf. If a
future moderation service adds that ability, update this boundary and complete
a new privacy/security review before using it.

**Expected result:** the reporter knows what was actually changed, on whose
device or share, and what remains visible elsewhere.

**If it fails:** do not mark the case resolved. Escalate the product limitation
to the release owner and keep the reporter informed in the same thread.

### Step 5: Resolve and close

Reply with:

- the report reference;
- the action that was actually completed;
- any remaining limitation, in plain language;
- how to unblock or where the organizer can review Table membership;
- an invitation to reply if the behavior continues.

Move the thread to `Closed` only after the containment/action message is sent.
Retain only what the mailbox retention policy requires. Do not download report
attachments to a personal device, and do not add report text or identities to
analytics, test fixtures, screenshots or release notes.

**Expected result:** the email thread itself shows receipt time, severity,
response time, action and resolution.

**If it fails:** leave the thread in `Escalated` with the next owner and next
review time written in the latest reply or internal note.

## Verification

- [ ] New report arrives at `privacy@getplated.food` with reason and opaque
      references but no post text, comment text, display name or photo.
- [ ] Reporter receives a human response within 24 hours.
- [ ] Block hides the author in feed, thread, profile/activity surfaces,
      widgets, local notification scheduling and deep-link navigation.
- [ ] Unblock restores visibility.
- [ ] A Table organizer can remove a test guest and the removed guest can no
      longer use the share.
- [ ] The response states accurately whether an action was local, share-wide,
      or only guidance.
- [ ] The drill is entered in the history table without personal or content
      data.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Tapping Report opens no composer | No configured mail account or mail compose is unavailable | Ask the person to email `privacy@getplated.food` manually with the reason and report reference if visible; record the product gap |
| A blocked person's old notification is still in Notification Center | iOS delivered it before the block | Explain that Plated suppresses future scheduling/presentation but cannot withdraw an already delivered system notification |
| Block is not reflected on a second device | Blocks are intentionally device-local in this release | Repeat Block on the second device; do not claim account-wide sync |
| Organizer cannot remove a person | They are not the CloudKit share owner, identity is missing, or the network is unavailable | Confirm organizer role and connectivity; retry from Table › People; keep the case open |
| Opaque author reference cannot be mapped safely | Legacy record or no moderation directory mapping exists | Do not guess from a display name; use local Block and organizer removal, and escalate the product limitation |
| Reporter sends sensitive media | They misunderstood the minimal-report boundary | Do not forward it; restrict access, obtain legal/privacy advice where necessary, and ask them not to send more |

## Rollback and correction

- A mistaken local block is reversible at **Table › People › Blocked people ›
  Unblock**.
- Participant removal is a deliberate access-control action and may be durable;
  do not promise one-tap restoration. Escalate mistaken removal to the release
  owner for a fresh invitation/access review.
- Email cannot be unsent. If a response misstated what Plated did, correct it in
  the same thread immediately and record the correction in the history below.

## Escalation

| Situation | Contact | Method |
|---|---|---|
| Immediate danger | Local emergency services | Reporter contacts the appropriate local emergency number |
| Credible illegal content, child-safety issue, preservation request or subpoena | Release owner and qualified legal counsel | Immediate private escalation; keep sensitive material out of project trackers |
| Block/removal control fails in the current App Store candidate | Release owner / engineering | Stop submission or pause distribution until reproduced and fixed |
| Response-time coverage cannot be maintained | Release owner | Pause external distribution and update reviewer notes if submission state changed |
| Privacy or account-deletion request | Privacy inbox owner | Follow `docs/sign-in-with-apple-deletion.md`; keep it separate from the conduct report |

## History

| Date | Run by | Notes |
|---|---|---|
| September 23, 2026 | Release preparation | Runbook created; production two-account moderation drill still required |
