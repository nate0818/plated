import XCTest
@testable import Plated

@MainActor
final class HouseholdInvitationReceiptTests: XCTestCase {
    private var prepared: Seats.Prepared {
        .init(outcome: .ready(URL(string: "https://example.invalid/test-only")!), seat: "fresh-seat")
    }

    func testOnlyAnActualSentResultProducesAFreshReceipt() throws {
        let receipt = try XCTUnwrap(HouseholdInvitationReceipt.fresh(
            .sent(name: "Alessandra Schembari", phone: nil, prepared: prepared)))
        XCTAssertEqual(receipt.seat, "fresh-seat")
        XCTAssertEqual(receipt.displayName, "Alessandra")
        XCTAssertFalse(receipt.isResend)
        XCTAssertNil(HouseholdInvitationReceipt.fresh(.cancelled))
        XCTAssertNil(HouseholdInvitationReceipt.fresh(.declined(name: "Alessandra", phone: nil, prepared: prepared)))
        XCTAssertNil(HouseholdInvitationReceipt.fresh(.failed(name: "Alessandra", phone: nil, prepared: prepared)))
        XCTAssertNil(HouseholdInvitationReceipt.fresh(.noLink(name: "Alessandra", reason: "Unavailable")))
    }

    func testAReadyLinkAndSeatAreRequiredEvenForASentResult() {
        XCTAssertNil(HouseholdInvitationReceipt.fresh(
            .sent(name: "Alessandra", phone: nil, prepared: .noCloud)))
        let seatless = Seats.Prepared(outcome: prepared.outcome)
        XCTAssertNil(HouseholdInvitationReceipt.fresh(
            .sent(name: "Alessandra", phone: nil, prepared: seatless)))
        let emptySeat = Seats.Prepared(outcome: prepared.outcome, seat: "")
        XCTAssertNil(HouseholdInvitationReceipt.fresh(
            .sent(name: "Alessandra", phone: nil, prepared: emptySeat)))
    }

    func testPhoneOnlyContactsUseNaturalFallbackCopy() throws {
        let receipt = try XCTUnwrap(HouseholdInvitationReceipt.resent(wasSent: true, seat: "existing", name: "  "))
        XCTAssertEqual(receipt.displayName, "them")
        XCTAssertEqual(receipt.subjectName, "They")
        XCTAssertEqual(receipt.departureSubject, "They are")
    }

    func testResendReceiptRequiresSentAndKeepsTheOriginalSeat() throws {
        XCTAssertNil(HouseholdInvitationReceipt.resent(wasSent: false, seat: "existing", name: "Sam"))
        XCTAssertNil(HouseholdInvitationReceipt.resent(wasSent: true, seat: "", name: "Sam"))
        let receipt = try XCTUnwrap(HouseholdInvitationReceipt.resent(wasSent: true, seat: "existing", name: "Sam"))
        XCTAssertEqual(receipt.seat, "existing")
        XCTAssertTrue(receipt.isResend)
    }

    func testOnlyTheExactJoinedSeatClearsWaiting() throws {
        let receipt = try XCTUnwrap(HouseholdInvitationReceipt.fresh(
            .sent(name: "Sam", phone: nil, prepared: prepared)))
        XCTAssertEqual(receipt.state(in: []), .unavailable)
        XCTAssertEqual(receipt.state(in: [.init(seat: "fresh-seat", state: .invited)]), .pending)
        XCTAssertEqual(receipt.state(in: [.init(seat: "another-Sam-seat", state: .joined)]), .unavailable)
        XCTAssertEqual(receipt.state(in: [.init(seat: "fresh-seat", state: .joined)]), .joined)
        XCTAssertEqual(receipt.state(in: [.init(seat: "fresh-seat", state: .left)]), .ended)
    }

    func testDeletedMembershipCannotRegressToAnOutstandingInvitation() throws {
        let receipt = try XCTUnwrap(HouseholdInvitationReceipt.resent(wasSent: true, seat: "removed-seat", name: "Sam"))
        XCTAssertEqual(receipt.state(in: [.init(seat: "removed-seat", state: .joined)]), .joined)
        XCTAssertEqual(receipt.state(in: []), .unavailable)
        XCTAssertEqual(receipt.state(in: [.init(seat: "replacement-seat", state: .invited)]), .unavailable)
    }

    func testEndedMembershipDoesNotKeepAStaleJoinedClaimDuringReconciliation() throws {
        let receipt = try XCTUnwrap(HouseholdInvitationReceipt.resent(wasSent: true, seat: "same-seat", name: "Sam"))
        XCTAssertEqual(receipt.state(in: [
            .init(seat: "same-seat", state: .joined),
            .init(seat: "same-seat", state: .left)
        ]), .ended)
        XCTAssertEqual(receipt.state(in: [
            .init(seat: "same-seat", state: .joined),
            .init(seat: "other-seat", state: .left)
        ]), .joined)
    }
}
