import XCTest
@testable import Plated

@MainActor
final class TableAudienceTests: XCTestCase {
    func testAcceptedGuestAppearsBeforeTheyPostWithoutDuplicatingHousehold() {
        let seats = [
            TableShare.Seat(id: "host", name: "Nate", isOwner: true, isMe: true),
            TableShare.Seat(id: "member", name: "Alessandra", isOwner: false, isMe: false),
            TableShare.Seat(id: "friend", name: "Riley", isOwner: false, isMe: false),
            TableShare.Seat(id: "friend", name: "Riley", isOwner: false, isMe: false),
        ]

        let guests = TableSeatsSheet.acceptedGuests(
            from: seats, excluding: ["host", "member"]
        )

        XCTAssertEqual(guests.map(\.id), ["friend"])
    }
}
