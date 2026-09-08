import Foundation
import SwiftData

/// Updates stable rows in place. Provenance and purchased quantities survive
/// reopening, meal moves, serving edits and the rolling shopping window.
struct GroceryListBuilder {
    let context: ModelContext

    /// Main actor because the marks it folds are; the sheet and the
    /// regression checks, its only callers, both already are.
    @MainActor
    @discardableResult
    func rebuild(weekOf date: Date, includePantryStaples: Bool = false) throws -> [GroceryItem] {
        let start = date.startOfDay
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        // The window's nights, this phone's own and the household's, are
        // gathered and sorted in `nights` below.
        let meals = try context.fetch(FetchDescriptor<PlannedMeal>(predicate: #Predicate {
            $0.date >= start && $0.date < end && $0.cookedAt == nil
        }))
        // A night is this Apple ID's own row and its `shoppingID` is minted
        // with it, so a backfill here can only be a row that predates the
        // field. No household minter to wait for: a night is not a household
        // record (docs/household.md §3.2), and the id the plan pipe names
        // its record with rides the private mirror to this person's other
        // devices like the row itself.
        for meal in meals where meal.shoppingID == nil {
            meal.shoppingID = UUID().uuidString
        }
        let lines = aggregate(
            nights: Self.nights(meals: meals, from: start, to: end),
            includePantryStaples: includePantryStaples
        )
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
            item.originTitle = line.sources.map(\.title).joined(separator: ", ")
            if let mark = GroceryMarks.shared.mark(for: key) {
                // The mark is the household's fact and these rows are this
                // phone's projection of it, so it wins outright: every local
                // check-off writes a mark first, and a row that disagrees
                // with its mark is a row from before the mark existed.
                GroceryMarks.apply(mark, to: item)
            } else {
                item.purchases = purchases
                item.isChecked = item.isPurchased()
            }
            result.append(item)
        }
        // Retain rows in other date ranges: the user may be shopping ahead.
        for old in autos where old.weekStart == start && !used.contains(old.persistentModelID) { context.delete(old) }
        try context.save()
        return result
    }

    /// One night's contribution to the list, whoever planned it.
    ///
    /// A night somebody else in the household planned is a
    /// `PlanLedger.Entry` and never a `PlannedMeal` (docs/household.md 3.2),
    /// so before this the list covered only this phone's own nights: a
    /// housemate's ragu put no beef on it, and their mark on that beef
    /// arrived at a phone with no row to carry it. The ingredients ride the
    /// record for that reason, because the recipe behind their night need
    /// not be in this cookbook.
    struct SourceNight {
        var id: String
        var title: String
        var date: Date
        var lines: [PlanShare.Line]
    }

    /// The window's nights from both halves of the plan, in one order.
    ///
    /// Sorted on facts every phone shares and never on fetch order, because
    /// the aggregation appends sources in this order and two phones
    /// rebuilding one household's plan have to produce one list. The local
    /// half goes through `PlanShare.groceryLines` too, so the scaling and
    /// canonicalisation that decide the key are one piece of code rather
    /// than two that can drift apart.
    @MainActor
    static func nights(
        meals: [PlannedMeal], from start: Date, to end: Date,
        ledger: PlanLedger? = nil
    ) -> [SourceNight] {
        // Not a default argument: a default is evaluated in the CALLER's
        // isolation, and `PlanLedger.shared` is main-actor state, which
        // Swift 6 makes an error rather than a warning. Resolved inside,
        // where this function's own isolation already holds.
        let ledger = ledger ?? PlanLedger.shared
        var out = meals.compactMap { meal -> SourceNight? in
            guard let id = meal.shoppingID else { return nil }
            return SourceNight(id: id, title: meal.title, date: meal.date,
                               lines: PlanShare.groceryLines(for: meal))
        }
        for entry in ledger.all where !entry.cooked {
            guard !entry.shoppingID.isEmpty, let lines = entry.lines, !lines.isEmpty,
                  let date = PlanDay.date(entry.day), date >= start, date < end else { continue }
            out.append(SourceNight(id: entry.shoppingID, title: entry.title,
                                   date: date, lines: lines))
        }
        return out.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    }

    func aggregate(nights: [SourceNight], includePantryStaples: Bool) -> [AggregatedLine] {
        var lines: [String: AggregatedLine] = [:]
        for night in nights {
            for source in night.lines {
                if source.isPantryStaple && !includePantryStaples { continue }
                guard !source.normalizedName.isEmpty else { continue }
                let key = GroceryMeasure.key(source.normalizedName, source.unit)
                var line = lines[key] ?? AggregatedLine(
                    name: source.name, quantity: 0, unit: source.unit,
                    aisle: GroceryAisle(rawValue: source.aisle) ?? .other
                )
                line.quantity += source.quantity
                if let index = line.sources.firstIndex(where: { $0.id == night.id }) {
                    line.sources[index].quantity += source.quantity
                } else {
                    line.sources.append(.init(id: night.id, title: night.title,
                                              date: night.date, quantity: source.quantity))
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
