import Foundation
import SwiftData

/// Rolls the week's planned meals up into a consolidated shopping list.
///
/// Merging rule: same ingredient name + same unit collapses into one line with
/// summed quantities. Different units stay separate lines rather than guessing
/// at conversions — "2 cups rice" and "1 lb rice" are genuinely different asks.
struct GroceryListBuilder {
    let context: ModelContext

    /// Regenerates the auto-derived portion of the list for the week containing
    /// `date`. Hand-added lines and existing checkmarks survive.
    @discardableResult
    func rebuild(weekOf date: Date, includePantryStaples: Bool = false) throws -> [GroceryItem] {
        let weekStart = Calendar.current.startOfWeek(for: date)
        guard let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) else {
            return []
        }

        // Only meals not yet cooked — no shopping for dinners already eaten.
        let mealPredicate = #Predicate<PlannedMeal> { meal in
            meal.date >= weekStart && meal.date < weekEnd && meal.cookedAt == nil
        }
        let meals = try context.fetch(FetchDescriptor(predicate: mealPredicate))

        let aggregated = aggregate(meals: meals, includePantryStaples: includePantryStaples)

        let existing = try context.fetch(
            FetchDescriptor<GroceryItem>(
                predicate: #Predicate { $0.weekStart == weekStart }
            )
        )

        // Preserve what people checked off so a rebuild mid-shop is not destructive.
        let checkedNames = Set(existing.filter(\.isChecked).map { Self.key(name: $0.name, unit: $0.unit) })

        for item in existing where !item.isManual {
            context.delete(item)
        }

        var created: [GroceryItem] = []
        for line in aggregated {
            let item = GroceryItem(
                name: line.name,
                quantity: line.quantity,
                unit: line.unit,
                aisle: line.aisle,
                weekStart: weekStart
            )
            item.isChecked = checkedNames.contains(Self.key(name: line.name, unit: line.unit))
            item.originTitle = line.origin
            context.insert(item)
            created.append(item)
        }

        return created
    }

    /// Pure aggregation, split out so it can be exercised without a store.
    func aggregate(meals: [PlannedMeal], includePantryStaples: Bool) -> [AggregatedLine] {
        var lines: [String: AggregatedLine] = [:]

        for meal in meals {
            for (ingredient, quantity) in meal.scaledIngredients {
                if ingredient.isPantryStaple && !includePantryStaples { continue }
                guard !ingredient.normalizedName.isEmpty else { continue }

                let key = Self.key(name: ingredient.normalizedName, unit: ingredient.unit)
                if var existing = lines[key] {
                    existing.quantity += quantity
                    if existing.origin != meal.title { existing.origin = "Several recipes" }
                    lines[key] = existing
                } else {
                    lines[key] = AggregatedLine(
                        name: ingredient.name,
                        quantity: quantity,
                        unit: ingredient.unit,
                        aisle: ingredient.aisleValue,
                        origin: meal.title
                    )
                }
            }
        }

        return lines.values.sorted {
            $0.aisle.sortOrder == $1.aisle.sortOrder
                ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                : $0.aisle.sortOrder < $1.aisle.sortOrder
        }
    }

    struct AggregatedLine {
        var name: String
        var quantity: Double
        var unit: String
        var aisle: GroceryAisle
        var origin: String = ""
    }

    private static func key(name: String, unit: String) -> String {
        "\(name.trimmingCharacters(in: .whitespaces).lowercased())|\(unit.lowercased())"
    }
}
