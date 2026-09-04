import Foundation
import SwiftData

/// Updates stable rows in place. Provenance and purchased quantities survive
/// reopening, meal moves, serving edits and the rolling shopping window.
struct GroceryListBuilder {
    let context: ModelContext

    @discardableResult
    func rebuild(weekOf date: Date, includePantryStaples: Bool = false) throws -> [GroceryItem] {
        let start = date.startOfDay
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        let meals = try context.fetch(FetchDescriptor<PlannedMeal>(predicate: #Predicate {
            $0.date >= start && $0.date < end && $0.cookedAt == nil
        }))
        for meal in meals where meal.shoppingID == nil { meal.shoppingID = UUID().uuidString }
        let lines = aggregate(meals: meals, includePantryStaples: includePantryStaples)
        let all = try context.fetch(FetchDescriptor<GroceryItem>())
        let autos = all.filter { !$0.isManual }
        var used = Set<PersistentIdentifier>()
        var result: [GroceryItem] = []
        for line in lines {
            let key = GroceryMeasure.key(line.name, line.unit)
            let candidates = autos.filter { GroceryMeasure.key($0.name, $0.unit) == key }
            let item = candidates.first(where: { $0.weekStart == start })
                ?? candidates.first(where: { $0.sources.contains { source in line.sources.contains { $0.id == source.id } } })
                ?? GroceryItem(name: line.name, weekStart: start)
            if item.modelContext == nil { context.insert(item) }
            used.insert(item.persistentModelID)
            var purchases: [String: Double] = [:]
            for previous in candidates {
                for (mealID, amount) in previous.purchases { purchases[mealID] = max(purchases[mealID] ?? 0, amount) }
            }
            // Migrate legacy checked rows only up to the amount actually
            // checked. Increasing servings must expose the extra quantity.
            if purchases.isEmpty, let old = candidates.first(where: { $0.isChecked && $0.sourcesData == nil }) {
                var available = GroceryMeasure.canonical(old.quantity, old.unit).quantity
                for source in line.sources {
                    purchases[source.id] = min(available, source.quantity)
                    available = max(0, available - source.quantity)
                }
            }
            item.name = line.name
            item.quantity = line.quantity
            item.unit = line.unit
            item.aisleValue = line.aisle
            item.weekStart = start
            item.sources = line.sources
            item.purchases = purchases
            item.originTitle = line.sources.map(\.title).joined(separator: ", ")
            item.isChecked = item.isPurchased()
            result.append(item)
        }
        // Retain rows in other date ranges: the user may be shopping ahead.
        for old in autos where old.weekStart == start && !used.contains(old.persistentModelID) { context.delete(old) }
        try context.save()
        return result
    }

    func aggregate(meals: [PlannedMeal], includePantryStaples: Bool) -> [AggregatedLine] {
        var lines: [String: AggregatedLine] = [:]
        for meal in meals.sorted(by: { $0.date < $1.date }) {
            guard let mealID = meal.shoppingID else { continue }
            for (ingredient, quantity) in meal.scaledIngredients {
                if ingredient.isPantryStaple && !includePantryStaples { continue }
                guard !ingredient.normalizedName.isEmpty else { continue }
                let amount = GroceryMeasure.canonical(quantity, ingredient.unit)
                let key = GroceryMeasure.key(ingredient.normalizedName, amount.unit)
                var line = lines[key] ?? AggregatedLine(name: ingredient.name, quantity: 0, unit: amount.unit, aisle: ingredient.aisleValue)
                line.quantity += amount.quantity
                if let index = line.sources.firstIndex(where: { $0.id == mealID }) {
                    line.sources[index].quantity += amount.quantity
                } else {
                    line.sources.append(.init(id: mealID, title: meal.title, date: meal.date, quantity: amount.quantity))
                }
                lines[key] = line
            }
        }
        return lines.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    struct AggregatedLine {
        var name: String
        var quantity: Double
        var unit: String
        var aisle: GroceryAisle
        var sources: [GrocerySource] = []
        var origin: String { sources.map(\.title).joined(separator: ", ") }
    }
}
