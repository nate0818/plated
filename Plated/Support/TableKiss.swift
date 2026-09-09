import Foundation

/// Who can earn a Chef's kiss — seats that can plate, plus Table guests.
///
/// `members.count` was wrong in both directions: a by-name seat (kid,
/// grandparent) cannot plate and inflated the denominator; a guest who
/// plated from another household was invisible and deflated it so a
/// single plate fired the kiss on their phone (docs/open-decisions.md
/// §1b / §18).
enum TableKiss {
    /// Count of people who can plate this dish.
    ///
    /// Head and joined seats only; invited / notOnPlated / left do not
    /// plate. `dishAuthors` are post author names — unique guests not
    /// already in the household (first-name match, same bridge
    /// `TableFeedView.seatCount` has always used) are added. Floored at
    /// 1 so a solo table still has a denominator; `hasChefsKiss` still
    /// requires `seats >= 2`.
    static func seating(members: [HouseholdMember], dishAuthors: [String] = []) -> Int {
        let canPlate = members.filter { $0.seat == .head || $0.seat == .joined }.count
        let knownNames = Set(members.map(\.name))
        let guests = Set(
            dishAuthors.filter { author in
                !knownNames.contains(author)
                    && !knownNames.contains(String(author.split(separator: " ").first ?? ""))
            }
        )
        return max(canPlate + guests.count, 1)
    }
}
