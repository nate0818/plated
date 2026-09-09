import Foundation

/// What a screen says about a night this phone planned that the household
/// has since changed.
///
/// The sibling of `RemovedNightCopy`, and one file for the same reason: the
/// night sheet and the week row say this about one dinner, and split across
/// two they drift.
///
/// **This is the only way the person finds out.** `PlanLedger.absorb` drops
/// every delivered record this phone authored, so the delivery is the one
/// moment the fact exists, and `TableNews` cannot speak about it either: a
/// plan notice needs an already-read bell row for that night and the author
/// never has one for a night they planned themselves. Being put down to cook
/// reached every phone in the household except the one whose plan it was.
///
/// **The sentence names what changed, not that something did.** "Riley
/// changed Thursday" is a notification about a notification. A person needs
/// to know whether they are now cooking, because that is the fact with a
/// consequence attached.
///
/// **A change that names nobody loses the name and keeps the fact**, the
/// same call `TableNews.changer(_:)` and `RemovedNightCopy` both make. A
/// household is a handful of people and a guessed name is a person in the
/// room.
extension HouseholdEdits {
    /// The line for a night this phone planned and the household changed,
    /// or nil when there is nothing outstanding on it.
    ///
    /// `me` is this phone's identity, passed rather than read, so the
    /// sentence is a pure function of what it is given and a test can drive
    /// the cook case without standing up an account.
    /// `currentCookID` is who this phone's own copy of the night says is
    /// cooking, which is what makes the cook sentence a statement about a
    /// CHANGE rather than about the record.
    ///
    /// Without it the sentence fired whenever the household's cook happened
    /// to be the reader, so a housemate renaming a dish on a night the
    /// reader was ALREADY cooking was announced as "Riley put you down to
    /// cook", which is a claim about something Riley did not do. What
    /// changed is the only thing worth saying, and it is the only thing
    /// honest to say.
    static func line(
        for change: Change, me: String, currentCookID: String, currentTitle: String
    ) -> String {
        let who = change.by.split(separator: " ").first.map(String.init) ?? ""
        let dish = change.title.isEmpty ? "your night" : change.title
        // Being put down to cook is the fact with a consequence, so it leads
        // when it is NEW.
        if !change.cookID.isEmpty, change.cookID == me, change.cookID != currentCookID {
            return who.isEmpty
                ? "You have been put down to cook \(dish)."
                : "\(who) put you down to cook \(dish)."
        }
        // "changed this night to Ragu" is only true when the dish is what
        // moved. Gating the cook clause on the cook having changed pushed
        // every other kind of edit into this one, so a servings or a cook
        // change on a night already called Ragu was announced as a rename
        // to Ragu. That is the same false claim as before, moved one branch
        // over, which is the shape this fix was supposed to close.
        let named = !change.title.isEmpty
            && change.title != currentTitle.trimmingCharacters(in: .whitespaces)
        if named {
            return who.isEmpty
                ? "This night was changed to \(dish) on another phone."
                : "\(who) changed this night to \(dish)."
        }
        return who.isEmpty
            ? "This night was changed on another phone."
            : "\(who) changed this night."
    }

    /// The second line: what this phone still shows, so the two versions are
    /// named rather than implied. Nil when there is nothing useful to
    /// contrast, which is a title that has not changed.
    static func contrast(for change: Change, mineTitle: String) -> String? {
        let mine = mineTitle.trimmingCharacters(in: .whitespaces)
        guard !mine.isEmpty, !change.title.isEmpty, mine != change.title else { return nil }
        return "Your plan still says \(mine)."
    }

    /// The verb on the control that takes it. Names the outcome, not the
    /// mechanism: nobody is resolving a conflict, they are agreeing to the
    /// dinner the rest of the house is having.
    static let adoptTitle = "Use their version"

    /// The quiet answer beside it. Declining is not a control: leaving it
    /// alone IS the answer, and a button that only dismisses a sentence
    /// would be a control that does nothing.
    static let keepTitle = "Keep mine"

    /// The week row's version, which has one line and no controls. Shorter
    /// than the sheet's, because the row is a list item and the decision
    /// lives on the page it opens.
    static func rowLine(for change: Change, me: String, currentCookID: String) -> String {
        let who = change.by.split(separator: " ").first.map(String.init) ?? ""
        if !change.cookID.isEmpty, change.cookID == me, change.cookID != currentCookID {
            return who.isEmpty ? "You are down to cook this" : "\(who) put you down to cook"
        }
        return who.isEmpty ? "Changed on another phone" : "\(who) changed this night"
    }
}
