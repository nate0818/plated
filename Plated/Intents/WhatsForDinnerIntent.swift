import AppIntents
import SwiftData

/// "What's for dinner?" — the question this whole app exists to answer,
/// now answerable without opening it.
struct WhatsForDinnerIntent: AppIntent {
    static let title: LocalizedStringResource = "What's for Dinner"
    static let description = IntentDescription("Tells you what's plated for tonight.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        HouseholdSync.ensureObserving()
        let container = PlatedStore.shared
        let today = Calendar.current.startOfDay(for: .now)
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else {
            return .result(dialog: "I couldn't check the plan.")
        }
        let predicate = #Predicate<PlannedMeal> { $0.date >= today && $0.date < tomorrow }
        let meals = try container.mainContext.fetch(FetchDescriptor(predicate: predicate))
        if let dinner = meals.first(where: { $0.slotValue == .dinner }) {
            var line = "Tonight: \(dinner.title)"
            if let cook = dinner.cook { line += ", \(cook.name) cooks" }
            if let minutes = dinner.recipe?.totalMinutes, minutes > 0 { line += ", about \(Recipe.spokenDuration(minutes))" }
            return .result(dialog: "\(line).")
        }
        // A night somebody else in the household planned is still tonight's
        // dinner. It is a `PlanLedger.Entry` and never a `PlannedMeal`
        // (docs/household.md 3.2), so a fetch of this phone's own rows does
        // not see it, and without this Siri answered "nothing plated yet"
        // over a plan with a dish on it. That is the empty state asserting
        // something untrue, which DESIGN.md's Honesty section forbids: the
        // sentence is only allowed when the app really did look and there
        // really is nothing. The same word order as the branch above, so
        // one question does not get two voices depending on who planned it.
        if let remote = PlanLedger.shared.dinner(on: today) {
            var line = "Tonight: \(remote.title)"
            if !remote.cookName.isEmpty { line += ", \(remote.cookName) cooks" }
            if remote.recipeMinutes > 0 { line += ", about \(Recipe.spokenDuration(remote.recipeMinutes))" }
            return .result(dialog: "\(line).")
        }
        return .result(dialog: "Nothing plated yet tonight. Open Plated and pick something good.")
    }
}
