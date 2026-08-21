import Foundation
import SwiftData

/// Seed content for previews and first launch, so the app is explorable before
/// anyone has typed a recipe in.
enum SampleData {
    @MainActor
    static var previewContainer: ModelContainer = {
        let schema = Schema([
            Recipe.self, Ingredient.self, PlannedMeal.self,
            HouseholdMember.self, Gathering.self, GroceryItem.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        seed(into: container.mainContext)
        return container
    }()

    static func seed(into context: ModelContext) {
        let nate = HouseholdMember(
            name: "Nate",
            dietaryNotes: "Eats anything. Prefers spicy.",
            colorHex: "C86629",
            isPrimaryCook: true
        )
        context.insert(nate)

        let chili = Recipe(
            title: "Weeknight Chili",
            summary: "Thick, smoky, better the next day.",
            instructions: "Brown the beef with the onion. Add spices, tomatoes, and beans. Simmer 40 minutes.",
            servings: 6,
            prepMinutes: 15,
            cookMinutes: 45,
            tags: ["comfort", "batch"],
            weatherMoods: [.cold, .cool, .rainy]
        )
        context.insert(chili)
        addIngredients(to: chili, context: context, lines: [
            ("ground beef", 2, "lb", .meat, false),
            ("yellow onion", 1, "", .produce, false),
            ("kidney beans", 2, "cans", .pantry, false),
            ("crushed tomatoes", 28, "oz", .pantry, false),
            ("chili powder", 3, "tbsp", .pantry, true),
            ("olive oil", 2, "tbsp", .pantry, true)
        ])

        let salad = Recipe(
            title: "Grilled Chicken Chopped Salad",
            summary: "Fast, cold, no oven.",
            instructions: "Grill the chicken. Chop everything. Toss with vinaigrette.",
            servings: 4,
            prepMinutes: 20,
            cookMinutes: 15,
            tags: ["light", "grill"],
            weatherMoods: [.warm, .hot, .grillWeather]
        )
        context.insert(salad)
        addIngredients(to: salad, context: context, lines: [
            ("chicken breast", 1.5, "lb", .meat, false),
            ("romaine", 2, "heads", .produce, false),
            ("cherry tomatoes", 1, "pint", .produce, false),
            ("feta", 4, "oz", .dairy, false),
            ("olive oil", 3, "tbsp", .pantry, true)
        ])

        let pasta = Recipe(
            title: "Sunday Bolognese",
            summary: "Long simmer, worth it.",
            instructions: "Soffritto, then meat, then wine, then milk, then tomatoes. Three hours low.",
            servings: 8,
            prepMinutes: 25,
            cookMinutes: 180,
            tags: ["sunday", "batch"],
            weatherMoods: [.cold, .cool, .rainy]
        )
        context.insert(pasta)
        addIngredients(to: pasta, context: context, lines: [
            ("ground pork", 1, "lb", .meat, false),
            ("pancetta", 4, "oz", .meat, false),
            ("carrot", 2, "", .produce, false),
            ("celery", 2, "stalks", .produce, false),
            ("whole milk", 1, "cup", .dairy, false),
            ("tagliatelle", 1, "lb", .pantry, false)
        ])

        // A little history so the Insights tab has something to chart.
        let calendar = Calendar.current
        let history: [(Recipe, Int)] = [(chili, 7), (chili, 21), (pasta, 14), (salad, 3), (chili, 35)]
        for (recipe, daysAgo) in history {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: .now) else { continue }
            let meal = PlannedMeal(date: date, slot: .dinner, recipe: recipe, servings: recipe.servings)
            meal.cookedAt = date
            context.insert(meal)
        }
    }

    private static func addIngredients(
        to recipe: Recipe,
        context: ModelContext,
        lines: [(String, Double, String, GroceryAisle, Bool)]
    ) {
        for (index, line) in lines.enumerated() {
            let ingredient = Ingredient(
                name: line.0,
                quantity: line.1,
                unit: line.2,
                aisle: line.3,
                isPantryStaple: line.4,
                sortIndex: index
            )
            ingredient.recipe = recipe
            context.insert(ingredient)
        }
    }
}
