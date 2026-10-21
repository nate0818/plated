import XCTest
import SwiftData
@testable import Plated

/// Explicit adoption is the only path from a household version back into
/// its author's private meal. No live CloudKit operations are used here.
@MainActor
final class HouseholdEditsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try ModelContainer(for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        HouseholdEdits.clear()
    }

    override func tearDown() async throws {
        HouseholdEdits.clear()
        container = nil
    }

    private func recipe(_ title: String, key: String) -> Recipe {
        let recipe = Recipe(title: title)
        recipe.originID = key
        context.insert(recipe)
        return recipe
    }

    private func cook(_ name: String = "Sam", id: String = "sam") -> HouseholdMember {
        let member = HouseholdMember(name: name, seat: .joined)
        member.userRecordName = id
        context.insert(member)
        return member
    }

    private func dinner(recipe: Recipe? = nil) -> PlannedMeal {
        let meal = PlannedMeal(date: .now, recipe: recipe, customTitle: recipe == nil ? "Tacos" : "", servings: 6, cook: cook())
        meal.shoppingID = UUID().uuidString
        meal.authorID = "original-author"
        meal.notes = "Keep this private note"
        meal.tagline = "Original tagline"
        meal.cookedAt = .now
        meal.cookReaction = 3
        meal.actualMinutes = 42
        context.insert(meal)
        return meal
    }

    private func change(_ meal: PlannedMeal, title: String = "Leftovers",
                        hasRecipe: Bool? = false, origin: String = "",
                        cookID: String = "") -> HouseholdEdits.Change {
        .init(shoppingID: meal.shoppingID!, recordName: "plan-" + meal.shoppingID!,
              title: title, cookID: cookID, cookName: "Sam", servings: meal.servings,
              day: PlanDay.string(meal.date), slot: meal.slot,
              recipeOriginKey: origin, hasRecipe: hasRecipe,
              tagline: "Already made. Dinner is taken care of.",
              cooked: false, by: "Riley", at: .now)
    }

    func testAdoptingLeftoversNeverGuessesMatchingRecipeAndClearsCookingMetadata() throws {
        let original = recipe("Tacos", key: "tacos")
        for offset in 1...4 {
            let past = PlannedMeal(date: Calendar.current.date(byAdding: .day, value: -offset, to: .now)!, recipe: original)
            past.cookedAt = past.date
            context.insert(past)
        }
        _ = recipe("Leftovers", key: "actual-leftovers-recipe")
        let meal = dinner(recipe: original)
        let id = meal.shoppingID
        let created = meal.createdAt
        let date = meal.date
        var update = change(meal, cookID: "sam")
        // Contradictory old fields cannot turn the explicit non-recipe
        // leftovers choice back into a cooking accomplishment.
        update.cooked = true
        update.cookedAt = .now
        XCTAssertTrue(HouseholdEdits.adopt(update, in: context))
        try context.save()
        XCTAssertEqual(meal.title, "Leftovers")
        XCTAssertNil(meal.recipe)
        XCTAssertNil(meal.cook)
        XCTAssertNil(meal.cookedAt)
        XCTAssertEqual(meal.cookReaction, 0)
        XCTAssertEqual(meal.actualMinutes, 0)
        XCTAssertEqual(meal.tagline, update.tagline)
        XCTAssertEqual(meal.shoppingID, id)
        XCTAssertEqual(meal.date, date)
        XCTAssertEqual(meal.createdAt, created)
        XCTAssertEqual(meal.servings, 6)
        XCTAssertEqual(meal.authorID, "original-author")
        XCTAssertEqual(meal.notes, "Keep this private note")
        XCTAssertEqual(original.timesCooked, 4, "A choice for tonight must not erase the original recipe's real history")
    }

    func testExplicitNoRecipeDetachesEvenWhenTheOldRecipeHasTheSameTitle() {
        let meal = dinner(recipe: recipe("Leftovers", key: "recipe-leftovers"))
        XCTAssertTrue(HouseholdEdits.adopt(change(meal), in: context))
        XCTAssertNil(meal.recipe)
        XCTAssertNil(meal.cook)
    }

    func testRecipeIdentityWinsOverSameTitleAndWorksFromAFormerLeftoversNight() {
        let wrong = recipe("Soup", key: "wrong-soup")
        let intended = recipe("Soup", key: "intended-soup")
        let meal = dinner(recipe: wrong)
        meal.customTitle = "Soup"
        XCTAssertTrue(HouseholdEdits.adopt(change(meal, title: "Soup", hasRecipe: true,
                                                origin: intended.planningKey), in: context))
        XCTAssertTrue(meal.recipe === intended)
        meal.recipe = nil
        meal.customTitle = "Leftovers"
        XCTAssertTrue(HouseholdEdits.adopt(change(meal, title: "Soup", hasRecipe: true,
                                                origin: intended.planningKey), in: context))
        XCTAssertTrue(meal.recipe === intended)
    }

    func testMissingExplicitRecipeIdentityDoesNotAttachASameNamedDifferentRecipe() {
        let meal = dinner(recipe: recipe("Tacos", key: "old"))
        _ = recipe("Soup", key: "not-the-requested-soup")
        XCTAssertTrue(HouseholdEdits.adopt(change(meal, title: "Soup", hasRecipe: true,
                                                origin: "unavailable-origin"), in: context))
        XCTAssertNil(meal.recipe)
        XCTAssertEqual(meal.title, "Soup")
    }

    func testRecipeWithoutOriginUsesOnlyAnUnambiguousTitle() {
        let intended = recipe("Soup", key: "soup")
        let meal = dinner()
        XCTAssertTrue(HouseholdEdits.adopt(change(meal, title: "Soup", hasRecipe: true), in: context))
        XCTAssertTrue(meal.recipe === intended)
        _ = recipe("Soup", key: "another-soup")
        XCTAssertTrue(HouseholdEdits.adopt(change(meal, title: "Soup", hasRecipe: true), in: context))
        XCTAssertNil(meal.recipe, "Duplicate names do not identify the recipe the household chose")
    }

    func testLegacyChangeWithoutRecipeEvidenceKeepsTheOwnersAttachedRecipe() {
        let original = recipe("Tacos", key: "tacos")
        let meal = dinner(recipe: original)
        var update = change(meal, hasRecipe: nil)
        update.tagline = nil
        XCTAssertTrue(HouseholdEdits.adopt(update, in: context))
        XCTAssertTrue(meal.recipe === original, "A name alone cannot prove that an old saved change removed the recipe")
        XCTAssertEqual(meal.tagline, "Original tagline")
    }

    func testLegacyChangeCanUseItsExplicitRecipeOrigin() {
        let intended = recipe("Soup", key: "soup")
        let meal = dinner()
        XCTAssertTrue(HouseholdEdits.adopt(change(meal, title: "Soup", hasRecipe: nil,
                                                origin: intended.planningKey), in: context))
        XCTAssertTrue(meal.recipe === intended)
    }

    func testExplicitUnassignmentClearsCookWhileAnUnknownIdentityPreservesTheCurrentChoice() {
        let meal = dinner()
        let originalCook = meal.cook
        var update = change(meal, title: meal.title, hasRecipe: nil, cookID: "not-in-the-roster")
        XCTAssertTrue(HouseholdEdits.adopt(update, in: context))
        XCTAssertTrue(meal.cook === originalCook)
        update.cookID = ""
        XCTAssertTrue(HouseholdEdits.adopt(update, in: context))
        XCTAssertNil(meal.cook)
    }

    func testKnownCookIdentityStillAssignsTheRequestedMember() {
        let meal = dinner()
        let intended = cook("Riley", id: "riley")
        XCTAssertTrue(HouseholdEdits.adopt(change(meal, title: meal.title, hasRecipe: nil,
                                                cookID: "riley"), in: context))
        XCTAssertTrue(meal.cook === intended)
    }

    private func entry(for meal: PlannedMeal, hasRecipe: Bool = false, origin: String = "") -> PlanLedger.Entry {
        var remote = TableShare.RemotePlan()
        remote.recordName = "plan-" + meal.shoppingID!
        remote.shoppingID = meal.shoppingID!
        remote.day = PlanDay.string(meal.date)
        remote.slot = meal.slot
        remote.title = "Leftovers"
        remote.servings = meal.servings
        remote.hasRecipe = hasRecipe
        remote.recipeOriginKey = origin
        remote.tagline = "Already made. Dinner is taken care of."
        remote.editorName = "Riley"
        remote.cooked = false
        return PlanLedger.Entry(remote)
    }

    func testNotingAChangeCarriesRecipeEvidenceButDoesNotMutateThePrivateMeal() throws {
        let original = recipe("Tacos", key: "tacos")
        let meal = dinner(recipe: original)
        HouseholdEdits.note([entry(for: meal)])
        let pending = try XCTUnwrap(HouseholdEdits.pending(shoppingID: meal.shoppingID!))
        XCTAssertEqual(pending.hasRecipe, false)
        XCTAssertEqual(pending.tagline, "Already made. Dinner is taken care of.")
        XCTAssertEqual(meal.title, "Tacos")
        XCTAssertTrue(meal.recipe === original)
        XCTAssertNotNil(meal.cook)
        XCTAssertNotNil(meal.cookedAt)
    }

    func testSettledDecisionIsRepeatedOnlyForChangedRecipeEvidence() throws {
        let meal = dinner()
        let first = entry(for: meal)
        HouseholdEdits.note([first])
        HouseholdEdits.settle(meal.shoppingID!)
        HouseholdEdits.note([first])
        XCTAssertNil(HouseholdEdits.pending(shoppingID: meal.shoppingID!))
        var different = first
        different.hasRecipe = true
        different.recipeOriginKey = "real-recipe-leftovers"
        HouseholdEdits.note([different])
        let pending = try XCTUnwrap(HouseholdEdits.pending(shoppingID: meal.shoppingID!))
        XCTAssertEqual(pending.hasRecipe, true)
        XCTAssertEqual(pending.recipeOriginKey, different.recipeOriginKey)
    }

    func testLegacyDecisionIsNotReopenedJustBecauseRecipePresenceWasLearned() {
        let meal = dinner()
        let current = entry(for: meal)
        var old = change(meal, hasRecipe: nil)
        old.tagline = nil
        old.settled = true
        XCTAssertTrue(old.answers(current), "An upgrade must not silently overturn an answer to the same household facts")
        old.recipeOriginKey = "different-recipe"
        XCTAssertFalse(old.answers(current), "A changed recipe identity is a different household choice")
    }

    func testOlderSavedChangesDecodeWithoutNewPresenceAndTaglineFields() throws {
        let meal = dinner()
        let update = change(meal)
        let encoded = try JSONEncoder().encode(update)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "hasRecipe")
        object.removeValue(forKey: "tagline")
        let old = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(HouseholdEdits.Change.self, from: old)
        XCTAssertNil(decoded.hasRecipe)
        XCTAssertNil(decoded.tagline)
        XCTAssertEqual(decoded.shoppingID, update.shoppingID)
        XCTAssertEqual(decoded.title, update.title)
        XCTAssertEqual(decoded.cookID, update.cookID)
    }

    func testUnavailableRecipeNamedLeftoversDoesNotBecomeANonCookingChoiceAndCanBeRetried() throws {
        let original = recipe("Tacos", key: "tacos")
        let meal = dinner(recipe: original)
        let originalCook = meal.cook
        let originalCookedAt = meal.cookedAt
        // A different recipe with the requested title is not a match for
        // the explicit identity carried by the household's change.
        _ = recipe("Leftovers", key: "different-recipe")
        HouseholdEdits.note([entry(for: meal, hasRecipe: true, origin: "missing-leftovers-recipe")])
        let pending = try XCTUnwrap(HouseholdEdits.pending(shoppingID: meal.shoppingID!))
        let result = HouseholdEdits.adoptResult(pending, in: context)
        guard case .unavailable(let message) = result else {
            return XCTFail("An unresolved explicit recipe must remain available for retry")
        }
        XCTAssertTrue(message.contains("recipe"))
        XCTAssertTrue(message.contains("Refresh"))
        XCTAssertTrue(meal.recipe === original)
        XCTAssertEqual(meal.title, "Tacos")
        XCTAssertFalse(meal.isLeftovers)
        XCTAssertTrue(meal.cook === originalCook)
        XCTAssertEqual(meal.cookedAt, originalCookedAt)
        XCTAssertEqual(meal.cookReaction, 3)
        XCTAssertEqual(meal.actualMinutes, 42)
        XCTAssertNotNil(HouseholdEdits.pending(shoppingID: meal.shoppingID!))

        let intended = recipe("Leftovers", key: "missing-leftovers-recipe")
        XCTAssertEqual(HouseholdEdits.adoptResult(pending, in: context), .adopted)
        XCTAssertTrue(meal.recipe === intended)
        XCTAssertEqual(meal.title, "Leftovers")
        XCTAssertFalse(meal.isLeftovers, "A resolved recipe retains its recipe meaning")
        XCTAssertNil(HouseholdEdits.pending(shoppingID: meal.shoppingID!))
    }

    func testExplicitRecipeNamedLeftoversWithoutAnOriginAlsoWaitsWhenNoRecipeMatches() {
        let original = recipe("Tacos", key: "tacos")
        let meal = dinner(recipe: original)
        let update = change(meal, hasRecipe: true)
        XCTAssertFalse(HouseholdEdits.adopt(update, in: context))
        XCTAssertTrue(meal.recipe === original)
        XCTAssertEqual(meal.title, "Tacos")
        XCTAssertFalse(meal.isLeftovers)
    }

    func testCallerCanKeepAdoptionPendingUntilItsModelSaveSucceeds() throws {
        let meal = dinner(recipe: recipe("Tacos", key: "tacos"))
        HouseholdEdits.note([entry(for: meal)])
        let pending = try XCTUnwrap(HouseholdEdits.pending(shoppingID: meal.shoppingID!))
        XCTAssertEqual(HouseholdEdits.adoptResult(pending, in: context, settleOnSuccess: false), .adopted)
        XCTAssertTrue(meal.isLeftovers)
        XCTAssertNotNil(HouseholdEdits.pending(shoppingID: meal.shoppingID!),
                        "The caller may still need to restore the model if saving fails")
        try context.save()
        HouseholdEdits.settle(meal.shoppingID!)
        XCTAssertNil(HouseholdEdits.pending(shoppingID: meal.shoppingID!))
    }
}
