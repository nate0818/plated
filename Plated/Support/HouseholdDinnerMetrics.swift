import Foundation

@MainActor
struct HouseholdDinnerMetrics {
    var plannedDates: [Date]
    var cookedCount: Int

    init(local: [PlannedMeal], shared: [PlanLedger.Entry]) {
        var planned: [String: Date] = [:]
        var cooked = Set<String>()
        for meal in local where !meal.isDeleted && meal.slotValue == .dinner {
            let id = meal.shoppingID.map { "plan-" + $0 } ?? String(describing: meal.persistentModelID)
            planned[id] = meal.date
            if meal.isCooked { cooked.insert(id) }
        }
        for entry in shared where entry.slot == MealSlot.dinner.rawValue && !entry.isGoing {
            if let date = PlanDay.date(entry.day) { planned[entry.recordName] = date }
            if entry.cooked { cooked.insert(entry.recordName) }
        }
        plannedDates = Array(planned.values)
        cookedCount = cooked.count
    }

    var bestWeek: Int {
        let calendar = Calendar.current
        let dates = Set(plannedDates.map { calendar.startOfDay(for: $0) })
        return Dictionary(grouping: dates) { calendar.dateInterval(of: .weekOfYear, for: $0)?.start ?? $0 }
            .values.map(\.count).max() ?? 0
    }
}
