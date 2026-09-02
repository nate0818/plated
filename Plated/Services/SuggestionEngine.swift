import Foundation

/// Produces the "it's going to be 55 and cloudy tomorrow — good day for your
/// chili, Nate" nudge.
///
/// Scoring is intentionally simple and local: weather-mood match, how long since
/// the dish was last made, and whether it clears everyone's dietary notes. No
/// network call, no model — it runs instantly and works offline. A generative
/// pass over the phrasing can layer on top later without changing this ranking.
struct SuggestionEngine {
    struct Suggestion {
        let recipe: Recipe
        let score: Double
        let reason: String
        let headline: String
    }

    let recipes: [Recipe]
    let members: [HouseholdMember]

    /// Ranks candidates for a given day, best first.
    func suggestions(
        for date: Date,
        forecast: ForecastProvider.DayForecast?,
        addressing name: String? = nil,
        limit: Int = 3
    ) -> [Suggestion] {
        let candidates = recipes.compactMap { recipe -> Suggestion? in
            // Anything that trips a household member's hard no is out entirely.
            let blocked = members.contains { !recipe.conflicts(for: $0).isEmpty }
            if blocked { return nil }

            var score = 0.0
            var reasons: [String] = []

            if let mood = forecast?.mood, recipe.moods.contains(mood) {
                score += 3
                reasons.append(mood.title.lowercased())
            }

            // Favor dishes that have not come around in a while.
            if let last = recipe.lastCookedAt {
                let weeks = Calendar.current.dateComponents([.weekOfYear], from: last, to: date).weekOfYear ?? 0
                score += min(Double(weeks) * 0.25, 3)
            } else {
                score += 1.5 // never cooked — worth trying
                reasons.append("you haven't made it yet")
            }

            if recipe.isFavorite { score += 1 }

            // On a weeknight, prefer something that fits in a weeknight.
            if !Calendar.current.isDateInWeekend(date) && recipe.totalMinutes > 0 && recipe.totalMinutes <= 45 {
                score += 0.75
            }

            guard score > 0 else { return nil }

            return Suggestion(
                recipe: recipe,
                score: score,
                reason: reasons.joined(separator: ", "),
                headline: headline(recipe: recipe, forecast: forecast, name: name)
            )
        }

        return Array(candidates.sorted { $0.score > $1.score }.prefix(limit))
    }

    private func headline(recipe: Recipe, forecast: ForecastProvider.DayForecast?, name: String?) -> String {
        let dish = recipe.title
        guard let forecast else {
            return name.map { "How about \(dish), \($0)?" } ?? "How about \(dish)?"
        }

        let temp = Int(forecast.highF.rounded())
        let condition = forecast.conditionDescription.lowercased()
        let opener = "It's going to be \(temp)° and \(condition)"
        let closer = name.map { "great day for your \(dish), \($0)." } ?? "great day for your \(dish)."
        return "\(opener). \(closer)"
    }
}
