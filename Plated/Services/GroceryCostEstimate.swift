import Foundation

/// A store total is all-or-nothing: one unknown or stale line makes the
/// basket estimate unavailable. Showing a plausible subtotal as the basket
/// price would be less useful than telling the shopper what is missing.
struct GroceryCostEstimate {
    struct InputLine: Sendable {
        var name: String
        var quantity: Double
        var unit: String
        var package: IngredientPackage?
    }

    struct Result: Equatable {
        var total: Double?
        var pricedLines: Int
        var missingLines: Int
        var packageCount: Int
        var store: String
    }

    static func calculate(
        lines: [InputLine],
        store: String,
        now: Date = .now,
        maxAge: TimeInterval = 45 * 24 * 60 * 60
    ) -> Result {
        let chosenStore = store.trimmingCharacters(in: .whitespacesAndNewlines)
        let needed = lines.filter { $0.quantity.isFinite && $0.quantity > 0 }
        if needed.isEmpty {
            return Result(total: 0, pricedLines: 0, missingLines: 0,
                          packageCount: 0, store: chosenStore)
        }
        guard !chosenStore.isEmpty else {
            return Result(total: nil, pricedLines: 0, missingLines: needed.count,
                          packageCount: 0, store: chosenStore)
        }

        var total = 0.0
        var priced = 0
        var missing = 0
        var packages = 0
        for line in needed {
            guard let package = line.package,
                  package.isUsable,
                  package.store.localizedCaseInsensitiveCompare(chosenStore) == .orderedSame,
                  let updatedAt = package.updatedAt,
                  updatedAt <= now,
                  now.timeIntervalSince(updatedAt) <= maxAge,
                  let size = package.size,
                  let price = package.price,
                  size.isFinite, size > 0,
                  price.isFinite, price >= 0 else {
                missing += 1
                continue
            }
            let need = GroceryMeasure.canonical(line.quantity, line.unit)
            let pack = GroceryMeasure.canonical(size, package.unit)
            guard need.unit == pack.unit, pack.quantity > 0 else {
                missing += 1
                continue
            }
            let count = max(1, Int(ceil(need.quantity / pack.quantity - 0.000001)))
            total += Double(count) * price
            packages += count
            priced += 1
        }
        let includedLineCount = needed.count
        return Result(
            total: missing == 0 && priced == includedLineCount ? total : nil,
            pricedLines: priced,
            missingLines: missing,
            packageCount: packages,
            store: chosenStore
        )
    }
}
