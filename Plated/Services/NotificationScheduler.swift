import Foundation
import UserNotifications
import SwiftData

/// The only part of Plated that can reach someone who isn't holding it.
///
/// **What this deliberately is not.** No streaks, no "you haven't opened
/// Plated in 3 days", no engagement bait. A cooking streak punishes the
/// night you order takeout, which is a night the app should have nothing to
/// say about. Everything scheduled here is a fact about a real obligation
/// to a real person: somebody is cooking, or nobody is and the week starts
/// tomorrow. If we can't name the obligation, we don't send anything.
///
/// All local. No server, no push certificate, no network — the schedule is
/// derived from the plan already on the device, which means it also works
/// on a plane and costs nothing to run.
@MainActor
enum NotificationScheduler {

    private static let ritualID = "plated.ritual.week"
    private static let turnPrefix = "plated.turn."
    private static let askedKey = "plated.notifications.asked"

    /// Whether the user has opted in, as far as the system is concerned.
    static func authorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    /// Ask — but only after the app has earned it.
    ///
    /// Never call this at launch. A permission sheet shown before the app
    /// has done anything for you is the fastest way to a permanent "no",
    /// and iOS only lets you ask once. The right moment is just after
    /// somebody plans their first night: they have just told us they intend
    /// to cook, so "shall I remind you" is a continuation of their own
    /// thought rather than an interruption of it.
    @discardableResult
    static func askOnceAfterFirstPlan() async -> Bool {
        guard !UserDefaults.standard.bool(forKey: askedKey) else {
            return await authorized()
        }
        UserDefaults.standard.set(true, forKey: askedKey)
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        return granted
    }

    /// Rebuild the whole schedule from the plan.
    ///
    /// Wholesale rather than incremental on purpose: a plan can change in
    /// ways that are hard to diff — a meal moves day, a cook is swapped, a
    /// night is deleted — and a stale reminder telling someone to cook a
    /// dish that no longer exists is worse than no reminder at all. Tearing
    /// ours down and re-adding is cheap; iOS caps us at 64 pending, and we
    /// schedule at most eight.
    static func rebuild(meals: [PlannedMeal], ownerName: String) async {
        // The user's switch, checked here rather than at each call site.
        // Without it the Plan tab's own rebuild would quietly re-add every
        // reminder the moment after somebody turned them off in Settings,
        // and a toggle that doesn't stay off is a broken promise, not a
        // setting. Defaults true, which is why `object(forKey:) == nil`
        // has to count as on.
        let defaults = UserDefaults.standard
        let wanted = defaults.object(forKey: "remindersOn") as? Bool ?? true
        guard wanted else { return }
        guard await authorized() else { return }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier)
                .filter { $0 == ritualID || $0.hasPrefix(turnPrefix) }
        )
        await scheduleTurns(meals: meals, ownerName: ownerName, center: center)
        await scheduleRitual(meals: meals, center: center)
    }

    /// The night before a night that belongs to someone.
    ///
    /// Named, always. "Dinner tomorrow" is an app talking; "Riley's cooking
    /// tomorrow" is a household talking, and only one of those makes you
    /// look up. Your own night is phrased as yours, because the obligation
    /// lands differently when it's the one you took.
    private static func scheduleTurns(
        meals: [PlannedMeal], ownerName: String, center: UNUserNotificationCenter
    ) async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let horizon = cal.date(byAdding: .day, value: 7, to: today) ?? today

        for meal in meals where meal.date > today && meal.date <= horizon {
            guard let cook = meal.cook else { continue }
            let dish = meal.recipe?.title ?? meal.customTitle
            guard !dish.isEmpty else { continue }

            // 7pm the evening before: late enough that the day is done,
            // early enough to still buy something on the way home.
            var when = cal.dateComponents([.year, .month, .day], from: meal.date)
            if let dayBefore = cal.date(byAdding: .day, value: -1, to: meal.date) {
                when = cal.dateComponents([.year, .month, .day], from: dayBefore)
            }
            when.hour = 19
            guard let fire = cal.date(from: when), fire > .now else { continue }

            let mine = cook.name == ownerName
            // First name only. "Riley cooks tomorrow" is how a household
            // talks; the full name is how a system does.
            let who = cook.name.split(separator: " ").first.map(String.init) ?? cook.name
            let content = UNMutableNotificationContent()
            content.title = mine ? "Your night tomorrow" : "\(who) cooks tomorrow"
            content.body = mine
                ? "\(dish). Everything you need is in the list."
                : "\(dish). Nothing for you to do — just turn up."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: turnPrefix + meal.persistentModelID.hashValue.description,
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: cal.dateComponents([.year, .month, .day, .hour], from: fire),
                    repeats: false
                )
            )
            try? await center.add(request)
        }
    }

    /// Sunday evening, and only when the week ahead is actually empty.
    ///
    /// The condition is the whole design. A weekly "plan your week!" that
    /// fires whether or not you already planned it is the notification
    /// people turn off, and turning it off costs us the reminders that
    /// matter too. Silence when the week is handled is what buys the right
    /// to speak when it isn't.
    private static func scheduleRitual(
        meals: [PlannedMeal], center: UNUserNotificationCenter
    ) async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let weekEnd = cal.date(byAdding: .day, value: 8, to: today) else { return }
        let plannedAhead = meals.filter { $0.date > today && $0.date < weekEnd }.count
        // Three or more nights is a week somebody has thought about.
        guard plannedAhead < 3 else { return }

        let content = UNMutableNotificationContent()
        content.title = "The week's still open"
        content.body = plannedAhead == 0
            ? "Nothing's plated yet. Five minutes now is five conversations you don't have later."
            : "A few nights are still empty. Worth a look before the week starts."
        content.sound = .default

        var when = DateComponents()
        when.weekday = 1   // Sunday
        when.hour = 18
        let request = UNNotificationRequest(
            identifier: ritualID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        )
        try? await center.add(request)
    }

    /// Everything ours, gone — for the Settings toggle. Only ours: another
    /// part of the app may schedule its own one day, and a blanket
    /// `removeAllPendingNotificationRequests` would take those with it.
    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier)
                .filter { $0 == ritualID || $0.hasPrefix(turnPrefix) }
        )
    }
}
