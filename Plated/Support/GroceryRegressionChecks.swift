#if DEBUG
import Foundation
import SwiftData

/// Run with -plated-test-groceries. A separate, memory-only store exercises the
/// actual builder and models without touching household data or CloudKit.
@MainActor
enum GroceryRegressionChecks {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static func run() throws {
        let config = ModelConfiguration(schema: PlatedStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: PlatedStore.schema, configurations: [config])
        let context = container.mainContext
        // The store is memory-only but the marks book is real app-group
        // state, so a previous run's check-offs would fold into this run's
        // rows and every mark recorded here would queue for the household.
        // Cleared on both sides.
        GroceryMarks.shared.clear()
        HouseholdOutbox.shared.clear()
        defer {
            GroceryMarks.shared.clear()
            HouseholdOutbox.shared.clear()
        }
        let start = Date.now.startOfDay
        func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: start)! }
        var count = 0
        func expect(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Failure(description: name) }
            count += 1
            print("PLATED GROCERY CHECK: PASS \(name)")
        }
        let recipe = Recipe(title: "Rice bowls", servings: 2)
        recipe.ingredients = [Ingredient(name: "Rice", quantity: 100, unit: "g", aisle: .pantry)]
        context.insert(recipe)
        let first = PlannedMeal(date: day(0), recipe: recipe, servings: 2)
        let second = PlannedMeal(date: day(1), recipe: recipe, servings: 4)
        context.insert(first)
        context.insert(second)
        let manual = GroceryItem(name: "Dish soap", weekStart: start, isManual: true)
        context.insert(manual)
        let builder = GroceryListBuilder(context: context)
        let row = try builder.rebuild(weekOf: start).first!
        let rowID = row.persistentModelID
        let firstID = first.shoppingID!
        let firstScope: Set<String> = [firstID]
        let ounce = GroceryMeasure.canonical(100, "g").quantity
        try expect(row.sources.count == 2 && abs(row.quantity - ounce * 3) < 0.000001, "Combines shared ingredients with both meal sources")
        row.setPurchased(true, for: firstScope)
        try expect(row.isPurchased(for: firstScope) && !row.isPurchased() && abs(row.outstanding() - ounce * 2) < 0.000001, "Checking one meal leaves the other meal to buy")
        let rebuilt = try builder.rebuild(weekOf: start).first!
        try expect(rebuilt.persistentModelID == rowID && rebuilt.isPurchased(for: firstScope), "Reopening preserves row identity and purchased portions")
        first.servings = 4
        _ = try builder.rebuild(weekOf: start)
        try expect(!row.isPurchased(for: firstScope) && abs(row.outstanding(for: firstScope) - ounce) < 0.000001, "Increasing servings exposes only the additional amount")
        let beforeCheck = row.purchasesData
        row.setPurchased(true)
        // The sheet's undo path: restore, then record the restored value as
        // the newest mark, or the check it took back wins on the next open.
        row.purchasesData = beforeCheck
        row.isChecked = row.isPurchased()
        row.recordMark()
        try expect(abs(row.outstanding() - ounce * 3) < 0.000001, "Undo restores purchased quantities")
        _ = try builder.rebuild(weekOf: start)
        try expect(abs(row.outstanding() - ounce * 3) < 0.000001, "Reopening after an undo keeps the undone check undone")
        try expect(GroceryMarks.shared.mark(for: row.lineKey)?.purchases == row.purchases, "A check-off is recorded as the line's mark")
        row.isDismissed = true
        row.recordMark()
        _ = try builder.rebuild(weekOf: start)
        try expect(row.isDismissed && GroceryMarks.shared.mark(for: row.lineKey)?.dismissedUntil == row.windowEnd, "A struck line stays struck when the list is rebuilt")
        row.setPurchased(true)
        first.date = day(8)
        let ahead = try builder.rebuild(weekOf: day(8)).first!
        try expect(ahead.isPurchased(for: firstScope) && ahead.sources.first?.date == day(8), "Moving a meal keeps its purchases and updates its date")
        try expect(!ahead.isDismissed, "A dismissal lapses with the window it was made in")
        let current = try builder.rebuild(weekOf: start).first!
        try expect(current.isPurchased() && current.sources.count == 1, "Returning to the current window retains the remaining meal's purchases")
        let all = try context.fetch(FetchDescriptor<GroceryItem>())
        try expect(all.contains { $0.persistentModelID == manual.persistentModelID }, "Rebuilding preserves manually added groceries")
        let legacyRecipe = Recipe(title: "Lentils", servings: 2)
        legacyRecipe.ingredients = [Ingredient(name: "Lentils", quantity: 200, unit: "g", aisle: .pantry)]
        context.insert(legacyRecipe)
        context.insert(PlannedMeal(date: start, recipe: legacyRecipe, servings: 2))
        let legacy = GroceryItem(name: "Lentils", quantity: 100, unit: "g", weekStart: start)
        legacy.isChecked = true
        context.insert(legacy)
        let migrated = try builder.rebuild(weekOf: start).first { $0.name == "Lentils" }!
        try expect(!migrated.isPurchased() && abs(migrated.outstanding() - ounce) < 0.000001, "Legacy checkmarks never cover an increased quantity")
        let mass = GroceryMeasure.shopping(500, "g")
        try expect(mass.unit == "lb" && mass.quantity * 16 >= GroceryMeasure.canonical(500, "g").quantity, "Shopping converts grams to a sufficient buying amount")
        try expect(GroceryMeasure.shopping(100, "ml").text == "3½ fl oz", "Fluid ounces remain correctly abbreviated")
        let unmeasured = GroceryItem(name: "Salt")
        unmeasured.sources = [.init(id: "salt", title: "Soup", date: start, quantity: 0)]
        try expect(!unmeasured.isPurchased(), "Unmeasured ingredients start unchecked")
        unmeasured.setPurchased(true)
        try expect(unmeasured.isPurchased(), "Unmeasured ingredients can be checked off")
        // A solo phone has no household zone, so a queued mark would answer
        // .retry forever and be paid for on every launch. The mark is still
        // in the book; publishAll queues the book when sharing begins.
        HouseholdOutbox.shared.clear()
        row.setPurchased(true)
        let queued = HouseholdOutbox.shared.hasPending(GroceryMarks.recordName(for: row.lineKey))
        let shared = HouseholdShare.membership != .solo
        try expect(queued == shared, "A check-off queues for the household only once there is one")
        try expect(GroceryMarks.shared.mark(for: row.lineKey) != nil, "A check-off is written to the book either way")
        print("PLATED GROCERY CHECKS: \(count) passed")
    }
}
#endif
