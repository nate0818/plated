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
        var parts: [String] = []
        if quantity > 0 { parts.append(Self.format(quantity)) }
        if !unit.isEmpty { parts.append(unit) }
        parts.append(name)
        return parts.joined(separator: " ")
    }

    static func format(_ value: Double) -> String {
        value.rounded() == value
            ? String(Int(value))
            : String(format: "%.2f", value).replacingOccurrences(of: "0$", with: "", options: .regularExpression)
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
