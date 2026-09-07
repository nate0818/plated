import ActivityKit
import Foundation

/// The cook timer on the Lock Screen and in the Dynamic Island.
///
/// The one time-bound thing in the app, done the way a delivery app does
/// an order: one activity, a countdown the system renders with no updates
/// from us, and an end. Nothing else in Plated earns a Live Activity. A
/// day-long "tacos tonight" has no end and would be a billboard, which
/// Apple's review guideline 4.5.3 now names.
///
/// One timer at a time is the ledger's rule, so a new request ends the
/// old activity first, the same way `NotificationScheduler` replaces the
/// alarm by re-adding its identifier.
@MainActor
enum CookTimerLive {

    static func start(dish: String, step: Int, endsAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[CookTimer] live activities are off for Plated")
            return
        }
        end()
        let attributes = CookTimerAttributes(dish: dish, step: step)
        // Stale at the finish: the view says "Time's up" from then on
        // without a single push, and `reconcile` takes it down once the
        // person has seen the app again.
        let content = ActivityContent(
            state: CookTimerAttributes.ContentState(endsAt: endsAt),
            staleDate: endsAt
        )
        do {
            let activity = try Activity<CookTimerAttributes>.request(
                attributes: attributes, content: content, pushType: nil
            )
            print("[CookTimer] live activity \(activity.id.prefix(8)) until \(endsAt)")
        } catch {
            print("[CookTimer] live activity refused: \(error.localizedDescription)")
        }
    }

    /// Cleared, or the evening is over. Immediate: a timer that was
    /// cancelled should not linger on a Lock Screen saying it is running.
    static func end() {
        for activity in Activity<CookTimerAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// On every return to the front. A finished timer nobody cleared has
    /// been saying "Time's up" since it rang; once the app is open again
    /// that has been heard, and the ledger is the record. A timer the
    /// ledger no longer knows about (cleared on another screen, or the
    /// session aged out) comes down too.
    static func reconcile(endsAt: Date?) {
        for activity in Activity<CookTimerAttributes>.activities {
            let ends = activity.content.state.endsAt
            let stillRunning = endsAt.map { abs($0.timeIntervalSince(ends)) < 1 && ends > .now } ?? false
            if !stillRunning {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
        }
    }
}
