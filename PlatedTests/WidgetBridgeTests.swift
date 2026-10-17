import XCTest
import SwiftData
@testable import Plated

@MainActor
final class WidgetBridgeTests: XCTestCase {
    let day = Date(timeIntervalSince1970: 4_102_444_800).startOfDay

    func testGrocerySnapshotBuildsBeforeSheetOpensAndDoesNotCommitDrafts() throws {
        let container = try ModelContainer(for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = container.mainContext
        context.autosaveEnabled = false
        let recipe = Recipe(title: "Widget dinner", servings: 2)
        recipe.ingredients = [Ingredient(name: "Widget test beans", quantity: 2, unit: "cups")]
        context.insert(recipe)
        context.insert(PlannedMeal(date: day, recipe: recipe, servings: 2))
        try context.save()
        XCTAssertTrue(try context.fetch(FetchDescriptor<GroceryItem>()).isEmpty)
        recipe.title = "Unsaved recipe edit"
        context.insert(Recipe(title: "Unrelated draft"))

        let grocery = try XCTUnwrap(WidgetBridge.groceryLine(from: context, windowStart: day))
        XCTAssertEqual(grocery.openCount, 1)
        XCTAssertEqual(grocery.totalCount, 1)
        XCTAssertEqual(grocery.sample, ["Widget test beans"])
        let reader = ModelContext(container)
        XCTAssertEqual(try reader.fetch(FetchDescriptor<Recipe>()).map(\.title), ["Widget dinner"])
        XCTAssertTrue(context.hasChanges)
    }

    func testGrocerySnapshotPreservesPurchasesAndReopensIncreasedQuantity() throws {
        let container = try ModelContainer(for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = container.mainContext
        let recipe = Recipe(title: "Widget dinner", servings: 2)
        recipe.ingredients = [Ingredient(name: "Widget quantity beans", quantity: 2, unit: "cups")]
        context.insert(recipe)
        let meal = PlannedMeal(date: day, recipe: recipe, servings: 2)
        context.insert(meal)
        try context.save()
        let item = try XCTUnwrap(GroceryListBuilder(context: context).rebuild(weekOf: day).first)
        item.purchases = Dictionary(uniqueKeysWithValues: item.sources.map { ($0.id, $0.quantity) })
        item.isChecked = true
        try context.save()
        XCTAssertEqual(WidgetBridge.groceryLine(from: context, windowStart: day)?.openCount, 0)
        meal.servings = 4
        try context.save()
        XCTAssertEqual(WidgetBridge.groceryLine(from: context, windowStart: day)?.openCount, 1)
    }

    func testGrocerySnapshotHonorsPantryPreferenceAndPersistentManualExtras() throws {
        let container = try ModelContainer(for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = container.mainContext
        let recipe = Recipe(title: "Pantry dinner")
        recipe.ingredients = [Ingredient(name: "Widget pantry salt", quantity: 1, unit: "tsp", isPantryStaple: true)]
        context.insert(recipe); context.insert(PlannedMeal(date: day, recipe: recipe))
        context.insert(GroceryItem(name: "Old unbought extra", weekStart: day.addingTimeInterval(-20 * 86400), isManual: true))
        let dismissed = GroceryItem(name: "Dismissed extra", weekStart: day, isManual: true)
        dismissed.isDismissed = true; context.insert(dismissed)
        try context.save()
        XCTAssertEqual(WidgetBridge.groceryLine(from: context, windowStart: day)?.sample, ["Old unbought extra"])
        let included = try XCTUnwrap(WidgetBridge.groceryLine(from: context, windowStart: day, includePantryStaples: true))
        XCTAssertEqual(included.openCount, 2)
        XCTAssertEqual(included.sample, ["Old unbought extra", "Widget pantry salt"])
    }
}
