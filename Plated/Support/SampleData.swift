import Foundation
import SwiftData
import UIKit

/// Seed content for previews and first launch, so the app is explorable before
/// anyone has typed a recipe in. Dish photos here are bundled stand-ins; in
/// real use every photo on a plate is one somebody at the table took.
enum SampleData {
    @MainActor
    static var previewContainer: ModelContainer = {
        let schema = Schema([
            Recipe.self, Ingredient.self, PlannedMeal.self,
            HouseholdMember.self, Gathering.self, GroceryItem.self,
            TablePost.self, TableComment.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        seed(into: container.mainContext)
        return container
    }()

    /// Bundled stand-in photo, downscaled at build time to stay CloudKit-polite.
    static func photo(_ name: String) -> Data? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg") else { return nil }
        return try? Data(contentsOf: url)
    }

    @MainActor
    static func seed(into context: ModelContext) {
        // People — Nate owns the account; Sam and Riley have standing nights.
        let nate = HouseholdMember(
            name: "Nate", colorHex: "FF5A3C", isPrimaryCook: true,
            role: "owner", roleLine: "Head of table", cookWeekdays: [6, 4] // Fri, Wed
        )
        let sam = HouseholdMember(
            name: "Sam", colorHex: "3DA35D",
            role: "partner", roleLine: "Partner · plans & cooks", cookWeekdays: [7, 1] // Sat, Sun
        )
        let riley = HouseholdMember(
            name: "Riley", colorHex: "C88A00",
            role: "kid", roleLine: "Kid · ideas & helping", cookWeekdays: [3] // Tue
        )
        [nate, sam, riley].forEach { context.insert($0) }

        // Recipes — the household cookbook.
        let salmon = Recipe(
            title: "Lemon Butter Salmon", summary: "Weeknight hero. Crispy skin, bright sauce.",
            servings: 4, prepMinutes: 10, cookMinutes: 15, tags: ["Fast", "Favorite"],
            weatherMoods: [.mild, .warm]
        )
        salmon.isFavorite = true
        salmon.photoData = photo("salmon-plate")
        salmon.ingredients = [
            Ingredient(name: "Salmon fillets", quantity: 4, unit: "", aisle: .meat, sortIndex: 0),
            Ingredient(name: "Lemon", quantity: 2, unit: "", aisle: .produce, sortIndex: 1),
            Ingredient(name: "Butter", quantity: 4, unit: "tbsp", aisle: .dairy, sortIndex: 2),
            Ingredient(name: "Asparagus", quantity: 1, unit: "bunch", aisle: .produce, sortIndex: 3)
        ]

        let pizza = Recipe(
            title: "Pizza Night", summary: "Everyone builds their own. Flour everywhere.",
            servings: 4, prepMinutes: 25, cookMinutes: 12, tags: ["Kids pick"],
            weatherMoods: [.cool, .rainy]
        )
        pizza.photoData = photo("pizza")
        pizza.ingredients = [
            Ingredient(name: "Pizza dough", quantity: 2, unit: "balls", aisle: .bakery, sortIndex: 0),
            Ingredient(name: "Mozzarella", quantity: 16, unit: "oz", aisle: .dairy, sortIndex: 1),
            Ingredient(name: "Tomato sauce", quantity: 1, unit: "jar", aisle: .pantry, sortIndex: 2),
            Ingredient(name: "Basil", quantity: 1, unit: "bunch", aisle: .produce, sortIndex: 3)
        ]

        let skewers = Recipe(
            title: "BBQ Skewers", summary: "Grill season never ends at this table.",
            servings: 6, prepMinutes: 20, cookMinutes: 15, tags: ["Grill", "Crowd"],
            weatherMoods: [.grillWeather, .hot]
        )
        skewers.photoData = photo("skewers")
        skewers.ingredients = [
            Ingredient(name: "Chicken thighs", quantity: 2, unit: "lb", aisle: .meat, sortIndex: 0),
            Ingredient(name: "Bell peppers", quantity: 3, unit: "", aisle: .produce, sortIndex: 1),
            Ingredient(name: "Red onion", quantity: 2, unit: "", aisle: .produce, sortIndex: 2),
            Ingredient(name: "BBQ sauce", quantity: 1, unit: "bottle", aisle: .pantry, sortIndex: 3)
        ]

        let bowls = Recipe(
            title: "Rainbow Bowls", summary: "Twenty minutes, one bowl, every color.",
            servings: 4, prepMinutes: 15, cookMinutes: 5, tags: ["Fast", "Veggie"],
            weatherMoods: [.warm, .mild]
        )
        bowls.photoData = photo("veggie")
        bowls.ingredients = [
            Ingredient(name: "Quinoa", quantity: 1.5, unit: "cups", aisle: .pantry, sortIndex: 0),
            Ingredient(name: "Avocado", quantity: 2, unit: "", aisle: .produce, sortIndex: 1),
            Ingredient(name: "Cherry tomatoes", quantity: 1, unit: "pint", aisle: .produce, sortIndex: 2),
            Ingredient(name: "Chickpeas", quantity: 1, unit: "can", aisle: .pantry, sortIndex: 3)
        ]

        let steak = Recipe(
            title: "Steak Bowls", summary: "Riley's specialty. Don't touch the marinade.",
            servings: 4, prepMinutes: 15, cookMinutes: 12, tags: ["Riley's"],
            weatherMoods: [.mild, .cool]
        )
        steak.photoData = photo("plates")
        steak.ingredients = [
            Ingredient(name: "Flank steak", quantity: 1.5, unit: "lb", aisle: .meat, sortIndex: 0),
            Ingredient(name: "Rice", quantity: 2, unit: "cups", aisle: .pantry, isPantryStaple: true, sortIndex: 1),
            Ingredient(name: "Lime", quantity: 3, unit: "", aisle: .produce, sortIndex: 2)
        ]

        let poke = Recipe(
            title: "Poke Night", summary: "The fast one. Rice cooker does the work.",
            servings: 2, prepMinutes: 15, cookMinutes: 0, tags: ["Fast", "No-cook"],
            weatherMoods: [.hot, .warm]
        )
        poke.photoData = photo("poke")
        poke.ingredients = [
            Ingredient(name: "Ahi tuna", quantity: 1, unit: "lb", aisle: .meat, sortIndex: 0),
            Ingredient(name: "Sushi rice", quantity: 2, unit: "cups", aisle: .pantry, sortIndex: 1),
            Ingredient(name: "Cucumber", quantity: 1, unit: "", aisle: .produce, sortIndex: 2),
            Ingredient(name: "Soy sauce", quantity: 1, unit: "bottle", aisle: .pantry, isPantryStaple: true, sortIndex: 3)
        ]

        let pancakes = Recipe(
            title: "Pancake Dinner", summary: "Breakfast for dinner. Zero regrets, full syrup.",
            servings: 4, prepMinutes: 10, cookMinutes: 15, tags: ["Crowd fave"],
            weatherMoods: [.rainy, .cold]
        )
        pancakes.isFavorite = true
        pancakes.photoData = photo("pancakes")
        pancakes.ingredients = [
            Ingredient(name: "Flour", quantity: 2, unit: "cups", aisle: .pantry, isPantryStaple: true, sortIndex: 0),
            Ingredient(name: "Eggs", quantity: 3, unit: "", aisle: .dairy, sortIndex: 1),
            Ingredient(name: "Maple syrup", quantity: 1, unit: "bottle", aisle: .pantry, sortIndex: 2),
            Ingredient(name: "Blueberries", quantity: 1, unit: "pint", aisle: .produce, sortIndex: 3)
        ]

        [salmon, pizza, skewers, bowls, steak, poke, pancakes].forEach { context.insert($0) }

        // The week — planned around "today" so the home screen is always alive.
        // Today: salmon (Nate). Two days stay open so picking has somewhere to land.
        let today = Calendar.current.startOfDay(for: .now)
        func day(_ offset: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: offset, to: today) ?? today
        }
        let plan: [(Int, Recipe, HouseholdMember, String)] = [
            (0, salmon, nate, ""),
            (1, pizza, sam, "Kids pick"),
            (2, skewers, sam, "Grandma joins"),
            (4, steak, riley, "Riley cooks"),
            (5, poke, nate, "Fast one")
        ]
        for (offset, recipe, cook, tag) in plan {
            let meal = PlannedMeal(
                date: day(offset), slot: .dinner, recipe: recipe,
                servings: recipe.servings, cook: cook, tagline: tag
            )
            if recipe === salmon { meal.customTitle = "Salmon Night" }
            context.insert(meal)
        }

        // The Table — moments from the people Nate has seated.
        let post1 = TablePost(
            authorName: "Sam Meadows", authorColorHex: "3DA35D",
            dishTitle: "Pancake Dinner",
            caption: "Breakfast for dinner. Zero regrets, full syrup.",
            createdAt: Calendar.current.date(byAdding: .hour, value: -2, to: .now) ?? .now,
            plateCount: 9, photoData: photo("pancakes")
        )
        post1.comments = [
            TableComment(
                authorName: "Grandma",
                text: "This is the recipe I told you about —",
                linkURL: "https://cooking.nytimes.com/recipes/pancakes",
                createdAt: Calendar.current.date(byAdding: .minute, value: -90, to: .now) ?? .now
            ),
            TableComment(
                authorName: "Riley",
                text: "Best dinner of the week and it isn't close",
                createdAt: Calendar.current.date(byAdding: .minute, value: -70, to: .now) ?? .now
            ),
            TableComment(
                authorName: "Dan Alvarez",
                text: "Syrup-to-pancake ratio is elite here",
                createdAt: Calendar.current.date(byAdding: .minute, value: -40, to: .now) ?? .now
            )
        ]
        let post2 = TablePost(
            authorName: "Dan Alvarez", authorColorHex: "C88A00",
            dishTitle: "BBQ Skewers",
            caption: "Grill season never ends at this table.",
            createdAt: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now,
            plateCount: 5, photoData: photo("skewers")
        )
        post2.comments = [
            TableComment(
                authorName: "Sam Meadows",
                text: "Saving this for Sunday, calling it now",
                createdAt: Calendar.current.date(byAdding: .hour, value: -20, to: .now) ?? .now
            ),
            TableComment(
                authorName: "Maya Chen",
                text: "That char is perfect",
                createdAt: Calendar.current.date(byAdding: .hour, value: -18, to: .now) ?? .now
            )
        ]
        let post3 = TablePost(
            authorName: "Maya Chen", authorColorHex: "B95CF4",
            dishTitle: "Rainbow Bowls",
            caption: "Twenty minutes, one bowl, every color.",
            createdAt: Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .now,
            plateCount: 3, photoData: photo("veggie")
        )
        post3.comments = [
            TableComment(
                authorName: "Nate",
                text: "Twenty minutes?? Dropping the link if you have it",
                createdAt: Calendar.current.date(byAdding: .day, value: -2, to: .now) ?? .now
            )
        ]
        [post1, post2, post3].forEach { context.insert($0) }

        seedDiscover(into: context)

        try? context.save()
    }

    /// Discover — dinners from tables that chose to be open. Stand-in content
    /// until the real public network arrives with CloudKit.
    @MainActor
    static func seedDiscover(into context: ModelContext) {
        let open: [(String, String, String, String, Int, Int)] = [
            // dish, table, caption, photo, plates, hoursAgo
            ("Golden Hour Pancakes", "The Morning Table", "Sunday stack, backlit on purpose.", "pancakes", 23, 3),
            ("Charred Skewer Sunday", "Ember & Oak", "If it isn't a little burnt, start over.", "skewers", 14, 6),
            ("Rainbow Bowl, 20 Minutes", "The Weeknight Club", "Weeknight rules: one bowl, every color, no drama.", "veggie", 9, 10),
            ("Midnight Salmon", "After Service", "What line cooks make when the restaurant closes.", "salmon-dark", 31, 26),
            ("Friday Pizza Ritual", "The Rossi Table", "Nonna's dough, the kids' toppings. Non-negotiable.", "pizza", 18, 30),
            ("Poke for Two", "Tide & Rice", "Rice cooker on, knife out, done before the news.", "poke", 7, 49),
            ("Steak Bowl Standard", "Counter Culture", "The marinade is a family secret. The bowl is not.", "plates", 11, 55),
            ("Lemon Butter Weeknight", "The Garcias", "Crispy skin club, table of six.", "salmon-plate", 5, 76)
        ]
        let hexes = ["FF5A3C", "3DA35D", "C88A00", "B95CF4"]
        for (index, entry) in open.enumerated() {
            let (dish, table, caption, photoName, plates, hoursAgo) = entry
            context.insert(TablePost(
                authorName: table,
                authorColorHex: hexes[index % hexes.count],
                dishTitle: dish,
                caption: caption,
                isDiscover: true,
                createdAt: Calendar.current.date(byAdding: .hour, value: -hoursAgo, to: .now) ?? .now,
                plateCount: plates,
                photoData: photo(photoName)
            ))
        }
    }
}
