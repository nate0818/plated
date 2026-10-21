# Social and people design fidelity — October 18, 2026

Reference: the original, unchanged `docs/design-polish-review-2026-10-18/review.js` and `review.css`, including its rendered green proposals. Baseline: build 45 native PNGs in `docs/design-parity-recheck-2026-10-18/after`. Source starting revision: `fc87ad1`. This independent pass read the original annotations and viewed the native green and cream images. It did not accept the earlier “native adaptations” section as proof of parity.

## Findings and source corrections

| Surface | Verified discrepancy in build 45 | Approved treatment / correction in this worktree |
| --- | --- | --- |
| Table media | Shared `PhotoWell` limited media to 320 points; approved 402-point proposal used 288. Native photo plus caption and two interactive preview comments consumed the first viewport. | Table now requests a 288-point maximum and 10-point corners; natural aspect ratio remains respected. The full conversation is reached through View N comments. |
| Table caption | A 23-point standalone serif title, 15-point caption, two full comment previews and large action glyphs differed materially from the compact proposal. | Author, retained title and caption share a 14-point reading run. No authored title is discarded. Actions use regular 22-point glyphs and 12-point counts. The complete conversation and its reactions remain available in the thread. |
| Table byline | Semibold tracked 11-point timestamp had the micro-label treatment instead of the approved quiet 12-point metadata. Avatar was 38 instead of 36. | Timestamp uses caption typography; avatar is 36 points. |
| Composer identity | Native avatar 44 versus approved 36; audience 13 semibold versus 12 regular. | Compact 36-point identity and quieter audience. |
| Composer writing/tools | Prompt 23 instead of 22, oversized inter-section gap, fully capsule tools, missing footer rule; saved status was below tools instead of attached to identity. | 22-point serif prompt, 16-point section spacing, 15-point tool corners, footer rule, real saved/pending/error status beside the author. Targets remain at least 44 points. |
| Composer photo | Fit-to-image height up to 240 and one overflow menu differed from approved 225-point bounded photo with direct controls. | 225-point photo, direct Remove at upper right and Change photo at lower left. “Change photo” remains honest: replacement exists, an image editor does not. |
| Thread summary | Native 15-point caption and 26-point reaction separated content more than approved 14/22; extra header separator. | 14-point reading, 22-point reaction and no redundant header rule. Semantic ink supplied to Comments. |
| Thread replies | Reaction count sat horizontally beside the heart. Reply labels used tracked micro typography. | Heart is 17 points above a 10-point count; metadata uses 12-point caption. Nested line is inset with the reply instead of starting at the outer page edge. |
| Thread composer | Filled square plus and separate filled send circle preserved the old silhouette. | Current-author avatar carries a small attachment badge; field and arrow share one 46-point capsule. Attachment, mention, photo and link actions remain available through the avatar control. Send retains a 44-point target. |
| Activity | Entire event sentence had uniform emphasis; object omitted from timestamp context; unread dot at trailing edge; 40-point avatars. | Actor emphasized separately, object + event time, leading 5-point sage unread marker, 36-point avatars, 42-point thumbnail, 17-point row insets. Existing excerpt/deep-link logic preserved. |
| Household header | Ringed Back plus gear plus bell differed from approved plain Back and gear in the pushed destination. | Quiet Back and regular gear; embedded household omits duplicate bell. Nonembedded root keeps its navigation access. |
| Household cover | Missing-photo dashed banner and repeated seated-name caption reproduced old visual structure. | Shallow 103-point cover with original approved Our household / Good food. Together. treatment. Missing photos add an honest Add photo action rather than an invented image. Whole cover is the photo-change action. |
| Household people | Native rows had 52-point inner minimum + 24-point vertical padding (76 total); proposal approximately 62. Menu buttons retained filled discs. | 44-point inner target + 18-point vertical inset (62 total), 14-point name, 12-point context, no filled menu disc. People title is 22 points. |
| Household responsibility | Outlined rotation cells and large automatic-turns card/scoreboard overwhelmed the lower overview; approved shared-plan explanation was missing. | Filled day cells with a single 1.5-point active outline, help above them, approved shared-plan explanation. Automation remains in an explicit Turn-taking settings disclosure; How turns work explains the behavior; stats remain through an explicit text destination. |
| Profile navigation | Filled square Back/Settings differed from approved clear controls. | Quiet 44-point controls. |
| Profile contribution | Spread equal-width counts, extra Last 7 days heading + summary, stretched tabs, no member View household action; literal “1 household milestones earned.” | 18-point counts / 11-point labels with 25-point gaps; concise verified latest-event row; leading tabs with 19-point gaps and 12-point type; member household action; correct singular/plural. Accessibility counts keep a 2-column grid and tabs stack. |
| Profile grid | Native Posts grid had no page gutter. | 20-point gutters match the approved content column. |
| Create | System black glyphs in cream, 12-point details vs 13, extra 10-point inter-row gap, 22-point vertical padding vs 23. | Coordinator owns the CreateMenuSheet correction because it shares MainShellView with navigation work. |
| Shared palette | Native white raised controls in cream versus approved #E2E8D9 caused composer/Profile controls to wash into the paper. Multiple semantic values differed. | Coordinator owns exact semantic palette and shared-control corrections. |

## Data differences are not design failures, but also are not coverage

The existing own-profile fixture has 0 posts and 0 cooked dinners. The household fixture has local Sam/Riley seats, no household photo, and no verified recent action. Activity fixtures use historical simple sentences. These are valid states, but cannot prove the proposed populated profile grid, joined member profile, actual avatar, covered household or contextual comment/join/reaction rows.

The original proposal’s illustrative photos/counts must not be copied into real data. Equivalent isolated fixtures are needed to verify the layout branches.

## Remaining checks before a parity claim

- Fresh native images from this exact source, both appearances; none were generated by this subtask.
- Table pending/sending/retry, text-only/photo, short/long title and caption, no comments/many comments, group scope, own/other menus, empty/loading/offline/recovery.
- Composer empty/photo/saved, photo failure/retry, crop/replace meaning, audience selection, long author, keyboard, poll, tags, title in More, cancellation and restored draft.
- Thread notification-target highlight, reply target/Cancel, sending/retry, deleted parent with descendants, long names, comment photos/links/mentions, attachments through avatar, disabled/enabled Send, reaction announcement.
- Activity fresh comment excerpt + target, household join, grouped reactions + thumbnail, read/unread, unseen items not marked read, blocked/deleted object, empty/error/offline where available.
- Household real photo + absent photo, organizer/member/invited/removed/local seat, long title, latest activity, removal error/retry, new invitation after removal, rotation Save/Cancel/Unassigned, automatic-turns expansion and persisted value.
- Profile self/member, populated photo grid, text-only posts, empty each collection, long name/bio, missing identity, own-only Saved, latest event present/absent, zero/one/many milestones, private data isolation.
- Compact/larger iPhone, minimum/current shipping OS, AX sizes, actual iPad landscape/narrow windows, keyboard and accessibility diagnostics.
- Physical VoiceOver, live cross-account photo/activity transport and lock-screen notifications remain separate device checks.

## Explicit remaining differences to resolve visually

People overflow remains visible because it provides existing iCloud repair access; the proposal only pictured Invite. The native minimum 44-point action targets are preserved where the mock’s visible icon/button was smaller. Household has a small stats destination after the approved privacy summary to preserve existing functionality. Composer exposes Change photo rather than falsely promising editing tools. These differences must be acknowledged during review, not hidden behind a blanket “native adaptation” claim.

## Verification performed by this subtask

Read-only baseline: original rendered proposals + native green/cream screenshots for Table, composer, thread, household, profile and Create; Activity unread green plus source. Syntax-only `swiftc -frontend -parse` passed for the seven edited Swift files. `git diff --check` passed. No build, fresh rendering, interaction test or device verification performed here. The coordinator is responsible for the final native run and its evidence ledger.

## Why the previous pass missed this

The prior screen matrix asserted a named element existed, then captured an image. It did not assert approved geometry or validate matching data branches. Review also treated palette, title preservation, photo size and added legacy controls as generic adaptations. That turned semantic intent into a completion claim while the actual composition still differed. The original artifact must stay the expected result; screenshots and implementation must be inspected against it, with state/fixture differences named explicitly.

## Independent follow-up review corrections

A second source review identified that the draft-status HStack could compete with long author/audience text, especially for error status at AX5. Composer now stacks status below identity at accessibility sizes and uses ViewThatFits to select the stacked layout whenever the compact row cannot fit at other sizes. Saved/pending/error strings remain driven by actual draft state.

The automatic-turn preference was incorrectly hidden behind an info control labelled How turns work. It now has an explicit Turn-taking settings disclosure with an expanded/collapsed accessibility value; the info control continues to reveal explanatory help separately. The existing AppStorage binding and 44-point targets remain intact.

These follow-up source changes passed syntax parsing and diff whitespace checks. Fresh native rendering of populated/error drafts at AX5 and interaction/persistence checks for the preference are still required; no app build was run by this subtask.

## Initial fresh native capture review

Viewed all ten PNGs from `/Users/natemeadows/Plated/build/fidelity-initial-named`: Table, Create, composer, thread and Profile in both appearances. This batch predates the final draft-status reflow and turn-taking disclosure corrections. The coordinator owns exact binary provenance. The original browser could not be reopened in this pass because the Mac was locked; comparison used the unchanged original CSS/JS plus the earlier actual proposal-render inspection. This is not a fresh browser comparison.

Verified visible improvements include the Table photo's 288-point height, regular heart actions, compact caption, semantic cream/green palette, quiet Profile/Thread controls, bounded comment composer, and semantic Create glyphs. These observations do not constitute a full screen or release pass.

Remaining concrete findings:

- The cream thread prompt was still system gray. Explicit inkSecondary prompts have now been applied to thread reply/link, composer title/poll, profile fields and household Add by name; text entry uses semantic ink. These new changes have syntax proof only.
- Profile Edit profile looks full-width, but the captured AX tree gives its button a 68.3-by-17-point rectangle. Its frame/background live outside Button(title:); move sizing/contentShape into the label. View household uses the same source pattern.
- Comment avatars remain 30 points at both nesting levels instead of approved parent 36/reply 28. The nested guide starts at x53, versus the original CSS's page20 + margin47 = x67.
- The Table caption uses adjacent bold actor and authored-title runs, yielding “Sam Pancake Dinner.” as a single heading-like phrase. Keep the actor bold and preserve the authored title in regular caption text.
- Table audience typography is 13 points versus the original 12. The 28-point gap from filter bottom to first author control exceeds the original 19-point post margin.
- Create descriptions are semantically equivalent but are not verbatim original copy.

The empty composer and own zero-post profile cannot prove photo/saved/error drafts or populated member profile/grid. Thread reply-target, keyboard, notification highlight and deleted-parent states remain outside this ten-image batch. Profile/household avatar transport and push delivery still require live-account proof.

## Capture-confirmed correction pass

The coordinator authorized the remaining native-capture findings after the signed unit suite completed. Source now makes Profile Edit profile and View household label-based buttons, with the full-width minimum-44-point label, background and contentShape inside the Button. This addresses the previously measured text-only hit region; fresh AX geometry and edge taps still need verification.

Thread comment avatars now use 36 points for parents and 28 for replies. Reply guide is inset 47 points from the content edge (x67 on a 402-point phone); reply content starts another 14 points inward. The invisible profile action remains 44-by-44 inside the label, while negative trailing layout padding keeps the original visual text column. Its hit rectangle can extend into adjacent noninteractive author text; no second interactive target occupies that space. Check actual AX rectangles and profile taps in the rebuilt binary.

The Table caption now bolds only the actor and preserves authored title and caption as regular 14-point prose. Audience copy uses 12-point caption typography. Filter bottom inset is 3 points plus the post's existing 16-point top inset, yielding the approved 19-point gap before its author control.

Syntax parsing and diff whitespace checks passed for this correction pass. No builds, native screenshots or interaction tests were run by this subtask after these edits.

## Publication and reply behavior — source changed after pass2

This is a new authorized source window after the pass2 candidate. Pass2 screenshots, tests and binary hashes do not include these behavior changes and must not be cited as verification of them.

The previous feed's Waiting to sync label conflated idle/unattempted, active and known-failed publication. Its manual retry set also missed composer/background/cooking publication callers. `TablePostPublication` now observes unique attempts keyed by account, destination and record identity at the single `TableShare.publish` entry point. Concurrent attempts are count-safe: one failure cannot hide another running attempt, duplicate completion cannot settle a new retry, and durable `isPublished` remains the acknowledgment of successful CloudKit saving. The ledger is transient; relaunch with an unpublished post says Saved on this device / not shared yet, rather than inventing an active attempt or retained error.

Publication preflight confirms account identity, allows local-placeholder resolution, refuses known-account changes and mismatched authored identities, moves tracking from unresolved to selected destination, and checks the account again after network waits. Account reset invalidates old attempts. No remote database schema, service configuration or live backend data was changed.

Own post and poll cards now distinguish Sending, Saved on this device / not shared yet, Couldn't share / saved on this device with Retry, and Shared with your Table. These describe publication to the Table; they do not promise delivery to a phone or a read receipt. No-status previews were removed as a misleading substitute for real state.

Thirteen cloud-free publication regression tests were added for state transitions, overlapping success/failure in both orders, duplicate completion, account/destination/record separation, account reset, destination resolution, legacy-own destination aliases, account continuation, durable success, automatic observation and non-delivery copy. These tests have been written and syntax-parsed only; the coordinator must run the new candidate suite.

Remaining native checks: own text/photo/poll card state layouts at default and AX sizes, Retry lifecycle without refresh, posting from every caller, offline/relaunch behavior, account change during preflight/save, and genuine cross-device visibility. Source parsing is not runtime or live publication proof.


Long reply branches now initially collapse when they contain more than two live replies. View N replies / Hide replies is reversible during the visit, uses a 44-point label target, and exposes Expanded/Collapsed to accessibility. Existing one- and two-reply conversations remain visible. New live replies, pending local replies, restored reply-draft parents and notification targets reveal only their ancestor path; an explicit Hide is not undone by an unrelated refresh. Deferred parent arrival preserves an already revealed target. An empty initial query is not treated as loaded history, avoiding accidentally expanding every historical branch on first sync.

The connected count/context check found that deleted leaves previously inflated descendant counts and could leave irrelevant deleted-only branches visible. Disclosure counts and the collapse threshold now count live descendants. Deleted ancestors remain only to connect a live reply, and an all-deleted thread receives the normal empty hint. Orphans/cycles stay reachable without duplicating rows or leaking collapsed descendants through the fallback. Pending-outbox changes are observed independently of comment changes; the waiting copy uses this device for iPad accuracy.

Twenty pure reply-policy tests were added for initial/short/long branches, reversible disclosure, explicit-hide persistence, notification targeting, new and pending replies, restored/reordered context, deleted nodes/counts, orphan/cycle safety, and resulting rendered row sequences. Helper typechecking, all changed Swift syntax parsing, and whitespace checks passed. The new XCTest suite has not run: a temporary standalone harness could not locate XCTest, and no app build was attempted by this subtask. The coordinator must run these tests on the new candidate and inspect native collapse/expand, notification scroll/highlight, pending/error/retry, keyboard and accessibility behavior. All of these changes are newer than pass2.

An independent read-only review of the publication changes found no concrete regression in the edited paths: wrapper coverage, rekeying, account guards, reset invalidation and durable-save ordering were inspected. This is source review, not CloudKit concurrency proof. The overlapping-attempt tests exercise the ledger; actual concurrent db.save conflict behavior still needs integration evidence.

## UI coverage preparation after behavior changes

Prepared, not executed: the compact-feed comment test now scrolls only `table-feed` or `table-post-thread` and selects the exact `post-review-comment-reactions` comment action. It asserts View 2 comments, the A market find title, Comments 2 and the unchanged like/selection result. The Plan-tab accessibility test now follows the approved feed-to-thread route rather than searching for inline reactions that the approved compact feed intentionally removed.

Optional memory-only fixtures extend the thread to four replies (five live comments total), leaving the original two-comment fixture untouched. Three new UI tests cover initial collapse, reversible View/Hide and reaction preservation at default/AX5, plus the actual shell-to-feed-to-targeted-thread link route without test scrolling. The target screenshot is retained; this test does not independently assert the transient highlight pixels.

Three new publication presentation tests cover all four labels, failed-only Retry with a 44-point target, and horizontal containment in both appearances and AX5. Their four own-post fixtures are memory-only and set only transient ledger state; no CloudKit save or phone delivery is inferred. The tests intentionally do not tap Retry because a UI fixture must not fake production network success or mutate a live account. Actual retry publication remains a separate integration check. No simulator, app build or UI test was run by this subtask. Swift syntax parsing and whitespace checks passed; the coordinator must rebuild before executing this new coverage.

## Schema-checker writer alias — frozen app source preserved

The schema gate uses enclosing Swift function names as historical writer identities. The publication helper rename from publish to publishRecord therefore produced 11 false additions although every literal written key and the PlatedDish record constructor remained unchanged. The checker now canonicalizes publishRecord to the historical publish manifest identity, guarded by the exact private publisher signature, the matching non-CloudKit stub, exactly two declarations, the single PlatedDish type constant and the helper's postType constructor. A colliding writer in another scanned source is rejected. New fields are still compared against the unchanged deployed manifest; changed or ambiguous record writers fail closed.

Validation: the current source passes with 159 fields. Temporary source copies prove that an undeployed field fails as publish.schemaProbeUndeployed, changing the record type fails the mapping guard, and a colliding writer fails the mapping guard. Bash syntax and diff whitespace checks pass. Manifest SHA-256 remains 5ee680c69cb6646659b919db01c189ac09107ef335720d5cd4bb98bbbeb30aaa. No --accept, deployment or schema waiver was used.

A coordinator-authorized overload rename was briefly applied before its superseding instruction arrived; those three Swift names were restored exactly to publishRecord. The final correction changes only the schema checker and these findings, leaving the app source at the frozen candidate.
