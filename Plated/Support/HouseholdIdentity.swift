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

    /// The bootstrap names an owner "Me" when Apple gave us nothing.
    /// Apple hands a name over on the FIRST authorization only and never
    /// again, so a placeholder can never be repaired by asking again —
    /// it has to be treated as a prompt everywhere it is displayed.
    static func isPlaceholder(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.isEmpty || trimmed == "me" || trimmed == "you"
    }

    /// What goes under the HOUSEHOLD label on Home — the name itself, and
    /// only the name. "Meadows' Household" beneath an eyebrow reading
    /// "HOUSEHOLD" says the word twice; a name a family would actually use
    /// says it once. A typed name is theirs and is never dressed up.
    static func displayName(typed: String, appleFamilyName: String, ownerName: String) -> String {
        let typed = typed.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty { return typed }

        let family = familyName(typed: "", appleFamilyName: appleFamilyName, ownerName: ownerName)
        guard !family.isEmpty else { return "Your household" }
        return "The \(family)"
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
