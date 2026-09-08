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
    /// A night another phone planned with this person as the cook. Under
    /// `turnPrefix` so the wholesale rebuild takes it down with the rest;
    /// its own segment so the rehearsal can list what the ledger earned.
    static let remoteTurnPrefix = turnPrefix + "remote."
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
        // A pan on the stove is the one thing in this app that cannot wait
        // for a Focus to end. Needs the Time Sensitive capability on the
        // App ID; without it iOS delivers this as active, which is what it
        // was before, so nothing is lost by asking.
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1
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

    /// Rebuild the whole schedule from the plan, this phone's own nights
    /// and the nights other phones planned with this person as the cook.
    ///
    /// Wholesale rather than incremental on purpose: a plan can change in
    /// ways that are hard to diff — a meal moves day, a cook is swapped, a
    /// night is deleted — and a stale reminder telling someone to cook a
    /// dish that no longer exists is worse than no reminder at all. Tearing
    /// ours down and re-adding is cheap; iOS caps us at 64 pending, and a
    /// week of turns, local or remote, is at most one reminder per night
    /// plus the Sunday ritual.
    ///
    /// The ledger is read here rather than passed in, so no caller can
    /// forget it: the Plan tab, the night sheet and the push all rebuild
    /// through this one door.
    ///
    /// No owner name either. Whose night it is is answered by identity on
    /// both roads, `HouseholdMember.isMe` for a local night and
    /// `PlanLedger.isMine(cook:)` for a remote one, so there is nothing
    /// for a caller to pass and nothing for it to get wrong: two people
    /// called Sam, and an owner who renamed themselves, both broke the
    /// name compare this parameter used to feed.
    static func rebuild(meals: [PlannedMeal]) async {
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
        await scheduleTurns(meals: meals, center: center)
        await scheduleRemoteTurns(meals: meals, center: center)
        await scheduleRitual(meals: meals, center: center)
    }

    /// The same door for a caller with a context and no meals in hand:
    /// the ledger just dropped nights (`PlanLedger.nightsDropped`), and
    /// what is left has to be read again before 19:00 comes round.
    @MainActor
    static func rebuild(from context: ModelContext) async {
        let meals = (try? context.fetch(FetchDescriptor<PlannedMeal>())) ?? []
        await rebuild(meals: meals)
    }

    /// The night before a night somebody else planned with you cooking.
    ///
    /// Only the cook's own reminder: a remote night is "Your night
    /// tomorrow" or nothing (docs/open-decisions.md §1c, the second answer,
    /// chosen for remote nights). The body names who planned it, because
    /// the obligation came from them and the dish is not in this cookbook.
    /// No grocery action: the list has nothing for a night planned on
    /// another phone. One turn reminder per day, ever: a day this phone's
    /// own plan says anything about is that plan's to remind.
    private static func scheduleRemoteTurns(
        meals: [PlannedMeal], center: UNUserNotificationCenter
    ) async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let horizon = cal.date(byAdding: .day, value: 7, to: today) ?? today
        let localDays = Set(meals.map { PlanDay.string($0.date) })

        for night in remoteTurns(PlanLedger.shared.myNights(), localDays: localDays) {
            let date = night.date
            guard date > today, date <= horizon, !night.title.isEmpty else { continue }
            guard let dayBefore = cal.date(byAdding: .day, value: -1, to: date) else { continue }
            var when = cal.dateComponents([.year, .month, .day], from: dayBefore)
            when.hour = 19
            guard let fire = cal.date(from: when), fire > .now else { continue }

            let by = night.authorFirstName
            let content = UNMutableNotificationContent()
            content.title = "Your night tomorrow"
            content.body = by.isEmpty ? "\(night.title)." : "\(night.title). Planned by \(by)."
            content.sound = .default
            content.categoryIdentifier = NotificationRouter.Category.plan
            content.userInfo = [NotificationRouter.Key.link: DeepLink.url(plan: date).absoluteString]

            let request = UNNotificationRequest(
                identifier: remoteTurnPrefix + night.recordName,
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: cal.dateComponents([.year, .month, .day, .hour], from: fire),
                    repeats: false
                )
            )
            try? await center.add(request)
        }
    }

    /// Which remote nights earn a reminder: none on a day any local meal
    /// claims, and one per day among the rest. Pure, so a test can hold it
    /// to "one turn reminder per day". `localDays` are `PlanDay` strings,
    /// the same calendar the ledger keeps its days in.
    static func remoteTurns(_ nights: [PlanLedger.Entry], localDays: Set<String>) -> [PlanLedger.Entry] {
        var taken = localDays
        var chosen: [PlanLedger.Entry] = []
        let ordered = nights.sorted { ($0.day, $0.slot, $0.title) < ($1.day, $1.slot, $1.title) }
        for night in ordered where !taken.contains(night.day) {
            taken.insert(night.day)
            chosen.append(night)
        }
        return chosen
    }

    /// The night before a night that belongs to someone.
    ///
    /// Named, always. "Dinner tomorrow" is an app talking; "Riley's cooking
    /// tomorrow" is a household talking, and only one of those makes you
    /// look up. Your own night is phrased as yours, because the obligation
    /// lands differently when it's the one you took.
    private static func scheduleTurns(
        meals: [PlannedMeal], center: UNUserNotificationCenter
    ) async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let horizon = cal.date(byAdding: .day, value: 7, to: today) ?? today

        for meal in meals where meal.date > today && meal.date <= horizon {
            guard let cook = meal.cook else { continue }
            // Never an obligation about somebody who is not there: a name
            // typed five seconds ago, to somebody who has never heard of
            // Plated, or a seat that has left the household. A left seat's
            // nights are meant to be handed back to unplanned
            // (docs/household.md section 8) and today no road but Remove
            // does it, so the reminder refuses the name rather than
            // trusting the plan to have been cleared.
            guard cook.seat != .invited, cook.seat != .left else { continue }
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
            // this, and so did the owner renaming themselves. And identity
            // rather than role: on a member's phone the head of table is
            // somebody else, and "Your night tomorrow" about their night
            // would be the wrong person's obligation.
            let mine = cook.isMe
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
        let ahead = meals.filter { $0.date > today && $0.date < weekEnd }
        // A night somebody else planned is a night: "Nothing's plated yet"
        // over a week the planner already shows three of Riley's dinners
        // on would be a claim the screen contradicts.
        let localDays = Set(ahead.map { PlanDay.string($0.date) })
        let remoteDays = Set(PlanLedger.shared.all
            .filter { $0.date > today && $0.date < weekEnd }
            .map(\.day)).subtracting(localDays)
        let plannedAhead = ahead.count + remoteDays.count
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
