import XCTest
import SwiftData
@testable import Plated

@MainActor
final class PlanMealChoiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let date = Date(timeIntervalSince1970: 1_792_512_345)

    override func setUp() async throws {
        container = try ModelContainer(for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        context.autosaveEnabled = false
    }

    override func tearDown() async throws { container = nil }

    func testChoosingLeftoversPersistsOnTheSameDayAndSlotWithTheSamePlanIdentity() throws {
        let meal = PlannedMeal(date: date, slot: .lunch, servings: 3)
        meal.authorID = "original-planner"
        meal.notes = "Lunch after the appointment"
        meal.createdAt = date.addingTimeInterval(-600)
        let shoppingID = try XCTUnwrap(meal.shoppingID)
        let createdAt = meal.createdAt

        context.insert(meal)
        meal.select(.leftovers)
        try context.save()
        let id = meal.persistentModelID

        // Read through another context so the assertion covers what was
        // saved, rather than only the object the choice just mutated.
        let reader = ModelContext(container)
        let rows = try reader.fetch(FetchDescriptor<PlannedMeal>())
        XCTAssertEqual(rows.count, 1, "Choosing leftovers must update the slot rather than duplicate it")
        let saved = try XCTUnwrap(rows.first)
        XCTAssertEqual(saved.persistentModelID, id)
        XCTAssertEqual(saved.shoppingID, shoppingID)
        XCTAssertEqual(saved.date, Calendar.current.startOfDay(for: date))
        XCTAssertEqual(saved.slotValue, .lunch)
        XCTAssertEqual(saved.authorID, "original-planner")
        XCTAssertEqual(saved.servings, 3)
        XCTAssertEqual(saved.notes, "Lunch after the appointment")
        XCTAssertEqual(saved.createdAt, createdAt)
        XCTAssertEqual(saved.title, "Leftovers")
        XCTAssertEqual(saved.tagline, "Enjoy what’s already made")
        XCTAssertTrue(saved.hasDish)
        XCTAssertTrue(saved.isLeftovers)
        XCTAssertFalse(saved.isCooked)
    }

    func testLeftoversPersistAcrossDistinctContainersUsingDiskStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Plated-leftovers-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("leftovers.store")
        let configuration = ModelConfiguration("Leftovers restart regression", schema: PlatedStore.schema,
            url: storeURL, cloudKitDatabase: .none)

        // A distinct container reopens the disk store after the writer scope.
        // SwiftData may internally retain the first container, so this proves
        // saved data across containers in one process, not a process restart.
        let shoppingID: String = try autoreleasepool {
            let writer = try ModelContainer(for: PlatedStore.schema, configurations: [configuration])
            let writeContext = ModelContext(writer)
            writeContext.autosaveEnabled = false
            let recipe = Recipe(title: "Soup", servings: 2)
            let cook = HouseholdMember(name: "Sam", role: "partner", seat: .joined)
            writeContext.insert(recipe)
            writeContext.insert(cook)
            let meal = PlannedMeal(date: date, slot: .lunch, recipe: recipe, servings: 3, cook: cook)
            meal.authorID = "restart-planner"
            meal.notes = "Use yesterday’s soup"
            meal.cookedAt = date
            meal.cookReaction = 3
            meal.actualMinutes = 25
            writeContext.insert(meal)
            try writeContext.save()
            let shoppingID = try XCTUnwrap(meal.shoppingID)
            meal.select(.leftovers)
            try writeContext.save()
            return shoppingID
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))

        try autoreleasepool {
            let reopened = try ModelContainer(for: PlatedStore.schema, configurations: [configuration])
            let readContext = ModelContext(reopened)
            let rows = try readContext.fetch(FetchDescriptor<PlannedMeal>())
            XCTAssertEqual(rows.count, 1)
            let saved = try XCTUnwrap(rows.first)
            // SwiftData's in-memory PersistentIdentifier wrapper changes with
            // the store coordinator. The persisted shopping ID is the plan's
            // stable identity across launches and the household wire key.
            XCTAssertEqual(saved.shoppingID, shoppingID)
            XCTAssertEqual(saved.date, Calendar.current.startOfDay(for: date))
            XCTAssertEqual(saved.slotValue, .lunch)
            XCTAssertEqual(saved.title, "Leftovers")
            XCTAssertEqual(saved.authorID, "restart-planner")
            XCTAssertEqual(saved.servings, 3)
            XCTAssertEqual(saved.notes, "Use yesterday’s soup")
            XCTAssertTrue(saved.hasDish)
            XCTAssertTrue(saved.isLeftovers)
            XCTAssertFalse(saved.isCooked)
            XCTAssertNil(saved.recipe)
            XCTAssertNil(saved.cook)
            XCTAssertNil(saved.cookedAt)
            XCTAssertEqual(saved.cookReaction, 0)
            XCTAssertEqual(saved.actualMinutes, 0)
            XCTAssertTrue(saved.scaledIngredients.isEmpty)
        }
    }

    func testReplacingACompletedRecipeClearsCookingAndGroceriesWithoutDeletingTheRecipe() throws {
        let recipe = Recipe(title: "Chickpea stew", servings: 2)
        recipe.ingredients = [Ingredient(name: "Chickpeas", quantity: 2, unit: "cups")]
        let cook = HouseholdMember(name: "Sam", role: "partner", seat: .joined)
        context.insert(recipe)
        context.insert(cook)
        let meal = PlannedMeal(date: date, recipe: recipe, customTitle: "Stew night", servings: 6,
            cook: cook, tagline: "Make a double batch")
        meal.cookedAt = date
        meal.cookReaction = 3
        meal.actualMinutes = 42
        context.insert(meal)
        try context.save()
        let recipeID = recipe.persistentModelID
        XCTAssertEqual(meal.scaledIngredients.first?.quantity, 6)

        meal.select(.leftovers)
        try context.save()

        let reader = ModelContext(container)
        let saved = try XCTUnwrap(try reader.fetch(FetchDescriptor<PlannedMeal>()).first)
        XCTAssertNil(saved.recipe)
        XCTAssertNil(saved.cook)
        XCTAssertNil(saved.cookedAt)
        XCTAssertEqual(saved.cookReaction, 0)
        XCTAssertEqual(saved.actualMinutes, 0)
        XCTAssertFalse(saved.isCooked)
        XCTAssertTrue(saved.scaledIngredients.isEmpty, "Reheating must not add the original ingredients again")
        XCTAssertEqual(saved.servings, 6)
        let recipes = try reader.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(recipes.count, 1)
        XCTAssertEqual(recipes.first?.persistentModelID, recipeID)
        XCTAssertEqual(recipes.first?.ingredients?.first?.name, "Chickpeas")
        XCTAssertEqual(recipes.first?.ingredients?.first?.quantity, 2)
    }

    func testRestoringTheChoiceSnapshotRestoresRelationshipsAndCookMetadataWithoutRollingBackOtherDrafts() throws {
        let recipe = Recipe(title: "Lentil soup", servings: 2)
        recipe.ingredients = [Ingredient(name: "Lentils", quantity: 1, unit: "cup")]
        let cook = HouseholdMember(name: "Sam", role: "partner", seat: .joined)
        let gathering = Gathering(title: "Lunch with friends", startDate: date)
        context.insert(recipe)
        context.insert(cook)
        context.insert(gathering)
        let meal = PlannedMeal(date: date, slot: .lunch, recipe: recipe, customTitle: "Soup with friends",
            servings: 4, cook: cook, tagline: "Serve with bread")
        meal.authorID = "planner-id"
        meal.notes = "Leave out the chilli"
        meal.cookedAt = date.addingTimeInterval(-120)
        meal.cookReaction = 2
        meal.actualMinutes = 31
        meal.gathering = gathering
        context.insert(meal)
        try context.save()
        let id = meal.persistentModelID
        let shoppingID = meal.shoppingID
        let originalCreatedAt = meal.createdAt
        let previous = meal.select(.leftovers)

        // This represents another valuable editor sharing the context.
        // A failed meal save must not invoke a context-wide rollback.
        let unrelatedDraft = Recipe(title: "Unsaved bread draft")
        context.insert(unrelatedDraft)
        previous.restore(on: meal)
        XCTAssertTrue(meal.recipe === recipe)
        XCTAssertTrue(meal.cook === cook)
        XCTAssertTrue(meal.gathering === gathering)
        XCTAssertEqual(unrelatedDraft.title, "Unsaved bread draft")
        XCTAssertTrue(context.hasChanges)
        try context.save()

        let reader = ModelContext(container)
        let saved = try XCTUnwrap(try reader.fetch(FetchDescriptor<PlannedMeal>()).first)
        XCTAssertEqual(saved.persistentModelID, id)
        XCTAssertEqual(saved.shoppingID, shoppingID)
        XCTAssertEqual(saved.date, Calendar.current.startOfDay(for: date))
        XCTAssertEqual(saved.slotValue, .lunch)
        XCTAssertEqual(saved.authorID, "planner-id")
        XCTAssertEqual(saved.servings, 4)
        XCTAssertEqual(saved.notes, "Leave out the chilli")
        XCTAssertEqual(saved.createdAt, originalCreatedAt)
        XCTAssertEqual(saved.recipe?.persistentModelID, recipe.persistentModelID)
        XCTAssertEqual(saved.cook?.persistentModelID, cook.persistentModelID)
        XCTAssertEqual(saved.gathering?.persistentModelID, gathering.persistentModelID)
        XCTAssertEqual(saved.customTitle, "Soup with friends")
        XCTAssertEqual(saved.tagline, "Serve with bread")
        XCTAssertEqual(saved.cookedAt, date.addingTimeInterval(-120))
        XCTAssertEqual(saved.cookReaction, 2)
        XCTAssertEqual(saved.actualMinutes, 31)
        XCTAssertTrue(saved.isCooked)
        XCTAssertFalse(saved.isLeftovers)
        XCTAssertEqual(saved.scaledIngredients.first?.quantity, 2)
        XCTAssertTrue(try reader.fetch(FetchDescriptor<Recipe>()).contains { $0.title == "Unsaved bread draft" })
    }

    func testRecipeNamedLeftoversKeepsItsRecipeSemanticsAfterSaving() throws {
        let recipe = Recipe(title: "Leftovers")
        context.insert(recipe)
        let meal = PlannedMeal(date: date, recipe: recipe)
        meal.cookedAt = date
        context.insert(meal)
        try context.save()
        let reader = ModelContext(container)
        let saved = try XCTUnwrap(try reader.fetch(FetchDescriptor<PlannedMeal>()).first)
        XCTAssertEqual(saved.title, "Leftovers")
        XCTAssertFalse(saved.isLeftovers)
        XCTAssertTrue(saved.isCooked)
    }
}
