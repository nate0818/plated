# UX audit repairs

Authorized 16 October 2026: redesign Plan around tonight and address all 26 audit findings. The changes preserve the Editorial visual language and four destinations. Existing website work is unrelated and was left intact. This ledger supersedes the original report's implementation status; REPORT.md and its evidence describe the pre-repair baseline at `f8707a1`.

## Experience contract

Plan opens on the task: understanding tonight and starting or resuming dinner. A real first-name greeting (or “Welcome home”) replaces the old introductory heading. One bounded panel groups the date, dish, photograph, cook, servings and primary action. Coming up is secondary; Calendar is an explicit mode with a route back to tonight. Empty, shared, cooking and completed nights have distinct, truthful states. At normal text size, Tonight's primary action is visible on the 375×667pt phone. Larger text scrolls in the same reading order. iPad uses the available width for tonight and the agenda.

Three structures were considered: greeting above the existing pinned calendar, a new Home tab, and tonight-first Plan with an explicit Calendar mode. The third implements the requested direction without another destination. Common region and proximity inform the meal panel; Hick's Law informs disclosure of secondary controls; Jakob's Law informs direct actions, tab reselection and draft recovery. These are design principles, not a claim that greeting copy has been validated in a usability study. The original report links the author-maintained Laws of UX framework associated with O'Reilly, Apple guidance and accessibility references.

## Repair ledger

“Implemented” means the defect has a code change. Evidence is identified separately: rendered screenshots, exercised interaction, unit regression, or source/build review. It does not imply a live CloudKit or real-device test where none occurred.

| Finding | Implemented change | Verification |
|---|---|---|
| 01 · Plan row geometry | Artwork has independent bounded geometry. Local/shared/empty/history rows reflow vertically at accessibility sizes; week titles keep their width. | Phone default/AX5 captures and scrolled Plan survey; source/build. |
| 02 · Table layout | Context, audience controls and feed share one scroll region; privacy content retains intrinsic height. | Phone default/AX5/landscape and iPad renders. |
| 03 · Edit Profile header | Cancel and the wrapping title have separate rows. | Default/AX5 and keyboard captures. |
| 04 · Thread hierarchy | Compact command bar; author and full-width dish heading in the scroll; attachment tools disclose separately from typing. | Default/AX5 phone and iPad renders. |
| 05 · Cooking layout | Compact session bar/footer, readable scrolling recipe, vertically arranged AX timer/actions and stable timer digits. | Direct-start/resume interaction; normal/AX5 timer renders. |
| 06 · Grocery priority | List follows one scope summary; options/prices disclose on demand. Short windows use a compact header, scope and footer. | Phone default/AX5 and landscape renders; iPad survey. |
| 07 · Accessible choice names | Segment children retain their own labels/selected traits. Plan's old Week/Month selector is replaced by the explicit Calendar mode. | Accessibility-tree and source review. Runtime VoiceOver remains a release check. |
| 08 · Enabled icon contrast | Enabled attachment controls use secondary ink instead of faint decoration color. | Source/token check; existing measured secondary-ink contrast is 5.44:1 Light / 8.42:1 Editorial. |
| 09 · Existing recipe drafts | Complete editable-state comparison; explicit Keep writing/Discard alert; interactive dismissal protected while dirty or loading a photo. | Edit → cancel → keep → discard → reopen test on phone; failed-save/discard retest on iPad. |
| 10 · Photo drafts | One atomic managed draft file includes photo bytes, writing, poll, tags and Table destination. Recipe-prefilled drafts cannot replace the ordinary post draft. | Photo-only round-trip, separate drafts and failed-write regression. UI camera/photo-picker relaunch remains a device check. |
| 11 · Shared occupancy | Recipe shortcut, move sheet, recipe planner and drag commit check shared authority; remote occupied dates cannot receive an extra local dinner. | Occupancy regression and drag rejection regression, plus source review of entry points. Live two-account races remain a release check. |
| 12 · Cooking intent | Start/Resume directly opens the selected session with frozen local/shared identity and servings. Remote completion writes the household edit queue; no duplicate local meal. Changed recipes are checked before completion. | Local start/minimize/resume/finish and shared six-serving interaction; Codable/queue/wire/adoption tests. Live remote completion remains a release check. |
| 13 · Recipe sharing promise | Full recipe exports preserve ingredients, servings and method, including legacy instructions. The Table action is explicitly **Post this dish** and discloses photo/description only. | Export regression and share-sheet source/render review. This selects the report's honest-relabel alternative; a full recipe attachment on Table was not added. |
| 14 · Table destination/result | Recipe dish posting goes through the normal destination-aware composer. Receipt says saved locally and directs upload-status checks to Table. One sheet owner handles each destination. | Composer destination logic/source review; sheet render. Live zero/one/multiple writable Tables remain a release check. |
| 15 · Grocery recovery | Soft removal, Undo remove and discoverable Removed items restoration. Outstanding manual extras remain until completed/removed; writer/widget use the same lifetime rule. | Manual-item age/deduplication regression; removal/restore source review. Cross-phone restoration remains a release check. |
| 16 · Gathering integrity | Durable form draft and dismissal choices; checked local save; latest values applied on retry; in-flight controls disabled; calendar errors retain the form. | Injected failed save and draft relaunch on phone/iPad; calendar retry source review. EventKit permission/event round-trip remains a device check. |
| 17 · Truthful save feedback | Profile, recipe planner and post edit only close/confirm after a checked commit. Narrow recovery preserves unrelated work. Profile has an explicit keyboard Done action; failure appears next to Save. Plan-again also retains its form on failure. | Injected profile/planner failures; source review for post edit/Plan-again; full suite. |
| 18 · Recipe replacement recovery | Snapshot restores recipe fields and original ingredient/photo identities after rejection. Old children retire only after successful commit; no context-wide rollback. | Original recipe/source/method/history/child identity + unrelated work regression; failed editor save/discard interaction. |
| 19 · Widget freshness | Stale/unknown differs from genuinely empty; widgets ask to refresh and show update context. Midnight invalidates the grocery count instead of claiming an empty list. | App/extension build and source review. Real widget timeline rollover remains a device check. |
| 20 · Honest statistics | Counts explicitly cooked local/shared dinners, deduplicated by plan identity. Weekly counts use distinct dates. Save metrics now say **Saved here**, with this-device scope. | Mixed-authority/uncooked/deduplication regression and source review. |
| 21 · Tab reselection | All four roots scroll to their top and pop destinations; Plan returns to Tonight. | Four-tab reselection interaction and before/after captures. |
| 22 · Targets | Cook-day choices scroll horizontally with a 44pt minimum; price fields have a 44pt minimum. | Geometry/source and design checks. |
| 23 · Joining state | Interactive dismissal is disabled while joining or resolving the seat. | Source/build. Slow-network real-account join remains a release check. |
| 24 · Widget continuity | Stable recipe/post IDs travel in snapshots and URLs; routes open the item, or explain unavailable content. | Source/build and existing deep-link tests. Real widget tap-through remains a device check. |
| 25 · Sheet/form reflow | Share/People/Profile headings wrap; profile cards and filters reflow; gathering labels sit above controls; share preview reflows at AX sizes. | Default/AX5 survey and iPad renders. |
| 26 · Tonight-first Plan | Greeting, grouped tonight meal, one direct action, quieter agenda, explicit Calendar, truthful empty/shared/active/completed variants. | Small-phone above-tab action assertion; Calendar/back, local start/resume/finish, empty and shared states; light/dark, AX5 and iPad renders. |

## Verification record

The current signed app/extension and test host build successfully for arm64 Simulator. Tests use an isolated iPhone SE (3rd generation, 375×667pt) and iPad Pro 11-inch, iOS 26.5, with `-plated-design-review` in-memory fixtures. No personal database, real invitations or household posts were used. Failure injection is compiled only for DEBUG and requires that isolated preview container.

- Native suite: **416 tests passed, 0 failed**, for the complete repair logic (`unit-complete.xcresult`), including the added drag regression.
- `verified-screens.xcresult`: 7 UI tests passed; includes all four landscape roots, large-text Plan rows, normal/AX5 survey, direct cooking, edit guard, light appearance and tab reselection. Visual review then found further AX empty-row, grocery-quantity and timer crowding; those were corrected, not accepted simply because capture tests passed.
- `failure-and-ipad.xcresult`: normal iPad survey plus empty/shared/completed and profile/gathering failure tests passed. Two harness assumptions failed (the planner already selects today; the title field does not present the ingredient editor's Done bar). Both were corrected; `ipad-failure-retest.xcresult`: 2 passed, 0 failed.
- `final-phone.xcresult`: later small-phone regression/render pass, followed by any focused corrections recorded below. 10 of 11 tests passed. The remaining phone profile test exposed a keyboard-access problem. The final correction gives each field an owned focus binding and an explicit Done action above the keyboard, and places failure feedback beside Save. The passing focused retest is recorded below.
- `focused-final.xcresult`: timer and landscape item-reachability tests passed; the Profile attempt still exposed keyboard access, which prompted the explicit Done control rather than being waived as a pass.
- `verified-final.xcresult`: **3 tests passed, 0 failed** on the latest build. Profile Done → reachable Save → rejected commit preserves the bio and shows the error beside Save. Landscape Groceries exposes a hittable shopping row without scrolling. The AX5 thread heading and input prompt fit. All three final screenshots were visually inspected. The final app/extension build and design checks passed after the final view refinements.
- Design/token checks: native source rules, native/widget token agreement, website/native token agreement and timer activity parity. Website files were not edited by this work.

Large `.xcresult` bundles and raw attachment exports are reproducible local artifacts and ignored by Git. Curated rendered evidence and readable accessibility trees are retained under `after/`.

## Remaining release verification

The [17 October release verification record](release/README.md) tracks the follow-up runtime checks and additional fixes. It supersedes the release-check statuses in the table above: actual Simulator VoiceOver, system widget gallery/install/Cookbook tap-through, EventKit create/update/delete, and Calendar denied/retry have now been exercised. Physical-device checks are recorded there separately. Live two-account household/Table verification remains unavailable because a second test account/device is not available. Local queue/merge tests do not substitute for it. These changes do not certify every device/account/network combination or establish “100% flawless.” User testing should still confirm that a new arrival understands tonight, the cook and next action, and can find another date.

## Open the results

- [Tonight-first Plan, Editorial](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/after/final-phone-screens/normal-plan.png) · [Light](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/after/final-phone-screens/light-week.png)
- [Final landscape Groceries](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/after/verified-final-screens/final-landscape-groceries.png)
- [Final AX5 thread](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/after/verified-final-screens/final-ax-thread.png)
- [Rejected profile save, draft retained](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/after/verified-final-screens/failure-profile-draft-retained.png)
- [Evidence index](/Users/natemeadows/Plated/docs/ux-audit-2026-10-16/after/README.md)
