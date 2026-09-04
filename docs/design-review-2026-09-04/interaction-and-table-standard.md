# Plated: interaction craft and the complete Table

September 4, 2026. This supplements [the product direction](product-design-direction.md). The orange, typography, and warm material palette remain. This pass restores capabilities the earlier concept omitted and specifies the engineering needed to make the experience trustworthy.

The current preview is an interactive design prototype. This pass changes the preview and review documents, not the SwiftUI app, CloudKit schema, or published website. It is not a claim that the production product is finished.

## Judgment

The previous concept was not an acceptable end state. It improved hierarchy but reduced some existing product depth. The native app already contains substantially more thoughtful interaction work than that prototype showed. A redesign must preserve that work, measure it, and make the pieces agree.

The target is a product that feels considerate under interruption: you can leave a half-written reply, adjust dinner for six, return to your cooking step, and understand exactly what your household can see. The quality bar applies to recovery and permissions as much as to typography.

## Existing work to preserve

These are source observations, not new device verification:

| Existing work | Source | Design requirement |
|---|---|---|
| Horizontal intent, predicted swipe distance, cancellation recovery, revealed action hit testing, accessible equivalents | [SwipeRow.swift](../../Plated/Views/Components/SwipeRow.swift#L35) | Preserve the implementation and its edge cases. Never replace it with a threshold-only swipe. |
| Interactive edge back with a navigation transition guard | [SwipeBack.swift](../../Plated/Support/SwipeBack.swift#L28) | Every ordinary detail remains one-handed and cancelable. |
| Meal removal swipes and drag to move, with a menu equivalent | [WeekView.swift](../../Plated/Views/WeekView.swift#L409) | Keep both direct manipulation and named actions. |
| Grocery, household, activity, day-detail, and owned-comment row actions | [GrocerySheet.swift](../../Plated/Views/GrocerySheet.swift#L232), [HouseholdHomeView.swift](../../Plated/Views/HouseholdHomeView.swift#L489), [NotificationsView.swift](../../Plated/Views/NotificationsView.swift#L80), [DayDetailView.swift](../../Plated/Views/DayDetailView.swift#L191), [PostThreadView.swift](../../Plated/Views/PostThreadView.swift#L842) | Do not lose secondary actions in a visual refresh. |
| Everyone / Household feed scope, dedicated post destination, author profiles, photo double-tap, polls, saved state | [TableFeedView.swift](../../Plated/Views/TableFeedView.swift#L16) | Restore these to the concept and preserve them in implementation. |
| Reply composer, reply-to attribution, photo/link/mention attachments, comment removal | [PostThreadView.swift](../../Plated/Views/PostThreadView.swift#L350) | The thread is a full reading and writing experience. |
| Named springs, state symbol replacement, Reduce Motion handling | [Theme.swift](../../Plated/Support/Theme.swift#L290) and [DESIGN.md](../../DESIGN.md) | Centralize the behavior. No animation constants copied across screens. |
| Full first opening and a brief returning opening | [LaunchOpenerView.swift](../../Plated/Views/Onboarding/LaunchOpenerView.swift#L4) | Retain brand continuity while reducing mandatory waiting. |

## Table: photographs with real conversations

The feed is chronological by default. Photography, readable captions, clear authorship, and an attached recipe provide the visual appeal. Discussion has its own destination and enough structure to stay useful. No follower counts or popularity ranking are needed to make this feel substantial.

**Two separate choices:**

- **Everyone / Household** chooses whose posts you are browsing. Household includes posts by household members, even when they shared a post with the wider Table. Preserve the selected scope and its reading position independently.
- **Everyone at your Table / Household only** chooses who may read a new post, its attachments, and its conversation. Show this before publishing and beside the published post. The preview demonstrates this proposed audience model locally; it does not enforce remote permissions.

Tapping the photograph or title opens the post. Tapping its reply count goes directly to the conversation. Reading does not summon a keyboard. An explicit Reply action targets the person or comment and focuses the composer. Back returns to the same feed, scope, and position.

Replies have stable identities and parent references. Indentation stops after one visual level so deep discussion remains readable at 320 points; attribution and branch controls preserve the relationship. Collapsing a branch does not delete it. Removing a comment leaves the conversation beneath it intact. Replies support editing, photo and link attachments, and mentions constrained to the post's audience.

Polls allow one current choice per person, with an immediate selected symbol and proportional results. Changing your vote updates the same ballot. A published poll cannot quietly rename an option after people have voted. A missing poll has no empty vote counter.

Keep the app's own plate reaction glyph in the native product. A single tap changes the glyph and its selected state. A double-tap on a photograph adds your plate and briefly shows the result at your finger; repeated double-taps do not remove it. The preview uses supplied circle symbols to represent this behavior.

Private recipe copies, public post captions, attached recipe snapshots, and cooking history remain distinct. Editing your kitchen copy never rewrites an old discussion or changes somebody else's saved recipe.

## Motion and transitions

[Apple's motion guidance](https://developer.apple.com/design/human-interface-guidelines/motion) emphasizes purposeful feedback that follows the person's gesture. The native implementation should keep Plated's existing named springs and UIKit navigation behavior. Web preview timings below illustrate the intended pacing; they are not a replacement set of native tokens.

| Event | Intended behavior | Preview representation |
|---|---|---|
| Tab change | Stable navigation, retained stack and position; no tab bounce | Brief 160 ms content fade |
| Open a dish or post | The selected photograph leads into its destination | Approximately 340 ms image geometry transition plus content arrival |
| Back | Interactive edge gesture, cancelable, returning to the exact source | Edge-drag handler and directional 280 ms return; native physics still require device testing |
| Open / dismiss sheet | Arrives from and returns toward the same edge | Short upward arrival and 180 ms exit |
| Change selected scope | One selection indicator travels between two choices | 280 ms indicator movement |
| Save, favorite, plate, vote | Outline / filled or unchecked / checked state, readable without motion | Plate, bookmark, and poll symbols update with state |
| New reply | Appears beneath its actual parent without moving unrelated replies | Small 220 ms arrival |
| Cooking step | Consistent direction, stable controls, progress follows the step | Short directional content replacement |
| Swipe row | Content follows the finger, detent reveals actions, no destructive full-swipe commit | Intent detection, velocity projection, close-on-tap, one open row |
| Reduce Motion | Remove decorative travel while retaining state and readable feedback | OS preference plus local preview preference; short fades |

Haptics are semantic: selection at a changed position, confirmation at a committed action, warning at a refusal. Reuse `Haptic` instead of firing multiple feedback events from a button and its completion handler. Feel the sequence on hardware; a browser cannot validate it.

Fast repeated input must cancel or retarget animations. A transition must never keep the UI locked until an arbitrary visual completes. Image decode, resizing, and feed transformations should not block the main thread. Define a frame budget from the device's refresh rate and measure animation hitches on representative phones; do not infer smoothness from a desktop browser.

## Opening and loading

Distinguish the system launch surface, the first-run brand introduction, and content loading.

The proposed introduction keeps the lowercase wordmark and original orange. The dot settles into its place, then the welcome screen appears. It is skippable and approximately 1.25 seconds in the preview. This deliberately shortens the existing 4.3-second first-run piece. A returning opening is roughly 0.55 seconds in the demonstration and should disappear sooner whenever the native app can show its restored state. It must not replay on ordinary foregrounding.

These durations are demonstration ceilings, not a requirement to delay ready content. [Apple recommends a launch surface close to the first application screen](https://developer.apple.com/design/human-interface-guidelines/launching). The final system launch screen should bridge cleanly into actual app chrome. Brand onboarding happens after system launch.

Cached content appears immediately. A missing cache gets a skeleton shaped like the destination: a post for Table, rows for groceries. An unreachable service must not masquerade as an empty Table. Background refresh preserves visible content and does not replay an opening animation. No invented progress percentage, indefinite brand loop, or success state before a server receipt.

Use the preview's Entry point design control to play the first or returning opening. State review includes loading, empty, offline, and failed load.

## Profile and settings access

Use one recognizable avatar in the upper right across the four main sections and their detail screens. It opens the same profile/settings destination. An author's avatar continues to open that author, with a clear Back route.

The preview also exposes the account door in recipe and post editors and cooking. Draft text, serving counts, and cooking position survive the round trip. Navigation tabs stay hidden while settings is opened over an active editor or cooking task, preventing a background task from silently becoming an abandoned route. Small action sheets remain focused on their local choice; dismissing one returns to the screen's account door.

Settings groups should ultimately cover identity, household roles, Table membership and invitations, notification controls, appearance, accessibility, data/export, and account lifecycle. Only controls with a functioning service belong in the native release. This preview covers the previously modeled profile preferences plus motion comfort; account and membership services are not connected.

## Backend contracts required by this design

1. **Audience enforcement:** authorize reads, writes, attached assets, replies, notifications, and exports against stable membership IDs. An Everyone / Household query is not an authorization check. The current feed membership scope compares names. The current Table share deliberately uses link-based `.readWrite` permission at [TableShare.swift:152](../../Plated/Services/TableShare.swift#L152) and re-enables it during invitation at [TableShare.swift:220](../../Plated/Services/TableShare.swift#L220). Household-only content must not be placed beneath that broad share and hidden in UI. Design a separately restricted share/record hierarchy, acceptance flow, and migration; test the permission boundaries with a guest account. This is an identified implementation requirement, not a claim that content has leaked.
2. **True thread identity:** [TableComment.replyToName](../../Plated/Models/TablePost.swift#L204) records a person's display name, not a parent comment. Introduce a CloudKit-safe optional parent record reference, preserving the existing name as legacy attribution. Never guess an old parent from a matching name. Constrain the parent to the same post and prevent cycles.
3. **Single-writer reactions and ballots:** retain `TableLedger` and `TableOutbox`; do not mirror share-derived reaction state through SwiftData. Replays use stable operation and record IDs. A vote replacement must not double-count under retries or two-device use.
4. **Drafts and receipts:** persist drafts before navigating or backgrounding, including attachment upload state. Distinguish saved locally, queued, sending, sent, failed, and conflicted. Keep failed content editable. Never show two posts after an uncertain publish retry.
5. **Edits and deletion:** version posts and comments. Preserve replies when editing their parent; use deletion tombstones when needed to preserve discussion structure. Publish deletions to the owning zone and reconcile every device. Define the undo interval and how a remote acknowledgement affects undo.
6. **Attachments and provenance:** generate thumbnails, normalize orientation, remove inappropriate metadata, retain author attribution, and enforce the audience on original images as well as thumbnails. Deleted assets need cleanup. A recipe attached to a post is a versioned copy.
7. **Membership lifecycle:** invited, accepted, revoked, and left are distinct facts. A forwarded invitation link and an explicitly approved member are different access models. UI copy must describe the chosen model accurately. Verify revocation against direct asset and deep-link access, not just disappearance from the People screen.
8. **Notifications and deep links:** open the precise post/comment and expand the right branch, preserving the surrounding stack. A mention cannot summon an outsider into a household-only conversation. If a post was deleted or membership changed, explain the destination's absence and provide a route back.

Do not perform a backend rewrite merely to support a cleaner screen. Extend the existing services coherently, honor the `PlatedDish*` schema namespace, preserve migrations, and prove the multi-device behavior before replacing a service.

## What is working in the updated preview

All four sections remain connected to the recipe, servings, planning, groceries, and cooking work from the previous pass. This update adds Everyone / Household scope; three distinct sample posts; dedicated conversations; parented replies with collapse, edit and removal; audience-aware mention choices; local reply photo and link attachment handling; dish/question composing with optional polls; one-vote state; author pages; double-tap reaction handling; swipe action rows with equivalent buttons; profile access across screens; draft continuity through settings; state symbols; transition choreography; shortened first and returning opening demonstrations; and reduced motion.

The current preview opens on Groceries to show the subsequent U.S. units correction. That is a review starting point, not a proposal to change the app's normal restored destination. Reloading discards preview edits. Guest accounts, network queues, system keyboard/sheet physics, haptics, native interactive navigation, and persistent drafts are not proven by this prototype.

### Verification in this pass

- Household scope excluded Riley's post and retained Sam's two posts. The scope's purpose and each post's audience remain separately visible.
- Reply-count navigation landed at the conversation without opening the keyboard. A reply to Riley appeared under Riley's comment. Editing an existing reply retained its position.
- A half-written reply, a new poll with populated choices, and an edited recipe title survived opening profile/settings and returning.
- A household question was composed, posted locally, and voted on. The resulting mention picker offered only You and Sam. Poll selection updated its symbol, percentage, and count.
- Double-clicking the photo added one plate and stayed in the feed. The count changed from two to three.
- The dinner-row action button revealed Move and Remove. Tapping the shifted row closed the actions without navigating. Browser drag injection did not produce a verifiable gesture, so finger-driven swipes and edge-back remain a device verification gate.
- A 320-pixel conversation fixture had matching scroll and client widths, with no horizontal overflow. Dark Table/conversation layouts were inspected at 360 pixels. The local Reduce Motion state stayed active through navigation.
- The orange first-opening sequence was visually captured and completed into Welcome. JavaScript syntax validation passed, and the exercised browser flows reported no runtime errors.

These are targeted prototype checks. Photo uploads, link fetching, native keyboard behavior, real push notifications, access control, and durable synchronization were not verified by them.

## Release-quality acceptance, beyond the preview

| Workstream | Done only when |
|---|---|
| Design system | Tokens, wordmark, icon sizing, focus, touch areas, and light/dark appearances agree across app, widgets, and website. Existing design/token gates pass. |
| Core dinner loop | Import → review → edit → servings → plan → groceries → cook → notes → repeat completes without lost counts, implicit recipe rewrites, or stale shopping checks. |
| Social experience | Feed → conversation → targeted reply → attachment → mention → notification → deep link works with correct audience and ownership on two different accounts. |
| Interruption | A call, backgrounding, app termination, keyboard dismissal, tab change, or settings visit does not silently lose an edit, timer, attachment, or reading position. |
| Failure and recovery | Offline publishing, interrupted uploads, expired membership, missing/deleted parents, conflicts, retries, and undo have tested outcomes. No false empty state or false success. |
| Accessibility | Real VoiceOver, Voice Control, Switch Control, Dynamic Type, keyboard, contrast, and Reduce Motion passes cover complete tasks, not isolated controls. |
| Native motion | Finger-following swipe, canceled back transition, sheet drag, fast repeated taps, image decode, and scrolling are reviewed on phones at supported refresh rates. |
| Account and data | Join/leave household, guest invitation, access revocation, export, sign-out, and account deletion have complete states and recoverable failures. |
| Measurement | Task completion, navigation mistakes, lost drafts, failed imports, duplicate mutations, and animation hitches are observed in testing; priorities follow evidence. |

Treat these as parallel disciplines on one product, not separate cosmetic and functional phases. The decisive end-to-end rehearsal uses a household owner, a second household member, and a Table guest on separate devices. It must include a guest being unable to open a household-only post. Only then can the experience earn the promise made by its UI.
