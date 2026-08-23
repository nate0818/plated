import Foundation
import SwiftData

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

    /// Rename someone at this table, carrying their work with them.
    ///
    /// **Authorship is a stored string, not a relationship.** Posts and
    /// comments stamp `authorName` at write time and the awards ledger is
    /// keyed by name, so setting `member.name` on its own orphans
    /// everything the person has ever done: their profile grid empties,
    /// their counts drop to zero, their dishes fall out of the Household
    /// scope, and the old name starts being counted as an extra guest at
    /// the table.
    ///
    /// That was survivable while nothing could rename the owner. The
    /// "Add your name" prompt made it reachable — bootstrap writes "Me",
    /// the user posts a dish, then accepts the prompt and loses the dish —
    /// so the rewrite has to happen with the rename, every time.
    ///
    /// Moving authorship to a relationship is the real fix and a larger
    /// change; until then, this is the one door renames go through.
    @discardableResult
    static func rename(
        _ member: HouseholdMember,
        to newName: String,
        in context: ModelContext
    ) -> Bool {
        let new = newName.trimmingCharacters(in: .whitespaces)
        let old = member.name
        guard !new.isEmpty, new != old else { return false }

        // Exact match on the stored string: that is what was stamped, and
        // matching loosely would rewrite a guest who shares a first name.
        if let posts = try? context.fetch(
            FetchDescriptor<TablePost>(predicate: #Predicate { $0.authorName == old })
        ) {
            for post in posts { post.authorName = new }
        }
        if let comments = try? context.fetch(
            FetchDescriptor<TableComment>(predicate: #Predicate { $0.authorName == old })
        ) {
            for comment in comments { comment.authorName = new }
        }
        // SEVEN fields key off a person's name as a string. The previous
        // comment here said five and declared the class closed, which is
        // the same instance-not-class error one level up — inside the
        // sentence claiming to have fixed it. Reachable on the ordinary
        // first-session path: the owner is "Me", somebody replies to them
        // or @-mentions them, then they accept "Add your name" — and
        // afterwards the reply chevron still reads "Me" and the mention
        // stops resolving.
        // Missing these two is the same "fixed the instance, not the class"
        // shape as everything else this branch has had to correct: latent
        // today because only the owner can be renamed, wrong the moment
        // anyone else can be.
        if let threads = try? context.fetch(
            FetchDescriptor<DirectMessage>(predicate: #Predicate { $0.peerName == old })
        ) {
            for message in threads { message.peerName = new }
        }
        if let notices = try? context.fetch(
            FetchDescriptor<PlatedNotification>(predicate: #Predicate { $0.actorName == old })
        ) {
            for notice in notices { notice.actorName = new }
        }
        if let replies = try? context.fetch(
            FetchDescriptor<TableComment>(predicate: #Predicate { $0.replyToName == old })
        ) {
            for reply in replies { reply.replyToName = new }
        }
        // `mentions` is an array, so it needs rewriting element-wise rather
        // than matched on.
        if let mentioning = try? context.fetch(FetchDescriptor<TableComment>()) {
            for comment in mentioning where comment.mentions.contains(old) {
                comment.mentions = comment.mentions.map { $0 == old ? new : $0 }
            }
        }
        Awards.rekey(from: old, to: new)

        member.name = new
        try? context.save()
        return true
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
