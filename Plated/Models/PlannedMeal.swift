import Foundation
import SwiftData

/// One recipe (or a freeform note like "leftovers") landing in one slot on one
/// day. This is the unit the week calendar renders and analytics counts.
@Model
final class PlannedMeal {
    /// Normalized to the start of its day so grouping by date is exact.
    var date: Date = Date.now
    var slot: String = MealSlot.dinner.rawValue
    /// Used when there is no recipe — "takeout", "leftovers", "Grandma's".
    var customTitle: String = ""
    var notes: String = ""
    var servings: Int = 4
    /// Set when the meal actually happened. Drives "times cooked" in Insights.
    var cookedAt: Date?
    var createdAt: Date = Date.now

    var recipe: Recipe?
    var gathering: Gathering?

    init(
        date: Date = .now,
        slot: MealSlot = .dinner,
        recipe: Recipe? = nil,
        customTitle: String = "",
        servings: Int = 4
    ) {
        self.date = Calendar.current.startOfDay(for: date)
        self.slot = slot.rawValue
        self.recipe = recipe
        self.customTitle = customTitle
        self.servings = servings
        self.createdAt = .now
    }

    var slotValue: MealSlot {
        get { MealSlot(rawValue: slot) ?? .dinner }
        set { slot = newValue.rawValue }
    }

    var title: String {
        if let recipe, !recipe.title.isEmpty { return recipe.title }
        return customTitle.isEmpty ? "Unplanned" : customTitle
    }

    var isCooked: Bool { cookedAt != nil }

    /// Ingredient quantities scaled from the recipe's base servings to this meal's.
    var scaledIngredients: [(ingredient: Ingredient, quantity: Double)] {
        guard let recipe, recipe.servings > 0 else { return [] }
        let factor = Double(servings) / Double(recipe.servings)
        return recipe.sortedIngredients.map { ($0, $0.quantity * factor) }
    }
}
