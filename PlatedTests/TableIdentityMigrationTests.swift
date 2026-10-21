import XCTest
import SwiftData
@testable import Plated

/// Model-only identity confirmation. These fixtures use an in-memory store,
/// never ask CloudKit for an identity, and never change the cached account.
@MainActor
final class TableIdentityMigrationTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let placeholder = "local-this-device"
    private let confirmed = "confirmed-account"

    override func setUp() async throws {
        container = try ModelContainer(
            for: TablePost.self, TableComment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    override func tearDown() async throws { container = nil }

    private func post(_ title: String, author: String, owner: String = "", remote: Bool = false) -> TablePost {
        let post = TablePost(authorName: "Sam", dishTitle: title, caption: "Original caption")
        post.authorID = author
        post.shareZoneOwner = owner
        post.isRemote = remote
        context.insert(post)
        return post
    }

    private func comment(_ text: String, author: String, on post: TablePost) -> TableComment {
        let comment = TableComment(authorName: "Sam", text: text, authorID: author)
        comment.post = post
        context.insert(comment)
        return comment
    }

    func testBothOfflinePostsRetainTheirRecordAndDestinationWhenIdentityConfirms() throws {
        let personal = post("My Table", author: placeholder)
        let shared = post("Household Table", author: placeholder, owner: "household-owner")
        let personalRecord = personal.shareRecordName
        let sharedRecord = shared.shareRecordName
        try context.save()

        XCTAssertEqual(try TableIdentity.reattributeTableContent(
            from: placeholder, to: confirmed, in: context), 2)
        XCTAssertEqual(personal.authorID, confirmed)
        XCTAssertEqual(shared.authorID, confirmed)
        XCTAssertEqual(personal.shareRecordName, personalRecord)
        XCTAssertEqual(shared.shareRecordName, sharedRecord)
        XCTAssertEqual(personal.shareZoneOwner, "")
        XCTAssertEqual(shared.shareZoneOwner, "household-owner")
        XCTAssertFalse(personal.isPublished)
        XCTAssertFalse(shared.isPublished)
        XCTAssertFalse(personal.isRemote)
        XCTAssertFalse(shared.isRemote)

        // A new context reads the saved authors, not just the live objects.
        let saved = try ModelContext(container).fetch(FetchDescriptor<TablePost>())
        XCTAssertEqual(Set(saved.map(\.shareRecordName)), [personalRecord, sharedRecord])
        XCTAssertTrue(saved.allSatisfy { $0.authorID == confirmed })
    }

    func testOnlyExactLocalAuthorshipMigratesNeverPeersRemoteRowsOrDiscover() throws {
        let own = post("Own", author: placeholder)
        let anotherPlaceholder = post("Other device", author: "local-other-device")
        let peer = post("Peer", author: "peer-account")
        let unstamped = post("Legacy unstamped", author: "")
        let remote = post("Remote", author: placeholder, owner: "peer-account", remote: true)
        let discover = post("Discover", author: placeholder)
        discover.isDiscover = true
        try context.save()

        XCTAssertEqual(try TableIdentity.reattributeTableContent(
            from: placeholder, to: confirmed, in: context), 1)
        XCTAssertEqual(own.authorID, confirmed)
        XCTAssertEqual(anotherPlaceholder.authorID, "local-other-device")
        XCTAssertEqual(peer.authorID, "peer-account")
        XCTAssertEqual(unstamped.authorID, "")
        XCTAssertEqual(remote.authorID, placeholder)
        XCTAssertEqual(discover.authorID, placeholder)
    }

    func testOwnRepliesOnPeerPostsMigrateWithoutChangingTheThreadOrOtherAuthors() throws {
        let peerPost = post("Peer post", author: "peer-account", owner: "peer-account", remote: true)
        let ownPost = post("Own post", author: placeholder)
        let peerComment = comment("Peer comment", author: "peer-account", on: ownPost)
        let otherDeviceComment = comment("Other device", author: "local-other-device", on: peerPost)
        let ownComment = comment("Offline comment", author: placeholder, on: peerPost)
        let ownReply = comment("Offline reply", author: placeholder, on: peerPost)
        ownReply.parentCommentID = ownComment.shareRecordName
        ownReply.replyToName = "Sam"
        ownReply.deletedAt = Date(timeIntervalSince1970: 100)
        let commentRecord = ownComment.shareRecordName
        let replyRecord = ownReply.shareRecordName
        try context.save()

        XCTAssertEqual(try TableIdentity.reattributeTableContent(
            from: placeholder, to: confirmed, in: context), 3)
        XCTAssertEqual(ownComment.authorID, confirmed)
        XCTAssertEqual(ownReply.authorID, confirmed)
        XCTAssertEqual(peerPost.authorID, "peer-account")
        XCTAssertEqual(peerComment.authorID, "peer-account")
        XCTAssertEqual(otherDeviceComment.authorID, "local-other-device")
        XCTAssertTrue(ownComment.post === peerPost)
        XCTAssertTrue(ownReply.post === peerPost)
        XCTAssertEqual(ownComment.shareRecordName, commentRecord)
        XCTAssertEqual(ownReply.shareRecordName, replyRecord)
        XCTAssertEqual(ownReply.parentCommentID, commentRecord)
        XCTAssertEqual(ownReply.replyToName, "Sam")
        XCTAssertEqual(ownReply.deletedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(peerPost.shareZoneOwner, "peer-account")
        XCTAssertTrue(peerPost.isRemote)

        let saved = try ModelContext(container).fetch(FetchDescriptor<TableComment>())
        XCTAssertEqual(saved.first { $0.shareRecordName == replyRecord }?.authorID, confirmed)
        XCTAssertEqual(saved.first { $0.shareRecordName == replyRecord }?.post?.shareRecordName, peerPost.shareRecordName)
    }

    func testKnownAccountSwitchDoesNotAdoptPostsOrComments() throws {
        let oldPost = post("Previous account", author: "old-account")
        let oldComment = comment("Previous account comment", author: "old-account", on: oldPost)
        let provisional = post("Provisional", author: placeholder)
        try context.save()

        XCTAssertEqual(try TableIdentity.reattributeTableContent(
            from: "old-account", to: confirmed, in: context), 0)
        XCTAssertEqual(oldPost.authorID, "old-account")
        XCTAssertEqual(oldComment.authorID, "old-account")
        XCTAssertEqual(provisional.authorID, placeholder)
        XCTAssertFalse(context.hasChanges)
    }

    func testInvalidOrUnconfirmedIdentityTransitionsDoNotChangeRowsOrSave() throws {
        let own = post("Own", author: placeholder)
        try context.save()
        var saves = 0
        for (old, new) in [(placeholder, ""), (placeholder, "local-another"),
                           (placeholder, placeholder), ("", confirmed), ("local-", confirmed)] {
            XCTAssertEqual(try TableIdentity.reattributeTableContent(
                from: old, to: new, in: context, save: { _ in saves += 1; return true }), 0)
        }
        XCTAssertEqual(saves, 0)
        XCTAssertEqual(own.authorID, placeholder)
        XCTAssertFalse(context.hasChanges)
    }

    func testPublishedContentKeepsItsAcknowledgmentAndPayload() throws {
        let own = post("Already shared", author: placeholder, owner: "household-owner")
        own.isPublished = true
        own.photoData = Data([1, 2, 3])
        own.taggedNames = ["Riley"]
        own.pollOptions = ["Pasta", "Pizza"]
        let created = own.createdAt
        let record = own.shareRecordName
        try context.save()

        XCTAssertEqual(try TableIdentity.reattributeTableContent(
            from: placeholder, to: confirmed, in: context), 1)
        XCTAssertEqual(own.authorID, confirmed)
        XCTAssertEqual(own.authorName, "Sam")
        XCTAssertEqual(own.caption, "Original caption")
        XCTAssertEqual(own.shareRecordName, record)
        XCTAssertEqual(own.shareZoneOwner, "household-owner")
        XCTAssertTrue(own.isPublished)
        XCTAssertEqual(own.createdAt, created)
        XCTAssertEqual(own.photoData, Data([1, 2, 3]))
        XCTAssertEqual(own.taggedNames, ["Riley"])
        XCTAssertEqual(own.pollOptions, ["Pasta", "Pizza"])
    }

    func testSaveFailureRestoresOnlyChangedAuthorsAndAllowsRetryWithoutLosingOtherEdits() throws {
        let own = post("Own", author: placeholder)
        let peer = post("Peer", author: "peer-account", owner: "peer-account", remote: true)
        let note = comment("My comment", author: placeholder, on: peer)
        try context.save()
        own.caption = "Unsaved writing must survive"
        peer.caption = "Unrelated incoming edit"
        var saves = 0

        XCTAssertThrowsError(try TableIdentity.reattributeTableContent(
            from: placeholder, to: confirmed, in: context, save: { _ in
                saves += 1
                XCTAssertEqual(own.authorID, self.confirmed)
                XCTAssertEqual(note.authorID, self.confirmed)
                return false
            }))
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(own.authorID, placeholder)
        XCTAssertEqual(note.authorID, placeholder)
        XCTAssertEqual(peer.authorID, "peer-account")
        XCTAssertEqual(own.caption, "Unsaved writing must survive")
        XCTAssertEqual(peer.caption, "Unrelated incoming edit")
        XCTAssertTrue(context.hasChanges)

        XCTAssertEqual(try TableIdentity.reattributeTableContent(
            from: placeholder, to: confirmed, in: context), 2)
        let saved = try ModelContext(container).fetch(FetchDescriptor<TablePost>())
        XCTAssertEqual(saved.first { $0.shareRecordName == own.shareRecordName }?.authorID, confirmed)
        XCTAssertEqual(saved.first { $0.shareRecordName == own.shareRecordName }?.caption, "Unsaved writing must survive")
        XCTAssertEqual(saved.first { $0.shareRecordName == peer.shareRecordName }?.caption, "Unrelated incoming edit")
    }

    func testRepeatingTheSameMigrationDoesNotClaimANewPlaceholder() throws {
        let own = post("Own", author: placeholder)
        try context.save()
        XCTAssertEqual(try TableIdentity.reattributeTableContent(
            from: placeholder, to: confirmed, in: context), 1)
        let another = post("Another identity", author: "local-another-device")
        try context.save()
        var saves = 0

        XCTAssertEqual(try TableIdentity.reattributeTableContent(
            from: placeholder, to: confirmed, in: context, save: { _ in saves += 1; return true }), 0)
        XCTAssertEqual(saves, 0)
        XCTAssertEqual(own.authorID, confirmed)
        XCTAssertEqual(another.authorID, "local-another-device")
    }

    // MARK: Confirmation ordering

    @MainActor
    private final class ConfirmationHarness {
        var identity: String
        var lookups: [CheckedContinuation<String?, Never>?] = []
        var onLookup: (() -> Void)?
        var saveResults: [Bool] = []
        var migrations = 0
        var commits = 0
        var resets: [String] = []
        var failures = 0

        init(identity: String) { self.identity = identity }

        var services: TableIdentity.ConfirmationServices {
            .init(
                current: { self.identity },
                lookup: {
                    await withCheckedContinuation { continuation in
                        self.lookups.append(continuation)
                        self.onLookup?()
                    }
                },
                migrate: { old, new, context in
                    self.migrations += 1
                    try TableIdentity.reattributeTableContent(from: old, to: new, in: context, save: { context in
                        if !self.saveResults.isEmpty, !self.saveResults.removeFirst() { return false }
                        do { try context.save(); return true } catch { return false }
                    })
                },
                commit: { _, new, _ in self.identity = new; self.commits += 1 },
                reset: { new in self.identity = new; self.resets.append(new) },
                failed: { _ in self.failures += 1 }
            )
        }

        func finish(_ index: Int, with answer: String?) {
            guard lookups.indices.contains(index), let continuation = lookups[index] else {
                XCTFail("The controlled identity lookup was not suspended"); return
            }
            lookups[index] = nil
            continuation.resume(returning: answer)
        }

        func finishRemaining() {
            for index in lookups.indices where lookups[index] != nil { finish(index, with: nil) }
        }
    }

    private func suspendedConfirmation(_ harness: ConfirmationHarness) async -> Task<String?, Never> {
        let started = expectation(description: "Identity lookup suspended")
        harness.onLookup = { started.fulfill() }
        let task = Task { await TableIdentity.confirmAndReattribute(in: context, services: harness.services) }
        await fulfillment(of: [started], timeout: 2)
        harness.onLookup = nil
        return task
    }

    func testOverlappingConfirmationsRetryTheExactPlaceholderAfterFirstSaveFails() async throws {
        let own = post("Offline post", author: placeholder)
        let note = comment("Offline comment", author: placeholder, on: own)
        try context.save()
        let harness = ConfirmationHarness(identity: placeholder)
        harness.saveResults = [false, true]
        defer { harness.finishRemaining() }
        let first = await suspendedConfirmation(harness)
        let second = await suspendedConfirmation(harness)
        XCTAssertEqual(harness.identity, placeholder, "Lookup must not consume the placeholder")

        harness.finish(0, with: confirmed)
        let failed = await first.value
        XCTAssertNil(failed)
        XCTAssertEqual(harness.identity, placeholder)
        XCTAssertEqual(own.authorID, placeholder)
        XCTAssertEqual(note.authorID, placeholder)
        XCTAssertEqual(harness.commits, 0, "Books/cache cannot move before model authors are saved")

        harness.finish(1, with: confirmed)
        let recovered = await second.value
        XCTAssertEqual(recovered, confirmed)
        XCTAssertEqual(harness.identity, confirmed)
        XCTAssertEqual(own.authorID, confirmed)
        XCTAssertEqual(note.authorID, confirmed)
        XCTAssertEqual(harness.migrations, 2)
        XCTAssertEqual(harness.commits, 1)
        XCTAssertEqual(harness.failures, 1)
        XCTAssertTrue(harness.resets.isEmpty)
    }

    func testStaleKnownAccountAnswerCannotUndoANewerAccountReset() async throws {
        let oldPost = post("Account A post", author: "account-a")
        try context.save()
        let harness = ConfirmationHarness(identity: "account-a")
        defer { harness.finishRemaining() }
        let oldLookup = await suspendedConfirmation(harness)
        let newLookup = await suspendedConfirmation(harness)

        harness.finish(1, with: "account-b")
        let switched = await newLookup.value
        XCTAssertEqual(switched, "account-b")
        harness.finish(0, with: "account-a")
        let stale = await oldLookup.value
        XCTAssertNil(stale)
        XCTAssertEqual(harness.identity, "account-b")
        XCTAssertEqual(harness.resets, ["account-b"])
        XCTAssertEqual(harness.migrations, 0)
        XCTAssertEqual(oldPost.authorID, "account-a")
    }

    func testStalePlaceholderAnswerCannotReattributeToAnotherConfirmedAccount() async throws {
        let own = post("Offline post", author: placeholder)
        try context.save()
        let harness = ConfirmationHarness(identity: placeholder)
        defer { harness.finishRemaining() }
        let staleLookup = await suspendedConfirmation(harness)
        let newLookup = await suspendedConfirmation(harness)

        harness.finish(1, with: "account-b")
        let accepted = await newLookup.value
        XCTAssertEqual(accepted, "account-b")
        harness.finish(0, with: "account-a")
        let stale = await staleLookup.value
        XCTAssertNil(stale)
        XCTAssertEqual(harness.identity, "account-b")
        XCTAssertEqual(own.authorID, "account-b")
        XCTAssertEqual(harness.migrations, 1)
        XCTAssertEqual(harness.commits, 1)
        XCTAssertTrue(harness.resets.isEmpty)
    }

    func testOverlappingMatchingAnswersReuseOnlyACompletedConfirmation() async throws {
        let own = post("Offline post", author: placeholder)
        try context.save()
        let harness = ConfirmationHarness(identity: placeholder)
        defer { harness.finishRemaining() }
        let first = await suspendedConfirmation(harness)
        let second = await suspendedConfirmation(harness)

        harness.finish(0, with: confirmed)
        let firstResult = await first.value
        harness.finish(1, with: confirmed)
        let secondResult = await second.value
        XCTAssertEqual(firstResult, confirmed)
        XCTAssertEqual(secondResult, confirmed)
        XCTAssertEqual(own.authorID, confirmed)
        XCTAssertEqual(harness.migrations, 1)
        XCTAssertEqual(harness.commits, 1)
    }

    func testCancelledConfirmationDoesNotMigrateOrReturnAConfirmedAccount() async throws {
        let own = post("Offline post", author: placeholder)
        try context.save()
        let harness = ConfirmationHarness(identity: placeholder)
        defer { harness.finishRemaining() }
        let task = await suspendedConfirmation(harness)
        task.cancel()
        harness.finish(0, with: confirmed)
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertEqual(harness.identity, placeholder)
        XCTAssertEqual(own.authorID, placeholder)
        XCTAssertEqual(harness.migrations, 0)
        XCTAssertEqual(harness.commits, 0)
    }

    func testUnresolvedAnswersLeaveIdentityAndAuthorshipUntouched() async throws {
        let own = post("Offline post", author: placeholder)
        try context.save()
        let harness = ConfirmationHarness(identity: placeholder)
        for answer: String? in [nil, "", "local-not-confirmed"] {
            var services = harness.services
            services.lookup = { answer }
            let result = await TableIdentity.confirmAndReattribute(in: context, services: services)
            XCTAssertNil(result)
        }
        XCTAssertEqual(harness.identity, placeholder)
        XCTAssertEqual(own.authorID, placeholder)
        XCTAssertEqual(harness.migrations, 0)
        XCTAssertEqual(harness.commits, 0)
        XCTAssertTrue(harness.resets.isEmpty)
    }
}
