# Table comment reactions and cookbook saving

## Experience and implementation

A person reading a comment or reply can like it without leaving the conversation, see its count, and undo their own like. The familiar heart is secondary to Reply. The same control appears beside comment previews in the feed. A filled heart and the selected accessibility trait identify the current person's reaction; color is not the only cue. Each target is at least 44 points. Pending writes show a clock and announce “waiting to sync.”

The existing binary reaction transport is keyed by the note's stable `note-…` record name. It uses the deployed `PlatedDishPlate` fields, including `postRecordName` and the cascade `postRef`, now pointing to the comment. The CloudKit share parent remains `table-root`. Post IDs and note IDs cannot collide. No mirrored model fields, CloudKit fields, or record types were added; the existing outbox JSON format remains compatible. Older apps ignore comment likes in their UI rather than adding them to post counts.

The JSON ledger owns counts and the observable durable outbox owns pending status. A rapid like/unlike replaces one intent. Its older in-flight completion cannot remove the newer intent. Comment deletion clears queued likes and local counts. Hard deletion preserves a tombstone anchor for surviving replies. Reaction writes now fetch the current server record, reject older timestamps, and preserve change tags when saving; conflicts re-read, and failures stay retryable. This also corrects older queued post reactions and ballots overwriting newer server state.

Comment authors receive coalesced Activity rows when others like their comments, including comments on somebody else's post. The row carries a heart, the actor, a comment excerpt, and a link to the containing post. Self reactions do not notify. Unlike updates the remaining names and face without resetting read state or time; the last unlike or comment deletion removes the row. Existing reaction notification preferences apply. Comment likes remain passive like post reactions; this change does not add a social APNs backend.

Screenshot review also corrected truncated reply recipients at AX5, deleted comments inflating feed counts, the Reply action on deleted comments, and the singular “Show 1 reply” label. Replayed comments now repair missing author IDs before deciding who should receive reaction Activity. The accessibility audit also exposed invisible Plan text/actions behind the Table; applying visibility to Plan’s actual navigation content removes them while keeping its state. The new UI test verifies accessibility returns when Plan is selected again.

## Cookbook-saving clarity

The thread header no longer contains a generic Save button or Saved receipt. Eligible recipe/legacy dish posts offer **Post options → Save to cookbook**. General posts and posts already in the cookbook omit that action. The feed uses the full Save to cookbook label and an explicit recipe-draft accessibility hint. Canceling the prefilled editor returns to the conversation without saving. Saving one's own post from a profile-opened thread now follows the feed's existing rule: no self-award or self-credit Activity row.

## Verification

- Full app and widget simulator build succeeded.
- Full unit suite: 515 tests, 4 existing Calendar opt-in skips, zero failures. See `build/comment-reactions-verified-unit.xcresult` and `/tmp/plated-comment-reactions-verified-unit.log` for final counts.
- Twelve new production-path regression tests cover separate comment/reply/post targets; like/unlike queue coalescing and in-flight completion; JSON compatibility; stale merges; deletion cleanup; contextual, deduplicated Activity; retractions; conflict retries; offline failure; and legacy author repair.
- Simulator UI runs: `build/comment-reactions-options-ui.xcresult` (iPhone 17 Pro, iOS 27), `build/thread-options-compact-verified-ui.xcresult` (iPhone SE 3, iOS 26.5), `build/comment-reactions-ipad-ui.xcresult` (iPad Pro 11, iOS 26.5). Screenshots and audit reports are attached to those runs. UI assertions cover touch targets, selected traits, accessible values, independent reply counts, collapse/reopen, deleted-comment controls, feed previews, and largest Dynamic Type.
- Final iPhone 17 Pro rerun: six interaction checks and one report-only accessibility capture passed (`build/comment-reactions-options-ui.xcresult`). Added checks exercise the cookbook menu, prefilled editor, cancellation, feed label, and general/already-saved post eligibility. The audit again returned no issues. Final app/widget build: `/tmp/plated-thread-options-final-build.log`.
- Final compact iPhone rerun: six interaction checks and one report-only accessibility capture completed with zero test failures (`build/thread-options-compact-verified-ui.xcresult`). The contrast diagnostic below persists. A preceding method-filtered invocation executed zero tests and is not counted. Screenshots confirm the full cookbook label fits the compact feed.
- Final service regression rerun: 62 tests passed (`build/comment-reactions-final-service-tests.xcresult`).
- Fourteen interaction checks passed across the two iPhone sizes and iPad. The separate accessibility test captures evidence and is not a passing accessibility gate. The iOS 27 thread audit returned no issues after the inactive Plan fix. The iOS 26.5 compact audit still reports contrast for the Nate reply author at the bottom of the scroll viewport, where the row extends behind the opaque composer. The compact diagnostic is reproduced in `build/thread-options-compact-verified-ui.xcresult`; its [full diagnostic](compact-accessibility.txt) is retained for physical inspection, not suppressed or counted as an accessibility pass.
- `make design tokens`, `scripts/check-schema`, and `git diff --check` pass. Schema manifest remains 159 deployed fields.
- SwiftUI static audit ran. It found no flags in the new reaction component; broader pre-existing thread/feed findings are retained for the ongoing audit rather than represented as newly verified.

Screenshots: [dark thread](thread-dark.png), [light feed](feed-light.png), [AX5 reply](reply-ax5-light.png), [iPad AX5](ipad-reply-ax5.png), [explicit cookbook menu](cookbook-menu.png).

Standard SwiftUI profile: native menu and buttons with existing Editorial tokens. Provisional design review: 84/100 (platform 13/15, layout 13/15, semantics 14/15, interaction 18/20, motion 14/15, accessibility 5/10, implementation/performance evidence 7/10), capped by missing physical assistive-technology and multi-account evidence. A second visual pass corrected the name wrapping and comment counts; this score is not release certification.

## Remaining release evidence

The compact accessibility diagnostic, physical VoiceOver navigation, and two-account CloudKit delivery have not been exercised for these new controls. Use two real account sessions to verify likes and unlikes in each direction, foreground delivery without pull-to-refresh, background/relaunch persistence, airplane-mode retries, and comment deletion with a queued reaction. Check Activity on the comment author's phone, including a reply on the other person's post, and confirm reaction preferences and mute behavior.

The unresolved social APNs delivery work in `docs/social-delivery-2026-10-17.md` remains a separate release gate. Simulator tests do not establish phone notification delivery. TestFlight remains build 40; this change has not been distributed. No claim of complete accessibility certification or zero bugs is made.
