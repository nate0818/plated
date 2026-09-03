# CLAUDE.md

Plated is a household dinner planner for iOS: a week you plan together, a
private Table you post dishes to, and a cookbook. SwiftUI + SwiftData, mirrored
to CloudKit. Several Claude sessions often work this repo at once, so anything
another session needs to know belongs in a file, not in one session's memory.

## Design

Use **@DESIGN.md** as the source of truth for all UI, visual and copy work.

When creating or modifying an interface:

- Follow the existing tokens and components. `Plated/Support/Theme.swift` holds
  the real values; reuse before inventing, and never hard-code a colour.
- Preserve the register described in DESIGN.md — quiet chrome, earned colour.
- Flag deliberate deviations rather than making them quietly.

## Verifying

**The simulator lies about this app.** Every one of these was invisible there and
obvious on a phone: WeatherKit returning nothing, the VisionKit scanner,
`canSendText()` (always false on sim, so the whole invite path is dead), text
rendering a hair larger so fixed-height layouts overflow, and Foundation Models.

- `make phone` builds the working tree and installs it on Nate's iPhone.
- `scripts/testflight.sh` bumps the build, archives, and uploads.
- `make design` checks the DESIGN.md rules a machine can check, and both
  ship paths refuse a build that breaks one. A deliberate exception is fine
  but has to say so at the line: `// design-ok(<rule>): why this one is right`.
- Prefer looking at a screenshot over reasoning about layout. Prefer touching the
  flow over trusting that it compiles.
- When a flow crosses process boundaries — Contacts, CloudKit, Messages —
  `print()` at every step. Silence is indistinguishable from success, and an
  empty console usually means no code ran at all.

## Traps that cost hours

- **Xcode drops unknown `INFOPLIST_KEY_*` settings silently.** `CKSharingSupported`
  and `UIBackgroundModes` live in `config/PlatedInfo.plist`. Verify a key landed by
  reading the built app's `Info.plist`, not by trusting a green build.
- **Two `.sheet` modifiers on one view is undefined behaviour**, and a UIKit
  controller that dismisses itself (`CNContactPickerViewController`) never tells
  SwiftUI, so `onDismiss` may never fire. Chain such flows through UIKit's
  `dismiss(animated:completion:)` — see `Plated/Services/InviteFlow.swift`.
- **A `CKShare`'s URL is server-assigned**: read it off the record that comes back
  from `modifyRecords`, never off the instance you saved.
- **CloudKit needs table GRANTs, not just RLS** on the Supabase side; "expose new
  tables" being off locks out the service role too.
- **Model changes must stay CloudKit-safe**: new properties optional or defaulted.
- **Hand-written CloudKit types live in the `PlatedDish*` namespace and nothing
  else may.** The SwiftData mirror adopts any private-database record whose
  type matches one of its entity names, which is the ghost post in MEMORY.md.
  `TableShare.assertNoEntityCollision()` makes that a DEBUG check rather than
  something to remember. `TablePost` is the one exception and is read-only: it
  IS the collision, and it cannot be renamed without abandoning tables shared
  before the rename.
- **Share-derived state does not go in the mirror.** Plates and ballots live in
  `TableLedger`, a JSON book in the app group, and the queue in `TableOutbox`
  beside it. Put them in a `@Model` and the mirror becomes a second writer to
  a fact the shared zone already owns: two devices mid-propagation ping-pong a
  recomputed count, and a person's own plate flickers on and off in front of
  them. A mirrored outbox is worse — a distributed queue with no lease, where
  two of one person's devices both drain the same row.
- **A CloudKit list field minted from an empty array is minted as the wrong
  type, permanently**, and every later save carrying a real list then fails
  `.invalidArguments`. Omit the key instead of writing `[]`.
- **CloudKit has no boolean type.** A Bool is stored as INT64 and
  `record[key] as? Bool` is a bridging coin flip. Use `TableShare.int(_:_:)`.
- **The widget is a second target and cannot import `Theme.swift`.** Its
  tokens are hand-copied into `PlatedWidgets/PlatedWidgets.swift`, and that
  copy has already drifted once: it shipped `inkSecondary` at the rejected
  `0x8A8074` for weeks after the app fixed it, while receiving other edits in
  the same enum. A fork that gets *some* fixes is worse than one that gets
  none, because nothing about it looks stale. `scripts/check-tokens` diffs the
  two and both `make phone` and `scripts/testflight.sh` now refuse to ship on
  drift. Change a colour in Theme.swift, change it there too.
- The store migration in `PlatedStore` is precious. An unreadable live store must
  always abort. Never simplify it to an existence check.

## Working with other sessions

The repo is shared. Before a wide change, check `git status` for another
session's in-flight work, and say what you touched. Merges to `main` go through
a fast-forward that leaves the working tree alone:

```
git fetch . <branch>:main
```

## Conventions

- Commit messages are a sentence about the change, not a category prefix.
- Comments explain **why**, especially the non-obvious constraint that forced the
  shape of the code. Do not narrate what the line already says.
- Keep `MEMORY.md` notes for decisions; keep durable project law in this file or
  DESIGN.md so every session and every human can see it.
- `docs/open-decisions.md` holds the questions that were measured and
  deliberately left open. Read it before reopening one of them, and delete the
  entry when it is decided. A judgment call with two defensible answers is not
  a bug to be fixed quietly at 4am.
