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
    /// "owner" (head of table), "partner", "kid", or "member".
    var role: String = "member"
    /// The line under the name — "Partner · plans & cooks".
    var roleLine: String = ""
    /// Calendar weekday numbers (1 = Sunday … 7 = Saturday) this person cooks.
    var cookWeekdays: [Int] = []
    /// This person's face. Downsized JPEG, same treatment as a recipe photo.
    ///
    /// Optional because it always can be: Sign in with Apple does not hand
    /// over the Apple ID picture and never has, so there is no path that
    /// guarantees one. What there IS is a good path, and the monogram is the
    /// floor rather than the default. See `ProfilePhoto`.
    @Attribute(.externalStorage) var photoData: Data?
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \PlannedMeal.cook)
    var assignedMeals: [PlannedMeal]? = []

    init(
        name: String = "",
        dietaryNotes: String = "",
        avoidedIngredients: [String] = [],
        colorHex: String = "C86629",
        isPrimaryCook: Bool = false,
        role: String = "member",
        roleLine: String = "",
        cookWeekdays: [Int] = []
    ) {
        self.name = name
        self.dietaryNotes = dietaryNotes
        self.avoidedIngredients = avoidedIngredients
        self.colorHex = colorHex
        self.isPrimaryCook = isPrimaryCook
        self.role = role
        self.roleLine = roleLine
        self.cookWeekdays = cookWeekdays
        self.createdAt = .now
    }

    var isOwner: Bool { role == "owner" }

    var firstInitial: String { name.first.map(String.init)?.uppercased() ?? "?" }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}
