import Foundation
import SwiftData

/// A dish the household knows how to make. Recipes are reusable across the
/// calendar; each scheduling of one creates a `PlannedMeal`.
@Model
final class Recipe {
    var title: String = ""
    var summary: String = ""
    var instructions: String = ""
    var sourceURL: String = ""
    var servings: Int = 4
    var prepMinutes: Int = 0
    var cookMinutes: Int = 0
    var tags: [String] = []
    var isFavorite: Bool = false
    /// "private", "household", or "table" — who can see this recipe.
    var visibility: String = "household"
    /// When true, household members can tweak it. Only the creator deletes.
    var householdCanEdit: Bool = true
    /// Set when this recipe was saved from a Table or Discover post — a stable
    /// key so "already in your cookbook" never trips on a mere title match.
    var originID: String = ""
    var createdAt: Date = Date.now
    /// Downsized JPEG. Kept small deliberately — CloudKit charges by the byte.
    @Attribute(.externalStorage) var photoData: Data?

    /// Weather conditions this dish suits, driving the daily suggestion.
    /// Stored as `WeatherMood` raw values.
    var weatherMoods: [String] = []

    @Relationship(deleteRule: .cascade, inverse: \Ingredient.recipe)
    var ingredients: [Ingredient]? = []

    @Relationship(deleteRule: .nullify, inverse: \PlannedMeal.recipe)
    var plannedMeals: [PlannedMeal]? = []

    init(
        title: String = "",
        summary: String = "",
        instructions: String = "",
        sourceURL: String = "",
        servings: Int = 4,
        prepMinutes: Int = 0,
        cookMinutes: Int = 0,
        tags: [String] = [],
        weatherMoods: [WeatherMood] = []
    ) {
        self.title = title
        self.summary = summary
        self.instructions = instructions
        self.sourceURL = sourceURL
        self.servings = servings
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.tags = tags
        self.weatherMoods = weatherMoods.map(\.rawValue)
        self.createdAt = .now
    }

    var totalMinutes: Int { prepMinutes + cookMinutes }

    var sortedIngredients: [Ingredient] {
        (ingredients ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    var moods: [WeatherMood] {
        weatherMoods.compactMap(WeatherMood.init(rawValue:))
    }

    /// How many times this recipe was actually cooked, for the Insights tab.
    var timesCooked: Int {
        (plannedMeals ?? []).filter { $0.cookedAt != nil }.count
    }

    var lastCookedAt: Date? {
        (plannedMeals ?? []).compactMap(\.cookedAt).max()
    }

    /// Names a given member should be warned about before this lands on the plan.
    func conflicts(for member: HouseholdMember) -> [String] {
        let avoided = member.avoidedIngredients.map { $0.lowercased() }
        guard !avoided.isEmpty else { return [] }
        return sortedIngredients
            .filter { ingredient in avoided.contains { ingredient.normalizedName.contains($0) } }
            .map(\.name)
    }
}
