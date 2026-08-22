import Foundation

/// What this household is called. Apple hands over a family name exactly
/// once — at first Sign in with Apple, and only if the person agreed to
/// share it — so the name has to be recoverable from somewhere else and
/// editable by hand, or the house ends up permanently called "Your".
enum HouseholdIdentity {

    /// The family name, best source first: what the user typed, then what
    /// Apple gave us at sign-in, then the head of table's own surname.
    static func familyName(typed: String, appleFamilyName: String, ownerName: String) -> String {
        let typed = typed.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty { return typed }

        let apple = appleFamilyName.trimmingCharacters(in: .whitespaces)
        if !apple.isEmpty { return apple }

        let parts = ownerName.split(separator: " ").filter { $0.first?.isLetter == true }
        if parts.count > 1, let last = parts.last { return String(last) }
        return ""
    }

    /// "Meadows" → "Meadows'"; "Chen" → "Chen's". A surname already ending
    /// in s takes the bare apostrophe — "Meadows's Household" reads wrong
    /// on a wall and wrong on a screen.
    static func possessive(_ name: String) -> String {
        guard !name.isEmpty else { return "" }
        return name.lowercased().hasSuffix("s") ? "\(name)'" : "\(name)'s"
    }

    /// The Home masthead: "Meadows' Household" — or an honest fallback
    /// while the house is still nameless.
    static func title(typed: String, appleFamilyName: String, ownerName: String) -> String {
        let family = familyName(typed: typed, appleFamilyName: appleFamilyName, ownerName: ownerName)
        guard !family.isEmpty else { return "Your Household" }
        return "\(possessive(family)) Household"
    }

    /// Who sits here, for the banner's caption: real names while the table
    /// is small enough to read, a count once it isn't.
    static func seatedLine(names: [String]) -> String {
        let firsts = names.compactMap { $0.split(separator: " ").first.map(String.init) }
        switch firsts.count {
        case 0: return "Everyone who sits at your table"
        case 1: return firsts[0]
        case 2: return "\(firsts[0]) and \(firsts[1])"
        case 3: return "\(firsts[0]), \(firsts[1]) and \(firsts[2])"
        default: return "\(firsts[0]), \(firsts[1]) and \(firsts.count - 2) more"
        }
    }
}
