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
- `scripts/testflight.sh` bumps the build, archives, uploads, then waits for
  processing and adds the build to the External group, which is the public
  TestFlight link. Upload alone reaches Internal only; `scripts/asc groups`
  shows what each group is actually serving.
- A fresh simulator has no household, so every widget and half the screens
  are empty. `-plated-seed-sample` (Debug only) puts the preview household
  into the live store: `xcrun simctl launch <udid> com.natemeadows.plated
  -plated-seed-sample`. Never on a phone signed into iCloud.
- **Injected simulator taps fall through iOS context menus** (the icon's
  long-press menu, Edit > Add Widget) and land on whatever is underneath.
  To photograph the widget gallery or the icon menu, drive SpringBoard from
  an XCUITest (`XCUIApplication(bundleIdentifier: "com.apple.springboard")`)
  in a throwaway project outside the repo; `press(forDuration:)` on a
  widget opens its menu, on a bare icon it launches the app.
- **A connected iPhone that is locked stalls `xcodebuild` forever.** It
  retries `com.apple.mobile.notification_proxy` every three seconds, with
  the device listed under Devices Offline the whole time, and never reaches
  compilation. Through `make test`'s grep it looks exactly like a slow
  build: no output, no error, xcodebuild at 0% CPU. Two sessions lost about
  an hour each to it on the same afternoon. Unlock the phone, or read
  `xcodebuild` raw rather than filtered before believing anything about the
  code.
- `make design` checks the DESIGN.md rules a machine can check, and both
  ship paths refuse a build that breaks one. A deliberate exception is fine
  but has to say so at the line: `// design-ok(<rule>): why this one is right`.
- `make test` runs `PlatedTests` on a simulator. The news digest
  (`TableNews.digest`) is pure and tested there; a test is how the merge's
  reaction-dropping bug was found, which no screen could ever have shown.
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
- **A household night is not a `PlannedMeal`, so every reader of one went
  blind at once.** Dropping the meal merge was right (a fact in a
  `.automatic` store would have two writers), but it also meant a night
  somebody else planned is only ever a `PlanLedger.Entry`. Ten files fetch
  `PlannedMeal`; three of them were answering for half the plan and saying
  so out loud. Siri said "Nothing plated yet tonight" over a housemate's
  dinner, Prongsby said "Nothing's plated for Thursday", and the grocery
  list left their ingredients off while still receiving their check-off
  marks, keyed to rows it had never built. When a fact stops being mirrored,
  grep the whole class (`FetchDescriptor<Model>`) rather than fixing the one
  surface you noticed.
- **Hand-written CloudKit types carry a reserved `Plated` prefix (`PlatedDish*`
  for the Table, `PlatedHousehold*` for the household) and nothing else may.**
  The SwiftData mirror adopts any private-database record whose type matches
  one of its entity names, which is the ghost post in MEMORY.md.
  `TableShare.assertNoEntityCollision()` makes that a DEBUG check rather than
  something to remember. `TablePost` is the one exception and is read-only: it
  IS the collision, and it cannot be renamed without abandoning tables shared
  before the rename.
- **Share-derived state does not go in the mirror.** Plates and ballots live in
  `TableLedger`, a JSON book in the app group, the queue in `TableOutbox`
  beside it, and other phones' planned nights in `PlanLedger` (with the
  publisher's book `plan-share.json` and the edit queue `plan-edits.json`,
  which is a queue and so is per device for the same reason `TableOutbox`
  is); see `docs/plan-share.md`. Put them in a `@Model` and the mirror becomes a second writer to
  a fact the shared zone already owns: two devices mid-propagation ping-pong a
  recomputed count, and a person's own plate flickers on and off in front of
  them. A mirrored outbox is worse — a distributed queue with no lease, where
  two of one person's devices both drain the same row.
- **A value crossing the seam needs a human. An absence does not.** The
  household may take a night off the author's plan outright: a `removed`
  flag on the record, and the author's phone deletes that one `PlannedMeal`.
  That is NOT the merge the rule above forbids, and the difference is worth
  stating so nobody reads it as permission. After the deletion the
  household's night lives only in the zone and this phone's row is gone, so
  there is no second version of any fact for two writers to converge on and
  nothing to ping-pong. Folding a title, a cook or a serving count back into
  a `PlannedMeal` is still two writers and still forbidden. The test is
  whether anything is left to disagree about.
- **A CloudKit list field minted from an empty array is minted as the wrong
  type, permanently**, and every later save carrying a real list then fails
  `.invalidArguments`. Omit the key instead of writing `[]`.
- **CloudKit has no boolean type.** A Bool is stored as INT64 and
  `record[key] as? Bool` is a bridging coin flip. Use `TableShare.int(_:_:)`.
- **Holding down the app icon offers the sizes of the FIRST widget in the
  bundle and greys out the rest.** With a small-only widget first, "Medium-
  sized widget" and "Large widget" sat disabled in Plated's own menu, and
  nothing in the gallery was reachable from there. `TonightWidget` comes in
  all three families and stays first in `PlatedWidgetsBundle`; a widget
  added above it must too.
- **The widget is a second target and cannot import `Theme.swift`.** Its
  tokens are hand-copied into `PlatedWidgets/PlatedWidgets.swift`, and that
  copy has already drifted once: it shipped `inkSecondary` at the rejected
  `0x8A8074` for weeks after the app fixed it, while receiving other edits in
  the same enum. A fork that gets *some* fixes is worse than one that gets
  none, because nothing about it looks stale. `scripts/check-tokens` diffs the
  two and both `make phone` and `scripts/testflight.sh` now refuse to ship on
  drift. Change a colour in Theme.swift, change it there too.
- **A read a SwiftUI body performs may not write observed state, and a write
  that changes nothing is still a write.** `PlanLedger.photo(for:)` was made
  to clear its own cache on a miss, `photos[name] = nil`. A night with no
  photograph misses every time, the class is `@Observable`, and assigning nil
  to a key that is ALREADY ABSENT still counts as a mutation, so every read
  invalidated the view that had just performed it. One core at 99%, the test
  host never finishing, and the suite stopping rather than failing. It was
  diagnosed by sampling the stuck process; six runs before that were blamed
  on the simulator, a wedged device and a missing binary, because a hang
  looks exactly like a slow machine. Guard the write (`if photos[name] != nil`)
  and, when a run stalls with no output, sample the process before blaming
  the environment. "The environment did it" is a claim like any other and
  does not get to skip verification because it is convenient.
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
