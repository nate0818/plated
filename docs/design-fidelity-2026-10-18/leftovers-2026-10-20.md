# Eat leftovers — change and verification record

User request: “Add eat leftovers option for when choosing what to eat.”

Candidate: isolated `plated-approved-fidelity/Plated` worktree, base
`fc87ad199364019c1ed19c18c6ac24cc0d9b1eb5`, with the existing approved-design correction
work preserved. The earlier `candidate-source-pass7.json` predates these changes.
No original design approval artifact has been changed. No release was uploaded.

## Acceptance criteria

| Area | Required behavior |
| --- | --- |
| Choice | Eat leftovers is reachable in the day/meal chooser and dinner menu, with a 44-point accessible target. |
| Identity | The selected date and slot retain their shopping ID, author, notes and servings. Other dates are unaffected. |
| Saved state | No recipe, stale photo, cook assignment, completion timestamp, cooking reaction or actual minutes remain. |
| Presentation | Compact Leftovers title, useful description and Change dinner plan; no Start cooking, Mark cooked, fake recipe artwork or assignment prompt. |
| Local recovery | Failed saves keep the sheet open and restore only action-owned state; failed new choices leave no unsaved duplicate. |
| Shared authority | Edit the existing household record; show pending/conflict/refusal honestly; no competing private plan. |
| Groceries | Clear the replaced recipe's ingredient lines immediately and on the wire. Restore correctly scaled lines if a recipe is chosen again. |
| Household acceptance | Explicit no-recipe evidence survives received-change adoption without matching a real cookbook recipe titled Leftovers. |
| History | Counts as a planned night, not freshly cooked or eating out; old stale flags cannot award new cooking credit. |
| Widgets/reminders | Show the plan without stale recipe artwork, cook assignment or a new cooking reminder. |
| Persistence | Save and reopen an isolated disk store; verify the same identity, date/slot and no-recipe state. |
| Variants | Native review in both appearances, default/AX text, compact/large phone and supported landscape iPad remains required. |

## Verification completed

- App, widget and app-test target: **build-for-testing passed**.
- Fresh UI runner `com.natemeadows.plated.LeftoversUI`: **build-for-testing passed**.
- **3 Foundation-only classification tests passed**, zero failures, against exact
  copied production `PlanMealChoice.swift`. This does not execute app behavior.
- **45 additional app regression tests and 7 UI probes compiled but did not run**.
  They cover local choice/conversion/rollback, disk-store reopen, metrics and widget
  snapshots, shared edits/ingredient scaling/queued relaunch, household adoption,
  removal recovery, date switching, recipe replacement and failed-save recovery.
- Static checks passed: 183 Swift files against design rules; 10 app/widget tokens;
  timer source equality; 159 recorded CloudKit fields; `git diff --check`.
- 309 app/widget/test inputs were hashed before compilation and verified unchanged
  afterward. Digest: `24ba349c6facbecc1b14fa610f21ab1a29d5ca00182aeca84dd10401bc43933b`.
- [Exact source, compiled outputs and logs](leftovers-source.json) record provenance.
  The prior pass-7 source manifest is historical for this addition.

No database schema field was added. Optional fields in local edit/recovery JSON are
backward compatible. The original approval `review.js` and `review.css` hashes are
unchanged. An existing redundant-await warning remains in HouseholdShare.swift.

## Still unverified

Xcode's first-launch check returns 69. An elevated simulator listing times out;
both fresh build logs confirm CoreSimulator 1171.7.0 is installed while Xcode needs
1174.9.2. Approval was already given; the pending administrator-authenticated Xcode
setup is still necessary. A successful compile does not override that failure.

No fresh native render, interaction, VoiceOver, live CloudKit two-account round trip
or upgrade test has been executed for this addition. Disk persistence has an authored
close/reopen model test, not a runtime pass. Shared queued/conflict/refusal behavior
has compiled regression coverage, not live network proof. Required phone sizes,
appearances, accessibility sizes and landscape iPad checks remain in the queue.

The local Debug app/widget still identifies as 1.0.1 (45), with different source and
binary hashes from distributed build 45. It has **not** been installed on the user's
phone or uploaded to TestFlight. No commit, push, production archive, export or
release occurred for this addition. Earlier release gates remain outstanding.
