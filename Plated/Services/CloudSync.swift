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
        /// Nothing came — either the mirror was idle, or what it was doing
        /// didn't finish in time. The ordinary answer on a current device.
        case quiet
        /// An import ended badly. `endDate` alone cannot tell you this.
        case failed
    }

    /// Wait for CloudKit to finish pulling, so a pull-to-refresh means
    /// something.
    ///
    /// Two deadlines, not one, and that is the whole design. Nothing here
    /// can *ask* CloudKit to sync — no such API is exposed — so this
    /// listens, and a healthy already-current table produces no import at
    /// all. A single cap makes that common case pay the rare case's price:
    /// every ordinary "nothing new" pull rides to the ceiling. So the first
    /// deadline is short and only asks *is the mirror doing anything*; if
    /// it isn't, nothing is coming and we stop. The long deadline is
    /// spent only once we've seen work actually in flight.
    ///
    /// `floor` keeps the control from flashing and snapping back in a way
    /// that reads as a no-op.
    ///
    /// Note it can only observe imports that finish *after* the observer is
    /// registered — one landing in the moment between the pull starting and
    /// this call subscribing is missed, and that pull runs to a deadline.
    /// Inherent to listening rather than polling.
    static func waitForImport(
        floor: Duration = .milliseconds(450),
        quietWindow: Duration = .milliseconds(700),
        activeTimeout: Duration = .seconds(3)
    ) async -> RefreshOutcome {
        // A deadline shorter than the floor isn't a deadline. Ordering the
        // three keeps the caps meaningful whatever a caller passes.
        let quiet = max(quietWindow, floor)
        let active = max(activeTimeout, quiet)

        async let settled = settle(quietWindow: quiet, activeTimeout: active)
        async let minimumBeat: Void = sleep(floor)
        let (outcome, _) = await (settled, minimumBeat)
        return outcome
    }

    /// Tracks whether the mirror ever started work, so the deadline can
    /// grow to fit real activity instead of being guessed up front.
    private actor Activity {
        private(set) var started = false
        func mark() { started = true }
    }

    private static func settle(quietWindow: Duration, activeTimeout: Duration) async -> RefreshOutcome {
        await withTaskGroup(of: RefreshOutcome.self) { group in
            let activity = Activity()

            group.addTask { await observeImports(noting: activity) }
            group.addTask {
                await sleep(quietWindow)
                // Idle mirror: no import has even begun, so none is coming.
                // Holding the spinner past here would be hoping, not waiting.
                if await activity.started {
                    await sleep(activeTimeout - quietWindow)
                }
                return .quiet
            }

            let first = await group.next() ?? .quiet
            group.cancelAll()
            return first
        }
    }

    /// Returns when CloudKit reports an import that has actually ended,
    /// noting along the way whether one ever began.
    ///
    /// `endDate` and `succeeded` are two separate facts and the API exposes
    /// both for a reason: the first says the attempt is over, the second
    /// says it worked. A failed import carries an `endDate` too, so gating
    /// on that alone would end the wait early and hand back a success —
    /// telling the user "refreshed" in the one moment they most need to
    /// know it didn't.
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
    private static func observeImports(noting activity: Activity) async -> RefreshOutcome {
        let stream = NotificationCenter.default.notifications(
            named: NSPersistentCloudKitContainer.eventChangedNotification
        )
        for await note in stream {
            let event = note.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event
            guard let event, event.type == .import else { continue }
            guard event.endDate != nil else {
                // Started but not finished — this is the signal that buys
                // the long deadline.
                await activity.mark()
                continue
            }
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
