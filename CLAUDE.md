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
