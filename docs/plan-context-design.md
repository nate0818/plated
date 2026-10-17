# Plan: dinner, weather and recent history

The October 17 screenshot showed a tall empty dinner panel followed by a large
unused area. The primary task is deciding dinner for the selected date.

Considered: (1) a taller illustrated hero, which adds decoration without helping
the decision; (2) a dashboard grid of equally weighted cards, which obscures the
primary task on a phone; (3) a compact dinner decision followed by a forecast
and a quiet history summary. Use option 3 with the existing Editorial tokens.

The dinner panel keeps one orange action and exposes Eating out directly.
Supporting content uses rules and typography rather than more large containers.
Weather follows the selected date; meals still show only that date. The dinner
log is explicitly the last seven calendar days through today, for the household.
Cooked counts completed dinners only. Eating out counts marked nights through
today, not future plans. No inferred streaks or claims that an unlogged day was
eaten out. Local/shared copies of a dinner count once.

Weather uses existing WeatherKit data with high/low labels, rain probability,
Apple attribution and sources. Location is requested only after an explicit
action. Denied, loading, failed and out-of-range states remain useful and visible.
Sample weather/history is confined to Debug review fixtures.

Dynamic Type stacks the dinner actions and history figures. Controls retain
44-point targets; forecasts and counts have concise VoiceOver summaries.
No new animations, persisted fields or CloudKit schema changes.

## Initial dinner-context validation

- Xcode 27.0, Plated Debug app and widget build passed.
- Native suite: 427 executed, 423 passed, 4 intentional opt-in Calendar skips,
  zero failures. All five new production dinner-history tests passed.
- iPhone 17 Pro / iOS 27 simulator: 10 UI cases passed (six new context cases,
  real VoiceOver-service reading order, three selected-day regression cases).
- iPhone SE 3 / iOS 26.5: six context cases passed; two final focused cases
  passed for successful eating-out saving and injected save failure. Failure
  reverts only this change and preserves the previous history count.
- Visually inspected dark/light, default text and AX5 screenshots on the compact
  phone, the typical phone layout, and the isolated iPad layout. Actions stack,
  content scrolls, and only the selected date's meals appear.
- Fixtures exercise empty/filled history, location unrequested/denied, network
  failure, selected-date forecasts, and unavailable historical weather. Weather
  is visibly marked Preview weather; this is not live WeatherKit verification.
- VoiceOver reads the dinner heading, both actions, forecast and both counts in
  order. It is a real simulator service transcript, not proof of physical gestures.
- Design checks, app/widget token parity, schema gate and whitespace checks pass.
- SwiftUI static audit: no high findings. Four new medium review items are the
  1-point divider, decorative 32-point weather symbol/44-point frame, and Apple's
  fixed-aspect attribution mark. They do not constrain text and the symbol is
  hidden from accessibility. Existing WeekView findings remain outside this change.
- No custom graphics, materials or new animation was introduced. Shared buttons
  already suppress scale with Reduce Motion; surfaces are opaque. No Instruments
  performance or new system reduced-effects run was collected.

Standard-profile rubric (provisional): platform 14/15, layout 14/15, semantics
14/15, interaction 18/20, motion/material 12/15, accessibility 8/10, implementation
8/10 = 88/100 before the evidence cap; **84/100 capped** pending system
reduced-effects verification. This is not a claim that every release gate passed.
Live WeatherKit/attribution rendering on a signed physical device and the previous
multi-account release gaps remain unverified while the phone is disconnected.

Evidence: `build/plan-context-unit-signed.xcresult`,
`build/plan-context-ui-final.xcresult`, `build/plan-context-compact.xcresult`,
`build/plan-context-save-recovery.xcresult`. Reviewed screenshots and the VoiceOver
transcript are retained in [plan-context-2026-10-17](plan-context-2026-10-17/).

The initial unsigned native run could not initialize its CloudKit container;
normal simulator signing resolved that harness issue. The first UI iteration
found inherited container identifiers masking count identifiers; removing those
container IDs fixed the issue, confirmed by the passing UI and VoiceOver runs.

## Cook and household follow-up

The cook is now a separate, labeled control with a face and a full sentence.
Rotation is labeled Suggested cook until the user assigns someone. A cook can be
assigned before a recipe; the dinner remains open, and choosing a dish preserves
both an explicit cook and an explicit No cook assigned choice. Eating out says
No cooking needed. Failed assignment rolls back only that edit.

Plan includes a household section below weather/history. Rows show the available
profile photo, name and recorded cooking/sharing totals for the same seven-day
period, and open the person's profile. Profiles also show that activity summary.
Invitations remain pending, missing photos use initials, and no activity is
invented. Cooking credit requires a completed dinner assigned to that person;
posting credit follows account identity. Shared/local echoes count once.

The investigation found and fixed these concrete identity defects:

- People hid the organizer's own photo on another member's phone because the
  cloned-host-photo guard applied to every person other than the reader.
- Table avatars, profile destinations and profile posts used names despite
  carrying stable account IDs; renamed people could lose their photos/content,
  and same-name people could be confused.
- Publishing a local dinner used the reader's ID for an organizer without a
  participant ID, even when the organizer was a different account. The cook's
  user record now takes precedence over that fallback.
- The remote cook face understood participantID but omitted userRecordName.

The UI uses the available synced roster/photo data. These corrections do not
prove that a particular missing asset has arrived from another live account.
No new shared model or schema fields were introduced.


Final native regression: 436 executed, 432 passed, four opt-in Calendar skips.
An additional production widget-publisher test passed, reading the actual app-group
snapshot: assigning only a cook keeps the day open, retains the cook, and supplies
no invented food photo. These are simulator data-path checks, not a new physical
Home Screen widget pass.

The first household UI run found the identifier on an accessibility wrapper rather
than its inner button. The row now uses native Button accessibility semantics;
tests also locate the user-facing name. The renamed-profile flow and AX5 household
navigation pass on the compact phone. Final full UI run evidence follows below.
