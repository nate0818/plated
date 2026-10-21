import Foundation

/// A read-only summary of the household's dinner log. Planning a recipe is
/// not evidence it was cooked, and a future eating-out plan is not history.
@MainActor
struct PlanDinnerHistory {
    let start: Date
    let end: Date
    let cooked: Int
    let eatingOut: Int

    init(local: [PlannedMeal], shared: [PlanLedger.Entry], now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let firstDay = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        start = firstDay
        end = today
        let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        struct Dinner {
            let date: Date
            let cooked: Bool
            let eatingOut: Bool
        }
        var dinners: [String: Dinner] = [:]
        // Local rows take precedence over an echo of the same shared record.
        // Never persist this derived view into the SwiftData mirror.
        for entry in shared where entry.slot == MealSlot.dinner.rawValue {
            guard !entry.isGoing, let date = PlanDay.date(entry.day) else { continue }
            let id = entry.shoppingID.isEmpty ? entry.recordName : "plan-" + entry.shoppingID
            dinners[id] = Dinner(date: date, cooked: entry.cooked
                && !PlanRowVoice.isLeftovers(title: entry.title, hasRecipe: entry.hasRecipe),
                eatingOut: PlanRowVoice.isEatingOut(title: entry.title, hasRecipe: entry.hasRecipe))
        }
        for meal in local where !meal.isDeleted && meal.slotValue == .dinner {
            let id = meal.shoppingID.flatMap { $0.isEmpty ? nil : "plan-" + $0 }
                ?? String(describing: meal.persistentModelID)
            dinners[id] = Dinner(date: meal.date, cooked: meal.isCooked && !meal.isLeftovers,
                eatingOut: PlanRowVoice.isEatingOut(title: meal.title, hasRecipe: meal.recipe != nil))
        }
        let recent = dinners.values.filter { $0.date >= firstDay && $0.date < exclusiveEnd }
        cooked = recent.filter { $0.cooked && !$0.eatingOut }.count
        eatingOut = recent.filter(\.eatingOut).count
    }
}
