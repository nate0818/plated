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

    enum AuthorizationState: Equatable {
        case notDetermined
        case allowed
        case denied
    }

    private static let ritualID = "plated.ritual.week"
    private static let turnPrefix = "plated.turn."
    private static let askedKey = "plated.notifications.asked"
    /// The cook timer's namespace, declared here so the next person can see
    /// it. `rebuild` and `cancelAll` below remove only `ritualID` and things
    /// prefixed `turnPrefix`, so a timer somebody started thirty seconds ago
    /// survives a plan rebuild — which is the whole reason the timer is cheap.
    static let cookPrefix = "plated.cook."
    static let cookTimerID = cookPrefix + "timer"

    /// One alarm for the one running cook timer.
    ///
    /// Replaces rather than stacks: one timer at a time is a deliberate
    /// limit, and re-adding the same identifier is how UNUserNotificationCenter
    /// spells "replace".
    static func scheduleCookTimer(in seconds: TimeInterval, title: String, body: String) async {
        guard seconds > 0, await authorized() else {
            print("[CookTimer] not scheduling: seconds=\(seconds) authorized=\(await authorized())")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Its own category, so a locked screen still says what rang.
        content.categoryIdentifier = NotificationRouter.Category.cook
        let request = UNNotificationRequest(
            identifier: cookTimerID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
        print("[CookTimer] scheduled in \(Int(seconds))s")
    }

    static func cancelCookTimer() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [cookTimerID])
        print("[CookTimer] cancelled")
    }

    /// Whether the user has opted in, as far as the system is concerned.
    static func authorized() async -> Bool {
        await authorizationState() == .allowed
    }

    static func authorizationState() async -> AuthorizationState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .allowed
        case .notDetermined:
            return .notDetermined
        default:
            return .denied
        }
    }

    /// Settings is another earned prompt: the person has explicitly pressed
    /// “Turn on,” so the system sheet is the expected result of their action.
    /// Keep the same asked flag as the post-plan prompt so Plated never asks
    /// twice from two different surfaces.
    @discardableResult
    static func requestFromSettings() async -> Bool {
        UserDefaults.standard.set(true, forKey: askedKey)
        return (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// The whole answer, for a control that has to tell "never asked" from
    /// "asked and refused": the first can still be asked, the second can
    /// only be sent to iOS Settings.
    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Whether the one ask has been spent, whatever the answer was.
    static var hasAsked: Bool { UserDefaults.standard.bool(forKey: askedKey) }

    private static let pendingAskKey = "plated.notifications.askPending"

    /// Ask, but not here: the caller is somewhere the prompt must not land
    /// (an invitation accepted on a cold start, under the launch opener or
    /// the sign-in screen). The shell collects it once it is on screen.
    static func askSoon() {
        guard !hasAsked else { return }
        UserDefaults.standard.set(true, forKey: pendingAskKey)
    }

    static func takePendingAsk() -> Bool {
        let pending = UserDefaults.standard.bool(forKey: pendingAskKey)
        if pending { UserDefaults.standard.removeObject(forKey: pendingAskKey) }
        return pending && !hasAsked
    }

    /// Ask — but only after the app has earned it.
    ///
    /// Never call this at launch. A permission sheet shown before the app
    /// has done anything for you is the fastest way to a permanent "no",
    /// and iOS only lets you ask once. There are three earned moments and
    /// whichever comes first spends the ask: planning a first night (they
    /// just said they intend to cook, so "shall I remind you" continues
    /// their own thought), posting a first dish (they just spoke to the
    /// table, so hearing back is the natural next wish), and accepting a
    /// seat at somebody else's table (a guest who never plans a night here
    /// would otherwise never be asked at all, and the Table would stay
    /// silent for exactly the people it exists to reach).
    @discardableResult
    static func askOnce() async -> Bool {
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
            // A system push saying "Riley cooks tomorrow" about a name typed
            // five seconds ago, to somebody who has never heard of Plated.
            guard cook.seat != .invited else { continue }
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

            // Identity, not a string compare — two people called Sam broke
            // this, and so did the owner renaming themselves.
            let mine = cook.isOwner
            // First name only. "Riley cooks tomorrow" is how a household
            // talks; the full name is how a system does.
            let who = cook.name.split(separator: " ").first.map(String.init) ?? cook.name
            let content = UNMutableNotificationContent()
            content.title = mine ? "Your night tomorrow" : "\(who) cooks tomorrow"
            content.body = mine
                ? "\(dish). Check the grocery list tonight."
                : "\(dish). Nothing for you to do."
            content.sound = .default
            // A tap lands on the plan; your own night also offers the list
            // the body just mentioned, so the sentence and the button agree.
            content.categoryIdentifier = mine
                ? NotificationRouter.Category.turnMine : NotificationRouter.Category.plan
            content.userInfo = [NotificationRouter.Key.link: DeepLink.url(.plan).absoluteString]

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
        content.title = "The week ahead"
        content.body = plannedAhead == 0
            ? "Nothing's plated yet."
            : "A few nights are still empty."
        content.sound = .default
        content.categoryIdentifier = NotificationRouter.Category.plan
        content.userInfo = [NotificationRouter.Key.link: DeepLink.url(.plan).absoluteString]

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
