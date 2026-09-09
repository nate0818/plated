import XCTest
@testable import Plated

/// The seat rules a sentence depends on. `hostedNames` is the list behind
/// "You host this household with Riley and Max." in Settings, and it used
/// to be "everybody but me who hasn't left", which named people who had
/// only ever been sent a link.
@MainActor
final class HouseholdMemberHostingTests: XCTestCase {

    override func setUp() async throws {
        HouseholdShare.setMembership(.solo)
        HouseholdShare.mySeat = nil
    }

    override func tearDown() async throws {
        HouseholdShare.setMembership(.solo)
        HouseholdShare.mySeat = nil
    }

    private func seat(_ name: String, _ seat: HouseholdMember.Seat,
                      role: String = "member", user: String? = nil) -> HouseholdMember {
        let member = HouseholdMember(name: name, role: role, seat: seat)
        member.userRecordName = user
        return member
    }

    func testHostedNamesKeepsJoinedAndByNameSeats() {
        let members = [
            seat("Nate Meadows", .head, role: "owner", user: TableIdentity.cached),
            seat("Riley Park", .joined, role: "partner", user: "riley-id"),
            seat("Max", .notOnPlated),
        ]
        XCTAssertEqual(members.hostedNames, ["Riley Park", "Max"])
    }

    func testHostedNamesDropsInvitedAndLeftSeats() {
        let members = [
            seat("Nate Meadows", .head, role: "owner", user: TableIdentity.cached),
            seat("Riley Park", .joined, role: "partner", user: "riley-id"),
            seat("Sam Ito", .invited),
            seat("Jess Kaur", .left, user: "jess-id"),
        ]
        XCTAssertEqual(
            members.hostedNames, ["Riley Park"],
            "an invited seat is a message that went out, not a person in the household"
        )
    }

    func testHostedNamesIsEmptyWhenNobodyHasArrived() {
        let members = [
            seat("Nate Meadows", .head, role: "owner", user: TableIdentity.cached),
            seat("Sam Ito", .invited),
        ]
        XCTAssertTrue(members.hostedNames.isEmpty)
    }
}
