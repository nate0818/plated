#if DEBUG
import Foundation
import SwiftData

@MainActor
enum PlannerDragChecks {
    struct Failure: Error, CustomStringConvertible { let description: String }

    /// Called only inside the explicit in-memory design-review branch.
    static func prepareReview(in context: ModelContext) {
        guard let recipes = try? context.fetch(FetchDescriptor<Recipe>()),
              let recipe = recipes.first(where: { $0.title == "Pancake Dinner" }) else { return }
        recipe.steps = ["Prep the vegetables.", "Heat the pan.", "Plate and serve."]
        for meal in (try? context.fetch(FetchDescriptor<PlannedMeal>())) ?? [] { context.delete(meal) }
        let today = Date.now.startOfDay
        context.insert(PlannedMeal(date: today, recipe: recipe, customTitle: "Drag test dinner"))
        context.insert(PlannedMeal(date: Calendar.current.date(byAdding: .day, value: 1, to: today)!, recipe: recipe, customTitle: "Second dinner"))
        context.insert(PlannedMeal(date: today, slot: .breakfast, recipe: recipe, customTitle: "Morning pancakes"))
        try? context.save()
    }

    static func run() throws {
        let config = ModelConfiguration(schema: PlatedStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: PlatedStore.schema, configurations: [config])
        let context = container.mainContext
        func day(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: Date.now.startOfDay)! }
        var count = 0
        func expect(_ value: Bool, _ message: String) throws {
            guard value else { throw Failure(description: message) }
            count += 1
            print("PLATED DRAG CHECK: PASS \(message)")
        }
        let recipe = Recipe(title: "Dinner")
        let cook = HouseholdMember(name: "Cook")
        let first = PlannedMeal(date: day(0), recipe: recipe, servings: 6, cook: cook)
        let second = PlannedMeal(date: day(1), customTitle: "Other dinner")
        let breakfast = PlannedMeal(date: day(0), slot: .breakfast, recipe: recipe)
        context.insert(recipe); context.insert(cook)
        [first, second, breakfast].forEach { context.insert($0) }
        try context.save()
        let all = [first, second, breakfast], id = first.shoppingID, token = MealPlanTransfer.token(for: first)
        try expect(MealPlanMove.perform(token, to: day(1), meals: all, context: context), "Drop onto an occupied date succeeds")
        try expect(first.date == day(1) && second.date == day(0), "Occupied dinner slots swap without losing a meal")
        try expect(first.shoppingID == id && first.recipe === recipe && first.cook === cook && first.servings == 6, "Moving preserves recipe, cook, servings and grocery identity")
        try expect(MealPlanMove.perform(MealPlanTransfer.token(for: breakfast), to: day(1), meals: all, context: context) && first.date == day(1), "A breakfast move never replaces dinner")
        first.date = day(2)
        try expect(MealPlanMove.perform(token, to: day(3), meals: all, context: context) && first.date == day(3), "A payload follows the original meal after another date change")
        try expect(!MealPlanMove.perform(token, to: day(-1), meals: all, context: context) && first.date == day(3), "Past destinations are rejected")
        second.cookedAt = .now
        try expect(!MealPlanMove.perform(token, to: second.date, meals: all, context: context), "Cooked occupants are protected")
        first.cookedAt = .now
        try expect(!MealPlanMove.perform(token, to: day(4), meals: all, context: context), "Cooked sources are protected")
        try expect(!MealPlanMove.perform("unrelated text", to: day(4), meals: all, context: context), "Unrelated drag payloads cannot change the plan")
        print("PLATED DRAG CHECKS: \(count) passed")
    }
}
#endif
