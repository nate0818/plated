import Foundation
import SwiftData

struct GroceryAdditionResult {
    let added: Int
    let alreadyThere: Int
}

/// One writer for ingredients sent straight from a recipe. It uses the same
/// manual grocery rows as recipe creation, but also makes the action safe to
/// repeat and folds quantities into a matching hand-added line.
enum RecipeGroceryWriter {
    private struct ResolvedLine {
        var name: String
        var quantity: Double
        var unit: String
        var aisle: GroceryAisle
        var ingredientCount: Int
    }

    @MainActor
    static func add(
        recipe: Recipe,
        lines: [(ingredient: Ingredient, quantity: Double)]? = nil,
        in context: ModelContext,
        weekOf date: Date = .now
    ) throws -> GroceryAdditionResult {
        let start = Calendar.current.startOfDay(for: date)
        let horizon = Calendar.current.date(byAdding: .day, value: -7, to: start) ?? start
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        let all = try context.fetch(FetchDescriptor<GroceryItem>())
        var active = all.filter { item in
            guard !item.isDismissed else { return false }
            return item.isManual
                ? item.weekStart >= horizon && item.weekStart < end
                : Calendar.current.isSameDay(item.weekStart, start)
        }
        let resolved = lines ?? recipe.sortedIngredients.map { ($0, $0.quantity) }
        // One recipe can legitimately mention the same grocery more than
        // once (garlic in the sauce and again in the garnish). Provenance is
        // recipe-level, so checking it line-by-line made the first mention
        // suppress every later one. Combine first, then make one idempotency
        // decision for the recipe's whole contribution to that grocery key.
        var grouped: [String: ResolvedLine] = [:]
        var keyOrder: [String] = []
        for line in resolved {
            let ingredient = line.ingredient
            let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let amount = GroceryMeasure.canonical(line.quantity, ingredient.unit)
            let key = GroceryMeasure.key(name, amount.unit)
            if grouped[key] == nil {
                grouped[key] = ResolvedLine(
                    name: ingredient.name,
                    quantity: 0,
                    unit: amount.unit,
                    aisle: ingredient.aisleValue,
                    ingredientCount: 0
                )
                keyOrder.append(key)
            }
            grouped[key]?.quantity += amount.quantity
            grouped[key]?.ingredientCount += 1
            if grouped[key]?.aisle == .other, ingredient.aisleValue != .other {
                grouped[key]?.aisle = ingredient.aisleValue
            }
        }
        let recipeID = stableID(for: recipe)
        let plannedSourceIDs = plannedSourceIDs(for: recipe, among: all)
        var added = 0
        var existing = 0

        for key in keyOrder {
            guard let line = grouped[key] else { continue }
            let matches = active.filter { $0.lineKey == key }

            if let manual = matches.first(where: {
                $0.isManual && $0.recipeOrigins.contains(where: { $0.id == recipeID })
            }) {
                updateOrigin(recipeID: recipeID, title: recipe.title, on: manual)
                existing += line.ingredientCount
                continue
            }

            // Rows written before stable provenance existed only have their
            // display title. Adopt that legacy title once so repeat taps stay
            // safe; every subsequent decision uses the stable recipe ID.
            if let legacy = matches.first(where: {
                $0.isManual && $0.recipeOrigins.isEmpty && originTitles(in: $0).contains(recipe.title)
            }) {
                updateOrigin(recipeID: recipeID, title: recipe.title, on: legacy)
                existing += line.ingredientCount
                continue
            }

            let alreadyCoveredByPlan = matches.contains { item in
                !item.isManual && item.sources.contains { plannedSourceIDs.contains($0.id) }
            }
            // A generated row from the weekly plan is not proof that this
            // recipe's additional quantity is already covered. Only skip a
            // repeat of this exact recipe; otherwise keep its need in the
            // manual layer so two recipes sharing flour still add up.
            if alreadyCoveredByPlan {
                existing += line.ingredientCount
                continue
            }

            if let manual = matches.first(where: \.isManual) {
                let previous = GroceryMeasure.canonical(manual.quantity, manual.unit)
                manual.quantity = previous.quantity + line.quantity
                manual.unit = previous.unit
                manual.isChecked = false
                updateOrigin(recipeID: recipeID, title: recipe.title, on: manual)
                if manual.aisleValue == .other { manual.aisleValue = line.aisle }
            } else {
                let item = GroceryItem(
                    name: line.name,
                    quantity: line.quantity,
                    unit: line.unit,
                    aisle: line.aisle,
                    weekStart: start,
                    isManual: true
                )
                updateOrigin(recipeID: recipeID, title: recipe.title, on: item)
                context.insert(item)
                active.append(item)
            }
            added += line.ingredientCount
        }
        try context.save()
        return GroceryAdditionResult(added: added, alreadyThere: existing)
    }

    /// `shareRecordName` is minted with every recipe and survives household
    /// sync and title edits. The fallbacks cover old local rows defensively.
    private static func stableID(for recipe: Recipe) -> String {
        if !recipe.shareRecordName.isEmpty { return recipe.shareRecordName }
        if !recipe.originID.isEmpty { return "origin-\(recipe.originID)" }
        return "local-\(String(describing: recipe.persistentModelID))"
    }

    @MainActor
    private static func plannedSourceIDs(
        for recipe: Recipe,
        among items: [GroceryItem]
    ) -> Set<String> {
        let candidateIDs = Set(items.filter { !$0.isManual }.flatMap { $0.sources.map(\.id) })
        guard !candidateIDs.isEmpty, let context = recipe.modelContext,
              let meals = try? context.fetch(FetchDescriptor<PlannedMeal>()) else { return [] }
        return Set(meals.compactMap { meal in
            guard meal.recipe?.persistentModelID == recipe.persistentModelID,
                  let id = meal.shoppingID, candidateIDs.contains(id) else { return nil }
            return id
        })
    }

    private static func originTitles(in item: GroceryItem) -> [String] {
        item.originTitle.split(separator: "·")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func updateOrigin(recipeID: String, title: String, on item: GroceryItem) {
        var origins = item.recipeOrigins
        var displayed = originTitles(in: item)
        if let index = origins.firstIndex(where: { $0.id == recipeID }) {
            let oldTitle = origins[index].title
            origins[index].title = title
            let anotherOriginUsesOldTitle = origins.enumerated().contains {
                $0.offset != index && $0.element.title == oldTitle
            }
            if oldTitle != title && !anotherOriginUsesOldTitle {
                displayed.removeAll { $0 == oldTitle }
            }
        } else {
            origins.append(.init(id: recipeID, title: title))
        }
        if !title.isEmpty && !displayed.contains(title) { displayed.append(title) }
        item.recipeOrigins = origins
        item.originTitle = displayed.joined(separator: " · ")
    }
}
