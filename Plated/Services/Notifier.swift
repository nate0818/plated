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
        guard let cook = members.first(where: { $0.cookWeekdays.contains(weekday) }) else { return }

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
    private static let key = "platedPlusActive"

    static var isActive: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
