# Plated release quality standard

Standing requirement from Nate, October 18, 2026: every detail matters; verification
is our responsibility. This standard defines the evidence required for each app
release. It is a process requirement, not a claim that these checks have all passed.

## 1. Establish the candidate and acceptance criteria

Record source commit, version/build, device/OS, account role, fixtures, environment,
and the approved design revision. Preserve unrelated work in an isolated checkout
when necessary. Keep the original approval unchanged.

Translate each approved annotation into an observable acceptance criterion. Compare
the running native app with it. Record intentional native adaptations and actual
data differences; do not use them to excuse missing layout or behavior.

Reconcile active routes, sheets, menus, overlays, system integrations, widgets and
deep links from the current source. The historical
[route/state inventory](ux-audit-2026-10-16/COVERAGE.md) is a starting point, not fresh
proof. The [15-screen design proposal](design-polish-review-2026-10-18/Plated-Design-Review.html)
is a visual reference, not an exhaustive route inventory. Later explicit user
instructions supersede it, including landscape-only iPad.

## 2. Check the full release inventory

Create a dated ledger with a row for each route and material state. Split the
families below into their actual screens and transitions; one row per family is
not sufficient evidence of complete coverage. Add newly discovered routes and
states. Explicitly identify dormant/disabled code instead of counting it as tested.

| Family | Required coverage |
| --- | --- |
| Launch and onboarding | Fresh install, returning session, authentication/cancellation/error, invitation launch, interrupted setup, tour, recovery and account switch. |
| Shell and navigation | Every tab, contextual/global creation, pushed screens, sheets, menus, overlays, tab reselection, back/dismiss, restoration, cold/warm deep links and resume strip. |
| Plan and calendar | Selected day only; today/past/future; empty, assigned, suggested, freeform, eating out, planned, cooking and cooked; local/shared/pending; choose, replace, move, repeat, remove, Undo; calendar/month navigation, gathering and conflicts. |
| Weather and history | Real forecast versus observed temperature, unavailable/denied/stale/retry, readable official attribution and link in both appearances, explicit time period, deduplicated recorded counts, actor/action and tomorrow context. |
| Recipes | Empty/populated/search/no results/filter/sort/favorite/collections; long titles and missing media; detail metadata/anchors/quantities/servings/checklist; new/edit/import/review/duplicate handling/share/export; save, cancel, discard and failure. |
| Groceries | Dates/scope, empty/populated/all checked, manual additions, quantities/provenance, pantry, edit/remove/restore/Undo, rebuild/deduplication, export, permission refusal and two-account checks. |
| Table and composer | Audience versus feed filter, food/place/ingredient/text/photo/poll posts, author/media/actions/caption, attachments and edits, draft persistence, dismissal, pending/sending/sent/failed/retry, edits/deletes and automatic updates. |
| Threads and reactions | Comment/reply posting, one-level nesting, long content, deleted parent/context, like/unlike/counts, reaction identity, reply target/cancel, keyboard, failed-send recovery, notification target and applicable save/report/block actions. |
| Activity and notifications | Empty/read/unread, mark read versus clear, actor/action/object/excerpt, joins/comments/replies/reactions, grouping, badges, preferences and permission states; foreground/background/terminated delivery and exact destination. |
| Household and invitations | Header/settings, photos, roster/roles/recent activity, organizer/member/guest permissions, invite/pending/joined/removed/leave, new invitation after removal versus obsolete link, failure recovery, explicit cook selection and Save/Cancel. |
| Profiles and milestones | Self/other member, avatar/banner/fallback, latest verified activity, count attribution/time range, public/shared/private collections, editing and discard, household navigation, earned/unearned milestones and details. |
| Cooking and timers | Steps/no steps, checkable ingredients, frozen recipe/servings, previous/next, minimize/resume, timer start/pause/resume/mute/reset/end, background alert ordering, interruption/relaunch, finish/save/Undo, notes and sharing. |
| Settings and account | Every row/destination, appearance, notifications, Calendar, identity, permissions, support/privacy, sign-out/account switch and recoverable versus destructive confirmations. |
| System integrations | Calendar create/update/remove, Reminders, photo library/camera/scanner, contacts, share/print/Messages, Weather, Siri/App Intents and Spotlight; unavailable/denied/revoked/retry paths. |
| Widgets and Live Activities | Every supported family, missing/current/stale data, photos, midnight rollover, app-group updates, lock screen/Dynamic Island, timer lifecycle, correct tap destination and removed-content fallback. |

For every applicable route, examine normal, loading, empty, partial, offline, pending,
failure, retry and success states; long names/text, missing photos and large counts;
own versus other-account data; and permission/role boundaries. Mark irrelevant
combinations N/A with a reason. Do not silently reduce coverage to happy paths.

## 3. Separate visual, behavioral and live proof

**Visual review:** inspect actual renders at readable scale in both appearances,
on compact and larger phones, default and accessibility text sizes, and supported
iPad sizes/orientations. Check every visible element: alignment, spacing, type
weight/scale/wrapping, image crop, icon meaning, target geometry, contrast, copy,
selection/disabled states, attribution, keyboard and safe-area overlap. Scroll
through the entire page and open its secondary controls. Check shared components
at all use sites. Review motion with Reduce Motion as well as normal settings.
Include the minimum-supported and current shipping iOS/iPadOS versions, plus
intermediate versions affected by changed system APIs. Determine support from the
current project, not a stale README. Record unavailable runtimes/devices as blocked.

**Interaction review:** exercise full journeys and their alternatives. Assert the
resulting data, counts, destination, persistence and recovery. Include rapid repeated
actions, cancellation during work, failures and app termination. Confirm no duplicate
events/posts/membership and no loss of drafts or unrelated data. Use realistic
isolated fixtures; do not manipulate a real household as disposable test data.
Test an in-place upgrade over the previous distributed build with representative
persisted data: migrations, account identity, settings, drafts, photos, queued work,
checked ingredients and active/paused timers must survive correctly. A clean install
or ordinary relaunch is not upgrade evidence.

**Accessibility review:** inspect labels, values, selection, focus order, hidden-tab
exposure, usable targets, truncation, contrast and keyboard access. Read raw results
from collect-only audit probes. Exercise VoiceOver gestures and focus transitions
on a device; simulator accessibility trees are a different evidence category.

**Live integrations:** use two real authorized account sessions to verify both
directions of photo/profile changes, invitation removal/reinvite/join, posts,
comments/reactions, Plan and groceries. Verify foreground updates without refresh.
Measure event-to-visible and event-to-notification latency and record it; do not call
sync timely based on an eventual pull-to-refresh result. Check duplicates, badges,
muted preferences, background/terminated delivery and deep links. Production
entitlements or an accepted APNs request alone do not prove phone delivery.

## 4. Run and inspect the release checks

`scripts/testflight.sh` currently checks design lint, native tokens and the recorded
schema, then builds and uploads. It does not enforce this entire standard. Complete
the evidence ledger before invoking distribution; do not mistake that script's exit
code for visual, functional or live-device sign-off. Review test instructions and
acceptance criteria for stale UI names and obsolete workarounds as well as code.

- Run the current automated app regression suite and applicable extension/backend
  suites, plus the UI journey and visual matrix. Revisit every known defect's
  regression; a focused passing test alone is not the full release baseline.
- Run `scripts/check-design`, `scripts/check-tokens --native-only`,
  `scripts/check-schema`, and `git diff --check`. Check the web separately when it is
  in release scope. The schema script checks a recorded manifest, not live CloudKit
  operations or every persisted-model field.
- Review warnings, logs, skipped tests and collected accessibility findings. Resolve
  failures rather than relabeling a completed capture as a pass. Keep original
  failures and the meaningful passing retest, with a clear link between them.
- After a correction, rebuild and retest the changed behavior and connected paths.
  Refresh screenshots affected by it. Shared typography/layout, navigation or
  persistence changes require review of all affected use sites. Do not keep rerunning
  unchanged broad suites after they pass unless a new change or concern justifies it.
- Reconcile missing evidence before release. Historical reports and previously
  installed binaries do not establish the new candidate's state.

## 5. Verify the artifact and delivery

Archive from the recorded source with no source changes during the build. Preserve
the archive, dSYMs, export, logs and IPA hash. Verify app and extension versions,
strict signatures, packaged capabilities/privacy manifests, matching symbols,
non-debuggable export, production APNs/CloudKit, and supported orientations.
Inspect the exported IPA's entitlements: export re-signs a development archive.

Confirm upload receipt, Apple processing and internal/external beta state. Verify
every authorized tester group includes the build or has all-build access, carry
forward individual testers when applicable, and read back tester notes. Distinguish
uploaded, processing, under review, available, and installed on a particular phone.
Do not claim a tester's phone is updated without evidence from that installation.
Update the README's current-release reference and tester instructions so they match
the verified candidate; stale procedures must not silently become acceptance tests.

## 6. Keep an explicit evidence ledger and completion report

Use this structure for each release; no pre-checked rows:

| Screen / state / criterion | Candidate and environment | Visual evidence | Interaction/data evidence | Device/account evidence | Status and follow-up |
| --- | --- | --- | --- | --- | --- |
| Exact route and expected result | Commit, build, OS, size, appearance, role | Inspected capture/reference or not checked | Scenario, assertions and result bundle or not checked | Actual session/result or unavailable | Pass / Fail / Blocked / N/A, reason and next step |

“Source reviewed,” “built,” “captured,” “visually inspected,” “interacted,” and
“verified live” are distinct. A pass applies only to the criterion and environment
actually checked. An inventory is not complete while relevant routes lack a row.

Fix known mismatches before declaring the design complete. A missing device/account
does not stop independent work, but it leaves its checks blocked. Record any explicit
user-approved exception with its scope; silence, previous approval of a different
exception, or a green unrelated suite is not a waiver. Do not repeatedly request
permission already given. Disclose remaining gaps before distribution where possible
and in the final report; never call an exception a passed check.

Report the concrete changes, observed results, exact build availability, and remaining
limits. Never promise zero bugs or 100% coverage of all possible combinations. The
obligation is thorough, repeatable scrutiny with honest evidence, rather than asking
Nate to discover the unfinished work.

Historical examples and failure lessons:
- [Original route/state audit](ux-audit-2026-10-16/COVERAGE.md)
- [Physical-device and integration record](ux-audit-2026-10-16/release/README.md)
- [Build 45 design correction and evidence](design-parity-recheck-2026-10-18/README.md)

This standard was added after build 45. It does not retroactively certify that build
or trigger a new app release for this documentation change.
