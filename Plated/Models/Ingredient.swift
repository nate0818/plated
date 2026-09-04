import Foundation
import SwiftData

/// One line of a recipe's ingredient list. Grocery aggregation groups these by
/// `normalizedName` + `unit` so "2 cloves garlic" and "1 clove garlic" merge.
@Model
final class Ingredient {
    var name: String = ""
    var quantity: Double = 0
    var unit: String = ""
    /// Store section, used to sort the grocery list into a walkable order.
    var aisle: String = GroceryAisle.other.rawValue
    var isPantryStaple: Bool = false
    var sortIndex: Int = 0

    var recipe: Recipe?

    init(
        name: String = "",
        quantity: Double = 0,
        unit: String = "",
        aisle: GroceryAisle = .other,
        isPantryStaple: Bool = false,
        sortIndex: Int = 0
    ) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.aisle = aisle.rawValue
        self.isPantryStaple = isPantryStaple
        self.sortIndex = sortIndex
    }

    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var aisleValue: GroceryAisle {
        get { GroceryAisle(rawValue: aisle) ?? .other }
        set { aisle = newValue.rawValue }
    }

    /// "2 cups flour" — quantity omitted when it is zero.
    var displayText: String {
        Self.line(quantity: quantity, unit: unit, name: name)
    }

    /// The one place an amount, a unit and a name become a sentence.
    ///
    /// Every screen that shows an ingredient was writing its own version of
    /// this, and they disagreed — which is how the importer's canonical
    /// units started reading as "3 clove garlic" and "2 cup fresh spinach"
    /// on one screen and correctly on another.
    static func line(quantity: Double, unit: String, name: String) -> String {
        var parts: [String] = []
        if quantity > 0 { parts.append(format(quantity)) }
        let written = unitText(unit, for: quantity)
        if !written.isEmpty { parts.append(written) }
        parts.append(name)
        return parts.joined(separator: " ")
    }

    /// A cook reads "½ cup", not "0.5 cup".
    static func format(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        let whole = Int(value)
        let fraction = value - Double(whole)
        let glyphs: [(Double, String)] = [
            (0.125, "⅛"), (0.25, "¼"), (1.0 / 3, "⅓"), (0.375, "⅜"), (0.5, "½"),
            (0.625, "⅝"), (2.0 / 3, "⅔"), (0.75, "¾"), (0.875, "⅞")
        ]
        if let glyph = glyphs.first(where: { abs(fraction - $0.0) < 0.02 })?.1 {
            return whole == 0 ? glyph : "\(whole)\(glyph)"
        }
        return String(format: "%.2f", value)
            .replacingOccurrences(of: "0$", with: "", options: .regularExpression)
    }

    /// The unit written for the amount in front of it.
    ///
    /// Storage keeps ONE canonical spelling per unit so the grocery list can
    /// merge "2 cups flour" from one recipe with "1 cup flour" from another
    /// — string equality is the whole merge. Display is a separate question,
    /// and the answer to it is plural.
    static func unitText(_ unit: String, for quantity: Double) -> String {
        guard !unit.isEmpty, quantity > 1 else { return unit }
        // Abbreviations and metric measures do not take a plural.
        let invariable: Set<String> = ["g", "kg", "ml", "l", "oz", "fl oz", "lb", "tsp", "tbsp", "qt", "pt", "gal"]
        let lower = unit.lowercased()
        if invariable.contains(lower) || lower.hasSuffix("s") { return unit }
        if lower.hasSuffix("ch") || lower.hasSuffix("sh") || lower.hasSuffix("x") { return unit + "es" }
        return unit + "s"
    }
}

enum GroceryAisle: String, Codable, CaseIterable, Identifiable {
    case produce = "Produce"
    case meat = "Meat & Seafood"
    case dairy = "Dairy & Eggs"
    case bakery = "Bakery"
    case pantry = "Pantry"
    case frozen = "Frozen"
    case beverages = "Beverages"
    case household = "Household"
    case other = "Other"

    var id: String { rawValue }

    /// Rough walking order through a typical store.
    var sortOrder: Int { Self.allCases.firstIndex(of: self) ?? 99 }

    var symbolName: String {
        switch self {
        case .produce: return "leaf"
        case .meat: return "fish"
        case .dairy: return "drop"
        case .bakery: return "birthday.cake"
        case .pantry: return "shippingbox"
        case .frozen: return "snowflake"
        case .beverages: return "cup.and.saucer"
        case .household: return "house"
        case .other: return "bag"
        }
    }
}
