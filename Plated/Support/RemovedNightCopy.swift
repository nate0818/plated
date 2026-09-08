import Foundation

/// What a screen says about a night the household took off.
///
/// One place, because four surfaces say it: the week row where the dinner
/// was, the Tonight hero, the planned row of a night that was held back, and
/// the night sheet. Split across those four it is how the week and the hero
/// come to disagree about the same night.
///
/// **These are what a person finds when they open the app, not the only
/// word they get.** For a while they were: the digest could not speak to
/// the author of a night, because `planNotices` needed an already-read
/// `plan:` row and the author never has one for a night they planned
/// themselves. The `ownRemoved` arm now sends a real push, so an empty
/// night drawing one of these instead of "Plan dinner" is the screen
/// agreeing with a banner rather than standing in for one. It still has to
/// stand alone: a push can be missed, dismissed, or switched off.
///
/// **A nameless removal loses the name and keeps the fact.** `Gone.by` is
/// empty when the record named nobody, and a household is eight people, so a
/// guessed "someone" is a person in the room. That is the same call
/// `TableNews.changer(_:)` makes for the digest.
extension RemovedNights {
    /// The line an empty night draws where "Plan dinner" would be, or nil
    /// when the household took nothing off that day.
    ///
    /// Only for a night that actually went. A night held back, cooked or
    /// being cooked, still has its meal and draws `heldLine` on the planned
    /// row instead, where the dish it is talking about is visible.
    static func removedLine(on date: Date, slot: MealSlot = .dinner) -> String? {
        guard let gone = gone(on: date, slot: slot), gone.settled, !gone.kept else { return nil }
        return sentence(gone, verb: "off the plan", trailing: "")
    }

    /// The heading the Tonight hero draws in place of "Something good starts
    /// here." A full sentence, because the hero sets it as one.
    static func removedHeading(on date: Date, slot: MealSlot = .dinner) -> String? {
        guard let line = removedLine(on: date, slot: slot) else { return nil }
        return line + "."
    }

    /// The line on a night the household took off that this phone is still
    /// carrying, which is the two hold-backs. Both name the reason, because
    /// "it stays on your week" without one reads as the app ignoring the
    /// household rather than protecting a record of what happened.
    static func heldLine(shoppingID: String) -> String? {
        guard !shoppingID.isEmpty,
              let gone = all.first(where: { $0.shoppingID == shoppingID })
        else { return nil }
        if gone.kept {
            return sentence(gone, verb: "off the household plan",
                            trailing: ". You cooked it, so it stays on your week.")
        }
        guard !gone.settled else { return nil }
        return sentence(gone, verb: "off the household plan",
                        trailing: ". You are cooking it, so it is still on your week.")
    }

    /// The same fact for a week row, which is one line and clips.
    ///
    /// `heldLine` is a sentence and runs to about seventy-five characters;
    /// the row draws its caption at `.caption` with `lineLimit(1)`, so that
    /// sentence arrived as "Riley took Tacos off the household plan. You
    /// cook…" and lost the half that matters. This says the same two facts
    /// in the row's own telegraphic register, the one it already uses for
    /// "Tonight · you cook · 25 min".
    static func heldRowLine(shoppingID: String) -> String? {
        guard !shoppingID.isEmpty,
              let gone = all.first(where: { $0.shoppingID == shoppingID })
        else { return nil }
        let who = gone.by.split(separator: " ").first.map(String.init) ?? ""
        let lead = who.isEmpty ? "Off the household plan" : "\(who) took it off"
        if gone.kept { return "\(lead) · you cooked it" }
        guard !gone.settled else { return nil }
        return "\(lead) · you're cooking it"
    }

    /// The subtitle under "Add it back", which names the dish so the control
    /// says what it will do rather than what it is.
    static func addBackDetail(on date: Date, slot: MealSlot = .dinner) -> String? {
        guard let gone = gone(on: date, slot: slot), gone.settled, !gone.kept, !gone.title.isEmpty
        else { return nil }
        return "Puts \(gone.title) back on the household plan."
    }

    /// What actually happened to this phone's copy, for the notice that has
    /// to say it. Read AFTER the drain has decided, never composed before:
    /// the two hold-backs keep the night, and a banner claiming it came off
    /// a week that still shows it contradicts the row underneath it.
    ///
    /// An id the book has never heard of means the drain took it, which is
    /// the ordinary case and the one the plain sentence is for.
    static func outcomeLine(for shoppingID: String) -> String {
        // Nothing, when the book does not know. It used to say "It came off
        // your week too" here, which is an INFERENCE presented as a fact:
        // the id being absent was read as "the drain took it", and a row can
        // also be absent because the fourteen-day prune reached it, because
        // `forget` cleared it, or because some other bug erased it. One such
        // bug existed, and it made this banner assert that a night had left
        // a week it was still sitting on, with the row underneath saying so.
        //
        // The title carries the whole fact on its own: "Riley took Tacos off
        // Thursday" is true however this phone's copy ended up. A second
        // sentence is worth having only when it is known, and silence is the
        // honest answer to a question the book cannot answer.
        guard !shoppingID.isEmpty,
              let gone = all.first(where: { $0.shoppingID == shoppingID })
        else { return "" }
        if gone.kept { return "You cooked it, so it stays on your week." }
        if !gone.settled { return "You are cooking it, so it stays on your week for now." }
        return "It came off your week too."
    }

    /// The dish the household took off that day, for a control that has to
    /// name it. Same gate as `addBackDetail`, so the two never disagree.
    static func addBackTitle(on date: Date, slot: MealSlot = .dinner) -> String? {
        guard let gone = gone(on: date, slot: slot), gone.settled, !gone.kept, !gone.title.isEmpty
        else { return nil }
        return gone.title
    }

    /// The origin key of the dish that was taken off, so add-back can find
    /// the recipe it actually was rather than the first one sharing a name.
    /// Empty for a home-written recipe, which falls back to the title.
    static func addBackOrigin(on date: Date, slot: MealSlot = .dinner) -> String? {
        guard let gone = gone(on: date, slot: slot), gone.settled, !gone.kept else { return nil }
        return gone.recipeOriginKey
    }

    /// Named or not, and never a guess in between. `trailing` carries its
    /// own leading full stop, so the opening clause needs no punctuation of
    /// its own and a line with no trailing stays a label rather than
    /// becoming a sentence.
    private static func sentence(_ gone: Gone, verb: String, trailing: String) -> String {
        let who = gone.by.split(separator: " ").first.map(String.init) ?? ""
        let dish = gone.title.isEmpty ? "That night" : gone.title
        // "came off" rather than "was taken off" with no name: a passive
        // implies an actor, and there is none to imply.
        let opening = who.isEmpty
            ? "\(dish) came \(verb)"
            : "\(who) took \(dish) \(verb)"
        return opening + trailing
    }
}
