import XCTest
import SwiftData
@testable import Plated

@MainActor
final class UXRepairTests: XCTestCase {
    func testReplacementRollbackPreservesOriginalChildrenHistoryAndUnrelatedWork() throws {
        let container = try ModelContainer(for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = container.mainContext
        let recipe = Recipe(title: "Original", summary: "Family version", sourceURL: "https://example.com/original")
        recipe.sourceName = "Original author"; recipe.sourceText = "Original source"
        recipe.importMethod = "paste"; recipe.importedAt = Date(timeIntervalSince1970: 10)
        recipe.steps = ["Original method"]; recipe.cookNotes = "Keep this note"
        let ingredient = Ingredient(name: "Original flour", quantity: 2, unit: "cups")
        recipe.ingredients = [ingredient]
        let meal = PlannedMeal(date: .now, recipe: recipe)
        meal.cookedAt = Date(timeIntervalSince1970: 20)
        context.insert(recipe); context.insert(meal); try context.save()
        let originalID = ingredient.persistentModelID
        let snapshot = RecipeEditSnapshot(recipe)
        let unrelated = Recipe(title: "Unrelated unsaved draft")
        context.insert(unrelated)
        recipe.title = "Replacement"; recipe.sourceURL = "https://example.com/new"
        recipe.sourceName = "New author"; recipe.sourceText = "New source"; recipe.importMethod = "url"
        recipe.importedAt = .now; recipe.steps = ["New method"]
        recipe.ingredients = [Ingredient(name: "New rice", quantity: 1, unit: "cup")]
        // This is the same narrow recovery used after a rejected import commit.
        snapshot.restore(in: context)
        try context.save() // A later, unrelated save must not resurrect the discarded replacement.
        XCTAssertEqual(recipe.title, "Original")
        XCTAssertEqual(recipe.sourceURL, "https://example.com/original")
        XCTAssertEqual(recipe.sourceName, "Original author")
        XCTAssertEqual(recipe.sourceText, "Original source")
        XCTAssertEqual(recipe.importMethod, "paste")
        XCTAssertEqual(recipe.importedAt, Date(timeIntervalSince1970: 10))
        XCTAssertEqual(recipe.steps, ["Original method"])
        XCTAssertEqual(recipe.sortedIngredients.map(\.persistentModelID), [originalID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Ingredient>()).map(\.name), ["Original flour"])
        XCTAssertEqual(recipe.cookNotes, "Keep this note")
        XCTAssertEqual(recipe.timesCooked, 1)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Recipe>()).contains { $0 === unrelated })
    }

    func testCompletePhotoDraftRoundTripAndSeparateRecipeDraft() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = TableComposerDraft(title: "", caption: "", kind: "Dish", poll: [], pollEntry: "",
            tags: [], destination: "host-1", photo: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        let second = TableComposerDraft(title: "Soup", caption: "Dinner", kind: "Dish", poll: [], pollEntry: "",
            tags: ["Sam"], destination: "host-2", photo: nil)
        let normalURL = try TableComposerDraft.url(for: "table", directory: directory)
        let recipeURL = try TableComposerDraft.url(for: "recipe-test", directory: directory)
        try first.save(to: normalURL); try second.save(to: recipeURL)
        XCTAssertEqual(try TableComposerDraft.load(from: normalURL), first)
        XCTAssertEqual(try TableComposerDraft.load(from: recipeURL), second)
        XCTAssertThrowsError(try second.save(to: directory))
        XCTAssertEqual(try TableComposerDraft.load(from: normalURL), first, "A failed draft write must not destroy the existing photo draft")
    }

    func testFullRecipeExportIncludesLegacyMethodAndQuantities() {
        let recipe = Recipe(title: "Old family recipe", instructions: "Mix, then bake for 20 minutes.", servings: 6)
        recipe.ingredients = [Ingredient(name: "Flour", quantity: 2, unit: "cups")]
        let text = RecipeShare.text(for: recipe, includeSource: false)
        XCTAssertTrue(text.contains("serves 6"))
        XCTAssertTrue(text.contains("Flour"))
        XCTAssertTrue(text.contains("Mix, then bake for 20 minutes."))
    }

    func testSharedCookingContextSurvivesRelaunchAndOldSessionsRemainReadable() throws {
        let legacy = Data(#"{"startedAt":1791417600,"lastTouched":1791417660,"step":0,"stepCount":3}"#.utf8)
        var session = try JSONDecoder().decode(CookLedger.Session.self, from: legacy)
        XCTAssertNil(session.remotePlanID)
        session.remotePlanID = "plan-remote-night"
        let restored = try JSONDecoder().decode(CookLedger.Session.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored.remotePlanID, "plan-remote-night")
    }
}
