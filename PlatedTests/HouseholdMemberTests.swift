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

    func testOccupyingDropsLeftAndInvitedGhosts() {
        let nate = seat("Nate Meadows", .head, role: "owner", user: "nate-id")
        nate.shareRecordName = "seat-nate"
        let nateTwin = seat("Nate", .joined, role: "owner", user: "nate-id")
        nateTwin.shareRecordName = "seat-nate-dup"
        let alessandra = seat("Alessandra", .joined, role: "partner", user: "ale-id")
        alessandra.shareRecordName = "seat-ale"
        let ghost = seat("Alessandra", .invited)
        ghost.shareRecordName = "seat-ale-invite"
        let left = seat("Jess Kaur", .left, user: "jess-id")
        left.shareRecordName = "seat-jess"
        let max = seat("Max", .notOnPlated)
        max.shareRecordName = "seat-max"
        let pending = seat("Sam Ito", .invited)
        pending.shareRecordName = "seat-sam"

        let rows = [nate, nateTwin, alessandra, ghost, left, max, pending]
        XCTAssertEqual(rows.count, 7, "the raw query is what printed 7 people")
        XCTAssertEqual(
            [HouseholdMember].occupying(from: rows).map(\.name),
            ["Nate Meadows", "Alessandra", "Max", "Sam Ito"],
            "left seats, identity twins, and an Invited ghost beside an already-joined twin are not people"
        )
        XCTAssertEqual([HouseholdMember].peopleEyebrow(rows.peopleCount), "4 people")
    }

    func testOccupyingDedupesTheSameIdentity() {
        let a = seat("Riley", .joined, role: "partner", user: "riley-id")
        a.shareRecordName = "seat-1"
        let b = seat("Riley Park", .joined, role: "partner", user: "riley-id")
        b.shareRecordName = "seat-2"
        let nate = seat("Nate", .head, role: "owner", user: "nate-id")
        nate.shareRecordName = "seat-nate"
        XCTAssertEqual(
            [HouseholdMember].occupying(from: [nate, a, b]).map(\.name),
            ["Nate", "Riley"]
        )
    }

    func testPeopleEyebrowIsSingularForOne() {
        XCTAssertEqual([HouseholdMember].peopleEyebrow(1), "1 person")
        XCTAssertEqual([HouseholdMember].peopleEyebrow(0), "0 people")
        XCTAssertEqual([HouseholdMember].peopleEyebrow(7), "7 people")
    }

    func testOccupyingPrefersANamedTwinOverNewMember() {
        let nate = seat("Nate Meadows", .head, role: "owner", user: "nate-id")
        nate.shareRecordName = "seat-nate"
        let unnamed = seat("New member", .joined, role: "partner", user: "ale-id")
        unnamed.shareRecordName = "seat-new"
        let named = seat("Alessandra", .joined, role: "partner", user: "ale-id")
        named.shareRecordName = "seat-ale"
        named.photoData = Data([1, 2, 3])
        XCTAssertEqual(
            [HouseholdMember].occupying(from: [nate, unnamed, named]).map(\.name),
            ["Nate Meadows", "Alessandra"]
        )
    }

    func testOwnRowOmitsRole() {
        let nate = seat("Nate Meadows", .head, role: "owner", user: TableIdentity.cached)
        XCTAssertEqual(nate.subtitle, "You · Owner")
        XCTAssertFalse(nate.subtitle.contains("Head of table"))
        XCTAssertFalse(nate.subtitle.contains("Host"))
        let partner = seat("Alessandra", .joined, role: "partner", user: TableIdentity.cached)
        XCTAssertEqual(partner.subtitle, "You")
        XCTAssertFalse(partner.subtitle.contains("Head of table"))
        XCTAssertFalse(partner.subtitle.contains("Owner"))
    }

    /// TF26: the owner row already carried a real CloudKit id while this
    /// phone's cache was still a `local-` placeholder. `isMe` was false,
    /// so the People row could not say You (and DESIGN forbids Head of
    /// table there).
    func testOwnRowIsYouWhileIdentityIsStillAPlaceholder() {
        HouseholdShare.setMembership(.hosting)
        defer { HouseholdShare.setMembership(.solo) }
        XCTAssertTrue(TableIdentity.isPlaceholder)
        let nate = seat("Nate Meadows", .head, role: "owner", user: "ck-nate-real")
        nate.shareRecordName = "seat-nate"
        XCTAssertTrue(nate.isMe)
        XCTAssertEqual(nate.subtitle, "You · Owner")
        XCTAssertFalse(nate.subtitle.contains("Head of table"))
    }

    func testForeignRowIsNotMeWhileIdentityIsAPlaceholder() {
        HouseholdShare.setMembership(.hosting)
        defer { HouseholdShare.setMembership(.solo) }
        let ale = seat("Alessandra", .joined, role: "partner", user: "ck-ale")
        XCTAssertFalse(ale.isMe)
        XCTAssertEqual(ale.subtitle, "Plans and cooks with you")
    }

    func testAnotherHostReadsAsHost() {
        HouseholdShare.setMembership(.member(owner: "owner-1"))
        defer { HouseholdShare.setMembership(.solo) }
        let nate = seat("Nate Meadows", .head, role: "owner", user: "nate-id")
        XCTAssertEqual(nate.subtitle, "Host")
        XCTAssertNotEqual(nate.subtitle, "You · Head of table")
        XCTAssertFalse(nate.subtitle.contains("Head of table"))
    }

    func testOccupyingDropsNamedInviteBesideUnnamedJoin() {
        let nate = seat("Nate Meadows", .head, role: "owner", user: "nate-id")
        nate.shareRecordName = "seat-nate"
        let unnamed = seat("New member", .joined, role: "partner", user: "ale-id")
        unnamed.shareRecordName = "seat-new"
        let invited = seat("Alessandra", .invited, role: "partner")
        invited.shareRecordName = "seat-invite"
        let occupying = [HouseholdMember].occupying(from: [nate, unnamed, invited])
        XCTAssertEqual(
            occupying.map(\.name),
            ["Nate Meadows", "New member"],
            "the Invited name is the same person as the restored join"
        )
        XCTAssertEqual([HouseholdMember].peopleEyebrow(occupying.count), "2 people")
    }

    func testActorLookupUsesUserRecordName() {
        let nate = seat("Nate Meadows", .head, role: "owner", user: TableIdentity.cached)
        nate.participantID = TableIdentity.cached
        let ale = seat("Alessandra", .joined, role: "partner", user: "ck-ale")
        ale.participantID = nil
        let members = [nate, ale]
        XCTAssertEqual(members.actor(id: "ck-ale", name: "Alessandra")?.name, "Alessandra")
        XCTAssertEqual(
            members.actor(id: TableIdentity.cached, name: "Alessandra")?.name,
            "Alessandra",
            "a join notice stamped with the host still resolves to the named joiner"
        )
        XCTAssertEqual(
            members.actor(id: "ck-ale", name: "Nate Meadows")?.name,
            "Alessandra",
            "a plan notice stamped with the host's name still resolves to the author id"
        )
    }

    func testSeatedLineDropsUnnamedPlaceholders() {
        XCTAssertTrue(HouseholdIdentity.isUnnamed("New member"))
        XCTAssertTrue(HouseholdIdentity.isRestoredPlaceholder("New member"))
        XCTAssertTrue(HouseholdIdentity.isUnnamed("Someone"))
        XCTAssertFalse(HouseholdIdentity.isRestoredPlaceholder("Me"))
        XCTAssertFalse(HouseholdIdentity.isUnnamed("Alessandra"))
        XCTAssertEqual(
            HouseholdIdentity.seatedLine(names: ["Nate Meadows", "New member"]),
            "Nate"
        )
        XCTAssertEqual(
            HouseholdIdentity.seatedLine(names: ["Nate Meadows", "Alessandra"]),
            "Nate and Alessandra"
        )
    }
}
