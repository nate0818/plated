# Live two-account release gate

**Not run.** The user confirmed that no second test device/account is available. Local queue/merge tests and the single-account physical-phone checks do not satisfy this gate.

Use two distinct test iCloud accounts, A and B, with the same candidate build. Keep account data disposable and record the device/OS, build, action time, resulting UI and relevant record IDs. Do not record credentials or unrelated personal data. Test both author/participant directions.

| Journey | Required observation |
|---|---|
| Household invitation and join | A creates an invitation; B joins and resolves its seat. Both show the same household and membership. Slow/repeated acceptance cannot create duplicate seats or leave joining dismissible halfway through. |
| Shared plan creation | A plans a recipe; B receives the night, cook, servings and ingredients. B's remote night remains a shared-ledger entry, not a duplicate local PlannedMeal. |
| Remote edits and adoption | B changes cook/servings/title; A sees an honest pending/incoming state and explicitly adopts applicable values. Retrying does not duplicate meals or bounce values between stores. |
| Concurrent changes | Change the same night from both accounts before delivery. Both converge on the server's result; rejected changes remain visible/recoverable. Repeat with removal versus edit. |
| Groceries | Check an item on A and observe it on B; uncheck on B and observe A. Increase servings after buying, then verify only the additional amount reopens. Remove/undo/restore manual extras without resurrection or loss. |
| Cooking | A starts a shared night, changes its cooking context, then completes it. B receives the correct plan completion and cook. Local step cursors/timers remain local. |
| Table | Publish a dish/question, open its thread, comment, plate/unplate and vote from both accounts. Confirm author identity, stable widget/notification item links and no reaction-count oscillation. |
| Offline and reconnect | Take B offline, queue edits and grocery actions, relaunch, reconnect. Pending copy stays truthful and delivery occurs once. Repeat with A offline and with an operation rejected by the server. |
| Removal and revocation | Remove a shared night and revoke membership/invitation access. Old links explain unavailable access; previously cached household/Table data and unauthorized edit queues do not remain usable. |
| Account availability | Exercise signed-out/unavailable iCloud without signing out of a personal production account. Show actionable errors and retain local drafts. Restore the account and verify recovery. |

Mark each row passed only after both devices show the expected result. Attach failures and repairs to the release ledger and rerun the affected journey. Do not infer delivery from an enqueue log or from a test that constructs both sides in one process.
