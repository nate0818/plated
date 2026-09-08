import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Household rows that have not reached the zone yet (docs/household.md §2).
///
/// A JSON book in the app group, per device, for the same reason
/// `TableOutbox` is: a mirrored queue is a distributed queue with no lease,
/// and two of one person's devices would both drain the same entry. The
/// entry is a record name and a kind, never a copy of the row: the row is
/// found again at push time, so the queue can never hold a second, stale
/// version of the thing it is sending.
///
/// `at` is the time of the FIRST local change since the row last matched
/// the server. A re-enqueue while an entry is pending keeps the earlier
/// time, because that is the version the push's `modifiedAt` has to carry
/// for the server-side comparison to mean anything.
@MainActor
final class HouseholdOutbox {
    static let shared = HouseholdOutbox()

    enum Kind: String, Codable, CaseIterable {
        case seat, meal, recipe, gathering, line, mark, root
    }

    struct Entry: Codable, Identifiable, Equatable {
        /// The CloudKit record name.
        var id: String
        var kind: Kind
        var isDelete: Bool
        var at: Date
        /// Refusals so far. A rate limit or a network blip does not count;
        /// only an answer that says the write itself is wrong.
        var tries: Int = 0
    }

    /// Seats and recipes go before the meals that reference them, so a
    /// meal never lands pointing at a record that is not there yet, and the
    /// root goes last because `publishedAt` on it means everything else has.
    static let drainOrder: [Kind] = [.seat, .recipe, .gathering, .meal, .line, .mark, .root]

    /// How many records `publishAll` queued, written by it and read by
    /// Home's "Sharing with your household, 40 of 360." Its presence is
    /// also how a drain knows it is ending the host's first publish rather
    /// than an ordinary edit, so `publishedAt` is stamped once and not on
    /// every quiet drain a solo host makes afterwards.
    static let publishTotalKey = "plated.household.publishTotal"

    private var entries: [Entry] = []
    /// Launch, foreground and every pull all ask for a drain; two running at
    /// once would push the same record twice and race their bookkeeping.
    private var draining = false
    /// A drain asked for while a join is running, waiting for it to end.
    /// One at a time: a second request while one is parked has nothing to
    /// add, because the drain that runs takes the whole queue.
    private var parkedForJoin: Task<Void, Never>?

    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetBridge.appGroupID)?
            .appending(path: "household-outbox.json")
    }

    private init() { load() }

    var pending: [Entry] { entries }
    var isEmpty: Bool { entries.isEmpty }

    func hasPending(_ recordName: String) -> Bool {
        entries.contains { $0.id == recordName }
    }

    /// Queue a save. An entry that is already waiting keeps its earlier `at`
    /// and its tries; an entry waiting as a delete stays a delete, because
    /// deletion wins any conflict and a row deleted then edited is a row that
    /// is gone.
    func enqueueUpsert(_ kind: Kind, _ recordName: String, at: Date = .now) {
        guard !recordName.isEmpty else { return }
        if let i = entries.firstIndex(where: { $0.id == recordName }) {
            guard !entries[i].isDelete else { return }
            entries[i].kind = kind
            entries[i].at = min(entries[i].at, at)
        } else {
            entries.append(Entry(id: recordName, kind: kind, isDelete: false, at: at))
        }
        save()
    }

    /// Queue a delete, replacing any save waiting for the same name.
    func enqueueDelete(_ kind: Kind, _ recordName: String) {
        guard !recordName.isEmpty else { return }
        entries.removeAll { $0.id == recordName }
        entries.append(Entry(id: recordName, kind: kind, isDelete: true, at: .now))
        save()
    }

    /// The root has one name, so enqueueing it is never about a row.
    func enqueueRoot() {
        enqueueUpsert(.root, HouseholdShare.rootRecordName)
    }

    func remove(_ id: String) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// This attempt was refused. Kept, so it goes out on the next drain.
    func failed(_ id: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].tries += 1
        // Twenty refusals is not a network blip, it is a write that will
        // never land. Dropping it is honest; retrying forever is a queue
        // that never drains and a battery that never rests.
        if entries[i].tries > 20 {
            print("PLATED HOUSEHOLD: outbox dropped \(id) after \(entries[i].tries) refusals")
            entries.remove(at: i)
        }
        save()
    }

    func clear() {
        entries = []
        // A drain waiting on a join has nothing left to send.
        parkedForJoin?.cancel()
        parkedForJoin = nil
        save()
    }

    /// Put everything queued into the zone, one kind at a time in
    /// `drainOrder`. `HouseholdShare.push` does the fetch-compare-save per
    /// record and batches the wire calls; this only decides what each
    /// answer means for the queue.
    ///
    /// Held back entirely while the identity is a placeholder: every record
    /// carries `modifiedBy`, and a row stamped `local-<uuid>` would arrive at
    /// the household as a stranger. `HouseholdSync.reattribute` fixes the
    /// rows the moment CloudKit answers who this is, and the next drain
    /// sends them.
    ///
    /// Answers whether it ran. A drain that was parked or refused is not
    /// a drain that found nothing to send, and a test has to tell them
    /// apart.
    @discardableResult
    func drain(context: ModelContext) async -> Bool {
        guard !entries.isEmpty else { return false }
        guard !TableIdentity.isPlaceholder else {
            print("PLATED HOUSEHOLD: outbox holding \(entries.count) entries until the identity is confirmed")
            return false
        }
        // A join adopts what the joiner brought across several saves before
        // it drains at its own end (docs/household.md §7, steps 4 and 5):
        // the owner row is being retired onto the claimed seat, recipes are
        // being stamped mine one fetch at a time. A debounced observer drain
        // or a pull's drain landing in between would push a row half-way
        // through that: a seat still carrying the owner role, a recipe
        // stamped but not yet enqueued beside its seat. So nothing drains
        // while `isJoining` is set. The join's own drain call is parked by
        // the same test, because nothing here can tell it from a stranger's;
        // it runs a beat later, the moment the join clears the flag, which is
        // the end the contract asks for.
        guard !HouseholdSync.isJoining else {
            parkUntilJoined(context: context)
            return false
        }
        return await run(context: context)
    }

    /// Wait for the join to finish, then drain. Polled rather than
    /// signalled: `isJoining` is a plain flag in `HouseholdSync`, and the
    /// join clears it right after its own drain call returns, so the wait
    /// is a tick or two in the ordinary case and the length of a seat-picker
    /// sheet at most. Fifteen minutes is neither; it is a flag that was
    /// never cleared, and holding every later edit hostage to it until
    /// relaunch is the worse failure, so the wait gives up and drains.
    private func parkUntilJoined(context: ModelContext) {
        guard parkedForJoin == nil else { return }
        print("PLATED HOUSEHOLD: outbox parked \(entries.count) entries until the join finishes")
        parkedForJoin = Task { @MainActor in
            let deadline = Date.now.addingTimeInterval(15 * 60)
            while HouseholdSync.isJoining, Date.now < deadline, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else { return }
            parkedForJoin = nil
            if HouseholdSync.isJoining {
                print("PLATED HOUSEHOLD: outbox stopped waiting for a join that never finished")
            }
            // Nobody is waiting on this drain, so its answer has no reader.
            _ = await run(context: context)
        }
    }

    private func run(context: ModelContext) async -> Bool {
        guard !entries.isEmpty, !draining else { return false }
        // CloudKit already told us not before a certain time (§6). Walking
        // the seven kinds to be handed `.retry` seven times costs nothing
        // but log noise and a background assertion, and the next drain
        // comes from the next save or the next pull anyway.
        guard !HouseholdShare.isRateLimited else {
            print("PLATED HOUSEHOLD: outbox holding \(entries.count) entries, still rate limited")
            return false
        }
        draining = true
        defer { draining = false }

        // A drain is the only thing standing between a local edit and the
        // zone, and it is usually started by a save the person made just
        // before putting the phone down (§6). Without the assertion iOS
        // suspends us mid-kind, the push is cancelled, and the entry sits
        // until the next launch.
        let assertion = Self.beginAssertion()
        defer { Self.endAssertion(assertion) }

        // Local edits that lost to a newer server version, and the versions
        // that won, gathered across the kinds so the bell hears about them
        // once per drain (§2, "Versions, not clocks").
        var lost = HouseholdShare.Changes()
        var conflicts: [String] = []

        for kind in Self.drainOrder {
            let batch = entries.filter { $0.kind == kind }
            guard !batch.isEmpty else { continue }

            let upserts = batch.filter { !$0.isDelete }
            if !upserts.isEmpty {
                print("PLATED HOUSEHOLD: pushing \(upserts.count) \(kind.rawValue) record(s)")
                let outcomes = await HouseholdShare.push(entries: upserts, context: context)
                let theirs = Self.conflicts(in: outcomes, entries: upserts)
                lost.absorb(theirs.theirs)
                conflicts += theirs.names
                for entry in upserts {
                    guard let outcome = outcomes[entry.id] else {
                        // No answer is not a refusal. Kept without a try,
                        // and said out loud, because a push that forgets
                        // to answer for a record is a bug worth seeing.
                        print("PLATED HOUSEHOLD: no outcome for \(entry.id), keeping it")
                        continue
                    }
                    switch outcome {
                    case .saved, .remoteNewer, .gone:
                        remove(entry.id)
                    case .retry:
                        continue
                    case .failed:
                        failed(entry.id)
                    }
                }
            }

            let deletes = batch.filter(\.isDelete)
            if !deletes.isEmpty {
                print("PLATED HOUSEHOLD: deleting \(deletes.count) \(kind.rawValue) record(s)")
                let ok = await HouseholdShare.delete(recordNames: deletes.map(\.id))
                for entry in deletes {
                    if ok { remove(entry.id) } else { failed(entry.id) }
                }
            }
        }
        print("PLATED HOUSEHOLD: outbox drained, \(entries.count) left")
        await stampPublishedIfFirstDrain(context: context)

        if !conflicts.isEmpty {
            // The row already shows their version: the push merged it the
            // moment it saw the server was newer. This is only the sentence
            // that says so, and it goes through the same gate and the same
            // own-action guard as every other household notice.
            await TableNews.deliver(
                household: lost, outcome: HouseholdShare.MergeOutcome(conflicts: conflicts), context: context
            )
        }
        return true
    }

    /// Hold the app awake for the length of a drain. A no-op off iOS, and
    /// on iOS a plain expiration handler: the system takes the time back
    /// and the entries stay queued, which is the same end as a cancelled
    /// push, just without the crash for an unended assertion.
    private static func beginAssertion() -> Any? {
        #if canImport(UIKit) && !os(watchOS)
        let id = UIApplication.shared.beginBackgroundTask(withName: "household-outbox") {
            print("PLATED HOUSEHOLD: background time ran out mid-drain, the rest waits")
        }
        return id == .invalid ? nil : id
        #else
        return nil
        #endif
    }

    private static func endAssertion(_ token: Any?) {
        #if canImport(UIKit) && !os(watchOS)
        guard let id = token as? UIBackgroundTaskIdentifier else { return }
        UIApplication.shared.endBackgroundTask(id)
        #endif
    }

    /// §6: when the host's outbox first drains empty after `publishAll`,
    /// `publishedAt` goes on the root.
    ///
    /// Nothing else writes it. Without it every member's Plan and Cookbook
    /// say "Still arriving from the host's phone." for the life of the
    /// household, and the join sheet promises an upload that finished
    /// weeks ago.
    ///
    /// The root is pushed here rather than enqueued, because enqueueing
    /// would re-enter the drain that is ending. A refusal takes the stamp
    /// back: the cache may never claim a date the zone does not carry.
    private func stampPublishedIfFirstDrain(context: ModelContext) async {
        guard entries.isEmpty, case .hosting = HouseholdShare.membership else { return }
        let defaults = HouseholdShare.groupDefaults
        guard defaults.object(forKey: Self.publishTotalKey) != nil else { return }
        guard HouseholdShare.cachedPublishedAt == nil else {
            defaults.removeObject(forKey: Self.publishTotalKey)
            return
        }
        defaults.set(Date.now, forKey: HouseholdShare.Keys.publishedAt)
        guard await HouseholdShare.pushRoot(HouseholdShare.localRoot(in: context)) else {
            defaults.removeObject(forKey: HouseholdShare.Keys.publishedAt)
            print("PLATED HOUSEHOLD: could not stamp publishedAt, trying after the next drain")
            return
        }
        defaults.removeObject(forKey: Self.publishTotalKey)
        print("PLATED HOUSEHOLD: the first publish is on the wire, publishedAt stamped")
    }

    /// What a drain owes the bell: the names whose local edit lost, and the
    /// server versions that won, shaped as a pull delivery so the digest can
    /// read `modifiedBy` and `modifiedAt` off them. Only a recipe or a meal
    /// earns the row (docs/household.md §2 and §10). A seat's fields have
    /// rules that make "theirs" the right answer rather than a loss, a mark
    /// is last-writer by design, and a line or a gathering is not a thing a
    /// person edits for long enough to be surprised by. Pure, so a test can
    /// hold it to that without a zone.
    static func conflicts(
        in outcomes: [String: HouseholdShare.PushOutcome], entries: [Entry]
    ) -> (theirs: HouseholdShare.Changes, names: [String]) {
        var theirs = HouseholdShare.Changes()
        var names: [String] = []
        for entry in entries where entry.kind == .recipe || entry.kind == .meal {
            guard case .remoteNewer(let served)? = outcomes[entry.id] else { continue }
            theirs.absorb(served)
            names.append(entry.id)
        }
        return (theirs, names)
    }

    // MARK: Disk

    private func load() {
        guard let url = Self.url, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let url = Self.url, let data = try? JSONEncoder().encode(entries) else { return }
        // Atomic: a kill mid-write must not leave a half-written queue,
        // which would decode as nothing and silently forget every push.
        try? data.write(to: url, options: .atomic)
    }
}
