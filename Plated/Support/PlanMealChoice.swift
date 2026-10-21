import Foundation

/// Explicit non-recipe choices use the existing freeform plan fields. A
/// recipe whose name mentions leftovers remains a recipe, with its own cook.
enum PlanMealChoice: CaseIterable, Sendable {
    case leftovers
    case eatingOut

    var title: String {
        switch self {
        case .leftovers: "Leftovers"
        case .eatingOut: "Eating out"
        }
    }

    var persistenceContext: StaticString {
        switch self {
        case .leftovers: "plan leftovers"
        case .eatingOut: "plan eating out"
        }
    }

    var tagline: String {
        switch self {
        case .leftovers: "Enjoy what’s already made"
        case .eatingOut: "Night off the stove"
        }
    }

    static func isLeftovers(title: String, hasRecipe: Bool) -> Bool {
        !hasRecipe && title.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(PlanMealChoice.leftovers.title) == .orderedSame
    }
}
