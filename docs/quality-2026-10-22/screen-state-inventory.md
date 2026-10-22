# Build 48 screen and state inventory — October 22, 2026

This is a fresh candidate ledger, not a full sign-off. It reconciles the active
routes and material state branches against the historical `COVERAGE.md` and
current `MainShellView`, `WeekView`, `TableFeedView`, `HouseholdHomeView`,
and Settings code. The four additional rows record newer Plan, Table and
phone-alert flows absent from the original inventory. A row marked pending
has not been promoted from historical evidence. See `README.md` for exact
test bundles and inspected captures. iOS 18.0, real accounts, physical
VoiceOver, installed widgets, Calendar permission and previous-TestFlight
upgrade remain unavailable or unverified for this candidate.

| Screen or route | Material states to reconcile | Fresh build-48 evidence / limit |
| --- | --- | --- |
| Launch/root routing | welcome, local continuation, Apple sign-in, interrupted invitation, optional tour, app entry | No fresh candidate-specific route/state verification recorded. |
| Welcome | normal and AX text, local/Apple choices | No fresh candidate-specific route/state verification recorded. |
| Apple fallback | authentication error/fail-open sheet and recovery | No fresh candidate-specific route/state verification recorded. |
| Tour | four page definitions, Skip/Next/Done, illustrations, reduced-motion branching | No fresh candidate-specific route/state verification recorded. |
| Invitation entry | empty input, invalid link, Cancel, handoff to join | No fresh candidate-specific route/state verification recorded. |
| Household join | loading, ready, switch, own share, blocked hosting, removed, already joined, seat choice, failure | No fresh candidate-specific route/state verification recorded. |
| Main shell | four tabs, create sheet, root/push/sheet boundaries, cook resume strip, deep-link routing, tab reselection | Major tabs/create captured by approved matrix; deep links and restoration pending. |
| Plan/week | selected date, date strip, today, empty/filled/cooked/eating-out, local/shared/pending branches, earlier/later rows, options | Selected-day/compact open states tested and visually inspected; other states partial. |
| Plan/month | month switching, date cells, planned markers, selected day | No fresh candidate-specific route/state verification recorded. |
| Day detail | slots, local/shared plans, add/swap/move/removed night paths | No fresh candidate-specific route/state verification recorded. |
| Plan a night | choose/add/pick/eat out/ask/gathering, local editing, remote pending/failure | No fresh candidate-specific route/state verification recorded. |
| Recipe picker | search, selected/planned indication, empty catalog/no results | No fresh candidate-specific route/state verification recorded. |
| Recipe assignment | dates, servings/cook, local replace, remote conflict, success | No fresh candidate-specific route/state verification recorded. |
| Move meal | date selection, local swap, cooked block, failure rollback | No fresh candidate-specific route/state verification recorded. |
| Drag/drop | drag payload, acceptance, local/shared authority boundaries | No fresh candidate-specific route/state verification recorded. |
| Plan again / removed nights | restore and repetition branches | No fresh candidate-specific route/state verification recorded. |
| Gathering | title/location/guests/time/calendar, save/retry/dismiss | No fresh candidate-specific route/state verification recorded. |
| Cookbook | populated grid, first-run empty, loading/unreachable, search/filter/no-match, favorite, context actions | Approved matrix captured; full catalog state review pending. |
| Filter and sort | filter groups, sort options, clear | No fresh candidate-specific route/state verification recorded. |
| Recipe detail | artwork, title, time/servings/effort, metadata/allergens, ingredients, method, notes, history, source, favorite, share/edit/plan | Approved matrix captured; independent full visual review pending. |
| Ingredients sheet | serving lens, list, add-to-groceries | No fresh candidate-specific route/state verification recorded. |
| Recipe editor | new/existing, keyboard toolbar, ingredient/step ordering, metadata, photos, save/retry/discard | No fresh candidate-specific route/state verification recorded. |
| Recipe import | URL, pasted text, scan, photo, loading, review, validation, duplicate update/keep both, failure/retry/discard | No fresh candidate-specific route/state verification recorded. |
| Recipe sharing | Table destination, Messages availability, system apps, copy, print, confirmation | No fresh candidate-specific route/state verification recorded. |
| Cooking | no steps/steps, previous/next, ingredient sheet, timer, mute/restart/clear, note, minimize/end/finish, save failure | Approved interactions passed; full timer/device matrix pending. |
| Groceries | normal/by-meal/date range, pantry toggle, extras, checked/unchecked/all bought, empty/failure, remove, sources, aisle ordering, price/budget, Reminders | Approved matrix captured; automated AX probe returned no issues; live sync pending. |
| Table feed | Your Table/Household scopes, dish/ask/poll, empty/loading/offline, pending publish, refresh, reactions, save/edit/delete/report/block | Both appearances captured by approved matrix; entry action passed. Accepted live audience pending. |
| Table composer | dish/question, photo/text/tags/poll/destination, empty/valid, draft, failed save, pending publish | Approved draft recovery passed; real publish/photo permission pending. |
| Ask composer | default question, text, poll validation/pending option, tags, destination, draft, retry | No fresh candidate-specific route/state verification recorded. |
| Post thread | author/header, photo/caption, replies, attachment/link/mention, save, reaction, draft, errors, safety actions | Approved comment interaction captured; one offscreen AX diagnostic flag reviewed; live comments pending. |
| Edit post | changed/valid, in-flight, local unpublished, publish/rollback, discard | No fresh candidate-specific route/state verification recorded. |
| Table people | household/friends/invited/other Tables/blocked, reach failure/retry, invite/share link, remove/leave dialogs | No fresh candidate-specific route/state verification recorded. |
| Own/other profile | own controls, other-member identity, artwork, dishes/questions/favorites, award shelf, household navigation | Approved profile routes captured; real second-account avatar/activity pending. |
| Edit profile / banner crop | initial/draft restoration, naming conflict, bio/avoid list, photo/banner, save/dismiss | No fresh candidate-specific route/state verification recorded. |
| Awards gallery / award detail | earned/unearned/progress, own/other visibility, metrics | No fresh candidate-specific route/state verification recorded. |
| Household home | banner/name, people/roles/invitations, sharing status, cook grid/automatic turns, statistics | Approved rotation/header interactions passed; real member join/photo pending. |
| Add/invite person | by name, duplicate validation, role, messages availability, prepared/sent/cancelled/failed invitation | No fresh candidate-specific route/state verification recorded. |
| Household statistics / badges | count definitions, progress, badge details | No fresh candidate-specific route/state verification recorded. |
| Settings | appearance, notifications, calendar, household/personal scope, identity/sign-out, support/privacy, permissions, tour | Alert row visually inspected in Light; real registration and other settings paths pending. |
| Activity | populated/empty, read/unread, destination routing, clear all | Approved interaction passed; live push and cross-account activity pending. |
| Shared components | mastheads, buttons, chips, segments, avatars, swipe rows, artwork, date strip, plan rows, typography, colors, motion | No fresh candidate-specific route/state verification recorded. |
| System integrations | photo library, camera/scanner, contact picker, Messages/share/print, Calendar, Reminders, notifications, Weather | No fresh candidate-specific route/state verification recorded. |
| Home/lock widgets | Tonight, Grocery, Cookbook, Table, Cook Turn; supported families; empty/current/aged data; links | No fresh candidate-specific route/state verification recorded. |
| Live Activity | lock-screen / Dynamic Island timer variants and app resume routing | No fresh candidate-specific route/state verification recorded. |
| Siri/App Intents | supported shortcut routes and disabled assistant intent | No fresh candidate-specific route/state verification recorded. |
| Plan / eat leftovers | selected date, available leftovers, cook choice, save/cancel, recorded outcome | No fresh candidate-specific route/state verification recorded. |
| Plan / weather and dinner history | today forecast, unavailable/retry, official attribution, recorded counts, both appearances | Open state and official Weather mark visually checked in both appearances on iOS 26.2 and Light on iOS 27; real forecast and failure/retry remain open. |
| Table / accepted guest before first post | accepted share, unknown/pending/offline read, audience label, invite action | Accepted-identity filtering passed unit test; Table entry passed UI test. Live acceptance and latency remain open. |
| Settings / phone alert connection | unregistered, checking, token pending, confirmed, rejected, retry, account change | Unregistered Light render inspected; retry state handled in source. Real 403/confirmed phone registration remain open. |

The approved 15-screen proposal is covered by the matrix only for the
fixture states exercised there. Capture completion is not visual acceptance.
This ledger intentionally retains untouched and unavailable combinations
as open work; build 48 is an incremental beta candidate, not a 100% claim.
