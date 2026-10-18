import XCTest
import SwiftData
import CloudKit
@testable import Plated

@MainActor
final class CommentReactionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var me: String { TableIdentity.cached }

    override func setUp() async throws {
        container = try ModelContainer(for: PlatedStore.schema, configurations: [
            ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        TableLedger.shared.clear()
        TableOutbox.shared.clear()
        TableNews.forgetAll()
        TableNews.rehearsing = true
    }

    override func tearDown() async throws {
        TableLedger.shared.clear()
        TableOutbox.shared.clear()
        TableNews.forgetAll()
        TableNews.rehearsing = false
        container = nil
    }

    private func comment(author: String? = nil, parent: TableComment? = nil) -> TableComment {
        let post: TablePost
        if let existing = parent?.post { post = existing }
        else {
            post = TablePost(authorName: "Sam", dishTitle: "Market tomatoes", kind: "post")
            post.authorID = "sam"
            post.shareZoneOwner = "sam-zone"
            context.insert(post)
        }
        let note = TableComment(authorName: "Nate", text: "Try them with basil.", authorID: author ?? me)
        note.parentCommentID = parent?.shareRecordName
        note.post = post
        context.insert(note)
        try? context.save()
        return note
    }

    private func delivery(_ note: TableComment, author: String = "alessandra", active: Bool = true, at: Date = .now) -> TableShare.Changes {
        var delta = TableShare.Changes()
        delta.reactions = [.init(post: note.shareRecordName, author: author,
            authorName: author == "alessandra" ? "Alessandra" : "Riley",
            value: active ? 1 : 0, at: at)]
        return delta
    }

    func testLikeAndUnlikeQueueOnlyTheCommentTargetInItsSharedZone() throws {
        let note = comment()
        XCTAssertTrue(TableReactions.toggleLike(note, context: context))
        XCTAssertTrue(note.likedByMeNow)
        XCTAssertEqual(note.totalLikes, 1)
        XCTAssertEqual(note.post?.totalPlates, 0)
        let first = try XCTUnwrap(TableOutbox.shared.pending.first)
        XCTAssertEqual(first.work, .plate(post: note.shareRecordName, zoneOwner: "sam-zone", active: true))
        XCTAssertFalse(TableReactions.toggleLike(note, context: context))
        XCTAssertFalse(note.likedByMeNow)
        XCTAssertEqual(note.totalLikes, 0)
        XCTAssertEqual(TableOutbox.shared.pending.count, 1)
        let last = try XCTUnwrap(TableOutbox.shared.pending.first)
        XCTAssertEqual(last.work, .plate(post: note.shareRecordName, zoneOwner: "sam-zone", active: false))
        TableOutbox.shared.finish(first, succeeded: true)
        XCTAssertEqual(TableOutbox.shared.pending, [last], "an in-flight like cannot discard a later unlike")
        let saved = try JSONEncoder().encode(last)
        XCTAssertEqual(try JSONDecoder().decode(TableOutbox.Entry.self, from: saved), last)
    }

    func testReplyLikesAreIndependentOfParentAndPostAndIgnoreOlderArrivals() {
        let parent = comment()
        let reply = comment(parent: parent)
        let now = Date.now
        TableShare.merge(delivery(parent, at: now), into: context)
        TableShare.merge(delivery(reply, author: "riley", at: now), into: context)
        TableShare.merge(delivery(reply, author: "riley", active: false, at: now.addingTimeInterval(2)), into: context)
        TableShare.merge(delivery(reply, author: "riley", at: now), into: context)
        XCTAssertEqual(parent.totalLikes, 1)
        XCTAssertEqual(reply.totalLikes, 0)
        XCTAssertEqual(parent.post?.totalPlates, 0)
        XCTAssertFalse(parent.likedByMeNow)
    }

    func testDeletedCommentRejectsTapAndIncomingReactionsButKeepsReply() {
        let parent = comment()
        let reply = comment(parent: parent)
        TableReactions.toggleLike(parent, context: context)
        var deleted = delivery(parent)
        var remote = TableShare.RemoteNote()
        remote.recordName = parent.shareRecordName
        remote.post = parent.post!.shareRecordName
        remote.deletedAt = .now
        deleted.notes = [remote]
        TableShare.merge(deleted, into: context)
        XCTAssertNotNil(parent.deletedAt)
        XCTAssertEqual(parent.totalLikes, 0)
        XCTAssertFalse(TableReactions.toggleLike(parent, context: context))
        XCTAssertTrue(TableOutbox.shared.isEmpty)
        XCTAssertEqual(reply.parentCommentID, parent.shareRecordName)
        TableShare.merge(delivery(parent), into: context)
        XCTAssertTrue(TableLedger.shared.platers(parent.shareRecordName).isEmpty)
    }

    func testHardDeletedCommentAndDeletedPostClearTheirCommentReactionIntents() {
        let parent = comment()
        let reply = comment(parent: parent)
        TableReactions.toggleLike(parent, context: context)
        var delta = TableShare.Changes()
        delta.deleted = [parent.shareRecordName]
        TableShare.merge(delta, into: context)
        XCTAssertNotNil(parent.deletedAt)
        XCTAssertEqual(parent.text, "")
        XCTAssertTrue(TableOutbox.shared.isEmpty)
        TableReactions.toggleLike(reply, context: context)
        delta.deleted = [reply.post!.shareRecordName]
        let replyID = reply.shareRecordName
        TableShare.merge(delta, into: context)
        XCTAssertTrue(TableOutbox.shared.isEmpty)
        XCTAssertTrue(TableLedger.shared.platers(replyID).isEmpty)
    }

    func testCommentAuthorGetsOneContextualActivityRowOnSomebodyElsesPost() async throws {
        let note = comment()
        let first = delivery(note)
        TableShare.merge(first, into: context)
        await TableNews.deliver(first, context: context)
        let rows = try context.fetch(FetchDescriptor<PlatedNotification>())
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(row.kindValue, .commentReaction)
        XCTAssertEqual(row.body, "Alessandra liked your comment: “Try them with basil.”")
        XCTAssertEqual(row.link, DeepLink.url(post: note.post!.shareRecordName, comment: note.shareRecordName).absoluteString)
        XCTAssertTrue(TableNews.digest(first, newSeats: [], context: context).isEmpty)
        let second = delivery(note, author: "riley")
        TableShare.merge(second, into: context)
        await TableNews.deliver(second, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlatedNotification>()), 1)
        XCTAssertTrue(row.body.contains("Alessandra and Riley"))
    }

    func testOwnLikesOtherPeoplesCommentsAndDeletedCommentsDoNotNotify() {
        let others = comment(author: "sam")
        let mine = comment()
        for delta in [delivery(others), delivery(mine, author: me)] {
            TableShare.merge(delta, into: context)
            TableNews.learnNames(from: delta)
            XCTAssertTrue(TableNews.digest(delta, newSeats: [], context: context).isEmpty)
        }
        mine.deletedAt = .now
        let delta = delivery(mine)
        TableShare.merge(delta, into: context)
        TableNews.learnNames(from: delta)
        XCTAssertTrue(TableNews.digest(delta, newSeats: [], context: context).isEmpty)
    }

    func testUnlikeRewritesWithoutRedatingThenRemovesActivity() async throws {
        let note = comment()
        for delta in [delivery(note), delivery(note, author: "riley")] {
            TableShare.merge(delta, into: context)
            await TableNews.deliver(delta, context: context)
        }
        let row = try XCTUnwrap(context.fetch(FetchDescriptor<PlatedNotification>()).first)
        row.isRead = true
        let date = row.createdAt
        let unlike = delivery(note, active: false)
        TableShare.merge(unlike, into: context)
        await TableNews.deliver(unlike, context: context)
        XCTAssertEqual(row.body, "Riley liked your comment: “Try them with basil.”")
        XCTAssertEqual(row.actorID, "riley")
        XCTAssertEqual(row.actorName, "Riley")
        XCTAssertTrue(row.isRead)
        XCTAssertEqual(row.createdAt, date)
        let last = delivery(note, author: "riley", active: false)
        TableShare.merge(last, into: context)
        await TableNews.deliver(last, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlatedNotification>()), 0)
    }

    func testCommentTombstoneRetractsActivity() async throws {
        let note = comment()
        let liked = delivery(note)
        TableShare.merge(liked, into: context)
        await TableNews.deliver(liked, context: context)
        var removed = TableShare.Changes()
        var remote = TableShare.RemoteNote()
        remote.recordName = note.shareRecordName
        remote.post = note.post!.shareRecordName
        remote.deletedAt = .now
        removed.notes = [remote]
        TableShare.merge(removed, into: context)
        await TableNews.deliver(removed, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlatedNotification>()), 0)
    }
    func testDelayedOfflineReactionCannotOverwriteANewerServerState() async {
        let id = CKRecord.ID(recordName: "plate-note-test-author")
        let incoming = CKRecord(recordType: "PlatedDishPlate", recordID: id)
        incoming["changedAt"] = Date(timeIntervalSince1970: 100) as CKRecordValue
        incoming["active"] = 1 as CKRecordValue
        let newer = CKRecord(recordType: "PlatedDishPlate", recordID: id)
        newer["changedAt"] = Date(timeIntervalSince1970: 200) as CKRecordValue
        newer["active"] = 0 as CKRecordValue
        var writes = 0
        let result = await TableShare.saveReaction(incoming, fetch: { _ in newer }, save: { record in writes += 1; return record })
        XCTAssertTrue(result)
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(TableShare.int(newer, "active"), 0)
    }

    func testConcurrentReactionConflictRefetchesAndKeepsTheNewerIntent() async {
        let id = CKRecord.ID(recordName: "plate-note-test-author")
        let incoming = CKRecord(recordType: "PlatedDishPlate", recordID: id)
        incoming["changedAt"] = Date(timeIntervalSince1970: 200) as CKRecordValue
        incoming["active"] = 0 as CKRecordValue
        let conflict = CKRecord(recordType: "PlatedDishPlate", recordID: id)
        conflict["changedAt"] = Date(timeIntervalSince1970: 150) as CKRecordValue
        conflict["active"] = 1 as CKRecordValue
        var reads = 0
        var writes = 0
        let result = await TableShare.saveReaction(incoming, fetch: { _ in
            reads += 1
            if reads == 1 { throw CKError(.unknownItem) }
            return conflict
        }, save: { record in
            writes += 1
            if writes == 1 { throw CKError(.serverRecordChanged) }
            XCTAssertEqual(TableShare.int(record, "active"), 0)
            XCTAssertEqual(record["changedAt"] as? Date, Date(timeIntervalSince1970: 200))
            return record
        })
        XCTAssertTrue(result)
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(writes, 2)
    }

    func testOfflineReactionWriteRemainsRetryable() async {
        let incoming = CKRecord(recordType: "PlatedDishPlate")
        let result = await TableShare.saveReaction(incoming, fetch: { _ in throw CKError(.networkUnavailable) },
            save: { record in XCTFail("a failed read cannot authorize overwriting a server record"); return record })
        XCTAssertFalse(result)
    }

    func testReplayedCommentRepairsMissingAuthorIdentityBeforeDecidingActivity() {
        let legacy = comment(author: "")
        var delta = delivery(legacy)
        var note = TableShare.RemoteNote()
        note.recordName = legacy.shareRecordName
        note.post = legacy.post!.shareRecordName
        note.authorID = me
        note.authorName = "Nate"
        note.text = legacy.text
        delta.notes = [note]
        TableShare.merge(delta, into: context)
        TableNews.learnNames(from: delta)
        XCTAssertEqual(legacy.authorID, me)
        XCTAssertEqual(TableNews.digest(delta, newSeats: [], context: context).filter { $0.kind == .commentLikes }.count, 1)
    }

}
