import Foundation

@MainActor
enum PlanOccupancy {
    static func shared(on date: Date, slot: MealSlot, entries: [PlanLedger.Entry]? = nil) -> PlanLedger.Entry? {
        (entries ?? PlanLedger.shared.plans(on: date, slot: slot)).first {
            !$0.isGoing && $0.day == PlanDay.string(date) && $0.slot == slot.rawValue
        }
    }

    static func isOccupied(on date: Date, slot: MealSlot, local: [PlannedMeal]) -> Bool {
        local.contains { Calendar.current.isDate($0.date, inSameDayAs: date) && $0.slotValue == slot }
            || shared(on: date, slot: slot) != nil
    }
}
