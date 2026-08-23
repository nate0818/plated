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
        /// An import finished and reported success. Note this is any
        /// successful import, including one that turned out to carry no
        /// records — CloudKit does not distinguish, so neither can we.
        case arrived
        /// Nothing came — either the mirror was idle, or what it was doing
        /// didn't finish in time. The ordinary answer on a current device.
        case quiet
        /// An import ended badly. `endDate` alone cannot tell you this.
        case failed
    }

    // MARK: The monitor

    /// Whether CloudKit is mid-flight, kept as **state you can sample**
    /// rather than an edge you have to be listening for.
    ///
    /// This is the whole reason it exists. A start is posted exactly once,
    /// when the work begins. A pull that subscribes afterwards — right
    /// after foregrounding, right after a push, which is the common shape —
    /// never sees that edge, so it can't tell "an import is running" from
    /// "nothing is happening", concludes early, and then drops the
    /// completion when it arrives. Worse, it drops a *failure* the same
    /// way and taps success over a broken sync.
    ///
    /// So one long-lived observer registers as early as the container
    /// exists and tracks what is in flight. A pull samples it instead of
    /// guessing.
    actor Monitor {
        static let shared = Monitor()

        /// Identities, not a tally.
        ///
        /// A counter fails in both directions and neither is visible: stuck
        /// above zero puts every pull on the long deadline forever (the
        /// slow-common-path regression, permanently), and wrongly zero puts
        /// the dropped-import bug back. Because absorption hops to this
        /// actor, two events can arrive out of order, and `max(0, n - 1)`
        /// on an end whose start hasn't landed yet leaves a permanent
        /// phantom. Tracking identities is order-independent: an end that
        /// arrives first is remembered, and the start it belongs to is then
        /// refused rather than resurrecting it.
        private var running: [UUID: ContinuousClock.Instant] = [:]
        /// Ordered so the oldest can be dropped; `Set` has no bounded
        /// prune. At this size a linear `contains` is free.
        private var finished: [UUID] = []

        /// An import abandoned mid-flight — app suspended, process killed,
        /// iCloud signed out underneath it — never posts a terminal event.
        /// Without an expiry its identifier sits in `running` for the life
        /// of the process and every later pull pays the long deadline.
        private static let staleAfter: Duration = .seconds(60)
        /// Enough to reconcile out-of-order delivery without growing for
        /// the life of the process.
        private static let rememberedEndings = 64

        /// Is CloudKit doing something right now?
        var isBusy: Bool {
            let now = ContinuousClock.now
            return running.values.contains { now - $0 < Self.staleAfter }
        }

        fileprivate func absorb(_ event: NSPersistentCloudKitContainer.Event) {
            guard counts(event.type) else { return }
            let now = ContinuousClock.now
            running = running.filter { now - $0.value < Self.staleAfter }

            if event.endDate == nil {
                // Out-of-order: if this event's ending already landed, the
                // work is over — don't put it back in flight.
                guard !finished.contains(event.identifier) else { return }
                running[event.identifier] = now
            } else {
                if !finished.contains(event.identifier) {
                    finished.append(event.identifier)
                }
                running[event.identifier] = nil
                if finished.count > Self.rememberedEndings {
                    finished.removeFirst(finished.count - Self.rememberedEndings)
                }
            }
        }
    }

    /// Registered **synchronously**, so there is no window between the
    /// mirror coming up and the watcher existing. An `AsyncSequence` over
    /// notifications only subscribes once its task gets scheduled, which
    /// reopens by microseconds exactly the gap this design exists to close.
    /// Idempotent: the token is a lazy static, so repeat calls are free.
    private static let watcher: NSObjectProtocol = {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: nil
        ) { note in
            guard let event = event(from: note) else { return }
            Task { await Monitor.shared.absorb(event) }
        }
    }()

    /// Call as early as the container exists — see `PlatedStore.shared`.
    static func startMonitoring() { _ = watcher }

    /// Setup counts, exports do not, and the asymmetry is load-bearing.
    ///
    /// Setup runs on first launch and after sign-in with the first import
    /// behind it, so a pull during setup should wait for what follows.
    ///
    /// **Exports must stay out.** `refreshFeed()` calls `context.save()`
    /// immediately before waiting, which frequently kicks off an export —
    /// so counting exports would put nearly every pull on the long
    /// deadline and reinstate the exact "2 seconds for nothing new"
    /// regression the two windows exist to fix. Do not "fix" the setup gap
    /// by widening this to every event type.
    private static func counts(_ type: NSPersistentCloudKitContainer.EventType) -> Bool {
        type == .import || type == .setup
    }

    private static func event(from note: Notification) -> NSPersistentCloudKitContainer.Event? {
        note.userInfo?[
            NSPersistentCloudKitContainer.eventNotificationUserInfoKey
        ] as? NSPersistentCloudKitContainer.Event
    }

    // MARK: The wait

    /// Wait for CloudKit to finish pulling, so a pull-to-refresh means
    /// something.
    ///
    /// Two deadlines, not one. Nothing here can *ask* CloudKit to sync —
    /// no such API is exposed — so this listens, and a healthy
    /// already-current table produces no import at all. A single cap makes
    /// that common case pay the rare case's price: every ordinary "nothing
    /// new" pull rides to the ceiling. So the short deadline asks only
    /// *is the mirror doing anything*, answered by sampling `Monitor`
    /// rather than by catching an edge; the long deadline is spent only
    /// once there is work to wait for.
    ///
    /// `floor` keeps the control from flashing. Note it also raises the
    /// quiet window when set above it (the windows are ordered), so a
    /// cosmetic change to the spinner's minimum does move detection
    /// semantics.
    ///
    /// Two imports overlapping resolve first-ended-wins, which is
    /// arbitrary with respect to the one the user cares about: A failing
    /// while B succeeds reports `.failed` even though records arrived.
    /// Untangling that needs per-event identity; naming it here because
    /// `.failed` drives a different haptic.
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

    /// Whether this wait has seen work worth staying for.
    private actor Activity {
        private(set) var started = false
        func mark() { started = true }
    }

    private static func settle(quietWindow: Duration, activeTimeout: Duration) async -> RefreshOutcome {
        await withTaskGroup(of: RefreshOutcome.self) { group in
            let activity = Activity()

            group.addTask { await observeImports(noting: activity) }
            group.addTask {
                // Sample first: an import that began before this wait did
                // is exactly the case the edge cannot tell us about.
                if await Monitor.shared.isBusy { await activity.mark() }
                await sleep(quietWindow)
                // Idle mirror: nothing has begun and nothing is running, so
                // nothing is coming. Holding the spinner past here would be
                // hoping rather than waiting.
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
    /// noting along the way whether anything began.
    ///
    /// `endDate` and `succeeded` are two separate facts and the API exposes
    /// both for a reason: the first says the attempt is over, the second
    /// says it worked. A failed import carries an `endDate` too, so gating
    /// on that alone would end the wait early and hand back a success —
    /// telling the user "refreshed" in the one moment they most need to
    /// know it didn't.
    ///
    /// **Deliberate gap, decided rather than overlooked:** only `.import`
    /// events become an *outcome*, so a household whose CloudKit setup is
    /// broken — signed in, but misconfigured — reads as `.quiet` on every
    /// pull, forever, with no warning. That is the wrong thing to fix here.
    /// Broken sync is persistent state and wants a persistent affordance; a
    /// gesture the user made for an unrelated reason, reported through a
    /// buzz that cannot distinguish "nothing new" from "your account is
    /// misconfigured", is not one. When a sync-status affordance exists,
    /// this is the comment that should send you to it. (A running `.setup`
    /// does buy the long window — that is internal and adds no outcome.)
    private static func observeImports(noting activity: Activity) async -> RefreshOutcome {
        let stream = NotificationCenter.default.notifications(
            named: NSPersistentCloudKitContainer.eventChangedNotification
        )
        for await note in stream {
            guard let event = event(from: note) else { continue }
            guard event.endDate != nil else {
                if counts(event.type) { await activity.mark() }
                continue
            }
            guard event.type == .import else { continue }
            return event.succeeded ? .arrived : .failed
        }
        // The stream only ends when this task is cancelled. The caller
        // cannot tell that from a real quiet — TableFeedView's
        // `Task.isCancelled` guard is what actually distinguishes them.
        return .quiet
    }

    /// Cancellation here is ordinary — the user let go and walked away.
    ///
    /// `tolerance: .zero` because the default leeway is generous enough to
    /// matter: it pushed the 700ms wake to 701–745ms and past 760ms under
    /// load, which turned promotion into a coin flip for imports starting
    /// anywhere in that band. Zero tolerance collapses the spread to ~2ms.
    private static func sleep(_ duration: Duration) async {
        try? await Task.sleep(for: duration, tolerance: .zero)
    }
}
