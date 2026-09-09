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

/// Settling a stuck Invited row once CloudKit says the person accepted.
@MainActor
final class SeatsInviteClaimTests: XCTestCase {

    private func standing(
        name: String = "",
        phone: String? = nil,
        email: String? = nil,
        id: String = "ck-alessandra"
    ) -> TableShare.Standing {
        TableShare.Standing(
            phone: phone, email: email, name: name,
            accepted: true, participantID: id
        )
    }

    func testSoleOpenInviteIsClaimedWhenTheyAccept() {
        let invited = HouseholdMember(
            name: "Alessandra", role: "partner", seat: .invited,
            shareRecordName: "seat-invite"
        )
        let head = HouseholdMember(
            name: "Nate", role: "owner", seat: .head, shareRecordName: "seat-nate"
        )
        head.userRecordName = "ck-nate"
        let hit = Seats.inviteToClaim(for: standing(), among: [head, invited])
        XCTAssertTrue(hit === invited)
    }

    /// "They're in" must flip Invited → joined on the same row, never
    /// delete. Deleting erased Alessandra when Invited was her only seat.
    func testMarkInviteArrivedPromotesInPlace() async throws {
        let container = try ModelContainer(
            for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
        let context = container.mainContext
        HouseholdShare.setMembership(.hosting)
        defer { HouseholdShare.setMembership(.solo) }

        let invited = HouseholdMember(
            name: "Alessandra", role: "partner", seat: .invited,
            shareRecordName: "seat-invite"
        )
        context.insert(invited)
        try context.save()

        await Seats.markInviteArrived(invited, in: context)

        let rows = try context.fetch(FetchDescriptor<HouseholdMember>())
        XCTAssertEqual(rows.count, 1, "They're in must not delete the only seat")
        XCTAssertEqual(rows[0].seat, .joined)
        XCTAssertEqual(rows[0].shareRecordName, "seat-invite")
        XCTAssertNotNil(rows[0].joinedAt)
    }

    func testPhoneMatchBeatsAmbiguousNames() {
        let a = HouseholdMember(
            name: "Sam", role: "partner", seat: .invited,
            phoneE164: "+15551110001", shareRecordName: "seat-a"
        )
        let b = HouseholdMember(
            name: "Sam", role: "partner", seat: .invited,
            phoneE164: "+15551110002", shareRecordName: "seat-b"
        )
        let hit = Seats.inviteToClaim(
            for: standing(name: "Sam", phone: "+15551110002"),
            among: [a, b]
        )
        XCTAssertTrue(hit === b)
    }

    func testFirstNameMatchWhenTwoInvitesExist() {
        let alessandra = HouseholdMember(
            name: "Alessandra", role: "partner", seat: .invited,
            shareRecordName: "seat-a"
        )
        let jo = HouseholdMember(
            name: "Jo", role: "partner", seat: .invited,
            shareRecordName: "seat-j"
        )
        let hit = Seats.inviteToClaim(
            for: standing(name: "Alessandra Rossi"),
            among: [alessandra, jo]
        )
        XCTAssertTrue(hit === alessandra)
    }

    func testAlreadySeatedIdentityIsNotClaimedAgain() {
        let invited = HouseholdMember(
            name: "Alessandra", role: "partner", seat: .invited,
            shareRecordName: "seat-invite"
        )
        let joined = HouseholdMember(
            name: "Alessandra Rossi", role: "partner", seat: .joined,
            shareRecordName: "seat-fresh"
        )
        joined.userRecordName = "ck-alessandra"
        XCTAssertNil(Seats.inviteToClaim(
            for: standing(name: "Alessandra"),
            among: [invited, joined]
        ))
    }

    func testTwoOpenInvitesStayAmbiguousWithoutANameOrPhone() {
        let a = HouseholdMember(
            name: "Alessandra", role: "partner", seat: .invited,
            shareRecordName: "seat-a"
        )
        let b = HouseholdMember(
            name: "Jo", role: "partner", seat: .invited,
            shareRecordName: "seat-b"
        )
        XCTAssertNil(Seats.inviteToClaim(for: standing(), among: [a, b]))
    }

    func testDisplayNamePrefersTheShareThenTheInviteLog() {
        XCTAssertEqual(
            Seats.displayName(standingName: "Alessandra Rossi", remembered: "Alessandra"),
            "Alessandra Rossi"
        )
        XCTAssertEqual(
            Seats.displayName(standingName: "", remembered: "Alessandra"),
            "Alessandra"
        )
        XCTAssertEqual(
            Seats.displayName(standingName: "New member", remembered: "Alessandra"),
            "Alessandra"
        )
        XCTAssertEqual(
            Seats.displayName(standingName: "", remembered: nil),
            "New member"
        )
    }

    func testBindShareIdentityCopiesNameAndPhotoFromATwin() async throws {
        let container = try ModelContainer(
            for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
        let context = container.mainContext
        let unnamed = HouseholdMember(
            name: "New member", role: "partner", seat: .joined,
            shareRecordName: "seat-new"
        )
        unnamed.userRecordName = "ck-ale"
        unnamed.participantID = "ck-ale"
        let named = HouseholdMember(
            name: "Alessandra", role: "partner", seat: .joined,
            shareRecordName: "seat-ale"
        )
        named.userRecordName = "ck-ale"
        named.photoData = Data([9, 8, 7])
        context.insert(unnamed)
        context.insert(named)
        try context.save()

        let changed = Seats.bindShareIdentity(in: context, standings: [])
        XCTAssertGreaterThan(changed, 0)
        XCTAssertEqual(unnamed.name, "Alessandra")
        XCTAssertEqual(unnamed.photoData, named.photoData)
    }

    func testBindShareIdentityUsesTheShareParticipantName() async throws {
        let container = try ModelContainer(
            for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
        let context = container.mainContext
        let unnamed = HouseholdMember(
            name: "New member", role: "partner", seat: .joined,
            shareRecordName: "seat-new"
        )
        unnamed.userRecordName = "ck-ale"
        unnamed.participantID = "ck-ale"
        context.insert(unnamed)
        try context.save()

        let changed = Seats.bindShareIdentity(
            in: context,
            standings: [standing(name: "Alessandra Rossi", id: "ck-ale")]
        )
        XCTAssertGreaterThan(changed, 0)
        XCTAssertEqual(unnamed.name, "Alessandra Rossi")
    }
}
