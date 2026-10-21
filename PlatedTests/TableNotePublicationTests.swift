import XCTest
import SwiftData
import CloudKit
@testable import Plated

/// Exercises the actual sender at each async boundary, with no Apple account
/// or network. The transport deliberately changes identity inside its await.
@MainActor
final class TableNotePublicationTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try ModelContainer(for: TablePost.self, TableComment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    private func note(author: String = "account-a", postAuthor: String = "host", owner: String = "host") throws -> TableComment {
        let post = TablePost(authorName: "Host", dishTitle: "Dinner")
        post.authorID = postAuthor
        post.shareRecordName = "post-test"
        post.shareZoneOwner = owner
        let note = TableComment(authorName: "Sam", text: "Try basil", authorID: author)
        note.shareRecordName = "note-test"
        note.post = post
        context.insert(post)
        context.insert(note)
        try context.save()
        return note
    }

    @MainActor
    private final class Probe {
        var account = "account-a"
        var cloudAccount = "account-a"
        var cloudSwitchAt: String?
        var preview = false
        var switchAt: String?
        var calls: [String] = []
        var owners: [String] = []
        var existing: CKRecord?
        var saved: CKRecord?
        var afterFetch: (() -> Void)?

        func visit(_ name: String) {
            calls.append(name)
            if switchAt == name { account = "account-b" }
            if cloudSwitchAt == name { cloudAccount = "account-b" }
        }

        var transport: TableShare.NoteTransport {
            .init(isPreview: { self.preview }, currentAccount: { self.account },
                  localIdentity: { _, account in ([account], ["Sam"]) },
                  accountAvailable: { self.visit("available"); return true },
                  verifiedAccount: { self.visit("identity"); return self.cloudAccount },
                  resolveZone: { owner in
                      self.owners.append(owner)
                      self.visit("zone")
                      return CKRecordZone.ID(zoneName: TableShare.zoneName, ownerName: owner)
                  },
                  fetch: { _ in
                      self.visit("fetch")
                      self.afterFetch?()
                      if let existing = self.existing { return existing }
                      throw CKError(.unknownItem)
                  },
                  save: { record in
                      self.saved = record
                      self.visit("save")
                      return record
                  },
                  confirmed: { _ in self.visit("confirmed") })
        }
    }

    private func push(_ note: TableComment, probe: Probe, actor: String = "account-a", owner: String? = nil, post: String = "post-test") async -> Bool {
        await TableShare.pushNote(note, post: post, zoneOwner: owner ?? note.post!.shareZoneOwner,
                                  expectedAccount: actor, transport: probe.transport)
    }

    func testTaskStartingAfterActorSwitchCannotSendOldAccountReply() async throws {
        let comment = try note()
        let probe = Probe()
        probe.account = "account-b"
        let sent = await push(comment, probe: probe)
        XCTAssertFalse(sent)
        XCTAssertTrue(probe.calls.isEmpty)
        XCTAssertEqual(comment.text, "Try basil")
    }

    func testSwitchAfterAccountAvailabilityStopsBeforeZoneLookup() async throws {
        let comment = try note()
        let probe = Probe()
        probe.switchAt = "available"
        let sent = await push(comment, probe: probe)
        XCTAssertFalse(sent)
        XCTAssertEqual(probe.calls, ["available"])
    }

    func testLegacyOwnZoneIsPinnedBeforeSwitchDuringResolution() async throws {
        let comment = try note(postAuthor: "account-a", owner: "")
        let probe = Probe()
        probe.switchAt = "zone"
        let sent = await push(comment, probe: probe)
        XCTAssertFalse(sent)
        XCTAssertEqual(probe.owners, ["account-a"], "An empty owner cannot become the new account's own zone")
        XCTAssertEqual(probe.calls, ["available", "identity", "zone"])
    }

    func testSwitchAfterRecordFetchCannotSaveOrApplyRemoteTombstone() async throws {
        let comment = try note()
        let probe = Probe()
        probe.switchAt = "fetch"
        let existing = CKRecord(recordType: "PlatedDishNote", recordID: .init(recordName: "note-test", zoneID: .init(zoneName: TableShare.zoneName, ownerName: "host")))
        existing["deletedAt"] = Date.now as CKRecordValue
        probe.existing = existing
        let sent = await push(comment, probe: probe)
        XCTAssertFalse(sent)
        XCTAssertEqual(probe.calls, ["available", "identity", "zone", "fetch"])
        XCTAssertNil(comment.deletedAt)
        XCTAssertEqual(comment.text, "Try basil")
    }

    func testSwitchWhileSaveIsInFlightDoesNotAcknowledgeOrNotifyNewSession() async throws {
        let comment = try note()
        let probe = Probe()
        probe.switchAt = "save"
        let sent = await push(comment, probe: probe)
        XCTAssertFalse(sent)
        XCTAssertEqual(probe.calls, ["available", "identity", "zone", "fetch", "identity", "save"])
        XCTAssertEqual(probe.saved?["authorID"] as? String, "account-a")
    }

    func testStableAuthorPublishesReplyToExactPostAndDestination() async throws {
        let comment = try note()
        comment.parentCommentID = "note-parent"
        let probe = Probe()
        let sent = await push(comment, probe: probe)
        XCTAssertTrue(sent)
        XCTAssertEqual(probe.calls, ["available", "identity", "zone", "fetch", "identity", "save", "identity", "confirmed"])
        XCTAssertEqual(probe.owners, ["host"])
        XCTAssertEqual(probe.saved?["authorID"] as? String, "account-a")
        XCTAssertEqual(probe.saved?["postRecordName"] as? String, "post-test")
        XCTAssertEqual(probe.saved?["parentCommentID"] as? String, "note-parent")
        XCTAssertEqual(probe.saved?["text"] as? String, "Try basil")
    }

    func testPostOwnerCanDeletePeerCommentWithoutRelabelingItsAuthor() async throws {
        let comment = try note(author: "peer", postAuthor: "account-a", owner: "")
        comment.deletedAt = .now
        comment.text = ""
        let probe = Probe()
        let sent = await push(comment, probe: probe)
        XCTAssertTrue(sent)
        XCTAssertEqual(probe.owners, ["account-a"])
        XCTAssertEqual(probe.saved?["authorID"] as? String, "peer")
        XCTAssertNotNil(probe.saved?["deletedAt"] as? Date)
        XCTAssertEqual(probe.saved?["text"] as? String, "")
    }

    func testDelayedOrganizerDeleteCannotBeReplayedAsNewActor() async throws {
        let comment = try note(author: "peer", postAuthor: "account-a", owner: "")
        comment.deletedAt = .now
        comment.text = ""
        let probe = Probe()
        probe.account = "account-b"
        let sent = await push(comment, probe: probe, actor: "account-a")
        XCTAssertFalse(sent)
        XCTAssertTrue(probe.calls.isEmpty)
        XCTAssertEqual(comment.authorID, "peer")
    }

    func testForeignCommentAndUnrelatedPostOwnerCannotWriteOrModerate() async throws {
        let comment = try note(author: "peer", postAuthor: "host", owner: "host")
        let probe = Probe()
        let sent1 = await push(comment, probe: probe)
        XCTAssertFalse(sent1)
        comment.deletedAt = .now
        let sent2 = await push(comment, probe: probe)
        XCTAssertFalse(sent2)
        XCTAssertTrue(probe.calls.isEmpty)
    }

    func testOwnCommentCanBeDeletedOnSomeoneElsesPost() async throws {
        let comment = try note()
        comment.deletedAt = .now
        comment.text = ""
        let probe = Probe()
        let sent = await push(comment, probe: probe)
        XCTAssertTrue(sent)
        XCTAssertEqual(probe.saved?["authorID"] as? String, "account-a")
        XCTAssertNotNil(probe.saved?["deletedAt"] as? Date)
    }

    func testPreviewAndPlaceholderRepliesExitBeforeAnyCloudOperation() async throws {
        let comment = try note()
        let preview = Probe()
        preview.preview = true
        let sent1 = await push(comment, probe: preview)
        XCTAssertFalse(sent1)
        XCTAssertTrue(preview.calls.isEmpty)
        let offline = Probe()
        offline.account = "local-this-device"
        comment.authorID = offline.account
        let sent2 = await push(comment, probe: offline, actor: offline.account)
        XCTAssertFalse(sent2)
        XCTAssertTrue(offline.calls.isEmpty)
    }

    func testMismatchedParentOrDestinationCannotRedirectRetry() async throws {
        let comment = try note()
        let probe = Probe()
        let sent1 = await push(comment, probe: probe, owner: "another-table")
        XCTAssertFalse(sent1)
        let sent2 = await push(comment, probe: probe, post: "another-post")
        XCTAssertFalse(sent2)
        XCTAssertTrue(probe.calls.isEmpty)
    }

    func testChangedParentWhileAwaitingFetchAbortsBeforeSave() async throws {
        let comment = try note()
        let probe = Probe()
        probe.afterFetch = { comment.post?.shareZoneOwner = "another-table" }
        let sent = await push(comment, probe: probe)
        XCTAssertFalse(sent)
        XCTAssertEqual(probe.calls, ["available", "identity", "zone", "fetch"])
    }

    func testExistingRecordForDifferentAuthorOrPostCannotBeOverwritten() async throws {
        for field in ["authorID", "postRecordName"] {
            let comment = try note()
            let probe = Probe()
            let record = CKRecord(recordType: "PlatedDishNote", recordID: .init(recordName: "note-test", zoneID: .init(zoneName: TableShare.zoneName, ownerName: "host")))
            record[field] = "unrelated" as CKRecordValue
            probe.existing = record
            let sent = await push(comment, probe: probe)
            XCTAssertFalse(sent)
            XCTAssertNil(probe.saved)
        }
    }

    func testDeletedServerCommentRemainsDeletedWithoutSavingAgain() async throws {
        let comment = try note()
        let probe = Probe()
        let record = CKRecord(recordType: "PlatedDishNote", recordID: .init(recordName: "note-test", zoneID: .init(zoneName: TableShare.zoneName, ownerName: "host")))
        let deleted = Date.now
        record["deletedAt"] = deleted as CKRecordValue
        probe.existing = record
        let sent = await push(comment, probe: probe)
        XCTAssertTrue(sent)
        XCTAssertEqual(comment.deletedAt, deleted)
        XCTAssertEqual(comment.text, "")
        XCTAssertNil(probe.saved)
        XCTAssertEqual(probe.calls, ["available", "identity", "zone", "fetch", "identity"])
    }

    func testAuthoritativeAccountMismatchRejectsEvenWhenCachedIDIsStillOld() async throws {
        let comment = try note(postAuthor: "account-a", owner: "")
        let probe = Probe()
        probe.cloudAccount = "account-b"
        let sent = await push(comment, probe: probe)
        XCTAssertFalse(sent)
        XCTAssertEqual(probe.account, "account-a", "The stale cache alone must not authorize the write")
        XCTAssertEqual(probe.calls, ["available", "identity"])
        XCTAssertTrue(probe.owners.isEmpty)
    }

    func testAuthoritativeSwitchDuringFetchRejectsBeforeSaveDespiteStaleCache() async throws {
        let comment = try note()
        let probe = Probe()
        probe.cloudSwitchAt = "fetch"
        let sent = await push(comment, probe: probe)
        XCTAssertFalse(sent)
        XCTAssertEqual(probe.account, "account-a")
        XCTAssertEqual(probe.calls, ["available", "identity", "zone", "fetch", "identity"])
        XCTAssertNil(probe.saved)
    }

    func testAuthoritativeSwitchDuringSaveCannotAcknowledgeNewSession() async throws {
        let comment = try note()
        let probe = Probe()
        probe.cloudSwitchAt = "save"
        let sent = await push(comment, probe: probe)
        XCTAssertFalse(sent)
        XCTAssertEqual(probe.account, "account-a")
        XCTAssertEqual(probe.calls, ["available", "identity", "zone", "fetch", "identity", "save", "identity"])
        XCTAssertFalse(probe.calls.contains("confirmed"))
    }

}
