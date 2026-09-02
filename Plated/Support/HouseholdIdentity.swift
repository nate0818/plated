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
        // The name, and only the name. "The Meadows" is a thing an app
        // decided to call a family, not a thing the family calls itself,
        // and it reads worse the less English the surname is: "The
        // Nguyen", "The Okafor". A typed name was already returned bare
        // above, so the prefix also made the two paths disagree.
        return family
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
    /// Why a rename did or didn't happen. A Bool collapsed "nothing to do",
    /// "that name is taken" and "the save failed" into one answer the
    /// caller then had to guess at — and it guessed wrong twice.
    enum RenameOutcome: Equatable {
        case renamed
        /// Already the desired state. Not a failure.
        case unchanged
        /// Somebody else at this table already answers to that name.
        case nameTaken(String)
        case invalid
        case failed
    }

    @discardableResult
    static func rename(
        _ member: HouseholdMember,
        to newName: String,
        in context: ModelContext
    ) -> RenameOutcome {
        let new = newName.trimmingCharacters(in: .whitespaces)
        let old = member.name
        guard !new.isEmpty else { return .invalid }

        // REFUSE A COLLISION, and refuse it here because `rename` is the
        // only thing that can create one.
        //
        // Every name-keyed path in this app — the profile aggregate, the
        // awards ledger, the Household feed scope — treats two members
        // with the same name as one person. Renaming the owner onto a
        // seated member's name merges them: both people's posts answer to
        // the same string, and `Awards.rekey` folds the real member's
        // earned saves into the owner's ledger.
        //
        // And the correction makes it worse. Renaming away afterwards
        // drags the OTHER person's posts along, because by then nothing in
        // the data distinguishes them — they are orphaned from everything
        // they ever made, permanently. There is no sequence of renames
        // that undoes it; the information was spent at the collision.
        //
        // The doc below says exact matching protects a guest who shares a
        // first name. True of matching, and no help at all here: exact
        // matching cannot separate names that are exactly equal. The guard
        // has to be upstream of the matching, which is here.
        let seated = (try? context.fetch(FetchDescriptor<HouseholdMember>())) ?? []
        if let clash = seated.first(where: {
            $0.persistentModelID != member.persistentModelID
                && $0.name.localizedCaseInsensitiveCompare(new) == .orderedSame
        }) {
            return .nameTaken(clash.name)
        }
        // Already the desired state, which is NOT a failure. The caller
        // reads false as "the save failed" and warns — and the sheet
        // prefills the name field, so its other control is Bio. Collapsing
        // these two meant editing your bio and leaving your name alone
        // ended on a warning buzz with the name write and the success
        // haptic both skipped. "Nothing to do" and "it didn't work" are
        // different answers to a different question.
        guard new != old else { return .unchanged }

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
        // NINE places carry a person's name — and this comment has now
        // said three, five, and seven, each time declaring the class
        // closed. It was wrong every time, which is the instance-not-class
        // error one level up: inside the sentence claiming to have fixed
        // it. The count came from enumerating every stored String and
        // [String] across every @Model, not from listing what came to
        // mind — and even that missed the last one, because a derived key
        // hides a name inside a value that isn't a name. Reachable on the ordinary
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
        // `TableComment.mentions` is deliberately NOT rewritten, and the
        // difference from `taggedNames` below is the whole point.
        //
        // `mentions` is DERIVED from `comment.text` and exists only to
        // decide which "@token" gets bolded — `mentionedText` matches the
        // text against this array. Rewriting the array without the text it
        // came from desyncs them: "@Me" in the text no longer matches
        // ["Nate"], so the mention loses its bolding AND still reads "@Me".
        // That is strictly worse than leaving it stale, which at least
        // renders as a name. This rewrite shipped for one commit and was a
        // net regression.
        //
        // And the text cannot be rewritten instead: substring replacement
        // on prose is unfixable, not merely risky — a name has no word
        // boundary you can trust across a household's vocabulary.
        //
        // The real fix is to stop freezing the token: render mentions
        // through the member lookup at display time, the way
        // `PersonRef.author` resolves a name to a seat. Until then, stale
        // and correctly styled beats fresh and broken.
        // The @-tags on a POST are rewritten, unlike a comment's `mentions`
        // above, and the difference is that these are stored STANDALONE —
        // they are rendered directly as chips and tapped to open a profile,
        // with no copy inside the caption to fall out of step with. A stale
        // tag here would open a profile for somebody who no longer exists.
        // (`TablePost.caption` has the same latent exposure if anything ever
        // starts matching caption tokens against this array. Nothing does
        // today; if something starts, this rewrite has to go the same way
        // `mentions` did.)
        if let tagged = try? context.fetch(FetchDescriptor<TablePost>()) {
            for post in tagged where post.taggedNames.contains(old) {
                post.taggedNames = post.taggedNames.map { $0 == old ? new : $0 }
            }
        }

        // Ninth, and a different kind: a name baked into a DERIVED key that
        // was then stored somewhere else. `TablePost.originKey` is computed
        // as "post:<authorName>|<dishTitle>", and `Recipe.originID` holds a
        // SNAPSHOT of it taken at save time. Rename the author and the
        // computed key moves while the snapshot doesn't, so
        // `originID == post.originKey` stops matching: a dish you saved
        // from the table quietly stops counting as saved, Discover's
        // "Saved" state reverts, and the duplicate-save guard in
        // PostThreadView stops guarding.
        //
        // Worth naming as a category, because a grep for name-holding
        // properties does NOT find this one — the field is a key, and the
        // name is inside it.
        let oldKeyPrefix = "post:\(old)|"
        let newKeyPrefix = "post:\(new)|"
        if let saved = try? context.fetch(FetchDescriptor<Recipe>()) {
            for recipe in saved where recipe.originID.hasPrefix(oldKeyPrefix) {
                recipe.originID = newKeyPrefix + recipe.originID.dropFirst(oldKeyPrefix.count)
            }
        }

        member.name = new

        // Report honestly. `try?` here swallowed the error and returned
        // true regardless, which mattered because the caller writes
        // `userFirstName` — durable, outside this transaction — and
        // `Awards.rekey` writes UserDefaults immediately. A failed save
        // used to leave every model row back at the old name while the
        // ledger and the AppStorage name had moved: identity split across
        // two stores, silently. That IS a torn write; it is just torn
        // across stores rather than within one.
        do {
            try context.save()
        } catch {
            // ROLL BACK, or this is the same split with the order flipped.
            // Every mutation above stays live in the context otherwise, so
            // @Query views show the new name everywhere while
            // `userFirstName` and the awards ledger still hold the old one
            // — the two on-disk stores agree and the running app agrees
            // with neither. Worse, mainContext autosave is enabled
            // (PlatedApp attaches with `.modelContainer`), so a transient
            // failure can be committed by a later autosave and land the
            // model side without the AppStorage name or the rekey. Which
            // is precisely the state this ordering exists to prevent.
            context.rollback()
            return .failed
        }

        // Only once the model side is durable. Ordering is the cheap half
        // of atomicity here: if the save fails, nothing outside the context
        // has moved, so the two stores cannot disagree.
        // Safe to merge because the collision guard above proved no living
        // member answers to `new` — merging is right for a rename and wrong
        // for a collision, and those are indistinguishable to `rekey`.
        Awards.rekey(from: old, to: new)
        return .renamed
    }

    /// Who sits here, for the banner's caption: real names while the table
    /// is small enough to read, a count once it isn't.
    static func seatedLine(names: [String]) -> String {
        let firsts = names.compactMap { $0.split(separator: " ").first.map(String.init) }
        switch firsts.count {
        case 0: return "Everyone in your household"
        case 1: return firsts[0]
        case 2: return "\(firsts[0]) and \(firsts[1])"
        case 3: return "\(firsts[0]), \(firsts[1]) and \(firsts[2])"
        default: return "\(firsts[0]), \(firsts[1]) and \(firsts.count - 2) more"
        }
    }
}
