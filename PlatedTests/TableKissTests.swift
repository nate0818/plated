import XCTest
import SwiftData
@testable import Plated

/// Holds `TableKiss.seating` to the denominator the feed and the digest
/// both use: people who can plate, not every HouseholdMember row.
@MainActor
final class TableKissTests: XCTestCase {

    func testKidsDoNotInflateTheKissDenominator() {
        let head = HouseholdMember(name: "Nate", role: "owner", seat: .head)
        let partner = HouseholdMember(name: "Riley", role: "partner", seat: .joined)
        let kid = HouseholdMember(name: "Ada", role: "kid", seat: .notOnPlated)
        // Two platers, one by-name seat — members.count would be 3 and the
        // kiss would never fire at two plates.
        XCTAssertEqual(TableKiss.seating(members: [head, partner, kid]), 2)
    }

    func testGuestAuthorsCountTowardEveryone() {
        let head = HouseholdMember(name: "Nate Meadows", role: "owner", seat: .head)
        // A solo household that hosts a friend at the Table: without the
        // guest, seating is 1 and hasChefsKiss refuses; with the guest,
        // two plates earn the kiss.
        XCTAssertEqual(TableKiss.seating(members: [head]), 1)
        XCTAssertEqual(
            TableKiss.seating(members: [head], dishAuthors: ["Sam Okafor", "Nate Meadows"]),
            2
        )
    }

    func testInvitedAndLeftSeatsDoNotPlate() {
        let head = HouseholdMember(name: "Nate", role: "owner", seat: .head)
        let invited = HouseholdMember(name: "Jo", role: "member", seat: .invited)
        let left = HouseholdMember(name: "Kim", role: "partner", seat: .left)
        XCTAssertEqual(TableKiss.seating(members: [head, invited, left]), 1)
    }
}
