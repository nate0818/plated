import XCTest
import SwiftData
@testable import Plated

@MainActor
final class PlanDinnerHistoryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var now: Date { Calendar.current.startOfDay(for: .now).addingTimeInterval(12 * 3600) }

    override func setUp() async throws {
        container = try ModelContainer(for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }
    override func tearDown() async throws { container = nil }

    private func meal(_ offset: Int, title: String = "Dinner", cooked: Bool = false, slot: MealSlot = .dinner) -> PlannedMeal {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: now)!
        let meal = PlannedMeal(date: date, slot: slot, customTitle: title)
        if cooked { meal.cookedAt = date }
        context.insert(meal)
        return meal
    }

    private func shared(_ offset: Int, id: String = UUID().uuidString, title: String = "Dinner", cooked: Bool = false) -> PlanLedger.Entry {
        var remote = TableShare.RemotePlan()
        remote.shoppingID = id; remote.recordName = "plan-" + id
        remote.day = PlanDay.string(Calendar.current.date(byAdding: .day, value: offset, to: now)!)
        remote.slot = MealSlot.dinner.rawValue; remote.title = title
        remote.cooked = cooked; remote.hasRecipe = false
        return PlanLedger.Entry(remote)
    }

    func testOnlyCompletedDinnersAndMarkedEatingOutWithinSevenCalendarDaysCount() {
        let local = [meal(-6, cooked: true), meal(0, cooked: true), meal(-2),
                     meal(-7, cooked: true), meal(1, cooked: true),
                     meal(-1, cooked: true, slot: .breakfast),
                     meal(-3, title: "Eating out"), meal(1, title: "Eating out"),
                     meal(-8, title: "Eating out"), meal(0, title: "Eating out", cooked: true)]
        let history = PlanDinnerHistory(local: local, shared: [], now: now)
        XCTAssertEqual(history.cooked, 2, "Scheduled and eating-out meals must not inflate cooking")
        XCTAssertEqual(history.eatingOut, 2, "Future or older plans are not recent history")
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: history.start, to: history.end).day, 6)
    }

    func testSharedDinnerIsCountedOnceAndLocalCompletionTakesPrecedenceOverStaleEcho() {
        let local = meal(-1, cooked: true)
        let echo = shared(-1, id: local.shoppingID!, cooked: false)
        let remote = shared(-2, cooked: true)
        let outside = shared(-3, title: "Eating out")
        let history = PlanDinnerHistory(local: [local], shared: [echo, remote, outside], now: now)
        XCTAssertEqual(history.cooked, 2)
        XCTAssertEqual(history.eatingOut, 1)
    }

    func testUncompletedLocalEchoDoesNotResurrectSharedCompletion() {
        let local = meal(-1)
        let history = PlanDinnerHistory(local: [local], shared: [shared(-1, id: local.shoppingID!, cooked: true)], now: now)
        XCTAssertEqual(history.cooked, 0)
    }

    func testPendingRemovalInvalidDatesAndOtherMealSlotsAreExcluded() {
        var removing = shared(-1, cooked: true)
        removing.pendingSince = now; removing.pendingRemoval = true
        var invalid = shared(-1, cooked: true); invalid.day = "invalid"
        var lunch = shared(-1, title: "Eating out"); lunch.slot = MealSlot.lunch.rawValue
        let history = PlanDinnerHistory(local: [], shared: [removing, invalid, lunch, shared(1, title: "Eating out")], now: now)
        XCTAssertEqual(history.cooked, 0); XCTAssertEqual(history.eatingOut, 0)
    }

    func testRecipeNamedEatingOutIsNotMistakenForRestaurantLog() {
        let dinner = meal(-1, title: "Eating out at home", cooked: true)
        let recipe = Recipe(title: "Eating out at home"); context.insert(recipe); dinner.recipe = recipe
        let history = PlanDinnerHistory(local: [dinner], shared: [], now: now)
        XCTAssertEqual(history.cooked, 1); XCTAssertEqual(history.eatingOut, 0)
    }
}
