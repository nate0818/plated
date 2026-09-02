import AppIntents
import SwiftData

/// "Plate the salmon tonight" from Shortcuts — finds the closest-named dish
/// in the cookbook and lands it on tonight if the night is open.
struct PlateTonightIntent: AppIntent {
    static let title: LocalizedStringResource = "Plate a Dish Tonight"
    static let description = IntentDescription("Puts a dish from your cookbook on tonight's plan.")

    @Parameter(title: "Dish", description: "The dish's name, or close enough.")
    var dish: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = PlatedStore.shared
        let context = container.mainContext

        let today = Calendar.current.startOfDay(for: .now)
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else {
            return .result(dialog: "I couldn't reach the plan.")
        }
        let tonightPredicate = #Predicate<PlannedMeal> { $0.date >= today && $0.date < tomorrow }
        let tonightMeals = try context.fetch(FetchDescriptor(predicate: tonightPredicate))
        if let existing = tonightMeals.first(where: { $0.slotValue == .dinner }) {
            return .result(dialog: "Tonight is already plated: \(existing.title). Swap it in the app if you'd rather.")
        }

        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let query = dish.lowercased()
        let match = recipes.first { $0.title.lowercased() == query }
            ?? recipes.first { $0.title.lowercased().contains(query) }
            ?? recipes.first { query.contains($0.title.lowercased()) }
        guard let recipe = match else {
            return .result(dialog: "No dish in your cookbook matches “\(dish)”.")
        }

        let members = try context.fetch(FetchDescriptor<HouseholdMember>())
        // Same rotation the app uses: standing weekday first, then the
        // take-turns toggle's fewest-dinners pick, then the head of table —
        // so plating by voice respects auto-rotate like plating by touch.
        let meals = try context.fetch(FetchDescriptor<PlannedMeal>())
        let cook = CookRotation.cook(for: today, members: members, meals: meals)

        context.insert(PlannedMeal(
            date: today, slot: .dinner, recipe: recipe,
            servings: recipe.servings, cook: cook
        ))
        try context.save()
        WidgetBridge.publish(from: context)

        var line = "Plated: \(recipe.title) tonight"
        if let cook { line += ", \(cook.name) cooks" }
        return .result(dialog: "\(line).")
    }
}
