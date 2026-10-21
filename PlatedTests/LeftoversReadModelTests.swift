import XCTest
import SwiftData
@testable import Plated

/// A legacy freeform row may still carry cookedAt or a cook. Choosing
/// leftovers now clears them, but read models must not award a fresh cook
/// for an older row or a delayed shared echo either.
@MainActor
final class LeftoversReadModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let now = Date(timeIntervalSince1970: 1_792_512_000)

    override func setUp() async throws {
        container = try ModelContainer(for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }

    override func tearDown() async throws { container = nil }

    private func leftovers(cook: HouseholdMember? = nil) -> PlannedMeal {
        let meal = PlannedMeal(date: now, customTitle: "Leftovers", cook: cook)
        meal.cookedAt = now
        context.insert(meal)
        return meal
    }

    private func sharedLeftovers() -> PlanLedger.Entry {
        var remote = TableShare.RemotePlan()
        remote.shoppingID = "leftovers-read-model-test"
        remote.recordName = "plan-" + remote.shoppingID
        remote.day = PlanDay.string(now)
        remote.slot = MealSlot.dinner.rawValue
        remote.title = "Leftovers"
        remote.hasRecipe = false
        remote.cooked = true
        remote.cookedAt = now
        remote.cookID = "sam-id"
        remote.cookName = "Sam"
        return PlanLedger.Entry(remote)
    }

    func testLocalAndSharedLeftoversNeverIncreaseFreshCookingOrEatingOutHistory() {
        let meal = leftovers()
        let history = PlanDinnerHistory(local: [meal], shared: [sharedLeftovers()], now: now)
        XCTAssertEqual(history.cooked, 0)
        XCTAssertEqual(history.eatingOut, 0)
        XCTAssertTrue(meal.hasDish, "Leftovers still fill the selected night")
        XCTAssertNotNil(meal.cookedAt, "A read model must not migrate or rewrite the stored row")
    }

    func testLeftoversDoNotCreditAnOldAssignedCookOrGenerateCookedActivity() {
        let sam = HouseholdMember(name: "Sam", role: "partner", seat: .joined)
        sam.userRecordName = "sam-id"
        context.insert(sam)
        let meal = leftovers(cook: sam)
        let activity = MemberDinnerActivity(member: sam, roster: [sam], meals: [meal],
            remote: [sharedLeftovers()], posts: [], now: now)
        XCTAssertEqual(activity.cooked, 0)
        XCTAssertNil(activity.latest)
    }

    func testInsightsAndAwardsKeepLeftoversPlannedWithoutCountingAnotherCook() {
        let meal = leftovers()
        let insights = MealInsights(meals: [meal], recipes: [])
        XCTAssertTrue(insights.cookedMeals().isEmpty)
        XCTAssertTrue(insights.frequencies().isEmpty)
        XCTAssertEqual(insights.varietyCount(), 0)
        XCTAssertTrue(insights.countsBySlot().allSatisfy { $0.count == 0 })
        let metrics = Awards.metrics(for: nil, meals: [meal], recipes: [], posts: [], householdSize: 1)
        XCTAssertEqual(metrics.cookedMeals, 0)
        XCTAssertEqual(metrics.distinctDishesCooked, 0)
        XCTAssertEqual(metrics.activeCookWeeks, 0)
        XCTAssertEqual(metrics.fullestPlannedWeek, 1, "Leftovers are still a deliberate meal plan")
    }

    func testARecipeCalledLeftoversCanStillBeCookedAndCounted() {
        let meal = leftovers()
        let recipe = Recipe(title: "Leftovers")
        context.insert(recipe)
        meal.recipe = recipe
        let history = PlanDinnerHistory(local: [meal], shared: [], now: now)
        XCTAssertEqual(history.cooked, 1)
        XCTAssertEqual(MealInsights(meals: [meal], recipes: [recipe]).cookedMeals().count, 1)
        XCTAssertEqual(Awards.metrics(for: nil, meals: [meal], recipes: [recipe], posts: [],
            householdSize: 1).cookedMeals, 1)
        var remote = sharedLeftovers()
        remote.hasRecipe = true
        XCTAssertEqual(PlanDinnerHistory(local: [], shared: [remote], now: now).cooked, 1)
    }
}
