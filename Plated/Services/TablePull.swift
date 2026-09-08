import Foundation
import SwiftData

/// One pull at a time, for both worlds.
///
/// `TableShare.fetchChanges` ran from four places at once: the push
/// delegate, the feed's refresh, the share-accepted handler and a tapped
/// notice, each starting from the same stored change token. The loser could
/// store an older token over the winner's, or forget the zone's token after
/// the winner had stored a good one and force a full replay next time; and
/// two overlapping `absorb`s of one delta could raise the same banner twice,
/// because each remembers its keys only after it has shown them.
///
/// So every road goes through here. A pull that arrives while one is in
/// flight joins it and runs once more after, which is the right shape for a
/// push that lands mid-refresh: the second pass picks up what the first
/// fetch was too early for.
///
/// The household zone (docs/household.md) goes through the same gate: both
/// outboxes drain first, so a push that just happened is not read back as
/// somebody else's change, then the Table zone, then the household zone.
///
/// One reader owns the household zone's cursor, and it is
/// `HouseholdShare.fetchChanges`. What it walks past is two different
/// things, though: the roster, cookbook and list belong to `HouseholdSync`,
/// and the nights belong to the peer plan pipe (docs/plan-share.md). So the
/// household delta is split here, and the plan half goes through
/// `ShareAcceptor.absorb` like any other, because that is the one place
/// `PlanLedger` is fed and the only one that gets what follows a night in
/// the right order.
@MainActor
enum TablePull {
    private static var inFlight: Task<Void, Never>?
    private static var again = false
    private static var lastPull: Date?

    /// Foreground pulls are throttled: `.active` fires after every
    /// permission sheet and every tab flip, and a table does not change
    /// that often. An accept or a join is a moment, never throttled.
    private static let foregroundGap: TimeInterval = 60

    static func pull(reason: String) async {
        if reason == "foreground", let last = lastPull,
           Date.now.timeIntervalSince(last) < foregroundGap {
            return
        }
        if let running = inFlight {
            again = true
            print("[Pull] \(reason) joined an in-flight pull")
            await running.value
            return
        }
        let task = Task { @MainActor in
            repeat {
                again = false
                let context = PlatedStore.shared.mainContext
                // Which household this phone is in, asked before anything
                // pushes or merges. The cache is per device and can lag a
                // join made on another one; on a failed listing this returns
                // the cache unchanged, so it is safe to ask every pass.
                _ = await HouseholdShare.refreshMembership()
                // The Table outbox looks a queued comment up by name at send
                // time; without a resolver it reads "no such comment" as
                // "deleted before it went" and discards it. The feed and the
                // banner action install the same closure.
                TableOutbox.shared.resolveNote = { [context] name in
                    let all = (try? context.fetch(FetchDescriptor<TableComment>())) ?? []
                    return all.first { $0.shareRecordName == name }
                }
                await TableOutbox.shared.drain(authorName: Seats.all(in: context).me?.name ?? "")
                await HouseholdOutbox.shared.drain(context: context)

                let changes = await TableShare.fetchChanges()
                await ShareAcceptor.absorb(changes)
                // Main cleaned these after every merge. Every merge is here now.
                await TableShare.removeSchemaProbes(from: context)

                let household = await HouseholdShare.fetchChanges()
                await HouseholdSync.absorb(household, context: context)
                // The nights the same walk collected, handed to the pipe
                // that owns them. After the household merge, so the news
                // and the reminders read a roster and a week that have
                // already landed; guarded, because an absorb costs an
                // identity round trip and a delta with no nights in it has
                // nothing to say.
                let plan = household.plan
                if !plan.plans.isEmpty || !plan.deleted.isEmpty
                    || !plan.replayedOwners.isEmpty || plan.householdShareChanged {
                    await ShareAcceptor.absorb(plan)
                }
                // A member whose Table accept failed at join is seated at
                // the household's Table the next time iCloud answers
                // (docs/household.md section 7, step 1).
                await HouseholdSync.ensureTableJoined()

                lastPull = .now
                print("[Pull] \(reason): \(changes.posts.count) posts, \(changes.notes.count) notes, \(changes.reactions.count) reactions\(changes.sharesChanged ? ", seats" : ""); household \(household.seats.count) seats, \(household.meals.count) meals, \(household.recipes.count) recipes, \(plan.plans.count) plans\(household.zoneGone ? ", zone gone" : "")")
                // This phone's own nights go out AFTER both folds, and not
                // awaited: a publish pass is CloudKit round trips of its
                // own, and a silent push's budget is spent on the fetch.
                PlanShare.schedule(reason: "pull")
            } while again
            // Cleared here, as the task's last act, and not after the
            // await below resumes: a pull landing in that gap would join
            // a task that had already finished, set `again`, and be lost.
            inFlight = nil
        }
        inFlight = task
        await task.value
    }
}
