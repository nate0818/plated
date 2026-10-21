import XCTest
import SwiftData
@testable import Plated

@MainActor
final class WidgetBridgeTests: XCTestCase {
    let day = Date(timeIntervalSince1970: 4_102_444_800).startOfDay

    func testTableWidgetIncludesTextOnlyGeneralPosts() throws {
        let container = try ModelContainer(for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = container.mainContext
        let post = TablePost(authorName: "Nate", caption: "Try the tomatoes at the market.", kind: "post")
        context.insert(post); try context.save()
        WidgetBridge.publish(from: context)
        let group = try XCTUnwrap(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetBridge.appGroupID))
        let snapshot = try JSONDecoder().decode(WidgetBridge.Snapshot.self,
            from: Data(contentsOf: group.appendingPathComponent("week-snapshot.json")))
        XCTAssertEqual(snapshot.table?.recordID, post.shareRecordName)
        XCTAssertEqual(snapshot.table?.caption, post.caption)
        XCTAssertEqual(snapshot.table?.hasPhoto, false)
    }

    func testCookOnlyReservationKeepsWidgetDinnerOpenWithoutInventedArtwork() throws {
        let container = try ModelContainer(for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = container.mainContext
        let cook = HouseholdMember(name: "Sam", role: "partner", seat: .joined)
        context.insert(cook)
        context.insert(PlannedMeal(date: .now, cook: cook))
        try context.save()
        PlanLedger.shared.clear()
        WidgetBridge.publish(from: context)
        let group = try XCTUnwrap(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetBridge.appGroupID))
        let data = try Data(contentsOf: group.appendingPathComponent("week-snapshot.json"))
        let snapshot = try JSONDecoder().decode(WidgetBridge.Snapshot.self, from: data)
        XCTAssertEqual(snapshot.tonight?.title, "Dinner to choose")
        XCTAssertEqual(snapshot.tonight?.cookName, "Sam")
        XCTAssertEqual(snapshot.days.first?.planned, false)
        XCTAssertEqual(snapshot.tonight?.hasPhoto, false)
    }

    func testLeftoversSnapshotKeepsThePlanWithoutInventingACookOrDishPhoto() throws {
        let container = try ModelContainer(for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = container.mainContext
        let cook = HouseholdMember(name: "Sam", role: "partner", seat: .joined)
        context.insert(cook)
        // An older freeform row can retain an assignment even though the
        // new choice clears it. The widget still must not say Sam cooks.
        let meal = PlannedMeal(date: .now, customTitle: "Leftovers", cook: cook)
        context.insert(meal)
        try context.save()
        PlanLedger.shared.clear()
        WidgetBridge.publish(from: context)
        let group = try XCTUnwrap(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetBridge.appGroupID))
        let data = try Data(contentsOf: group.appendingPathComponent("week-snapshot.json"))
        let snapshot = try JSONDecoder().decode(WidgetBridge.Snapshot.self, from: data)
        XCTAssertEqual(snapshot.tonight?.title, "Leftovers")
        XCTAssertEqual(snapshot.tonight?.hasPhoto, false)
        XCTAssertEqual(snapshot.tonight?.minutes, 0)
        XCTAssertNil(snapshot.tonight?.cookName)
        XCTAssertEqual(snapshot.tonight?.cookInitial, "")
        XCTAssertEqual(snapshot.days.first?.planned, true)
        XCTAssertNil(snapshot.days.first?.cookName)
        XCTAssertEqual(snapshot.plannedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: group.appendingPathComponent("tonight.jpg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: group.appendingPathComponent("tonight-dark.png").path))
    }

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
