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
/// The household zone goes through the same gate. Social writes drain
/// before the reads; bulk household publication follows them so a cookbook
/// upload cannot delay the next incoming comment. Digests exclude our own
/// identity regardless of which side of the read a write lands on.
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
    private static var maintenanceRequested = false
    private static var lastMaintenance: Date?
    private(set) static var lastHouseholdReadSucceeded = false
    private(set) static var lastReadSucceeded = false
    private(set) static var lastReadHadChanges = false

    static func pull(reason: String) async {
        maintenanceRequested = maintenanceRequested || reason != "automatic"
        if let running = inFlight {
            again = true
            print("[Pull] \(reason) joined an in-flight pull")
            await running.value
            return
        }
        let task = Task { @MainActor in
            lastReadHadChanges = false
            repeat {
                again = false
                let context = PlatedStore.shared.mainContext
                // Keep the visible feed current without repeating account,
                // subscription and full publication maintenance every tick.
                let maintenance = maintenanceRequested
                    || (lastMaintenance.map { Date.now.timeIntervalSince($0) >= 60 } ?? true)
                maintenanceRequested = false
                // Recheck membership before maintenance writes. Incremental
                // reads in between still process share changes and removal.
                if maintenance {
                    _ = await HouseholdShare.refreshMembership()
                    lastMaintenance = .now
                    Task { await TableShare.subscribe() }
                    Task { await Directory.retryDeviceRegistration() }
                }
                // The Table outbox looks a queued comment up by name at send
                // time; without a resolver it reads "no such comment" as
                // "deleted before it went" and discards it. The feed and the
                // banner action install the same closure.
                TableOutbox.shared.resolveNote = { [context] name in
                    let all = (try? context.fetch(FetchDescriptor<TableComment>())) ?? []
                    return all.first { $0.shareRecordName == name }
                }
                await TableOutbox.shared.drain(authorName: Seats.all(in: context).me?.name ?? "")
                // Claims that failed on accept get another try here, so an
                // Invited row on the host does not stick after a seated join.
                if maintenance {
                    await TableClaimOutbox.drain()
                }

                let changes = await TableShare.fetchChanges()
                if maintenance || changes.hasEvents { await ShareAcceptor.absorb(changes) }
                // Main cleaned these after every merge. Every merge is here now.
                if maintenance { await TableShare.removeSchemaProbes(from: context) }

                let household = await HouseholdShare.fetchChanges()
                lastHouseholdReadSucceeded = !household.failed && !household.zoneGone
                lastReadSucceeded = !changes.failed && !household.failed
                lastReadHadChanges = lastReadHadChanges || changes.hasEvents
                    || !household.isEmpty || household.sharesChanged || household.zoneGone
                    || household.plan.hasEvents
                if maintenance || !household.isEmpty || household.sharesChanged
                    || household.zoneGone || household.replayed {
                    await HouseholdSync.absorb(household, context: context)
                }
                // The merge can repair an older overwritten profile or
                // consume a fresh reinvitation. Publish that repair now.
                if maintenance { await HouseholdOutbox.shared.drain(context: context) }
                if maintenance, case .hosting = HouseholdShare.membership {
                    await Seats.settleStuckInvites(in: context)
                }
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
                if maintenance { await HouseholdSync.ensureTableJoined() }

                print("[Pull] \(reason): \(changes.posts.count) posts, \(changes.notes.count) notes, \(changes.reactions.count) reactions\(changes.sharesChanged ? ", seats" : ""); household \(household.seats.count) seats, \(household.recipes.count) recipes, \(plan.plans.count) plans\(household.zoneGone ? ", zone gone" : "")")
                // This phone's own nights go out AFTER both folds, and not
                // awaited: a publish pass is CloudKit round trips of its
                // own, and a silent push's budget is spent on the fetch.
                if maintenance { PlanShare.schedule(reason: "pull") }
                NotificationCenter.default.post(name: ShareAcceptor.didChangeRemotely, object: nil)
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
