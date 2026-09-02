import Foundation
import SwiftData

/// Writes activity into the in-app feed. One call per moment worth telling
/// the household about; the bell badge counts what's unread. Local-only
/// today — when the network arrives these fan out as real pushes.
@MainActor
enum Notifier {
    static func post(
        _ kind: PlatedNotificationKind,
        actor: String,
        body: String,
        into context: ModelContext
    ) {
        context.insert(PlatedNotification(kind: kind, actorName: actor, body: body))
    }

    /// Posts at most once per `key`, ever — for reactions that can toggle
    /// (plate/unplate/plate must not spam the poster). Storage is a rolling
    /// window: old keys age out, which is fine — a re-notification months
    /// later reads as news, not spam.
    static func postOnce(
        key: String,
        _ kind: PlatedNotificationKind,
        actor: String,
        body: String,
        into context: ModelContext
    ) {
        let defaultsKey = "notifier.onceKeys"
        var seen = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        guard !seen.contains(key) else { return }
        seen.append(key)
        if seen.count > 200 { seen.removeFirst(seen.count - 200) }
        UserDefaults.standard.set(seen, forKey: defaultsKey)
        post(kind, actor: actor, body: body, into: context)
    }

    /// Nudges once per day when tonight is somebody's turn and nothing is
    /// plated yet. Called on Plan appear; the AppStorage stamp stops nagging.
    static func nudgeTurnIfNeeded(
        meals: [PlannedMeal],
        members: [HouseholdMember],
        into context: ModelContext
    ) {
        let today = Calendar.current.startOfDay(for: .now)
        let stampKey = "lastTurnNudgeDay"
        let lastStamp = UserDefaults.standard.double(forKey: stampKey)
        guard lastStamp != today.timeIntervalSince1970 else { return }

        let tonightPlanned = meals.contains {
            Calendar.current.isSameDay($0.date, today) && $0.slotValue == .dinner
        }
        guard !tonightPlanned else { return }

        let weekday = Calendar.current.component(.weekday, from: today)
        // This fires on its own and asserts a standing obligation. It must
        // never assert one about somebody who was never contacted.
        guard let cook = members.first(where: { $0.cooks && $0.cookWeekdays.contains(weekday) })
        else { return }

        UserDefaults.standard.set(today.timeIntervalSince1970, forKey: stampKey)
        let name = cook.isOwner ? "your" : "\(cook.name)'s"
        post(
            .turnReminder, actor: cook.name,
            body: "Tonight is \(name) night to cook and nothing is plated yet.",
            into: context
        )
    }
}

/// Plated+ — the subscription that seats more than the head of table.
/// A UserDefaults flag until StoreKit products exist in App Store Connect;
/// the paywall says so honestly.
enum PlatedPlus {
    /// Nate has held the paywall decision — no gate, no Plated+ surfaces
    /// until he calls it. Flipping this one constant re-arms the seat gate
    /// and the Settings row; nothing else needs to change.
    static let gatingEnabled = false

    private static let key = "platedPlusActive"

    static var isActive: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
