import Foundation

/// Recipe precision is preserved in storage. Shopping uses familiar US
/// measures, with a buying amount rounded UP so a conversion cannot underbuy.
enum GroceryMeasure {
    struct Amount: Equatable {
        var quantity: Double
        var unit: String
        var text: String {
            guard quantity > 0 else { return unit }
            return [Ingredient.format(quantity), Ingredient.unitText(unit, for: quantity)].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }
    static func canonical(_ quantity: Double, _ unit: String) -> Amount {
        let u = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let q = quantity.isFinite ? max(0, quantity) : 0
        switch u {
        case "g", "gram", "grams": return .init(quantity: q / 28.349523125, unit: "oz")
        case "kg", "kilogram", "kilograms": return .init(quantity: q * 1000 / 28.349523125, unit: "oz")
        case "lb", "lbs", "pound", "pounds": return .init(quantity: q * 16, unit: "oz")
        case "ounce", "ounces": return .init(quantity: q, unit: "oz")
        case "ml", "milliliter", "milliliters": return .init(quantity: q / 29.5735295625, unit: "fl oz")
        case "l", "liter", "liters": return .init(quantity: q * 1000 / 29.5735295625, unit: "fl oz")
        case "cups": return .init(quantity: q, unit: "cup")
        case "cloves": return .init(quantity: q, unit: "clove")
        case "cans": return .init(quantity: q, unit: "can")
        case "bunches": return .init(quantity: q, unit: "bunch")
        case "heads": return .init(quantity: q, unit: "head")
        case "packages": return .init(quantity: q, unit: "package")
        default: return .init(quantity: q, unit: u)
        }
    }
    static func shopping(_ quantity: Double, _ unit: String) -> Amount {
        var amount = canonical(quantity, unit)
        if amount.unit == "oz", amount.quantity >= 16 {
            amount.quantity = ceil((amount.quantity / 16) * 4 - 0.000001) / 4
            amount.unit = "lb"
        } else if ["oz", "fl oz"].contains(amount.unit) {
            amount.quantity = ceil(amount.quantity * 4 - 0.000001) / 4
        } else if ["", "each", "clove", "can", "bunch", "head", "package", "piece", "slice"].contains(amount.unit) {
            amount.quantity = ceil(amount.quantity - 0.000001)
        }
        return amount
    }
    static func key(_ name: String, _ unit: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() + "|" + canonical(0, unit).unit
    }
}

struct GrocerySource: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var date: Date
    var quantity: Double
}
