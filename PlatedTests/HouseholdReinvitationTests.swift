import XCTest
import CloudKit
import SwiftData
@testable import Plated

@MainActor
final class HouseholdReinvitationTests: XCTestCase {
    private var store: ModelContainer!
    private var context: ModelContext { store.mainContext }
    private let guest = "guest-account"
    private let fresh = "seat-fresh-unpredictable"

    override func setUp() async throws {
        store = try ModelContainer(for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        reset()
    }

    override func tearDown() async throws { reset(); store = nil }

    private func reset() {
        HouseholdOutbox.shared.clear()
        HouseholdShare.setMembership(.solo)
        HouseholdShare.mySeat = nil
        for key in [HouseholdShare.Keys.accessEdits, HouseholdShare.Keys.removedIDs] {
            HouseholdShare.groupDefaults.removeObject(forKey: key)
        }
    }

    private func record(_ name: String = HouseholdShare.rootRecordName) -> CKRecord {
        CKRecord(recordType: name == HouseholdShare.rootRecordName ? HouseholdShare.rootType : HouseholdShare.seatType,
            recordID: .init(recordName: name))
    }

    func testRemovalFreshInvitationClaimAndRepeatRemoval() throws {
        HouseholdShare.setMembership(.hosting)
        let removed = HouseholdReinvitation.revoking(guest, entries: ["another-removed-account"])
        XCTAssertTrue(HouseholdReinvitation.blocks(guest, seat: "old-link", entries: removed))
        let granted = HouseholdReinvitation.authorizing(seat: fresh, entries: removed)
        XCTAssertFalse(HouseholdReinvitation.blocks(guest, seat: fresh, entries: granted))
        XCTAssertTrue(HouseholdReinvitation.blocks(guest, seat: "old-link", entries: granted))
        XCTAssertTrue(HouseholdReinvitation.blocks(guest, seat: nil, entries: granted))
        XCTAssertTrue(granted.contains(guest), "Older clients must fail closed")
        XCTAssertFalse(granted.contains { $0.contains(fresh) }, "The public root must not expose the bearer token")

        var root = HouseholdShare.RemoteRoot()
        root.removedIDs = granted
        var incoming = HouseholdShare.RemoteSeat()
        incoming.recordName = fresh
        incoming.name = "Alessandra"
        incoming.seat = HouseholdMember.Seat.joined.rawValue
        incoming.role = "partner"
        incoming.userRecordName = guest
        incoming.modifiedBy = guest
        incoming.photo = Data([1, 2, 3])
        var changes = HouseholdShare.Changes()
        changes.root = root; changes.seats = [incoming]
        HouseholdShare.merge(changes, into: context)
        let received = try XCTUnwrap(context.fetch(FetchDescriptor<HouseholdMember>()).first)
        XCTAssertEqual(received.photoData, incoming.photo)
        XCTAssertEqual(received.userRecordName, guest)
        XCTAssertFalse(HouseholdShare.cachedRemovedIDs.contains(guest))
        XCTAssertTrue(HouseholdShare.cachedRemovedIDs.contains("another-removed-account"))
        XCTAssertEqual(HouseholdShare.pendingAccessEdits.map(\.action), [.accept])
        let accepted = HouseholdShare.cachedAccessEntries
        let removedAgain = HouseholdReinvitation.revoking(guest, entries: accepted)
        XCTAssertTrue(HouseholdReinvitation.blocks(guest, seat: fresh, entries: removedAgain))
        XCTAssertTrue(HouseholdReinvitation.blocks(guest, seat: "old-link", entries: removedAgain))
    }

    func testOldOrUnclaimedSeatCannotRestoreRemovedAccount() throws {
        HouseholdShare.setMembership(.hosting)
        HouseholdShare.cacheAccessEntries(HouseholdReinvitation.authorizing(seat: fresh, entries: [guest]))
        for (name, state) in [("old-link", HouseholdMember.Seat.joined), (fresh, .invited)] {
            var s = HouseholdShare.RemoteSeat()
            s.recordName = name; s.userRecordName = guest; s.modifiedBy = guest; s.seat = state.rawValue
            var changes = HouseholdShare.Changes(); changes.seats = [s]
            HouseholdShare.merge(changes, into: context)
            XCTAssertTrue(HouseholdOutbox.shared.pending.contains { $0.id == name && $0.isDelete })
        }
        XCTAssertTrue(try context.fetch(FetchDescriptor<HouseholdMember>()).isEmpty)
        XCTAssertTrue(HouseholdShare.cachedRemovedIDs.contains(guest))
    }

    func testConcurrentRevocationWinsOverDelayedAcceptance() {
        let granted = HouseholdReinvitation.authorizing(seat: fresh, entries: [guest])
        let revoked = HouseholdReinvitation.revoking(guest, entries: granted)
        let delayed = HouseholdReinvitation.applying([.init(action: .accept, identity: guest, seat: fresh)], to: revoked)
        XCTAssertEqual(delayed, revoked)
        XCTAssertTrue(HouseholdReinvitation.blocks(guest, seat: fresh, entries: delayed))
    }

    func testAccessAcknowledgementRetainsNewerRemovalAndServerGrants() {
        HouseholdShare.queueAccessEdit(.init(action: .revoke, identity: guest))
        let sent = HouseholdShare.pendingAccessEdits
        HouseholdShare.queueAccessEdit(.init(action: .revoke, identity: "second-account"))
        let server = HouseholdReinvitation.authorizing(seat: fresh, entries: [guest])
        HouseholdShare.acknowledgeAccessEdits(sent, server: server)
        XCTAssertEqual(HouseholdShare.pendingAccessEdits.map(\.identity), ["second-account"])
        XCTAssertTrue(HouseholdReinvitation.allows(guest, seat: fresh, entries: HouseholdShare.cachedAccessEntries))
        XCTAssertTrue(HouseholdShare.cachedRemovedIDs.contains("second-account"))
    }

    func testFailedGrantSaveNeverMakesInvitationReady() async {
        let root = record(); root["removedIDs"] = [guest]
        var saves = 0
        let ready = await HouseholdShare.publishFreshInvitation(seat: fresh, fetch: { root }, save: { _ in
            saves += 1; throw CKError(.networkFailure)
        })
        XCTAssertFalse(ready); XCTAssertEqual(saves, 1)
        XCTAssertFalse(HouseholdReinvitation.allows(guest, seat: fresh, entries: HouseholdShare.cachedAccessEntries))
    }

    func testGrantConflictDoesNotRetryOverAConcurrentRemoval() async {
        let root = record(); root["removedIDs"] = [guest]
        var saves = 0
        let ready = await HouseholdShare.publishFreshInvitation(seat: fresh, fetch: { root }, save: { _ in
            saves += 1; throw CKError(.serverRecordChanged)
        })
        XCTAssertFalse(ready); XCTAssertEqual(saves, 1)
    }

    func testGrantMustBeSavedBeforeInvitationIsReady() async {
        let root = record(); root["removedIDs"] = [guest]
        root["name"] = "Meadows"
        var saved = false
        let ready = await HouseholdShare.publishFreshInvitation(seat: fresh, fetch: { root }, save: { record in
            XCTAssertTrue(HouseholdReinvitation.allows(self.guest, seat: self.fresh,
                entries: HouseholdShare.remoteRoot(from: record).removedIDs))
            XCTAssertEqual(record["name"] as? String, "Meadows")
            saved = true; return record
        })
        XCTAssertTrue(ready); XCTAssertTrue(saved)
        XCTAssertTrue(HouseholdReinvitation.allows(guest, seat: fresh, entries: HouseholdShare.cachedAccessEntries))
    }

    func testRemovalDuringGrantSaveKeepsLinkUnavailable() async {
        let root = record(); root["removedIDs"] = [guest]
        let ready = await HouseholdShare.publishFreshInvitation(seat: fresh, fetch: { root }, save: { record in
            HouseholdShare.queueAccessEdit(.init(action: .revoke, identity: self.guest))
            return record
        })
        XCTAssertFalse(ready)
        XCTAssertTrue(HouseholdReinvitation.blocks(guest, seat: fresh, entries: HouseholdShare.cachedAccessEntries))
    }

    func testMalformedAndOtherSeatsDoNotAuthorize() {
        let entries = [guest, "plated-reinvite-v1:bad:hash", "plated-reinvite-v2:anything"]
        XCTAssertTrue(HouseholdReinvitation.blocks(guest, seat: fresh, entries: entries))
        XCTAssertEqual(HouseholdReinvitation.removedIdentities(in: entries), [guest])
        let good = HouseholdReinvitation.authorizing(seat: fresh, entries: entries)
        XCTAssertFalse(HouseholdReinvitation.allows(guest, seat: fresh + "x", entries: good))
    }

    func testUploadAcknowledgementCannotDropNewerPhotoOrDelete() throws {
        let queue = HouseholdOutbox.shared
        queue.enqueueUpsert(.seat, "seat-person")
        let first = try XCTUnwrap(queue.pending.first)
        queue.enqueueUpsert(.seat, "seat-person")
        queue.acknowledge(first)
        XCTAssertTrue(queue.hasPending("seat-person"))
        let second = try XCTUnwrap(queue.pending.first)
        queue.enqueueDelete(.seat, "seat-person")
        queue.acknowledge(second)
        XCTAssertEqual(queue.pending.first?.isDelete, true)
        queue.acknowledge(try XCTUnwrap(queue.pending.first))
        XCTAssertTrue(queue.isEmpty)
    }

    func testLegacyQueueStillDecodes() throws {
        let data = Data("{\"id\":\"seat-person\",\"kind\":\"seat\",\"isDelete\":false,\"at\":0,\"tries\":0}".utf8)
        let entry = try JSONDecoder().decode(HouseholdOutbox.Entry.self, from: data)
        XCTAssertEqual(entry.id, "seat-person"); XCTAssertNil(entry.revision)
    }

    func testBlockedInvitationHasNoJoinClaimOrNamePrompt() {
        let copy = HouseholdInvitationCopy(state: .removed, host: "Nate Meadows", household: "Meadows")
        XCTAssertFalse(copy.title.contains("Join"))
        XCTAssertFalse(copy.subtitle?.contains("invited you") == true)
        XCTAssertTrue(copy.subtitle?.contains("new invitation") == true)
        XCTAssertFalse(copy.acceptsName)
        XCTAssertEqual(HouseholdInvitationCopy(state: .ready, host: "Nate", household: "Meadows").title, "Join Meadows?")
    }

    func testResumingSeatSetupDoesNotPretendToStartAnotherJoin() {
        let copy = HouseholdInvitationCopy(state: .needsSeat(candidates: []), host: "Nate", household: "Meadows")
        XCTAssertEqual(copy.title, "Finish joining Meadows")
        XCTAssertNil(copy.subtitle); XCTAssertTrue(copy.acceptsName)
    }

    func testParticipantOnlySeatCannotBeClaimedAsEmpty() {
        let linked = HouseholdMember(name: "Sam", role: "partner", seat: .joined, shareRecordName: "linked-seat")
        linked.userRecordName = ""; linked.participantID = guest
        context.insert(linked)
        XCTAssertTrue(HouseholdSync.openSeats(in: [linked]).isEmpty)
        XCTAssertNil(HouseholdSync.bindNamedSeat("linked-seat", in: context))
    }

    func testPartialRecordFailureCannotBeAcknowledgedAsACompletePage() throws {
        let photo = record("profile-with-photo")
        let results: [Result<CKRecord, Error>] = [.success(photo), .failure(CKError(.assetFileNotFound))]
        XCTAssertThrowsError(try CloudRecordPage.records(results))
        XCTAssertEqual(try CloudRecordPage.records([.success(photo)]).map { $0.recordID.recordName }, ["profile-with-photo"])
    }

    func testUpgradeMigratesOnlyAnAlreadyPersistedRemoval() {
        HouseholdShare.setMembership(.hosting)
        HouseholdShare.cacheAccessEntries([guest])
        HouseholdShare.initializeAccessEdits(legacyRootPending: true)
        XCTAssertEqual(HouseholdShare.pendingAccessEdits.map(\.identity), [guest])
        HouseholdShare.acknowledgeAccessEdits(HouseholdShare.pendingAccessEdits, server: [guest])
        HouseholdShare.initializeAccessEdits(legacyRootPending: true)
        XCTAssertTrue(HouseholdShare.pendingAccessEdits.isEmpty, "Ordinary edits cannot manufacture another removal")
    }

    func testJoiningAnEmptyIdentitySeatPreservesThePersonsOwnPhoto() throws {
        let own = HouseholdMember(name: "Alessandra", role: "owner", seat: .head)
        own.userRecordName = TableIdentity.cached; own.photoData = Data([1, 2, 3]); own.bio = "My profile"
        let invitation = HouseholdMember(name: "Contact name", role: "partner", seat: .invited, shareRecordName: fresh)
        invitation.userRecordName = ""; invitation.photoData = Data([9, 9])
        let past = PlannedMeal(date: .now.addingTimeInterval(-86_400), customTitle: "Pasta", cook: own)
        context.insert(own); context.insert(invitation); context.insert(past)
        XCTAssertTrue(HouseholdSync.saveClaimedProfile(invitation, context: context))
        XCTAssertEqual(invitation.name, "Alessandra")
        XCTAssertEqual(invitation.photoData, Data([1, 2, 3]))
        XCTAssertEqual(invitation.bio, "My profile")
        XCTAssertEqual(invitation.userRecordName, TableIdentity.cached)
        XCTAssertEqual(past.cook?.persistentModelID, invitation.persistentModelID)
        XCTAssertEqual(HouseholdShare.mySeat, fresh)
        XCTAssertEqual(try context.fetch(FetchDescriptor<HouseholdMember>()).count, 1)
        XCTAssertTrue(HouseholdOutbox.shared.hasPending(fresh))
    }

    func testFailedJoinSaveRestoresOwnPhotoAndCookLinksWithoutPublishing() throws {
        let own = HouseholdMember(name: "Alessandra", role: "owner", seat: .head)
        own.userRecordName = TableIdentity.cached; own.photoData = Data([1, 2, 3])
        let invitation = HouseholdMember(name: "Contact name", role: "partner", seat: .invited, shareRecordName: fresh)
        invitation.userRecordName = ""
        let past = PlannedMeal(date: .now.addingTimeInterval(-86_400), customTitle: "Pasta", cook: own)
        context.insert(own); context.insert(invitation); context.insert(past)
        let saved = HouseholdSync.saveClaimedProfile(invitation, context: context) { context, operation in
            if String(describing: operation) == "seat claimed" { return false }
            return Persist.save(context, operation)
        }
        XCTAssertFalse(saved)
        XCTAssertEqual(try context.fetch(FetchDescriptor<HouseholdMember>()).count, 2)
        XCTAssertEqual(own.photoData, Data([1, 2, 3]))
        XCTAssertEqual(past.cook?.persistentModelID, own.persistentModelID)
        XCTAssertEqual(invitation.seat, .invited)
        XCTAssertNil(HouseholdShare.mySeat)
        XCTAssertTrue(HouseholdOutbox.shared.isEmpty)
        XCTAssertFalse(HouseholdSync.suppressed)
        XCTAssertTrue(HouseholdSync.saveClaimedProfile(invitation, context: context), "Retry must complete the original claim")
        XCTAssertEqual(invitation.photoData, Data([1, 2, 3]))
    }

    func testClaimCannotDiscardOwnProfileForSomeoneElsesLinkedSeat() {
        let own = HouseholdMember(name: "Alessandra", role: "owner", seat: .head)
        own.userRecordName = TableIdentity.cached; own.photoData = Data([1, 2, 3])
        let taken = HouseholdMember(name: "Sam", role: "partner", seat: .joined, shareRecordName: fresh)
        taken.userRecordName = ""; taken.participantID = "someone-else"
        context.insert(own); context.insert(taken)
        XCTAssertFalse(HouseholdSync.saveClaimedProfile(taken, context: context))
        XCTAssertEqual(own.photoData, Data([1, 2, 3]))
        XCTAssertEqual(taken.name, "Sam")
        XCTAssertTrue(HouseholdOutbox.shared.isEmpty)
    }
}
