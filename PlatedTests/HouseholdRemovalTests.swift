import XCTest
import SwiftData
@testable import Plated

@MainActor
final class HouseholdRemovalTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var owner: HouseholdMember!
    private var member: HouseholdMember!

    override func setUp() async throws {
        container = try ModelContainer(for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        HouseholdShare.setMembership(.hosting)
        HouseholdShare.mySeat = nil
        HouseholdOutbox.shared.clear()
        HouseholdShare.groupDefaults.removeObject(forKey: HouseholdShare.Keys.accessEdits)
        HouseholdShare.groupDefaults.removeObject(forKey: HouseholdShare.Keys.removedIDs)
        owner = HouseholdMember(name: "Nate", role: "owner", seat: .head)
        owner.userRecordName = TableIdentity.cached
        member = HouseholdMember(name: "Alessandra", role: "partner", seat: .joined)
        context.insert(owner); context.insert(member)
        try context.save()
    }

    override func tearDown() async throws {
        HouseholdOutbox.shared.clear()
        HouseholdShare.groupDefaults.removeObject(forKey: HouseholdShare.Keys.accessEdits)
        HouseholdShare.groupDefaults.removeObject(forKey: HouseholdShare.Keys.removedIDs)
        HouseholdShare.setMembership(.solo)
        HouseholdShare.mySeat = nil
        container = nil
    }

    private func rows() throws -> [HouseholdMember] { try context.fetch(FetchDescriptor<HouseholdMember>()) }
    private func client() -> HouseholdRemoval.Services {
        .init(identity: { _ in .unavailable }, household: { _ in false }, table: { _ in false })
    }

    func testEmptyUserRecordStillRevokesValidParticipantOnBothShares() async throws {
        member.userRecordName = ""
        member.participantID = "accepted-account"
        let meal = PlannedMeal(date: .now, customTitle: "Pasta", cook: member)
        context.insert(meal); try context.save()
        let record = member.shareRecordName
        var calls: [String] = []
        var service = client()
        service.identity = { _ in XCTFail("A valid participant ID requires no identity guess"); return .unavailable }
        service.household = { calls.append("household:" + $0); return true }
        service.table = { calls.append("table:" + $0); return true }
        let result = await Seats.remove(member, in: context, services: service)
        XCTAssertEqual(result, .removed)
        XCTAssertEqual(calls, ["household:accepted-account", "table:accepted-account"])
        XCTAssertEqual(try rows().count, 1)
        XCTAssertNil(meal.cook)
        XCTAssertEqual(meal.title, "Pasta")
        XCTAssertTrue(HouseholdOutbox.shared.pending.contains { $0.id == record && $0.isDelete })
        XCTAssertTrue(HouseholdShare.cachedRemovedIDs.contains("accepted-account"))
    }

    func testMissingIdentityRecoversOnlyFromTheExactSharedSeat() async throws {
        let record = member.shareRecordName
        var revoked: [String] = []
        var service = client()
        service.identity = { XCTAssertEqual($0, record); return .linked("real-account") }
        service.household = { revoked.append($0); return true }
        service.table = { revoked.append($0); return true }
        let result = await Seats.remove(member, in: context, services: service)
        XCTAssertEqual(result, .removed)
        XCTAssertEqual(revoked, ["real-account", "real-account"])
        XCTAssertEqual(try rows().count, 1)
    }

    func testConfirmedUnlinkedJoinedProfileCanBeRemovedWithoutClaimingRevocation() async throws {
        var service = client()
        service.identity = { _ in .unlinked }
        service.household = { _ in XCTFail("No linked account to revoke"); return false }
        service.table = { _ in XCTFail("No linked account to revoke"); return false }
        let result = await Seats.remove(member, in: context, services: service)
        XCTAssertEqual(result, .removedUnlinked)
        XCTAssertTrue(result.message(name: "Alessandra")!.contains("wasn’t linked"))
        XCTAssertEqual(try rows().count, 1)
        XCTAssertTrue(HouseholdShare.cachedRemovedIDs.isEmpty)
    }

    func testFailedIdentityReadKeepsThePersonAndTheirCookAssignment() async throws {
        let meal = PlannedMeal(date: .now, customTitle: "Pasta", cook: member)
        context.insert(meal); try context.save()
        let result = await Seats.remove(member, in: context, services: client())
        XCTAssertEqual(result, .identityUnavailable)
        XCTAssertEqual(try rows().count, 2)
        XCTAssertTrue(meal.cook === member)
        XCTAssertTrue(HouseholdOutbox.shared.pending.isEmpty)
    }

    func testHouseholdFailureDoesNotDeleteOrAttemptTableRemoval() async throws {
        member.userRecordName = "real-account"
        var service = client()
        service.table = { _ in XCTFail("Household removal must be confirmed first"); return true }
        let result = await Seats.remove(member, in: context, services: service)
        XCTAssertEqual(result, .householdUnavailable)
        XCTAssertEqual(try rows().count, 2)
        XCTAssertTrue(HouseholdShare.cachedRemovedIDs.isEmpty)
    }

    func testPartialRemovalRetainsTheRowAndRetryFinishesBothShares() async throws {
        member.userRecordName = "real-account"
        var service = client()
        service.household = { _ in true }
        let first = await Seats.remove(member, in: context, services: service)
        XCTAssertEqual(first, .tableUnavailable)
        XCTAssertEqual(try rows().count, 2)
        XCTAssertTrue(HouseholdShare.cachedRemovedIDs.isEmpty)
        service.table = { _ in true }
        let retried = await Seats.remove(member, in: context, services: service)
        XCTAssertEqual(retried, .removed)
        XCTAssertEqual(try rows().count, 1)
        XCTAssertTrue(HouseholdShare.cachedRemovedIDs.contains("real-account"))
    }

    func testInvitedSeatWithAcceptedIdentityStillRevokesAccess() async throws {
        member.seat = .invited
        member.participantID = "real-account"
        var revoked: [String] = []
        var service = client()
        service.household = { revoked.append($0); return true }
        service.table = { revoked.append($0); return true }
        let result = await Seats.remove(member, in: context, services: service)
        XCTAssertEqual(result, .removed)
        XCTAssertEqual(revoked, ["real-account", "real-account"])
    }

    func testLocalPersonRemovalNeedsNoCloudAndRetainsTheirMeals() async throws {
        member.seat = .notOnPlated
        HouseholdShare.setMembership(.solo)
        let meal = PlannedMeal(date: .now, customTitle: "Pasta", cook: member)
        context.insert(meal); try context.save()
        let result = await Seats.remove(member, in: context, services: client())
        XCTAssertEqual(result, .removed)
        XCTAssertEqual(try rows().count, 1)
        XCTAssertNil(meal.cook)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PlannedMeal>()).count, 1)
        XCTAssertTrue(HouseholdOutbox.shared.pending.isEmpty)
    }

    func testOrganizerAndMemberPermissionsCannotBeBypassed() async throws {
        let protected = await Seats.remove(owner, in: context, services: client())
        XCTAssertEqual(protected, .protectedPerson)
        HouseholdShare.setMembership(.member(owner: "other-host"))
        let refused = await Seats.remove(member, in: context, services: client())
        XCTAssertEqual(refused, .notOrganizer)
        XCTAssertEqual(try rows().count, 2)
    }

    func testFailedLocalSaveRestoresOnlyRemovalAndKeepsOtherEdits() async throws {
        member.seat = .notOnPlated
        let meal = PlannedMeal(date: .now, customTitle: "Pasta", cook: member)
        context.insert(meal); try context.save()
        owner.bio = "An unrelated edit"
        var service = client()
        service.save = { context, operation in
            if String(describing: operation) == "seat removed" { return false }
            return Persist.save(context, operation)
        }
        let result = await Seats.remove(member, in: context, services: service)
        XCTAssertEqual(result, .saveFailed)
        XCTAssertEqual(try rows().count, 2)
        XCTAssertEqual(meal.cook?.persistentModelID, member.persistentModelID)
        XCTAssertEqual(owner.bio, "An unrelated edit")
        XCTAssertTrue(HouseholdOutbox.shared.pending.isEmpty)
    }
}
