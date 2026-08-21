import Foundation

/// Aggregates cooking history into the numbers shown on the Insights tab:
/// what the household actually eats, how often, and what has gone stale.
struct MealInsights {
    let meals: [PlannedMeal]
    let recipes: [Recipe]

    struct RecipeFrequency: Identifiable {
        var id: String { title }
        let title: String
        let count: Int
        let lastCooked: Date?
        let recipe: Recipe?
    }

    /// Restricts the window to meals cooked on or after `since`.
    func cookedMeals(since: Date? = nil) -> [PlannedMeal] {
        meals.filter { meal in
            guard let cookedAt = meal.cookedAt else { return false }
            guard let since else { return true }
            return cookedAt >= since
        }
    }

    /// "How many times have we had this" — the headline analytics question.
    func frequencies(since: Date? = nil, limit: Int? = nil) -> [RecipeFrequency] {
        var counts: [String: (count: Int, last: Date?, recipe: Recipe?)] = [:]

        for meal in cookedMeals(since: since) {
            let title = meal.title
            var entry = counts[title] ?? (0, nil, meal.recipe)
            entry.count += 1
            if let cookedAt = meal.cookedAt {
                entry.last = max(entry.last ?? cookedAt, cookedAt)
            }
            if entry.recipe == nil { entry.recipe = meal.recipe }
            counts[title] = entry
        }

        let result = counts
            .map { RecipeFrequency(title: $0.key, count: $0.value.count, lastCooked: $0.value.last, recipe: $0.value.recipe) }
            .sorted { $0.count == $1.count ? $0.title < $1.title : $0.count > $1.count }

        guard let limit else { return result }
        return Array(result.prefix(limit))
    }

    /// Recipes in the library that have not been cooked in a long time — the
    /// "you forgot about this one" list.
    func neglectedRecipes(notCookedIn days: Int = 90, limit: Int = 10) -> [Recipe] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        return recipes
            .filter { recipe in
                guard let last = recipe.lastCookedAt else { return recipe.timesCooked == 0 }
                return last < cutoff
            }
            .sorted { ($0.lastCookedAt ?? .distantPast) < ($1.lastCookedAt ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    /// Share of cooked meals that came from the recipe library rather than
    /// freeform entries like takeout — a rough "how much are we actually cooking".
    func homeCookedShare(since: Date? = nil) -> Double {
        let cooked = cookedMeals(since: since)
        guard !cooked.isEmpty else { return 0 }
        let fromRecipes = cooked.filter { $0.recipe != nil }.count
        return Double(fromRecipes) / Double(cooked.count)
    }

    /// Distinct dishes eaten in the window — a variety measure.
    func varietyCount(since: Date? = nil) -> Int {
        Set(cookedMeals(since: since).map(\.title)).count
    }

    /// Meal counts bucketed by slot, for the breakdown chart.
    func countsBySlot(since: Date? = nil) -> [(slot: MealSlot, count: Int)] {
        let cooked = cookedMeals(since: since)
        return MealSlot.allCases.map { slot in
            (slot, cooked.filter { $0.slotValue == slot }.count)
        }
    }
}
