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
    /// One of `RecipeCategory`'s raw values — "" until the cook files it.
    var category: String = ""
    /// One of `RecipeDifficulty`'s raw values. Stored explicitly so the cook
    /// can overrule the minutes-based guess ("90 minutes but braindead easy").
    var difficulty: String = ""
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

    var categoryValue: RecipeCategory? {
        get { RecipeCategory(rawValue: category) }
        set { category = newValue?.rawValue ?? "" }
    }

    /// Stored difficulty when set, otherwise derived from total minutes.
    var difficultyValue: RecipeDifficulty {
        get { RecipeDifficulty(rawValue: difficulty) ?? RecipeDifficulty.from(minutes: totalMinutes) }
        set { difficulty = newValue.rawValue }
    }

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

/// The cookbook's filing system — broad enough to group, small enough to pick
/// in one glance when saving a recipe.
enum RecipeCategory: String, Codable, CaseIterable, Identifiable {
    case comfort = "Comfort"
    case quick = "Quick & Easy"
    case healthy = "Healthy"
    case pasta = "Pasta"
    case grill = "Grill"
    case soupStew = "Soup & Stew"
    case salad = "Salad"
    case bowls = "Bowls"
    case bakes = "Bakes"
    case kidsPick = "Kids' Pick"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .comfort: return "heart"
        case .quick: return "bolt"
        case .healthy: return "leaf"
        case .pasta: return "fork.knife"
        case .grill: return "flame"
        case .soupStew: return "mug"
        case .salad: return "carrot"
        case .bowls: return "circle.circle"
        case .bakes: return "oven"
        case .kidsPick: return "star"
        }
    }
}

/// How much of an evening a dish costs. Guessed from minutes, overridable.
enum RecipeDifficulty: String, Codable, CaseIterable, Identifiable {
    case easy = "Easy"
    case weekend = "Weekend"
    case project = "Project"

    var id: String { rawValue }

    var sortOrder: Int { Self.allCases.firstIndex(of: self) ?? 99 }

    static func from(minutes: Int) -> RecipeDifficulty {
        switch minutes {
        case ..<30: return .easy
        case ..<60: return .weekend
        default: return .project
        }
    }
}
