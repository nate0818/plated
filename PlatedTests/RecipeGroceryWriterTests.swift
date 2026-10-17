import XCTest
import SwiftData
@testable import Plated

@MainActor
final class RecipeGroceryWriterTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try ModelContainer(
            for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
    }

    override func tearDown() async throws { container = nil }

    private func recipe(title: String, ingredients: [(String, Double, String)]) -> Recipe {
        let recipe = Recipe(title: title)
        context.insert(recipe)
        for (index, line) in ingredients.enumerated() {
            let ingredient = Ingredient(
                name: line.0, quantity: line.1, unit: line.2,
                aisle: .produce, sortIndex: index
            )
            ingredient.recipe = recipe
            context.insert(ingredient)
        }
        return recipe
    }

    private func grocery(named name: String) throws -> GroceryItem {
        let rows = try context.fetch(FetchDescriptor<GroceryItem>())
        return try XCTUnwrap(rows.first { $0.name == name })
    }

    func testUnboughtManualExtrasRemainEligibleAfterSevenDays() throws {
        let old = GroceryItem(name: "Garlic", quantity: 1, unit: "clove", aisle: .produce,
            weekStart: Calendar.current.date(byAdding: .day, value: -20, to: .now)!, isManual: true)
        context.insert(old); try context.save()
        let dish = recipe(title: "Soup", ingredients: [("Garlic", 2, "clove")])
        _ = try RecipeGroceryWriter.add(recipe: dish, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<GroceryItem>()).count, 1)
        XCTAssertEqual(old.quantity, 3)
    }

    func testRepeatedIngredientLinesFromOneRecipeAddTheirWholeQuantityOnce() throws {
        let salsa = recipe(title: "Salsa", ingredients: [
            ("Garlic", 2, "clove"),
            ("Garlic", 3, "cloves")
        ])

        let first = try RecipeGroceryWriter.add(recipe: salsa, in: context)
        let row = try grocery(named: "Garlic")
        XCTAssertEqual(first.added, 2)
        XCTAssertEqual(first.alreadyThere, 0)
        XCTAssertEqual(row.quantity, 5, accuracy: 0.0001)
        XCTAssertEqual(row.unit, "clove")
        XCTAssertEqual(row.recipeOrigins, [.init(id: salsa.shareRecordName, title: "Salsa")])

        let repeated = try RecipeGroceryWriter.add(recipe: salsa, in: context)
        XCTAssertEqual(repeated.added, 0)
        XCTAssertEqual(repeated.alreadyThere, 2)
        XCTAssertEqual(row.quantity, 5, accuracy: 0.0001)
    }

    func testDistinctRecipesWithTheSameTitleBothContribute() throws {
        let firstSoup = recipe(title: "Tomato Soup", ingredients: [("Tomatoes", 2, "can")])
        let secondSoup = recipe(title: "Tomato Soup", ingredients: [("Tomatoes", 3, "cans")])

        _ = try RecipeGroceryWriter.add(recipe: firstSoup, in: context)
        _ = try RecipeGroceryWriter.add(recipe: secondSoup, in: context)

        let row = try grocery(named: "Tomatoes")
        XCTAssertEqual(row.quantity, 5, accuracy: 0.0001)
        XCTAssertEqual(Set(row.recipeOrigins.map(\.id)), [firstSoup.shareRecordName, secondSoup.shareRecordName])

        let repeated = try RecipeGroceryWriter.add(recipe: firstSoup, in: context)
        XCTAssertEqual(repeated.alreadyThere, 1)
        XCTAssertEqual(row.quantity, 5, accuracy: 0.0001)
    }

    func testRenamingARecipeUpdatesProvenanceWithoutAddingAgain() throws {
        let recipe = recipe(title: "Friday Pasta", ingredients: [("Rigatoni", 1, "package")])
        _ = try RecipeGroceryWriter.add(recipe: recipe, in: context)

        recipe.title = "Sunday Pasta"
        let repeated = try RecipeGroceryWriter.add(recipe: recipe, in: context)

        let row = try grocery(named: "Rigatoni")
        XCTAssertEqual(repeated.added, 0)
        XCTAssertEqual(repeated.alreadyThere, 1)
        XCTAssertEqual(row.quantity, 1, accuracy: 0.0001)
        XCTAssertEqual(row.originTitle, "Sunday Pasta")
        XCTAssertEqual(row.recipeOrigins, [.init(id: recipe.shareRecordName, title: "Sunday Pasta")])
    }
}
