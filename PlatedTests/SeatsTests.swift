import XCTest
@testable import Plated

/// The sentence a person gets when there is no link to hand over.
///
/// Four call sites said "Sign in to iCloud to send an invite link." for
/// every failure, and one of them is a member who is signed in and simply
/// does not mint household links (docs/household.md §9). They tapped
/// Invite someone and were sent to Settings for a problem that does not
/// exist.
@MainActor
final class SeatsNoLinkReasonTests: XCTestCase {

    override func setUp() async throws {
        HouseholdShare.setMembership(.solo)
    }

    override func tearDown() async throws {
        HouseholdShare.setMembership(.solo)
    }

    func testAMemberIsToldWhoCanInvite() {
        HouseholdShare.setMembership(.member(owner: "owner-1"), ownerName: "Nate Meadows")
        XCTAssertEqual(
            Seats.noLinkReason(),
            "Only Nate can invite people to this household."
        )
    }

    /// Membership answers before anything the caller knows: a member's
    /// request cannot time out into a different explanation.
    func testAMemberIsToldTheSameThingWhenTheRequestTimedOut() {
        HouseholdShare.setMembership(.member(owner: "owner-1"), ownerName: "Nate Meadows")
        XCTAssertEqual(
            Seats.noLinkReason(.timedOut),
            "Only Nate can invite people to this household."
        )
    }

    func testAHostWhoseRequestTimedOutIsNotToldToSignIn() {
        HouseholdShare.setMembership(.hosting)
        XCTAssertEqual(
            Seats.noLinkReason(.timedOut),
            "iCloud is taking too long. Check your connection and try again."
        )
    }

    func testAHostWithNoAccountIsToldToSignIn() {
        HouseholdShare.setMembership(.hosting)
        XCTAssertEqual(
            Seats.noLinkReason(.noCloud),
            "Sign in to iCloud to send an invite link."
        )
        XCTAssertEqual(Seats.noLinkReason(), "Sign in to iCloud to send an invite link.")
    }

    /// A join that never recorded the host's name still says something
    /// true rather than an empty possessive.
    func testAMemberWithNoRememberedHostNameStillReads() {
        HouseholdShare.setMembership(.member(owner: "owner-1"), ownerName: nil)
        HouseholdShare.groupDefaults.removeObject(forKey: HouseholdShare.Keys.ownerName)
        XCTAssertEqual(
            Seats.noLinkReason(),
            "Only the host can invite people to this household."
        )
    }
}
