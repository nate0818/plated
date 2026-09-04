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
    /// Stable across moves and serving changes; grocery purchases belong to this meal.
    var shoppingID: String?

    /// The line under the meal name on the week row — "Kids pick", "Fast one".
    var tagline: String = ""

    var recipe: Recipe?
    var gathering: Gathering?
    var cook: HouseholdMember?

    init(
        date: Date = .now,
        slot: MealSlot = .dinner,
        recipe: Recipe? = nil,
        customTitle: String = "",
        servings: Int = 4,
        cook: HouseholdMember? = nil,
        tagline: String = ""
    ) {
        self.date = Calendar.current.startOfDay(for: date)
        self.slot = slot.rawValue
        self.recipe = recipe
        self.customTitle = customTitle
        self.servings = servings
        self.cook = cook
        self.tagline = tagline
        self.createdAt = .now
        self.shoppingID = UUID().uuidString
    }

    var slotValue: MealSlot {
        get { MealSlot(rawValue: slot) ?? .dinner }
        set { slot = newValue.rawValue }
    }

    /// The night's name. A custom name ("Salmon Night", "Leftovers") wins over
    /// the recipe's formal title.
    var title: String {
        if !customTitle.isEmpty { return customTitle }
        if let recipe, !recipe.title.isEmpty { return recipe.title }
        return "Unplanned"
    }

    var isCooked: Bool { cookedAt != nil }

    /// Ingredient quantities scaled from the recipe's base servings to this meal's.
    var scaledIngredients: [(ingredient: Ingredient, quantity: Double)] {
        guard let recipe, recipe.servings > 0 else { return [] }
        let factor = Double(servings) / Double(recipe.servings)
        return recipe.sortedIngredients.map { ($0, $0.quantity * factor) }
    }
}
