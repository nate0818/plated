import Foundation

/// What a screen says about a night the household took off.
///
/// One place, because four surfaces say it: the week row where the dinner
/// was, the Tonight hero, the planned row of a night that was held back, and
/// the night sheet. Split across those four it is how the week and the hero
/// come to disagree about the same night.
///
/// **The author gets no push and no bell row.** `TableNews.planNotices`
/// needs an already-read `plan:` row for the night, and the author never has
/// one for a night they planned themselves. So these sentences are not
/// decoration on top of a notification: they are the only way the person
/// learns their dinner went, which is why an empty night draws one instead
/// of "Plan dinner" rather than beside it.
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

    /// The subtitle under "Add it back", which names the dish so the control
    /// says what it will do rather than what it is.
    static func addBackDetail(on date: Date, slot: MealSlot = .dinner) -> String? {
        guard let gone = gone(on: date, slot: slot), gone.settled, !gone.kept, !gone.title.isEmpty
        else { return nil }
        return "Puts \(gone.title) back on the household plan."
    }

    /// The dish the household took off that day, for a control that has to
    /// name it. Same gate as `addBackDetail`, so the two never disagree.
    static func addBackTitle(on date: Date, slot: MealSlot = .dinner) -> String? {
        guard let gone = gone(on: date, slot: slot), gone.settled, !gone.kept, !gone.title.isEmpty
        else { return nil }
        return gone.title
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
