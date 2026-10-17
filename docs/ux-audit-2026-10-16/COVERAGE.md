# Audit coverage and limits

> This records the original audit coverage. The subsequent implementation and verification ledger is [REPAIRS.md](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/REPAIRS.md).

This ledger covers the native app and widget surfaces. “Source” means route/state logic inspected; “Rendered” means a captured screen was visually inspected; “Interaction” means the specified transition was exercised. These are different evidence levels. A screen appearing in a survey is not a pass for all its states.

## Environment and method

- Source baseline: `f8707a1`, 16 October 2026 working tree. Native production files unchanged.
- Fresh app + widget simulator build succeeded. Design/token checks passed (159 Swift files).
- Isolated iPhone SE (3rd generation), 375×667pt, iOS 26.5; default and largest accessibility content size, Editorial and Light appearances. All four roots were captured after rotation at 667×375pt using full-screen capture; Plan retained its Month selection. These checks do not establish all size-class permutations.
- Isolated 11-inch iPad Pro (M5), iOS 26.5; normal-text tablet survey. Multitasking widths, external keyboard and Stage Manager are not exercised.
- XCUITest screenshots and accessibility trees are exported under `evidence/screens/`; successful result bundles and logs are retained locally. Failed-run attachments/manifests/logs are preserved; their bulky partial simulator-diagnostic bundles were removed after export.
- Apple accessibility diagnostics collect contrast, hit-region, sufficient-description and clipped-text issues on Plan, Groceries and a Table thread in Light mode. The issue handler records results and returns true; a completed diagnostic test **does not mean accessibility passed**. Automated detections require manual interpretation. The 45 reported issues include hidden underlying tabs, offscreen/occluded text and a noninteractive progress indicator; those are not treated as 45 product defects. The thread clipping is independently visible; token contrast is measured separately.
- Preview launches use in-memory sample data. First-run tests use the repository’s isolated onboarding path. Sample meal names, missing method text and example activity are fixtures, not evidence that the user’s real recipes have those contents.
- Source review follows shared components, navigation entry points, model mutations, persistence outcomes, drafts, permissions, remote state and widget/deep-link contracts.

## Screen and state ledger

| Area / surface | Checked states and branches | Evidence / remaining work |
|---|---|---|
| Launch/root routing | welcome, local continuation, Apple sign-in, interrupted invitation, optional tour, app entry | Source; welcome/local entry rendered and exercised. Real Apple authentication/cancellation/revocation requires a device/account. |
| Welcome | normal and AX text, local/Apple choices | Rendered; local continuation exercised. |
| Apple fallback | authentication error/fail-open sheet and recovery | Source; actual Sign in with Apple errors not injected. |
| Tour | four page definitions, Skip/Next/Done, illustrations, reduced-motion branching | Source; initial tour rendered. All four transitions not separately exercised. |
| Invitation entry | empty input, invalid link, Cancel, handoff to join | Source and invalid-link/Cancel interaction. |
| Household join | loading, ready, switch, own share, blocked hosting, removed, already joined, seat choice, failure | Source. Real CloudKit acceptance, slow join, seat conflict and leaving prior household are outstanding. Finding 23. |
| Main shell | four tabs, create sheet, root/push/sheet boundaries, cook resume strip, deep-link routing, tab reselection | Source; roots/create rendered; reselection comparison. Actual lock-screen and terminated-app deep links outstanding. |
| Plan/week | selected date, date strip, today, empty/filled/cooked/eating-out, local/shared/pending branches, earlier/later rows, options | Source; default and AX rendered, scrolling inspected. Shared content states reviewed in code; live two-phone verification outstanding. Findings 01, 07, 11, 12, 26. Finding 26 was added in response to user-supplied arrival/hierarchy feedback and remains a design recommendation requiring usability validation. |
| Plan/month | month switching, date cells, planned markers, selected day | Source; default and AX rendered. Drag/drop transitions and edge autoscroll not exercised here. |
| Day detail | slots, local/shared plans, add/swap/move/removed night paths | Source; no claim of a separate rendered pass for every slot/state. |
| Plan a night | choose/add/pick/eat out/ask/gathering, local editing, remote pending/failure | Source; chooser rendered at normal/AX sizes. Remote mutations outstanding. |
| Recipe picker | search, selected/planned indication, empty catalog/no results | Source; populated picker rendered. |
| Recipe assignment | dates, servings/cook, local replace, remote conflict, success | Source and first-run open-planner interaction; populated picker rendered. Storage-failure and two-account checks outstanding. |
| Move meal | date selection, local swap, cooked block, failure rollback | Source; normal/AX rendered. Remote occupancy flaw found; real remote collision not executed. |
| Drag/drop | drag payload, acceptance, local/shared authority boundaries | Source. Touch/trackpad drag, autoscroll and conflicting updates require dedicated interaction coverage. |
| Plan again / removed nights | restore and repetition branches | Source; separate screenshots not captured. |
| Gathering | title/location/guests/time/calendar, save/retry/dismiss | Source; normal/AX rendered, including layout finding 25. Calendar denied/missing calendar and save failure not injected. |
| Cookbook | populated grid, first-run empty, loading/unreachable, search/filter/no-match, favorite, context actions | Source; populated and empty rendered at normal/AX; first-run routes exercised. Real cloud replay outstanding. |
| Filter and sort | filter groups, sort options, clear | Source; sheet rendered. Each filter combination not enumerated. |
| Recipe detail | artwork, title, time/servings/effort, metadata/allergens, ingredients, method, notes, history, source, favorite, share/edit/plan | Source; normal/AX and iPad rendering; first-run saved result exercised. Long unbroken strings and full localization matrix outstanding. |
| Ingredients sheet | serving lens, list, add-to-groceries | Source; corrected route rendered; add-to-groceries exercised after import. |
| Recipe editor | new/existing, keyboard toolbar, ingredient/step ordering, metadata, photos, save/retry/discard | Source; new save exercised. Existing-edit Cancel loss reproduced on iPad using a coordinate tap after ordinary XCUITest targeting failed; before/after screenshots and title assertions captured. Media pick/reorder, disk failure and process termination need further tests. |
| Recipe import | URL, pasted text, scan, photo, loading, review, validation, duplicate update/keep both, failure/retry/discard | Source; intake/review/save via pasted text and manual entry exercised. Camera/VisionKit, remote webpage formats, OCR and failed-store duplicate replacement outstanding. |
| Recipe sharing | Table destination, Messages availability, system apps, copy, print, confirmation | Source; share chooser rendered at normal/AX sizes (finding 25). External destinations and other-account recipe round-trip not sent. Findings 13–14. |
| Cooking | no steps/steps, previous/next, ingredient sheet, timer, mute/restart/clear, note, minimize/end/finish, save failure | Source; active-timer/no-steps fixture rendered normal/AX. Local Start cooking → recipe detail reproduced on iPad; future/shared branches are source-confirmed. Background timer sound, activity, interruptions and real step-by-step session still need device checks. |
| Groceries | normal/by-meal/date range, pantry toggle, extras, checked/unchecked/all bought, empty/failure, remove, sources, aisle ordering, price/budget, Reminders | Source; default/AX/Light/tablet rendering; first-run add from recipe exercised. Reminders permissions/export and two-phone marks outstanding. Findings 06, 07, 15, 22. |
| Table feed | Your Table/Household scopes, dish/ask/poll, empty/loading/offline, pending publish, refresh, reactions, save/edit/delete/report/block | Source; normal/AX/Light/tablet populated rendering. Online publish, other-account reactions and moderation delivery not exercised. |
| Table composer | dish/question, photo/text/tags/poll/destination, empty/valid, draft, failed save, pending publish | Source; normal/AX/tablet rendering. Photo draft omission confirmed in code; actual photo/library/relaunch scenario outstanding. |
| Ask composer | default question, text, poll validation/pending option, tags, destination, draft, retry | Source; normal/AX rendered. No posts sent to real people. |
| Post thread | author/header, photo/caption, replies, attachment/link/mention, save, reaction, draft, errors, safety actions | Source; normal/AX/tablet rendered. Thread-header and composer problems captured. Keyboard/reply nesting and real remote comments require follow-up. |
| Edit post | changed/valid, in-flight, local unpublished, publish/rollback, discard | Source. No actual online edits performed. |
| Table people | household/friends/invited/other Tables/blocked, reach failure/retry, invite/share link, remove/leave dialogs | Source; normal/AX reach-failure rendering, including title truncation (finding 25). Sending/removing/leaving not performed. |
| Own/other profile | own controls, other-member identity, artwork, dishes/questions/favorites, award shelf, household navigation | Source; own profile normal/AX/tablet rendering, including adaptive-layout defects (finding 25); household route exercised. Other-member variations source-only. |
| Edit profile / banner crop | initial/draft restoration, naming conflict, bio/avoid list, photo/banner, save/dismiss | Source; normal/AX and banner crop rendered. Persistence failure and real media permissions outstanding. |
| Awards gallery / award detail | earned/unearned/progress, own/other visibility, metrics | Source. Household stats rendered; separate award-gallery/detail visual inspection outstanding. Finding 20. |
| Household home | banner/name, people/roles/invitations, sharing status, cook grid/automatic turns, statistics | Source; profile-to-household route rendered. Offline/pending/removed/hosting/member branches source-only. |
| Add/invite person | by name, duplicate validation, role, messages availability, prepared/sent/cancelled/failed invitation | Source. Sending was intentionally not performed. Real Messages requires a device. |
| Household statistics / badges | count definitions, progress, badge details | Source; statistics rendered. Metric mismatches found. |
| Settings | appearance, notifications, calendar, household/personal scope, identity/sign-out, support/privacy, permissions, tour | Source; normal/AX/tablet rendered. OS permission and sign-out/destructive transitions not exercised. |
| Activity | populated/empty, read/unread, destination routing, clear all | Source; populated fixture rendered. Live cross-account delivery outstanding. |
| Shared components | mastheads, buttons, chips, segments, avatars, swipe rows, artwork, date strip, plan rows, typography, colors, motion | Source plus use-site rendering. Target geometry, contrast and naming findings recorded; no claim that every font/string combination passed. |
| System integrations | photo library, camera/scanner, contact picker, Messages/share/print, Calendar, Reminders, notifications, Weather | Route/permission/error handling source review. Real-device prompts and host app outcomes remain outstanding. |
| Home/lock widgets | Tonight, Grocery, Cookbook, Table, Cook Turn; supported families; empty/current/aged data; links | Source; build passed. Installed-widget rendering and tap tests not executed. Findings 19, 24. |
| Live Activity | lock-screen / Dynamic Island timer variants and app resume routing | Source. No explicit widgetURL found in activity views; actual cold/warm tap behavior needs a physical-device check before classifying a confirmed defect. |
| Siri/App Intents | supported shortcut routes and disabled assistant intent | Source route inventory; spoken invocation and Spotlight/system presentation outstanding. |

## Dormant or excluded surfaces

- `DiscoverView`, onboarding `ProfileSetupView` and `ContactsView` have no active production callers identified. They are retained legacy code, not counted as shipped screen passes.
- Prongsby is disabled by `ProngsbyFeature.isEnabled = false`; its views/intent remain in the source. Reactivation requires a new review.
- Plated+ gating is disabled by `PlatedPlus.gatingEnabled = false`. The preview paywall exists but is not counted as a current purchase flow. StoreKit purchase/restore was not audited as a working product feature.
- Website/marketing work, backend security, financial/clinical claims and performance/load testing are not part of this native UX audit.

## Evidence cautions and corrected hypotheses

- The initial landscape app-only screenshot API produced cropped portrait-shaped exports despite a landscape accessibility window. Those images are not product defects. The settled full-screen rerun (`landscape-screen-*`) is the valid rendering evidence.
- The first survey’s `13-ingredients` hook did not open the ingredients sheet; it captured the cookbook. Use `ingredients-corrected` from the deeper survey instead.
- Early existing-recipe and Start cooking probes failed ordinary XCUITest targeting. A later coordinate-based iPad run successfully completed both interactions and captured their outcomes. The field reported `isHittable = false`, yet a direct coordinate tap focused it; suspected photo hit-area interference was therefore rejected. The early runner failures are not product failures.
- Failed recipe-save retries do **not** allow continued editing: the editor disables its content when a save is pending. The initial hypothesis that retry ignores further edits was rejected.
- Avatar initials use `Color.ink`, not the person’s colored tone. A suspected light-avatar text contrast issue was rejected.
- Account/profile screens hide the root tab bar. A hypothesized visible account-push/reselect conflict was not retained as a confirmed defect.
- CalendarSync reuses an existing event ID. Duplicate calendar creation was not established and is not claimed.
- Hidden tabs remain in XCUITest’s diagnostic hierarchy even though source applies `accessibilityHidden`; this alone is not proof of VoiceOver focus leakage.
- Screenshot fixtures may include a timer or sample notification that real first-run users do not see. Sample-data content is not a production content defect.

## Outstanding sign-off scenarios

1. Two separate iCloud accounts: host/joined/member/guest, multiple Tables, invitation accept/decline/revoke, shared-plan collisions, grocery check/remove/restore, complete recipe round-trip and pending/failed retries.
2. Physical iPhone: camera and VisionKit, photo/contact restrictions, Messages send/cancel/fail, system share/print, notification denial/revocation, timer sound/background/lock screen/Live Activity resume.
3. Controlled persistence failure: recipe save and duplicate replacement, profile atomicity, planner confirmation, post edit, gathering; verify draft survival through retry, cancel and process termination.
4. Real assistive technology: VoiceOver focus order/rotor/actions, Voice Control names, Switch Control, hardware keyboard, Reduce Motion and increased contrast. Automated trees cannot replace this.
5. Device matrix: short and tall phones, intermediate Dynamic Type sizes, landscape, iPad split-window sizes, long names/titles, large lists, no-photo/no-method records, locales with different date/number formatting.

These are explicit coverage gaps, not silent passes. The confirmed findings are actionable now; real-device sign-off should follow the repairs.
