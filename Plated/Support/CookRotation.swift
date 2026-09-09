import Foundation
import SwiftData

/// Decides who cooks a given night. Standing weekday assignments win;
/// otherwise, when "Take turns automatically" is on, the open night goes to
/// whoever has cooked least that week — the rotation the Home toggle
/// promises. Falls back to the head of table.
@MainActor
enum CookRotation {
    static func cook(
        for date: Date,
        members: [HouseholdMember],
        meals: [PlannedMeal]
    ) -> HouseholdMember? {
        // A six-year-old could be handed Thursday and announced by push as
        // the cook, and an invited ghost could hold a standing night,
        // because nothing filtered on who can actually take the pan.
        let members = members.filter(\.cooks)

        let weekday = Calendar.current.component(.weekday, from: date)
        if let standing = members.first(where: { $0.cookWeekdays.contains(weekday) }) {
            return standing
        }

        let autoRotate = UserDefaults.standard.object(forKey: "autoRotateOpenNights") as? Bool ?? true
        guard autoRotate, !members.isEmpty else {
            // Turns off means open nights stay open, not that they quietly
            // fall to the owner.
            return nil
        }

        // Fewest dinners in this night's week takes the pan. Local
        // `PlannedMeal`s and remote `PlanLedger` nights both count: a week
        // where Riley cooked three nights on their phone and Maya cooked
        // none here would otherwise keep handing open nights to Riley.
        let weekStart = Calendar.current.startOfWeek(for: date)
        guard let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) else {
            return members.first(where: \.isOwner)
        }
        var counts: [PersistentIdentifier: Int] = [:]
        for meal in meals where meal.date >= weekStart && meal.date < weekEnd && meal.slotValue == .dinner {
            if let id = meal.cook?.persistentModelID {
                counts[id, default: 0] += 1
            }
        }
        for entry in PlanLedger.shared.all
            where entry.date >= weekStart && entry.date < weekEnd
                && entry.slotValue == .dinner
                && !entry.isGoing
                && !entry.cookID.isEmpty
        {
            if let member = members.first(where: { ($0.userRecordName ?? "") == entry.cookID }) {
                counts[member.persistentModelID, default: 0] += 1
            }
        }
        return members.min { lhs, rhs in
            let l = counts[lhs.persistentModelID] ?? 0
            let r = counts[rhs.persistentModelID] ?? 0
            return l == r ? lhs.createdAt < rhs.createdAt : l < r
        }
    }
}
