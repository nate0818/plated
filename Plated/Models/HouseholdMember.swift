import Foundation
import SwiftData

/// A person the household cooks for. Dietary notes here drive the warnings
/// shown when a recipe is dropped onto the week plan.
@Model
final class HouseholdMember {
    var name: String = ""
    var dietaryNotes: String = ""
    /// Ingredient names to flag on sight — allergies, dislikes, hard no's.
    var avoidedIngredients: [String] = []
    /// Hex string (no leading `#`) used to tint this member across the app.
    var colorHex: String = "C86629"
    var isPrimaryCook: Bool = false
    var createdAt: Date = Date.now

    init(
        name: String = "",
        dietaryNotes: String = "",
        avoidedIngredients: [String] = [],
        colorHex: String = "C86629",
        isPrimaryCook: Bool = false
    ) {
        self.name = name
        self.dietaryNotes = dietaryNotes
        self.avoidedIngredients = avoidedIngredients
        self.colorHex = colorHex
        self.isPrimaryCook = isPrimaryCook
        self.createdAt = .now
    }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}
