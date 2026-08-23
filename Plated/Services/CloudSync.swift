import Foundation
import CoreData

/// What the mirror is doing, for the one gesture that asks.
///
/// SwiftData's `cloudKitDatabase: .automatic` is an
/// `NSPersistentCloudKitContainer` underneath, and that class posts its
/// progress on the default notification centre whoever built it. We never
/// touch the container itself — reaching for one would spin up a second
/// mirror, which the store law forbids — we only listen.
enum CloudSync {

    /// How a wait ended. Three outcomes, because a person can tell them
    /// apart and should: something landed, nothing was there, or the sync
    /// broke. Collapsing the third into the first is how a refresh ends up
    /// reporting success at the exact moment iCloud failed.
    enum RefreshOutcome {
        /// An import finished and brought records with it.
        case arrived
        /// Nothing came before the deadline — the honest answer offline.
        case quiet
        /// An import ended badly. `endDate` alone cannot tell you this.
        case failed
    }

    /// Wait for CloudKit to finish pulling, so a pull-to-refresh means
    /// something.
    ///
    /// Resolves on the first completed import, or at `timeout`, whichever
    /// comes first — but never before `floor`, so the refresh control
    /// doesn't flash and snap back in a way that reads as a no-op.
    static func waitForImport(
        floor: Duration = .milliseconds(450),
        timeout: Duration = .seconds(2)
    ) async -> RefreshOutcome {
        async let settled = raceImportAgainst(timeout)
        async let minimumBeat: Void = sleep(floor)
        let (outcome, _) = await (settled, minimumBeat)
        return outcome
    }

    private static func raceImportAgainst(_ timeout: Duration) async -> RefreshOutcome {
        await withTaskGroup(of: RefreshOutcome.self) { group in
            group.addTask { await nextFinishedImport() }
            group.addTask {
                await sleep(timeout)
                return .quiet
            }
            let first = await group.next() ?? .quiet
            group.cancelAll()
            return first
        }
    }

    /// Returns when CloudKit reports an import that has actually ended.
    ///
    /// Two separate facts, and the API exposes both for a reason: `endDate`
    /// says the attempt is over, `succeeded` says it worked. A failed
    /// import carries an `endDate` too, so gating on that alone would end
    /// the wait early and hand back a success — telling the user "refreshed"
    /// in the one moment they most need to know it didn't.
    ///
    /// **Deliberate gap, decided rather than overlooked:** only `.import`
    /// events are inspected, so a household whose CloudKit *setup* is
    /// broken — signed in, but misconfigured — reads as `.quiet` on every
    /// pull, forever, with no warning. That is the wrong thing to fix here.
    /// Broken sync is persistent state and wants a persistent affordance; a
    /// gesture the user made for an unrelated reason, reported through a
    /// buzz that cannot distinguish "nothing new" from "your account is
    /// misconfigured", is not one. When a sync-status affordance exists,
    /// this is the comment that should send you to it.
    private static func nextFinishedImport() async -> RefreshOutcome {
        let stream = NotificationCenter.default.notifications(
            named: NSPersistentCloudKitContainer.eventChangedNotification
        )
        for await note in stream {
            let event = note.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event
            guard let event, event.type == .import, event.endDate != nil else { continue }
            return event.succeeded ? .arrived : .failed
        }
        // The stream only ends when this task is cancelled.
        return .quiet
    }

    /// Cancellation here is ordinary — the user let go and walked away —
    /// so it is swallowed at the one place that knows it is harmless,
    /// rather than by a `try?` at a call site that then can't tell a
    /// finished wait from an abandoned one.
    private static func sleep(_ duration: Duration) async {
        try? await Task.sleep(for: duration)
    }
}
