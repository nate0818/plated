import Foundation

/// What the app knows about tonight, as facts rather than as a view.
///
/// Plated exists to answer one question, and until now the app was the only
/// surface that would not answer it. The Home Screen widget draws tonight's
/// dish, its cook and its minutes; Siri says the whole sentence out loud. The
/// app's own week list said "Tonight · 25 min" and named nobody, because
/// `WeekView.tagLine` returns inside its `if today` branch and never reaches
/// the cook branch four lines below it. Every other night of the week names
/// the cook. The one night it matters did not.
///
/// Everything here is read off recorded state. Nothing is inferred, nothing
/// is rounded up into a claim: if there is no cook, the line does not mention
/// one, and if there is no time on the recipe, it does not invent a duration.
@MainActor
enum TonightAnswer {

    enum State {
        /// Tonight has a dinner on it.
        case plated(PlannedMeal)
        /// Tonight has a dinner and somebody has already marked it cooked.
        case cooked(PlannedMeal)
        /// Tonight is open, and there is at least something to plate.
        case open
    }

    /// Nil means the app has nothing worth saying: no dinner tonight and an
    /// empty cookbook, which is the first-launch case. An invitation to plate
    /// a night from a cookbook with nothing in it is a dead end dressed up as
    /// a prompt.
    static func state(meals: [PlannedMeal], hasRecipes: Bool) -> State? {
        let calendar = Calendar.current
        let tonight = meals.first {
            calendar.isDateInToday($0.date) && $0.slotValue == .dinner
        }
        guard let tonight else { return hasRecipes ? .open : nil }
        return tonight.isCooked ? .cooked(tonight) : .plated(tonight)
    }

    /// "You cook · 25 min", "Riley cooks", "Night off the stove", or nothing.
    ///
    /// Built only from what is recorded. A nil cook contributes no clause at
    /// all rather than "Someone cooks", which would be the interface filling
    /// a gap with a guess about a person.
    static func factLine(for meal: PlannedMeal) -> String? {
        var parts: [String] = []

        if let cook = meal.cook {
            parts.append(cook.isOwner ? "You cook" : "\(cook.name) cooks")
        }
        let minutes = meal.recipe?.totalMinutes ?? 0
        if minutes > 0 {
            parts.append(Recipe.durationText(minutes))
        }
        if parts.isEmpty {
            // A night with no cook and no recipe can still have been given a
            // line of its own: "Night off the stove" is what an eating-out
            // night carries.
            let tagline = meal.tagline.trimmingCharacters(in: .whitespaces)
            return tagline.isEmpty ? nil : tagline
        }
        return parts.joined(separator: " · ")
    }
}
