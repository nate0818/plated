import SwiftUI
import SwiftData

/// Identity travels with the card, even if another device changes its date
/// during a lift. Older date/slot payloads remain readable.
enum MealPlanTransfer {
    static func token(for meal: PlannedMeal) -> String {
        if let id = meal.shoppingID { return "plated-meal-id:\(id)" }
        return "plated-meal:\(Int(meal.date.startOfDay.timeIntervalSince1970)):\(meal.slot)"
    }

    static func meal(for token: String?, in meals: [PlannedMeal]) -> PlannedMeal? {
        guard let token else { return nil }
        if token.hasPrefix("plated-meal-id:") {
            let id = String(token.dropFirst("plated-meal-id:".count))
            return meals.first { $0.shoppingID == id }
        }
        if let date = DayTransfer.date(from: token) {
            return meals.first { Calendar.current.isDate($0.date, inSameDayAs: date) && $0.slotValue == .dinner }
        }
        let parts = token.split(separator: ":")
        guard parts.count == 3, parts[0] == "plated-meal", let seconds = TimeInterval(parts[1]), seconds.isFinite,
              let slot = MealSlot(rawValue: String(parts[2])) else { return nil }
        let date = Date(timeIntervalSince1970: seconds)
        return meals.first { Calendar.current.isDate($0.date, inSameDayAs: date) && $0.slotValue == slot }
    }
}

@MainActor
enum MealPlanMove {
    static func perform(_ token: String?, to target: Date, meals: [PlannedMeal], context: ModelContext) -> Bool {
        guard let meal = MealPlanTransfer.meal(for: token, in: meals), !meal.isCooked,
              target.startOfDay >= Date.now.startOfDay,
              !Calendar.current.isDate(meal.date, inSameDayAs: target) else { return false }
        let occupant = meals.first { $0.slot == meal.slot && Calendar.current.isDate($0.date, inSameDayAs: target) }
        guard occupant?.isCooked != true else { return false }
        let previous = meal.date, otherDate = occupant?.date
        meal.date = target.startOfDay
        occupant?.date = previous
        do {
            try context.save()
            return true
        } catch {
            meal.date = previous
            if let otherDate { occupant?.date = otherDate }
            Haptic.warn()
            return false
        }
    }
}

struct PlannerMealDrag: ViewModifier {
    let meal: PlannedMeal
    func body(content: Content) -> some View {
        if meal.isCooked { content }
        else {
            content.draggable(MealPlanTransfer.token(for: meal)) {
                Label(meal.title, systemImage: "fork.knife").plType(.body, .semibold)
                    .foregroundStyle(Color.ink).padding(16)
                    .background(Color.canvas, in: Radius.shape(Radius.chip))
            }
        }
    }
}
