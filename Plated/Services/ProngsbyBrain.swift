import Foundation

/// Prongsby's brain — the house fork. Grounded in this household's own
/// cookbook and plan, with a pocketful of kitchen knowledge. Deliberately
/// rule-based and on-device: no key, no network, no made-up nonsense. When
/// Plated grows a backend, this becomes the prompt-builder for the real
/// model and the offline fallback.
struct ProngsbyBrain {
    let recipes: [Recipe]
    let members: [HouseholdMember]

    func reply(to raw: String) -> String {
        let text = raw.lowercased()

        if let swap = substitution(in: text) { return swap }
        if let recipe = recipeMatch(in: text) {
            if text.contains("how long") || text.contains("time") {
                return "\(recipe.title) runs about \(recipe.totalMinutes) minutes — \(recipe.prepMinutes) of prep, \(recipe.cookMinutes) on the heat. \(recipe.difficultyValue.rawValue) night."
            }
            return describe(recipe)
        }
        if text.contains("what should") || text.contains("idea") || text.contains("tonight")
            || text.contains("make for dinner") || text.contains("cook for") {
            return suggestDinner()
        }
        if text.contains("tip") || text.contains("advice") {
            return Self.tips.randomElement() ?? Self.tips[0]
        }
        if text.contains("timer") {
            return "I can't run timers yet — say \"Hey Siri, set a timer\" and I'll keep the recipe open for you."
        }
        if text.contains("hello") || text.contains("hi ") || text == "hi" || text.contains("who are you") {
            return "I'm Prongsby, the house fork 🍴 Ask me what to cook tonight, how to make anything in your cookbook, or what to swap when you're out of buttermilk."
        }
        return "I'm still a young fork — I know your cookbook, dinner ideas, and common swaps. Try \"what should we make tonight?\" or \"substitute for sour cream\". The bigger brain arrives with Plated's network."
    }

    // MARK: Skills

    private func suggestDinner() -> String {
        let engine = SuggestionEngine(recipes: recipes, members: members)
        let picks = engine.suggestions(for: .now, forecast: nil, limit: 3)
        guard !picks.isEmpty else {
            return "Your cookbook is empty, which is very minimalist of you. Add a few dishes and I'll have opinions."
        }
        let lines = picks.enumerated().map { index, pick in
            "\(index + 1). \(pick.recipe.title) — \(pick.recipe.totalMinutes) min, \(pick.recipe.difficultyValue.rawValue.lowercased())"
        }
        return "Tonight I'd plate one of these:\n\n\(lines.joined(separator: "\n"))\n\nSay the word and plate it from the plan."
    }

    private func recipeMatch(in text: String) -> Recipe? {
        recipes.first { text.contains($0.title.lowercased()) }
    }

    private func describe(_ recipe: Recipe) -> String {
        var parts: [String] = []
        parts.append("\(recipe.title): \(recipe.totalMinutes) min, serves \(recipe.servings).")
        if !recipe.summary.isEmpty { parts.append(recipe.summary) }
        let ingredients = recipe.sortedIngredients
        if !ingredients.isEmpty {
            parts.append("You'll need: \(ingredients.map(\.displayText).joined(separator: ", ")).")
        }
        if !recipe.steps.isEmpty {
            let steps = recipe.steps.enumerated().map { "\($0 + 1). \($1)" }
            parts.append("The moves:\n\(steps.joined(separator: "\n"))")
        } else if !recipe.instructions.isEmpty {
            parts.append(recipe.instructions)
        } else {
            parts.append("No steps written down yet — open it in Recipes and add them; I'll recite them next time.")
        }
        return parts.joined(separator: "\n\n")
    }

    private func substitution(in text: String) -> String? {
        guard text.contains("substitut") || text.contains("instead of")
            || text.contains("swap") || text.contains("out of") || text.contains("replace") else { return nil }
        for (ingredient, swap) in Self.substitutions where text.contains(ingredient) {
            return "Out of \(ingredient)? \(swap)"
        }
        return "Tell me the ingredient — I know swaps for buttermilk, eggs, butter, sour cream, heavy cream, wine, breadcrumbs, and more."
    }

    private static let substitutions: [(String, String)] = [
        ("buttermilk", "Stir 1 tbsp lemon juice or vinegar into 1 cup milk and give it 5 minutes to curdle."),
        ("egg", "For baking: 1 tbsp ground flax + 3 tbsp water per egg, rested 5 minutes. For binding: 3 tbsp mayo."),
        ("butter", "Equal parts oil works in most cooking; in baking use ¾ the amount in oil, or swap in coconut oil 1:1."),
        ("sour cream", "Plain Greek yogurt, 1:1. Nobody at the table will know."),
        ("heavy cream", "¾ cup milk + ¼ cup melted butter per cup — whips poorly, cooks fine."),
        ("brown sugar", "1 cup white sugar + 1 tbsp molasses, or just use white and accept a lighter flavor."),
        ("baking powder", "¼ tsp baking soda + ½ tsp cream of tartar per teaspoon needed."),
        ("wine", "Equal parts stock with a splash of vinegar — red wine vinegar for red, white for white."),
        ("breadcrumb", "Crushed crackers, panko, oats, or yesterday's bread toasted and blitzed."),
        ("garlic", "¼ tsp garlic powder per clove, added with the liquids not the oil."),
        ("tomato sauce", "Tomato paste thinned 1:1 with water, seasoned with a pinch of sugar and salt."),
        ("honey", "Maple syrup 1:1, or sugar dissolved in a splash of warm water."),
        ("cornstarch", "Twice the flour, whisked cold before it hits the pan."),
        ("fish sauce", "Soy sauce with a small anchovy mashed in, or just soy and move on."),
        ("lemon", "Half the amount of vinegar, or lime — the household will survive.")
    ]

    private static let tips: [String] = [
        "Salt your pasta water like you mean it — it's the only chance the noodle gets.",
        "Dry meat sears, wet meat steams. Pat it down before it hits the pan.",
        "Read the whole recipe before you turn anything on. Ask me how I know.",
        "A sharp knife is safer than a dull one — it goes where you point it.",
        "Rest the steak as long as you cooked it. Impatience is a sauce thief.",
        "Taste as you go. The recipe is a map, not a contract.",
        "Acid at the end — a squeeze of lemon wakes up almost any dish.",
        "Mise en place isn't fancy, it's just not panicking later."
    ]
}
