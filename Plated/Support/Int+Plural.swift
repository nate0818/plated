import Foundation

extension Int {
    /// "1 person", "3 people", "1 ingredient", "12 ingredients".
    ///
    /// Pluralisation is a rule, not a decision to be made again at every
    /// call site — and it was being made again at every call site, so the
    /// seats sheet greeted a new household with "1 PEOPLE" two inches under
    /// a masthead that got it right. Six strings in the app had the same
    /// bug and every one of them was reachable on an ordinary day: one
    /// ingredient, one vote, one choice, one person.
    ///
    /// Pass the plural only when it is not the singular plus an s.
    ///
    ///     seatCount.things("person", "people")   // "1 person"
    ///     votes.things("vote")                   // "1 vote"
    func things(_ singular: String, _ plural: String? = nil) -> String {
        "\(self) \(word(singular, plural))"
    }

    /// The noun alone, for the places that lay the numeral out separately.
    func word(_ singular: String, _ plural: String? = nil) -> String {
        self == 1 ? singular : (plural ?? singular + "s")
    }
}
