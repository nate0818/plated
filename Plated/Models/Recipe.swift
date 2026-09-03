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
    /// Kept at the top of the cookbook, the way a pinned conversation stays
    /// at the top of Messages. Separate from `isFavorite` on purpose: a
    /// favourite is a judgement about the dish that lasts, a pin is about
    /// what you are cooking this week and is meant to be moved.
    var isPinned: Bool = false
    /// One of `RecipeCategory`'s raw values — "" until the cook files it.
    var category: String = ""
    /// One of `RecipeDifficulty`'s raw values. Stored explicitly so the cook
    /// can overrule the minutes-based guess ("90 minutes but braindead easy").
    var difficulty: String = ""
    /// One of `RecipeMealType`'s raw values. Dinner is the default because
    /// Plated is a dinner app first; everything else is the exception.
    var mealType: String = RecipeMealType.dinner.rawValue
    /// The actual method, one step per line — NYT-cooking style numbered
    /// steps, not a wall of prose.
    var steps: [String] = []
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

    /// Photos beyond the hero — process shots, the plated result, the mess.
    @Relationship(deleteRule: .cascade, inverse: \RecipePhoto.recipe)
    var extraPhotos: [RecipePhoto]? = []

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

    /// How long it takes, said the way a person says it. A slow-cooker
    /// dish is "6 hr 8 min", never "368 min" — past an hour, raw minutes
    /// stop being a duration and become arithmetic homework.
    static func durationText(_ minutes: Int) -> String {
        guard minutes > 0 else { return "" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        if rest == 0 { return "\(hours) hr" }
        return "\(hours) hr \(rest) min"
    }

    /// The same, spoken aloud — Prongsby and Siri read this one.
    static func spokenDuration(_ minutes: Int) -> String {
        guard minutes > 0 else { return "" }
        if minutes < 60 { return "\(minutes) minutes" }
        let hours = minutes / 60
        let rest = minutes % 60
        let hourWord = hours == 1 ? "hour" : "hours"
        if rest == 0 { return "\(hours) \(hourWord)" }
        return "\(hours) \(hourWord) \(rest) minutes"
    }

    var timeText: String { Self.durationText(totalMinutes) }

    var categoryValue: RecipeCategory? {
        get { RecipeCategory(rawValue: category) }
        set { category = newValue?.rawValue ?? "" }
    }

    /// Whether anybody has said, or implied by a time, how hard this is.
    ///
    /// `difficultyValue` falls back to `from(minutes:)`, whose first case is
    /// `..<30`, so a recipe with no time at all comes back "Easy". The fact
    /// row then set "Not set" and "Easy" side by side, both derived from the
    /// same missing number — one refusing to invent it, the other stating a
    /// conclusion from it. Imports are the live path: they write parsed
    /// minutes unfloored and never set a difficulty.
    ///
    /// Computed, so no schema change and nothing for the mirror to migrate.
    var difficultyIsKnown: Bool { !difficulty.isEmpty || totalMinutes > 0 }

    /// Stored difficulty when set, otherwise derived from total minutes.
    var difficultyValue: RecipeDifficulty {
        get { RecipeDifficulty(rawValue: difficulty) ?? RecipeDifficulty.from(minutes: totalMinutes) }
        set { difficulty = newValue.rawValue }
    }

    var mealTypeValue: RecipeMealType {
        get { RecipeMealType(rawValue: mealType) ?? .dinner }
        set { mealType = newValue.rawValue }
    }

    /// True when this came from someone else's table rather than this kitchen.
    var isImported: Bool { !originID.isEmpty }

    var sortedExtraPhotos: [RecipePhoto] {
        (extraPhotos ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    /// Favorite hearts plus times actually cooked — the "most loved" rank.
    var loveScore: Int { (isFavorite ? 3 : 0) + timesCooked }

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

/// Which meal of the day (or part of the meal) a recipe is for. Dinner
/// carries the app; the rest make the cookbook a real cookbook.
enum RecipeMealType: String, Codable, CaseIterable, Identifiable {
    case dinner = "Dinner"
    case lunch = "Lunch"
    case sideDish = "Side dish"
    case appetizer = "Appetizer"
    case dessert = "Dessert"
    case cocktail = "Cocktail"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .dinner: return "fork.knife"
        case .lunch: return "sun.max"
        case .sideDish: return "circle.grid.2x1"
        case .appetizer: return "hand.raised"
        case .dessert: return "birthday.cake"
        case .cocktail: return "wineglass"
        }
    }
}

/// One extra photo on a recipe. The hero stays on the recipe itself.
@Model
final class RecipePhoto {
    var sortIndex: Int = 0
    var caption: String = ""
    var createdAt: Date = Date.now
    @Attribute(.externalStorage) var photoData: Data?

    var recipe: Recipe?

    init(photoData: Data? = nil, sortIndex: Int = 0, caption: String = "") {
        self.photoData = photoData
        self.sortIndex = sortIndex
        self.caption = caption
        self.createdAt = .now
    }
}
