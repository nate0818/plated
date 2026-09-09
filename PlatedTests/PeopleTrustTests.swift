import XCTest
@testable import Plated

/// Product-wide people-trust: any host, any invitee. A joined seat must
/// never become the host, never stay a killed label when the invite is
/// known, and never wear the host's face. TF27 Meadows is one repro;
/// stranger names prove the rule is not a one-household patch.
@MainActor
final class PeopleTrustTests: XCTestCase {

    override func setUp() async throws {
        HouseholdInviteLog.reset()
        HouseholdShare.setMembership(.solo)
        HouseholdShare.mySeat = nil
    }

    override func tearDown() async throws {
        HouseholdInviteLog.reset()
        HouseholdShare.setMembership(.solo)
        HouseholdShare.mySeat = nil
    }

    // MARK: Host-clone predicate

    func testHostCloneIsFirstNameOrExactNotASharedGivenName() {
        XCTAssertTrue(HouseholdIdentity.isHostClone("Nate", hosts: ["Nate Meadows"]))
        XCTAssertTrue(HouseholdIdentity.isHostClone("Nate Meadows", hosts: ["Nate"]))
        XCTAssertTrue(HouseholdIdentity.isHostClone("sam chen", hosts: ["Sam Chen"]))
        XCTAssertFalse(HouseholdIdentity.isHostClone("Nate Smith", hosts: ["Nate Meadows"]))
        XCTAssertFalse(HouseholdIdentity.isHostClone("Jordan Lee", hosts: ["Sam Chen"]))
        XCTAssertFalse(HouseholdIdentity.isHostClone("Alessandra", hosts: ["Nate Meadows"]))
        XCTAssertFalse(HouseholdIdentity.isHostClone("New member", hosts: ["Nate"]))
    }

    func testCopyLockStringsAreExact() {
        XCTAssertEqual(HouseholdIdentity.PeopleCopy.ownOwnerSubtitle, "You · Owner")
        XCTAssertEqual(HouseholdIdentity.PeopleCopy.ownMemberSubtitle, "You")
        XCTAssertEqual(HouseholdIdentity.PeopleCopy.missingSelfName, "Add your name")
        XCTAssertEqual(HouseholdIdentity.PeopleCopy.missingOtherName, "No name yet")
        XCTAssertEqual(HouseholdIdentity.PeopleCopy.unnamedInvite, "Invited")
        XCTAssertEqual(HouseholdIdentity.PeopleCopy.reachFailure, "Couldn't reach iCloud.")
        XCTAssertEqual(HouseholdIdentity.PeopleCopy.tryAgain, "Try again")
        XCTAssertFalse(HouseholdIdentity.PeopleCopy.ownOwnerSubtitle.contains("Head of table"))
        XCTAssertFalse(HouseholdIdentity.PeopleCopy.ownOwnerSubtitle.contains("Host"))
    }

    func testDisplayFallbacksNeverPrintNewMember() {
        XCTAssertNotEqual(
            Seats.displayName(standingName: "", remembered: nil),
            "New member"
        )
        XCTAssertEqual(
            Seats.displayName(standingName: "", remembered: nil),
            "No name yet"
        )
        XCTAssertEqual(
            Seats.displayName(standingName: "New member", remembered: nil),
            "No name yet"
        )
        XCTAssertEqual(
            Seats.displayName(standingName: "New member", remembered: "Jordan Lee"),
            "Jordan Lee"
        )
        let unnamed = HouseholdMember(
            name: "New member", role: "partner", seat: .joined, shareRecordName: "seat-new"
        )
        let host = HouseholdMember(
            name: "Sam Chen", role: "owner", seat: .head, shareRecordName: "seat-sam"
        )
        host.userRecordName = TableIdentity.cached
        let drawn = Seats.resolvedDisplay(for: unnamed, among: [host, unnamed], reader: host)
        XCTAssertNotEqual(drawn.name, "New member")
        XCTAssertNotEqual(drawn.name, "Someone")
        XCTAssertEqual(drawn.name, "No name yet")
    }

    func testKilledLabelsAreUnnamedAndNeverPrint() {
        XCTAssertTrue(HouseholdIdentity.isUnnamed("New member"))
        XCTAssertTrue(HouseholdIdentity.isUnnamed("Someone"))
        XCTAssertTrue(HouseholdIdentity.isUnnamed("No name yet"))
        XCTAssertTrue(HouseholdIdentity.isUnnamed("Invited"))
        XCTAssertTrue(HouseholdIdentity.isUnnamed("Add your name"))
        XCTAssertEqual(
            HouseholdIdentity.printedName(
                stored: "New member", resolved: nil, isSelf: false, seat: .joined
            ),
            "No name yet"
        )
        XCTAssertEqual(
            HouseholdIdentity.printedName(
                stored: "", resolved: nil, isSelf: true, seat: .head
            ),
            "Add your name"
        )
        XCTAssertEqual(
            HouseholdIdentity.printedName(
                stored: "", resolved: nil, isSelf: false, seat: .invited
            ),
            "Invited"
        )
        XCTAssertEqual(
            HouseholdIdentity.printedName(
                stored: "Alessandra", resolved: nil, isSelf: false, seat: .joined
            ),
            "Alessandra"
        )
    }

    func testRememberedNameNeverReturnsTheHost() {
        HouseholdInviteLog.record(name: "Nate", phone: nil, email: nil, seat: "seat-host")
        XCTAssertNil(
            HouseholdInviteLog.rememberedName(
                forPhone: nil, email: nil, excluding: ["Nate Meadows"]
            ),
            "a sole unique log entry that is the host must not name a joiner"
        )
        HouseholdInviteLog.reset()
        HouseholdInviteLog.record(
            name: "Alessandra", phone: "+15551112222", email: nil, seat: "seat-invite"
        )
        XCTAssertEqual(
            HouseholdInviteLog.rememberedName(
                forPhone: nil, email: nil, excluding: ["Nate Meadows"]
            ),
            "Alessandra"
        )
        XCTAssertNil(
            HouseholdInviteLog.rememberedName(
                forPhone: "+15551112222", email: nil, excluding: ["Alessandra"]
            ),
            "a phone hit that is itself the excluded host name is refused"
        )
    }

    // MARK: TF27 Meadows

    func testTF27UnnamedJoinNextToOwnerNateResolvesToAlessandra() async throws {
        let (context, nate, joiner) = try household(
            host: "Nate Meadows",
            joinerStored: "New member",
            inviteName: "Alessandra",
            invitePhoto: Data([1, 2, 3])
        )
        nate.photoData = Data([9, 9, 9])

        let changed = Seats.bindShareIdentity(in: context, standings: [])
        XCTAssertGreaterThan(changed, 0)
        XCTAssertEqual(joiner.name, "Alessandra")
        XCTAssertNotEqual(joiner.name, nate.name)
        XCTAssertNotEqual(joiner.name, "Nate")
        XCTAssertEqual(joiner.photoData, Data([1, 2, 3]))
        XCTAssertNotEqual(joiner.photoData, nate.photoData)

        let people = [nate, joiner]
        let drawn = Seats.resolvedDisplay(for: joiner, among: people, reader: nate)
        XCTAssertEqual(drawn.name, "Alessandra")
        XCTAssertEqual(drawn.photo, Data([1, 2, 3]))
        XCTAssertEqual(drawn.subtitle, "Plans and cooks with you")
        XCTAssertEqual(Seats.seatedCaption(among: people, reader: nate), "Nate and Alessandra")
        XCTAssertNotEqual(Seats.seatedCaption(among: people, reader: nate), "Nate and Nate")
    }

    func testTF27StandingNamedNateDoesNotCloneTheHost() async throws {
        let (context, nate, joiner) = try household(
            host: "Nate Meadows",
            joinerStored: "New member",
            inviteName: "Alessandra"
        )
        _ = Seats.bindShareIdentity(
            in: context,
            standings: [standing(name: "Nate Meadows", id: "ck-joiner")]
        )
        XCTAssertEqual(joiner.name, "Alessandra")
        XCTAssertNotEqual(joiner.name, nate.name)
        XCTAssertNotEqual(joiner.name, "Nate Meadows")
    }

    func testTF27AlreadyClonedHostNameIsRepaired() async throws {
        let (context, nate, joiner) = try household(
            host: "Nate",
            joinerStored: "Nate",
            inviteName: "Alessandra"
        )
        XCTAssertEqual(joiner.name, "Nate", "precondition: the bug already wrote the host")
        _ = Seats.bindShareIdentity(in: context, standings: [])
        XCTAssertEqual(joiner.name, "Alessandra")
        let drawn = Seats.resolvedDisplay(for: joiner, among: [nate, joiner], reader: nate)
        XCTAssertEqual(drawn.name, "Alessandra")
        XCTAssertEqual(Seats.seatedCaption(among: [nate, joiner], reader: nate), "Nate and Alessandra")
    }

    func testHostStandingWithoutInviteBecomesNoNameYetNotHost() async throws {
        let (context, nate, joiner) = try household(
            host: "Nate Meadows",
            joinerStored: "New member",
            inviteName: nil
        )
        _ = Seats.bindShareIdentity(
            in: context,
            standings: [standing(name: "Nate", id: "ck-joiner")]
        )
        XCTAssertEqual(joiner.name, "No name yet")
        XCTAssertNotEqual(joiner.name, nate.firstName)
        XCTAssertNotEqual(joiner.name, nate.name)
        let drawn = Seats.resolvedDisplay(for: joiner, among: [nate, joiner], reader: nate)
        XCTAssertEqual(drawn.name, "No name yet")
        XCTAssertEqual(Seats.seatedCaption(among: [nate, joiner], reader: nate), "Nate")
    }

    func testIdentityCollisionWithHostStillUsesInviteName() async throws {
        let (context, nate, joiner) = try household(
            host: "Nate Meadows",
            joinerStored: "New member",
            inviteName: "Alessandra"
        )
        joiner.userRecordName = nate.userRecordName
        joiner.participantID = nate.userRecordName
        _ = Seats.bindShareIdentity(in: context, standings: [])
        XCTAssertEqual(joiner.name, "Alessandra")
        XCTAssertNotEqual(joiner.name, nate.name)
    }

    func testHostPhotoIsNeverCopiedOntoTheJoiner() async throws {
        let (context, nate, joiner) = try household(
            host: "Nate Meadows",
            joinerStored: "New member",
            inviteName: "Alessandra",
            invitePhoto: nil
        )
        nate.photoData = Data([7, 7, 7])
        joiner.photoData = nate.photoData
        _ = Seats.bindShareIdentity(in: context, standings: [])
        XCTAssertEqual(joiner.name, "Alessandra")
        XCTAssertNil(joiner.photoData)
        let drawn = Seats.resolvedDisplay(for: joiner, among: [nate, joiner], reader: nate)
        XCTAssertNil(drawn.photo)
    }

    // MARK: Stranger household (Sam Chen / Jordan Lee)

    func testStrangerJoinResolvesInviteeNeverHost() async throws {
        let (context, sam, jordan) = try household(
            host: "Sam Chen",
            joinerStored: "New member",
            inviteName: "Jordan Lee",
            invitePhoto: Data([4, 5, 6]),
            joinerID: "ck-jordan"
        )
        sam.photoData = Data([1, 1, 1])
        _ = Seats.bindShareIdentity(
            in: context,
            standings: [standing(name: "Sam Chen", id: "ck-jordan")]
        )
        XCTAssertEqual(jordan.name, "Jordan Lee")
        XCTAssertNotEqual(jordan.name, sam.name)
        XCTAssertNotEqual(jordan.name, "Sam")
        XCTAssertEqual(jordan.photoData, Data([4, 5, 6]))

        let people = [sam, jordan]
        let drawn = Seats.resolvedDisplay(for: jordan, among: people, reader: sam)
        XCTAssertEqual(drawn.name, "Jordan Lee")
        XCTAssertEqual(drawn.subtitle, "Plans and cooks with you")
        XCTAssertNotEqual(drawn.subtitle, "You")
        XCTAssertEqual(Seats.seatedCaption(among: people, reader: sam), "Sam and Jordan")
        XCTAssertNotEqual(Seats.seatedCaption(among: people, reader: sam), "Sam and Sam")

        let owner = Seats.resolvedDisplay(for: sam, among: people, reader: sam)
        XCTAssertEqual(owner.subtitle, "You · Owner")
        XCTAssertFalse(owner.subtitle.contains("Head of table"))
        XCTAssertFalse(owner.subtitle.contains("Host"))
    }

    func testStrangerInvitedTwinSuppliesNameAndPhoto() async throws {
        let container = try ModelContainer(
            for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
        let context = container.mainContext
        let host = HouseholdMember(
            name: "Sam Chen", role: "owner", seat: .head, shareRecordName: "seat-sam"
        )
        host.userRecordName = "ck-sam"
        let invited = HouseholdMember(
            name: "Jordan Lee", role: "partner", seat: .invited, shareRecordName: "seat-invite"
        )
        invited.photoData = Data([2, 2, 2])
        let joiner = HouseholdMember(
            name: "Someone", role: "partner", seat: .joined, shareRecordName: "seat-new"
        )
        joiner.userRecordName = "ck-jordan"
        joiner.participantID = "ck-jordan"
        context.insert(host)
        context.insert(invited)
        context.insert(joiner)
        try context.save()

        _ = Seats.bindShareIdentity(in: context, standings: [])
        XCTAssertEqual(joiner.name, "Jordan Lee")
        XCTAssertEqual(joiner.photoData, invited.photoData)
        XCTAssertNotEqual(joiner.name, host.name)
    }

    func testOwnRowCopyLockOwnerAndMember() {
        HouseholdShare.setMembership(.hosting)
        defer { HouseholdShare.setMembership(.solo) }
        let sam = HouseholdMember(
            name: "Sam Chen", role: "owner", seat: .head, shareRecordName: "seat-sam"
        )
        sam.userRecordName = TableIdentity.cached
        let jordan = HouseholdMember(
            name: "Jordan Lee", role: "partner", seat: .joined, shareRecordName: "seat-j"
        )
        jordan.userRecordName = "ck-jordan"
        let people = [sam, jordan]
        let owner = Seats.resolvedDisplay(for: sam, among: people, reader: sam)
        XCTAssertEqual(owner.subtitle, "You · Owner")
        XCTAssertEqual(owner.name, "Sam Chen")
        XCTAssertFalse(owner.subtitle.contains("Head of table"))

        HouseholdShare.setMembership(.member(owner: "ck-sam"))
        HouseholdShare.mySeat = "seat-j"
        jordan.userRecordName = TableIdentity.cached
        sam.userRecordName = "ck-sam"
        let memberSelf = Seats.resolvedDisplay(for: jordan, among: people, reader: jordan)
        XCTAssertEqual(memberSelf.subtitle, "You")
        XCTAssertFalse(memberSelf.subtitle.contains("Owner"))
        XCTAssertFalse(memberSelf.subtitle.contains("Head of table"))
        let hostRow = Seats.resolvedDisplay(for: sam, among: people, reader: jordan)
        XCTAssertEqual(hostRow.subtitle, "Host")
        XCTAssertNotEqual(hostRow.subtitle, "You · Owner")
    }

    func testUnnamedInvitePrintsInvitedNotHostInitials() {
        let sam = HouseholdMember(
            name: "Sam Chen", role: "owner", seat: .head, shareRecordName: "seat-sam"
        )
        sam.userRecordName = TableIdentity.cached
        let invite = HouseholdMember(
            name: "", role: "partner", seat: .invited, shareRecordName: "seat-invite"
        )
        let drawn = Seats.resolvedDisplay(for: invite, among: [sam, invite], reader: sam)
        XCTAssertEqual(drawn.name, "Invited")
        XCTAssertNotEqual(drawn.name, "Sam")
        XCTAssertNotEqual(drawn.name, "New member")
        XCTAssertEqual(drawn.name.first.map(String.init), "I")
    }

    func testSelfMissingNamePrintsAddYourName() {
        let me = HouseholdMember(
            name: "Me", role: "owner", seat: .head, shareRecordName: "seat-me"
        )
        me.userRecordName = TableIdentity.cached
        let drawn = Seats.resolvedDisplay(for: me, among: [me], reader: me)
        XCTAssertEqual(drawn.name, "Add your name")
        XCTAssertEqual(drawn.subtitle, "You · Owner")
    }

    func testActivityActorUsesJoinerNotHost() {
        let sam = HouseholdMember(
            name: "Sam Chen", role: "owner", seat: .head, shareRecordName: "seat-sam"
        )
        sam.userRecordName = TableIdentity.cached
        sam.participantID = TableIdentity.cached
        let jordan = HouseholdMember(
            name: "Jordan Lee", role: "partner", seat: .joined, shareRecordName: "seat-j"
        )
        jordan.userRecordName = "ck-jordan"
        let members = [sam, jordan]
        XCTAssertEqual(
            members.actor(id: "ck-jordan", name: "Jordan Lee")?.name,
            "Jordan Lee"
        )
        XCTAssertEqual(
            members.actor(id: TableIdentity.cached, name: "Jordan Lee")?.name,
            "Jordan Lee",
            "a join notice stamped with the host still resolves to the joiner"
        )
        XCTAssertEqual(
            members.actor(id: "ck-jordan", name: "Sam Chen")?.name,
            "Jordan Lee",
            "a plan notice stamped with the host's name still resolves to the author"
        )
        XCTAssertNotEqual(
            members.actor(id: TableIdentity.cached, name: "Jordan Lee")?.name,
            sam.name
        )
    }

    func testTF27ActivityActorUsesAlessandraNotNate() {
        let nate = HouseholdMember(
            name: "Nate Meadows", role: "owner", seat: .head, shareRecordName: "seat-nate"
        )
        nate.userRecordName = TableIdentity.cached
        nate.participantID = TableIdentity.cached
        let ale = HouseholdMember(
            name: "Alessandra", role: "partner", seat: .joined, shareRecordName: "seat-ale"
        )
        ale.userRecordName = "ck-ale"
        let members = [nate, ale]
        XCTAssertEqual(
            members.actor(id: TableIdentity.cached, name: "Alessandra")?.name,
            "Alessandra"
        )
        XCTAssertEqual(
            members.actor(id: "ck-ale", name: "Nate Meadows")?.name,
            "Alessandra"
        )
    }

    func testPeopleListResolvedDisplayMatchesBindForStrangerHousehold() async throws {
        let (context, sam, jordan) = try household(
            host: "Sam Chen",
            joinerStored: "New member",
            inviteName: "Jordan Lee"
        )
        _ = Seats.bindShareIdentity(in: context, standings: [])
        let roster = Seats.all(in: context)
        let occupying = [HouseholdMember].occupying(from: roster)
        let reader = occupying.me ?? sam
        let drawn = occupying.map { Seats.resolvedDisplay(for: $0, among: occupying, reader: reader) }
        XCTAssertEqual(drawn.map(\.name).sorted(), ["Jordan Lee", "Sam Chen"])
        XCTAssertFalse(drawn.contains { $0.name == "New member" || $0.name == "Sam Chen" && $0.subtitle == "Plans and cooks with you" })
        XCTAssertEqual(drawn.first { $0.name == "Sam Chen" }?.subtitle, "You · Owner")
        XCTAssertEqual(drawn.first { $0.name == "Jordan Lee" }?.subtitle, "Plans and cooks with you")
        XCTAssertEqual(Seats.seatedCaption(among: occupying, reader: reader), "Sam and Jordan")
    }

    func testOwnerNameIsNeverWrittenOntoJoinerFromBind() async throws {
        let (context, host, joiner) = try household(
            host: "Sam Chen",
            joinerStored: "New member",
            inviteName: "Jordan Lee"
        )
        _ = Seats.bindShareIdentity(
            in: context,
            standings: [standing(name: host.name, id: "ck-joiner")]
        )
        XCTAssertNotEqual(joiner.name, host.name)
        XCTAssertNotEqual(joiner.name, host.firstName)
        XCTAssertEqual(joiner.name, "Jordan Lee")
    }

    // MARK: Fixtures

    private func standing(name: String, id: String) -> TableShare.Standing {
        TableShare.Standing(
            phone: nil, email: nil, name: name, accepted: true, participantID: id
        )
    }

    private func household(
        host: String,
        joinerStored: String,
        inviteName: String?,
        invitePhoto: Data? = nil,
        joinerID: String = "ck-joiner"
    ) throws -> (ModelContext, HouseholdMember, HouseholdMember) {
        let container = try ModelContainer(
            for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
        let context = container.mainContext
        let head = HouseholdMember(
            name: host, role: "owner", seat: .head, shareRecordName: "seat-host"
        )
        head.userRecordName = "ck-host"
        let joiner = HouseholdMember(
            name: joinerStored, role: "partner", seat: .joined, shareRecordName: "seat-new"
        )
        joiner.userRecordName = joinerID
        joiner.participantID = joinerID
        if let inviteName {
            HouseholdInviteLog.record(
                name: inviteName, phone: "+15550001111", email: nil, seat: "seat-invite"
            )
            let invited = HouseholdMember(
                name: inviteName, role: "partner", seat: .invited, shareRecordName: "seat-invite"
            )
            invited.photoData = invitePhoto
            context.insert(invited)
        }
        context.insert(head)
        context.insert(joiner)
        try context.save()
        return (context, head, joiner)
    }
}
