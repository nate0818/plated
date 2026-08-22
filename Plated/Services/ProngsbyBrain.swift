import Foundation

/// Prongsby's brain — your AI cooking companion. Grounded in this
/// household's own cookbook, plan, and people, with a pocketful of kitchen
/// knowledge and exactly one comedy register: fork puns. Deliberately
/// rule-based and on-device: no key, no network, no made-up nonsense. When
/// Plated grows a backend, this becomes the prompt-builder for the real
/// model and the offline fallback.
struct ProngsbyBrain {
    let recipes: [Recipe]
    let members: [HouseholdMember]
    var meals: [PlannedMeal] = []

    // MARK: The voice

    /// One pun a day under the masthead. Indexed by day-of-year so the
    /// whole household sees the same joke — shared suffering builds family.
    static var taglineOfTheDay: String {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 0
        return taglines[day % taglines.count]
    }

    private static let taglines = [
        "Zero-blame kitchen. The fork takes the fall.",
        "I only roast vegetables, never cooks.",
        "Certified stainless. Morally flexible.",
        "Whisk-taker. Pun-maker.",
        "I've got three prongs and no bad ideas.",
        "Fluent in marinade and mild sarcasm.",
        "If dinner flops, we never speak of it.",
        "Sharp on the outside, soft on the inside.",
        "Utensil by day. Genius by dinner.",
        "I stand by every dish. Usually next to it.",
        "Trained on your cookbook. Raised by a drawer.",
        "The only fork that asks about your day.",
        "Salt first, apologize never.",
        "Al dente is a lifestyle, not a texture."
    ]

    /// Rotating status lines while the fork "thinks".
    static let thinkingLines = [
        "Preheating the brain…",
        "Saucing it up…",
        "Whisking a thought…",
        "Simmering on that…",
        "Sharpening the tines…",
        "Tasting for seasoning…",
        "Deglazing the details…",
        "Letting it rest…",
        "Reducing to the good part…",
        "Consulting the drawer…"
    ]

    private static let openers = [
        "Ooh, good one.",
        "Say less.",
        "On it like sauce on Sunday.",
        "The fork hears you.",
        "Right this way.",
        "Chef's hat: on."
    ]

    private func opener() -> String {
        // Roughly half the replies get a little flourish; always would be a lot.
        Bool.random() ? (Self.openers.randomElement()! + " ") : ""
    }

    // MARK: The router

    func reply(to raw: String) -> String {
        let text = raw.lowercased()

        if text.contains("hello") || text.contains("hi ") || text == "hi" || text == "hey"
            || text.contains("who are you") || text.contains("what can you do") {
            return "Well hello! I'm Prongsby — your AI cooking companion and the only fork that talks back (politely). I know your \(recipes.count) recipes, your week, and who's cooking when. Ask me for dinner ideas, swaps, resizing a dish, making something vegetarian, or planning a whole gathering. \(Self.taglineOfTheDay)"
        }
        if let swap = substitution(in: text) { return swap }
        if let scaled = scaleRecipe(text) { return scaled }
        if let modified = dietModify(text) { return modified }
        if let swapped = proteinSwap(text) { return swapped }
        if let plan = planAnswer(text) { return plan }
        if let party = gatheringPlan(text) { return party }
        if let recipe = recipeMatch(in: text) {
            if text.contains("how long") || text.contains("time") {
                return "\(recipe.title) runs about \(recipe.totalMinutes) minutes — \(recipe.prepMinutes) of prep, \(recipe.cookMinutes) on the heat. \(recipe.difficultyValue.rawValue) night. You've got this."
            }
            return describe(recipe)
        }
        if text.contains("what should") || text.contains("idea") || text.contains("suggest")
            || text.contains("make for dinner") || text.contains("cook for") || text.contains("tonight") {
            return suggestDinner()
        }
        if text.contains("tip") || text.contains("advice") {
            return opener() + (Self.tips.randomElement() ?? Self.tips[0])
        }
        if text.contains("timer") {
            return "I can't run timers — no thumbs, only tines. Say \"Hey Siri, set a timer\" and I'll hold the recipe open."
        }
        if text.contains("thank") {
            return ["Any time. I'll be in the drawer.", "That's what the third prong is for.", "De nada. Tip your dishwasher."].randomElement()!
        }
        return "Hmm — that one's past my prongs (for now; a bigger brain arrives with Plated's network). Here's what I'm genuinely good at: \"what should we make tonight?\", \"make \(recipes.first?.title ?? "Pizza Night") vegetarian\", \"scale \(recipes.first?.title ?? "it") for 8\", \"substitute for buttermilk\", \"who's cooking Friday?\", or \"plan a gathering for 10\"."
    }

    // MARK: Sous-chef skills

    /// "Scale Pizza Night for 8" — rewrites the ingredient list at the new
    /// serving count.
    private func scaleRecipe(_ text: String) -> String? {
        guard text.contains("scale") || text.contains("serving") || text.contains("double")
            || ((text.contains(" for ") || text.contains("feed")) && recipeMatch(in: text) != nil) else { return nil }
        guard let recipe = recipeMatch(in: text) else {
            return "Tell me which dish and how many — \"scale \(recipes.first?.title ?? "Pizza Night") for 8\" and I'll redo the math so you don't have to."
        }
        var target: Int?
        if text.contains("double") { target = recipe.servings * 2 }
        if let match = text.range(of: #"(?:for|to|feeds?|serves?)\s+(\d{1,2})"#, options: .regularExpression) {
            target = Int(text[match].components(separatedBy: CharacterSet.decimalDigits.inverted).joined())
        }
        guard let target, target > 0 else {
            return "How many mouths? Say \"scale \(recipe.title) for 8\" and consider it portioned."
        }
        let factor = Double(target) / Double(max(recipe.servings, 1))
        let ingredients = recipe.sortedIngredients
        guard !ingredients.isEmpty else {
            return "\(recipe.title) has no ingredients written down yet — add them in Recipes and I'll scale anything to anyone."
        }
        let lines = ingredients.map { ingredient -> String in
            let qty = ingredient.quantity * factor
            var parts: [String] = []
            if qty > 0 { parts.append(Ingredient.format((qty * 4).rounded() / 4)) }
            if !ingredient.unit.isEmpty { parts.append(ingredient.unit) }
            parts.append(ingredient.name)
            return "• " + parts.joined(separator: " ")
        }
        return opener() + "\(recipe.title), rescaled from \(recipe.servings) to \(target):\n\n\(lines.joined(separator: "\n"))\n\nCook times mostly hold — just don't crowd the pan. Crowded pans steam, and steamed is nobody's favorite adjective."
    }

    /// "Make the skewers vegetarian" — walks the ingredient list and swaps
    /// what the diet forbids.
    private func dietModify(_ text: String) -> String? {
        let diets: [(key: String, name: String, table: [String: String])] = [
            ("vegan", "vegan", Self.meatSwaps.merging(Self.dairySwaps) { a, _ in a }),
            ("vegetarian", "vegetarian", Self.meatSwaps),
            ("veggie", "vegetarian", Self.meatSwaps),
            ("gluten", "gluten-free", Self.glutenSwaps),
            ("dairy", "dairy-free", Self.dairySwaps)
        ]
        guard let diet = diets.first(where: { text.contains($0.key) }) else { return nil }
        guard let recipe = recipeMatch(in: text) else {
            return "Happy to \(diet.name)-ify anything in the cookbook — which dish? \"Make \(recipes.first?.title ?? "Pizza Night") \(diet.name)\" and I'll do the surgery."
        }
        let ingredients = recipe.sortedIngredients
        guard !ingredients.isEmpty else {
            return "\(recipe.title) has no ingredients written down yet — add them and I'll happily rebuild it \(diet.name)."
        }
        var swapped: [String] = []
        var kept: [String] = []
        for ingredient in ingredients {
            let lowered = ingredient.name.lowercased()
            if let (_, replacement) = diet.table.first(where: { lowered.contains($0.key) }) {
                swapped.append("• \(ingredient.name) → \(replacement)")
            } else {
                kept.append(ingredient.name)
            }
        }
        if swapped.isEmpty {
            return "Good news: \(recipe.title) is already \(diet.name) as written. The fork approves. Carry on."
        }
        var reply = opener() + "\(recipe.title), gone \(diet.name):\n\n\(swapped.joined(separator: "\n"))"
        if !kept.isEmpty {
            reply += "\n\nEverything else stays (\(kept.prefix(4).joined(separator: ", "))\(kept.count > 4 ? "…" : ""))."
        }
        reply += "\n\nSame method, same times — taste as you go and nobody at the table will file a complaint."
        return reply
    }

    /// "Swap the chicken for shrimp in the skewers."
    private func proteinSwap(_ text: String) -> String? {
        guard text.contains("swap") || text.contains("replace") || text.contains("instead of") else { return nil }
        guard let recipe = recipeMatch(in: text) else { return nil }
        let proteins = ["chicken", "beef", "steak", "pork", "salmon", "fish", "tuna", "shrimp", "turkey", "tofu", "lamb", "sausage"]
        let mentioned = proteins.filter { text.contains($0) }
        guard mentioned.count >= 2 else {
            return "Swap what for what in \(recipe.title)? Give me both — \"swap the chicken for shrimp\" — and I'll adjust the plan."
        }
        let from = mentioned[0], to = mentioned[1]
        var notes = "\(recipe.title) with \(to) instead of \(from) — done."
        if ["shrimp", "fish", "salmon", "tuna"].contains(to) {
            notes += " Seafood cooks fast: pull the time down to a third and take it off the heat the moment it turns opaque."
        } else if to == "tofu" {
            notes += " Press it, cube it, and get it properly brown before it meets the sauce — pale tofu convinced nobody, ever."
        } else if ["beef", "steak", "lamb", "pork"].contains(to) {
            notes += " Give it a harder sear and a few extra minutes than the \(from) wanted, plus a rest before you slice."
        }
        return opener() + notes
    }

    /// "What's for dinner tonight?" / "Who's cooking Friday?"
    private func planAnswer(_ text: String) -> String? {
        let asksWhat = text.contains("what's for dinner") || text.contains("whats for dinner")
            || text.contains("what's tonight") || text.contains("on the plan")
        let asksWho = text.contains("who's cooking") || text.contains("whos cooking")
            || text.contains("whose turn") || text.contains("who cooks")
        guard asksWhat || asksWho else { return nil }

        let target = dateMentioned(in: text) ?? Calendar.current.startOfDay(for: .now)
        let dayName = Calendar.current.isDateInToday(target) ? "tonight" : {
            let formatter = DateFormatter(); formatter.dateFormat = "EEEE"
            return formatter.string(from: target)
        }()
        guard let meal = meals.first(where: {
            Calendar.current.isSameDay($0.date, target) && $0.slotValue == .dinner
        }) else {
            return "Nothing's plated for \(dayName) yet — a blank placemat, full of potential. Want ideas? Just say \"what should we make?\""
        }
        if asksWho {
            guard let cook = meal.cook else {
                return "\(meal.title) is on for \(dayName), cook TBD — the pan waits for a hero."
            }
            return "\(cook.isOwner ? "You're" : "\(cook.name) is") on \(dayName): \(meal.title). \(cook.isOwner ? "I believe in you." : "Send encouragement, or at least stay out of the kitchen.")"
        }
        let minutes = meal.recipe?.totalMinutes ?? 0
        let cookLine = meal.cook.map { $0.isOwner ? " You're cooking." : " \($0.name)'s cooking." } ?? ""
        return "\(dayName.capitalized): \(meal.title)\(minutes > 0 ? " — about \(minutes) minutes" : "").\(cookLine)"
    }

    /// "Plan a gathering for 10" — builds a menu from the cookbook and
    /// scales the headliner.
    private func gatheringPlan(_ text: String) -> String? {
        guard text.contains("gather") || text.contains("party") || text.contains("hosting")
            || text.contains("guests") || text.contains("dinner party") else { return nil }
        var guests = 8
        if let match = text.range(of: #"(\d{1,2})"#, options: .regularExpression) {
            guests = Int(text[match]) ?? 8
        }
        let mains = recipes.filter { $0.mealTypeValue == .dinner }
            .sorted { $0.loveScore > $1.loveScore }
        guard let main = mains.first else {
            return "A gathering for \(guests)! First, teach me some dishes — the cookbook's empty and I can't feed \(guests) people vibes."
        }
        var menu = ["The headliner: \(main.title) (crowd-tested, \(main.loveScore) love points)"]
        if let side = recipes.first(where: { $0.mealTypeValue == .sideDish }) {
            menu.append("On the side: \(side.title)")
        }
        if let starter = recipes.first(where: { $0.mealTypeValue == .appetizer }) {
            menu.append("To start: \(starter.title)")
        }
        if let dessert = recipes.first(where: { $0.mealTypeValue == .dessert }) {
            menu.append("The finale: \(dessert.title)")
        }
        if let backup = mains.dropFirst().first {
            menu.append("Backup main if the table splits: \(backup.title)")
        }
        let factor = Double(guests) / Double(max(main.servings, 1))
        var reply = opener() + "A gathering for \(guests) — my kind of chaos. From your cookbook:\n\n\(menu.map { "• " + $0 }.joined(separator: "\n"))"
        if factor > 1.1 {
            reply += "\n\n\(main.title) serves \(main.servings), so run it at \(String(format: "%.1f", factor))× — say \"scale \(main.title) for \(guests)\" and I'll do the ingredient math."
        }
        reply += "\n\nWhen you're ready, use Plan → a night → Plan a gathering and it lands on the Apple Calendar too. I'll be there in spirit. And in the drawer."
        return reply
    }

    // MARK: Core skills

    private func suggestDinner() -> String {
        let engine = SuggestionEngine(recipes: recipes, members: members)
        let picks = engine.suggestions(for: .now, forecast: nil, limit: 3)
        guard !picks.isEmpty else {
            return "Your cookbook is empty, which is very minimalist of you. Add a few dishes and I'll have opinions — so many opinions."
        }
        let lines = picks.enumerated().map { index, pick in
            "\(index + 1). \(pick.recipe.title) — \(pick.recipe.totalMinutes) min, \(pick.recipe.difficultyValue.rawValue.lowercased())"
        }
        let closers = [
            "Say the word and plate it from the plan.",
            "All three respect the household's hard no's. I checked. Twice.",
            "I'd go with #1, but I'm biased toward whatever gets cooked."
        ]
        return opener() + "Tonight I'd plate one of these:\n\n\(lines.joined(separator: "\n"))\n\n\(closers.randomElement()!)"
    }

    private func recipeMatch(in text: String) -> Recipe? {
        // Full title first, then distinctive words ("the skewers") — whole
        // words only, or "tonight" matches Pizza *Night*, and generic
        // cooking words don't count as identity.
        if let exact = recipes.first(where: { text.contains($0.title.lowercased()) }) { return exact }
        let textWords = Set(text.split(whereSeparator: { !$0.isLetter }).map(String.init))
        let generic: Set<String> = ["night", "dinner", "lunch", "butter", "with", "bowl", "bowls"]
        return recipes.first { recipe in
            recipe.title.lowercased()
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count > 3 && !generic.contains($0) }
                .contains { textWords.contains($0) }
        }
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
            parts.append("No steps written down yet — open it in Recipes, add them, and I'll recite them back like poetry. Kitchen poetry.")
        }
        return parts.joined(separator: "\n\n")
    }

    private func substitution(in text: String) -> String? {
        guard text.contains("substitut") || text.contains("out of") || text.contains("no more") else { return nil }
        for (ingredient, swap) in Self.substitutions where text.contains(ingredient) {
            return opener() + "Out of \(ingredient)? \(swap)"
        }
        return "Tell me the ingredient — I know swaps for buttermilk, eggs, butter, sour cream, heavy cream, wine, breadcrumbs, and half the pantry."
    }

    private func dateMentioned(in text: String) -> Date? {
        let symbols = Calendar.current.weekdaySymbols // Sunday-first
        for (index, name) in symbols.enumerated() where text.contains(name.lowercased()) {
            var comps = DateComponents()
            comps.weekday = index + 1
            return Calendar.current.nextDate(after: .now, matching: comps, matchingPolicy: .nextTime)
                .map { Calendar.current.startOfDay(for: $0) }
        }
        if text.contains("tomorrow") {
            return Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))
        }
        return nil
    }

    // MARK: Knowledge

    private static let meatSwaps: [String: String] = [
        "chicken": "crispy tofu (pressed and properly browned)",
        "beef": "portobello mushrooms",
        "steak": "portobello mushrooms, sliced thick",
        "pork": "jackfruit or seared tempeh",
        "salmon": "roasted cauliflower steaks",
        "fish": "roasted cauliflower steaks",
        "tuna": "marinated chickpeas",
        "shrimp": "king oyster mushrooms, scored",
        "turkey": "seasoned lentils",
        "sausage": "plant sausage",
        "bacon": "smoked tempeh",
        "lamb": "braised mushrooms and white beans"
    ]

    private static let dairySwaps: [String: String] = [
        "butter": "olive oil (¾ the amount)",
        "milk": "oat milk",
        "cheese": "vegan cheese or nutritional yeast",
        "mozzarella": "vegan mozzarella",
        "parmesan": "nutritional yeast",
        "cream": "coconut cream",
        "yogurt": "coconut yogurt",
        "egg": "flax egg (1 tbsp ground flax + 3 tbsp water)"
    ]

    private static let glutenSwaps: [String: String] = [
        "flour": "1:1 gluten-free flour blend",
        "pasta": "gluten-free pasta",
        "dough": "gluten-free dough",
        "bread": "gluten-free bread",
        "breadcrumb": "gluten-free breadcrumbs",
        "soy sauce": "tamari",
        "tortilla": "corn tortillas"
    ]

    private static let substitutions: [(String, String)] = [
        ("buttermilk", "Stir 1 tbsp lemon juice or vinegar into 1 cup milk and give it 5 minutes to curdle. Science, but make it breakfast."),
        ("egg", "For baking: 1 tbsp ground flax + 3 tbsp water per egg, rested 5 minutes. For binding: 3 tbsp mayo."),
        ("butter", "Equal parts oil works in most cooking; in baking use ¾ the amount in oil, or coconut oil 1:1."),
        ("sour cream", "Plain Greek yogurt, 1:1. Nobody at the table will know. I certainly won't tell."),
        ("heavy cream", "¾ cup milk + ¼ cup melted butter per cup — whips poorly, cooks beautifully."),
        ("brown sugar", "1 cup white sugar + 1 tbsp molasses, or just use white and accept a lighter destiny."),
        ("baking powder", "¼ tsp baking soda + ½ tsp cream of tartar per teaspoon needed."),
        ("wine", "Equal parts stock with a splash of vinegar — red wine vinegar for red, white for white."),
        ("breadcrumb", "Crushed crackers, panko, oats, or yesterday's bread toasted and blitzed."),
        ("garlic", "¼ tsp garlic powder per clove, added with the liquids, not the hot oil."),
        ("tomato sauce", "Tomato paste thinned 1:1 with water, seasoned with a pinch of sugar and salt."),
        ("honey", "Maple syrup 1:1, or sugar dissolved in a splash of warm water."),
        ("cornstarch", "Twice the flour, whisked cold before it hits the pan."),
        ("fish sauce", "Soy sauce with a small anchovy mashed in, or just soy and move on with your life."),
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
        "Mise en place isn't fancy, it's just not panicking later.",
        "Warm your plates. Thirty seconds of care, restaurant-grade smugness.",
        "Save your pasta water. It's liquid gold that tastes like glue and works like magic."
    ]
}
