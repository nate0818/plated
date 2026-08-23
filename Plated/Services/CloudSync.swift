import Foundation
import CoreData
import UIKit

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

    /// The three windows, named so the monitor's expiry can derive from
    /// them instead of restating a number by hand.
    enum Defaults {
        /// Keeps the refresh control from flashing and snapping back.
        static let floor: Duration = .milliseconds(450)
        /// Long enough to ask "is the mirror doing anything", short enough
        /// that a current table doesn't pay for the answer.
        static let quietWindow: Duration = .milliseconds(700)
        /// The longest wait we will ever give real work.
        static let activeTimeout: Duration = .seconds(3)
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

        /// **A hint, not a ledger.** Its only consumer is a choice between
        /// two wait lengths, so being occasionally wrong is a designed
        /// property with a bounded cost — not a bug to be "fixed" into a
        /// state machine that is exactly right and impossible to reason
        /// about. But the two ways of being wrong are not symmetric, and
        /// that asymmetry decides the expiry below: a phantom entry costs
        /// one slow spinner per pull, while a missing entry costs a
        /// DROPPED IMPORT — the app telling the household its data arrived
        /// when it didn't, which is the correctness bug that has bitten
        /// this file twice. So err toward keeping entries.
        ///
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
        /// An open piece of work, and how many pulls it has already sent
        /// down the long deadline without ever confirming itself.
        private struct Entry {
            let began: ContinuousClock.Instant
            var promotions = 0
        }
        private var running: [UUID: Entry] = [:]
        /// Ordered so the oldest can be dropped; `Set` has no bounded
        /// prune. At this size a linear `contains` is free.
        private var finished: [UUID] = []

        /// An import abandoned mid-flight — app suspended, process killed,
        /// iCloud signed out underneath it — never posts a terminal event.
        /// Without an expiry its identifier sits in `running` for the life
        /// of the process and every later pull pays the long deadline.
        ///
        /// A **backstop**, deliberately not the mechanism.
        ///
        /// No threshold on elapsed-since-start can do this job, and it took
        /// three attempts to see why: a phantom *is* a live import that
        /// stopped being live. Both start the same clock by the same
        /// mechanism, so elapsed time has the same distribution under both
        /// hypotheses — a threshold cannot separate them, it can only swap
        /// one error for the other. 60s wasn't sitting between two
        /// distributions, it was sitting inside one, and `activeTimeout *
        /// 100` was the same felt number with a formula painted on it.
        ///
        /// Worse, the failure correlated with the users who need this most.
        /// `isBusy` is sampled once per wait, so an aged-out entry doesn't
        /// end one wait early — it makes *every later pull* take the short
        /// deadline, which is the dropped-import bug reinstated. And the
        /// imports that outlive any threshold are first syncs on bad
        /// networks pulling RecipePhoto blobs as CKAssets: precisely the
        /// households whose imports are likeliest to fail.
        ///
        /// So the real mechanisms are causal — `clearOnForeground` below,
        /// and the promotion budget — and this only catches whatever they
        /// both miss. Its exact value is no longer load-bearing, which is
        /// what finally makes it defensible.
        private static let staleAfter: Duration = .seconds(300)

        /// How many pulls one unconfirmed entry may send down the long
        /// deadline before it stops counting. Bounds the cost in the
        /// currency the user actually pays — "three slow pulls, ever" —
        /// and costs a real import nothing, because live work keeps
        /// producing events that reset the budget.
        private static let promotionBudget = 3
        /// Enough to reconcile out-of-order delivery without growing for
        /// the life of the process — and, less obviously, **this number is
        /// also the phantom threshold.** A tombstone that has been evicted
        /// can no longer refuse its own late start, so a phantom needs at
        /// least this many counted operations ending between a stray end
        /// and the start it belongs to. Measured exactly: 63 intervening
        /// ends and the refusal still holds, 64 and it doesn't. CloudKit
        /// does not run 64 concurrent imports, so it isn't reachable — but
        /// anyone lowering this for tidiness is lowering that too.
        private static let rememberedEndings = 64

        #if DEBUG
        /// One question has now shaped three versions of this file: does
        /// CloudKit post progress *during* a long import, or only at its
        /// start and end? If it re-posts, a live import keeps re-arming its
        /// own stamp, the expiry can never trip for one, and a whole class
        /// of worry here disappears — including the residue that a live
        /// import older than `staleAfter` reads as idle and has its
        /// completion dropped.
        ///
        /// It cannot be answered from a harness or a simulator: it needs a
        /// CloudKit-entitled run doing a real sync. So launch with
        /// `-plated-log-sync` and every counted event prints. **A repeated
        /// identifier carrying a nil endDate is the answer.**
        private static var logsEvents: Bool {
            ProcessInfo.processInfo.arguments.contains("-plated-log-sync")
        }

        private static func label(_ type: NSPersistentCloudKitContainer.EventType) -> String {
            switch type {
            case .setup: return "setup"
            case .import: return "import"
            case .export: return "export"
            @unknown default: return "other"
            }
        }
        #endif

        /// Is CloudKit doing something right now — and is that claim still
        /// worth acting on? Spends a promotion from every entry it answers
        /// `true` on, so an entry that never confirms itself goes quiet
        /// after `promotionBudget` pulls instead of forever.
        func isBusy() -> Bool {
            let now = ContinuousClock.now
            running = running.filter { now - $0.value.began < Self.staleAfter }
            let live = running.filter { $0.value.promotions < Self.promotionBudget }
            guard !live.isEmpty else { return false }
            for id in live.keys { running[id]?.promotions += 1 }
            return true
        }

        /// **The dominant phantom source, killed causally.** A suspend stops
        /// the process mid-import; the work dies and no terminal event ever
        /// arrives. Coming back to the foreground is direct evidence that
        /// anything still open is gone — faster and more reliable than any
        /// timer, and it handles the case the timer never did: background
        /// for twenty seconds, return, pull, and the clock-based expiry
        /// still had the phantom. If CloudKit restarts the work it posts a
        /// fresh start, which the observer catches and the quiet window
        /// promotes on.
        func clearOpenWork() {
            running.removeAll()
        }

        fileprivate func absorb(_ event: NSPersistentCloudKitContainer.Event) {
            #if DEBUG
            if Self.logsEvents {
                let phase = event.endDate == nil
                    ? "OPEN "
                    : (event.succeeded ? "DONE " : "FAIL ")
                print("PLATED SYNC \(phase)\(Self.label(event.type)) \(event.identifier) open=\(running.count)")
            }
            #endif
            guard counts(event.type) else { return }
            let now = ContinuousClock.now
            running = running.filter { now - $0.value.began < Self.staleAfter }

            if event.endDate == nil {
                // Out-of-order: if this event's ending already landed, the
                // work is over — don't put it back in flight.
                guard !finished.contains(event.identifier) else { return }
                // A fresh start is fresh evidence: it resets the budget.
                running[event.identifier] = Entry(began: now)
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
    /// Two registrations, both synchronous.
    ///
    /// `object: nil` accepts every poster, and `absorb` never checks
    /// `storeIdentifier` — so register-first trades a closed ordering
    /// question for an open identity one. Harmless today: the only other
    /// container in the process is `SampleData.previewContainer`, in-memory
    /// and reachable only from `#Preview` bodies that never run shipped,
    /// and the widget touches neither PlatedStore nor CloudSync.
    ///
    /// **Do not "fix" that by looking up our own store identifier here.**
    /// What makes register-first safe is precisely that nothing on this
    /// path reaches `PlatedStore.shared`. Touching it from a notification
    /// posted synchronously during `ModelContainer.init` would land on the
    /// thread already inside PlatedStore's `swift_once` and stall the
    /// launch until init returns.
    ///
    /// Swift 6 note: `Event` is not `Sendable` and crosses into the actor,
    /// and this stored `NSObjectProtocol` is itself an error under strict
    /// concurrency. Both compile silently at SWIFT_VERSION 5 and both need
    /// solving the day this project moves.
    private static let watcher: [NSObjectProtocol] = [
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: nil
        ) { note in
            guard let event = event(from: note) else { return }
            Task { await Monitor.shared.absorb(event) }
        },
        // Foreground is evidence, not a guess — see `clearOpenWork`. Lives
        // here rather than on PlatedApp's scenePhase so CloudSync stays
        // self-contained, and so it simply never fires in the App Intents
        // process, which has no pull to serve and doesn't need it.
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: nil
        ) { _ in
            Task { await Monitor.shared.clearOpenWork() }
        }
    ]

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
        floor: Duration = Defaults.floor,
        quietWindow: Duration = Defaults.quietWindow,
        activeTimeout: Duration = Defaults.activeTimeout
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
                if await Monitor.shared.isBusy() { await activity.mark() }
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
