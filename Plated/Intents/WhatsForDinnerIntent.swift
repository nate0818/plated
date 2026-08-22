import AppIntents
import SwiftData

/// "What's for dinner?" — the question this whole app exists to answer,
/// now answerable without opening it.
struct WhatsForDinnerIntent: AppIntent {
    static let title: LocalizedStringResource = "What's for Dinner"
    static let description = IntentDescription("Tells you what's plated for tonight.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = PlatedStore.shared
        let today = Calendar.current.startOfDay(for: .now)
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else {
            return .result(dialog: "I couldn't check the plan.")
        }
        let predicate = #Predicate<PlannedMeal> { $0.date >= today && $0.date < tomorrow }
        let meals = try container.mainContext.fetch(FetchDescriptor(predicate: predicate))
        guard let dinner = meals.first(where: { $0.slotValue == .dinner }) else {
            return .result(dialog: "Nothing plated yet tonight. Open Plated and pick something good.")
        }

        var line = "Tonight: \(dinner.title)"
        if let cook = dinner.cook { line += " — \(cook.name) cooks" }
        if let minutes = dinner.recipe?.totalMinutes, minutes > 0 { line += ", about \(minutes) minutes" }
        return .result(dialog: "\(line).")
    }
}
