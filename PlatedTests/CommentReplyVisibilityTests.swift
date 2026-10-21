import XCTest
@testable import Plated

final class CommentReplyVisibilityTests: XCTestCase {
    private typealias Comment = CommentReplyVisibility.Comment

    private func branch(_ id: String, count: Int = 3) -> [Comment] {
        [.init(id: id, parentID: nil)] + (1...count).map {
            .init(id: "\(id)-\($0)", parentID: id)
        }
    }

    func testFirstLoadedSnapshotCollapsesLongBranchesButKeepsShortConversationVisible() {
        var visibility = CommentReplyVisibility()
        let comments = branch("long") + branch("short", count: 2)
        visibility.observe(comments)
        XCTAssertTrue(visibility.isCollapsed("long", descendantCount: 3))
        XCTAssertFalse(visibility.isCollapsed("short", descendantCount: 2))
        XCTAssertFalse(visibility.isCollapsed("long-1", descendantCount: 0))
    }

    func testInitialEmptyQueryDoesNotExpandTheFirstHistoricalSnapshot() {
        var visibility = CommentReplyVisibility()
        visibility.observe([])
        visibility.observe(branch("history"))
        XCTAssertTrue(visibility.isCollapsed("history", descendantCount: 3))
    }

    func testExpandAndHideAreReversibleAndUnrelatedUpdatesRespectTheChoice() {
        var visibility = CommentReplyVisibility()
        let comments = branch("conversation")
        visibility.observe(comments)
        visibility.toggle("conversation", descendantCount: 3, in: comments)
        XCTAssertFalse(visibility.isCollapsed("conversation", descendantCount: 3))
        visibility.toggle("conversation", descendantCount: 3, in: comments)
        XCTAssertTrue(visibility.isCollapsed("conversation", descendantCount: 3))
        visibility.observe(comments + [.init(id: "unrelated", parentID: nil)])
        XCTAssertTrue(visibility.isCollapsed("conversation", descendantCount: 3))
        visibility.toggle("conversation", descendantCount: 3, in: comments)
        XCTAssertFalse(visibility.isCollapsed("conversation", descendantCount: 3))
    }

    func testNotificationRevealsOnlyTheTargetAncestorPath() {
        var visibility = CommentReplyVisibility()
        let comments = branch("target") + branch("other")
            + [.init(id: "nested", parentID: "target-1")]
        visibility.observe(comments)
        visibility.reveal(["nested"], in: comments)
        XCTAssertFalse(visibility.isCollapsed("target", descendantCount: 4))
        XCTAssertFalse(visibility.isCollapsed("target-1", descendantCount: 3))
        XCTAssertTrue(visibility.isCollapsed("other", descendantCount: 3))
    }

    func testTargetingTheParentDoesNotExpandItsReplies() {
        var visibility = CommentReplyVisibility()
        let comments = branch("parent")
        visibility.observe(comments)
        visibility.reveal(["parent"], in: comments)
        XCTAssertTrue(visibility.isCollapsed("parent", descendantCount: 3))
    }

    func testNewReplyStaysVisibleWhenAConversationFirstCrossesTheCollapseThreshold() {
        var visibility = CommentReplyVisibility()
        visibility.observe(branch("conversation", count: 2))
        visibility.observe(branch("conversation", count: 3))
        XCTAssertFalse(visibility.isCollapsed("conversation", descendantCount: 3))
    }

    func testNewReplyRevealsAnExplicitlyHiddenBranchWithoutOpeningOtherBranches() {
        var visibility = CommentReplyVisibility()
        let comments = branch("conversation") + branch("other")
        visibility.observe(comments)
        visibility.toggle("conversation", descendantCount: 3, in: comments)
        visibility.toggle("conversation", descendantCount: 3, in: comments)
        visibility.observe(comments + [.init(id: "new", parentID: "conversation-2")])
        XCTAssertFalse(visibility.isCollapsed("conversation", descendantCount: 4))
        XCTAssertTrue(visibility.isCollapsed("other", descendantCount: 3))
    }

    func testPendingReplyIsVisibleOnReopenAndExplicitHideStillWorks() {
        var visibility = CommentReplyVisibility()
        let comments = branch("pending") + branch("other")
        visibility.observe(comments, pendingIDs: ["pending-2"])
        XCTAssertFalse(visibility.isCollapsed("pending", descendantCount: 3))
        XCTAssertTrue(visibility.isCollapsed("other", descendantCount: 3))
        visibility.toggle("pending", descendantCount: 3, in: comments)
        visibility.observe(comments, pendingIDs: ["pending-2"])
        XCTAssertTrue(visibility.isCollapsed("pending", descendantCount: 3))
    }

    func testLocallySavedReplyIsRevealedBeforeTheNextObservation() {
        var visibility = CommentReplyVisibility()
        let comments = branch("conversation")
        visibility.observe(comments)
        visibility.reveal(["saved"], in: comments + [.init(id: "saved", parentID: "conversation-1")])
        XCTAssertFalse(visibility.isCollapsed("conversation", descendantCount: 4))
    }

    func testTargetRemainsVisibleWhenMissingAncestorsSyncLater() {
        var visibility = CommentReplyVisibility()
        let orphan: Comment = .init(id: "target", parentID: "late-parent")
        visibility.observe([orphan])
        visibility.reveal(["target"], in: [orphan])
        let loaded = branch("grandparent") + [orphan, .init(id: "late-parent", parentID: "grandparent")]
        visibility.observe(loaded)
        XCTAssertFalse(visibility.isCollapsed("grandparent", descendantCount: 5))
        XCTAssertFalse(visibility.isCollapsed("late-parent", descendantCount: 3))
    }

    func testHideAfterTargetRevealIsNotUndoneByARefresh() {
        var visibility = CommentReplyVisibility()
        let comments = branch("conversation")
        visibility.observe(comments)
        visibility.reveal(["conversation-1"], in: comments)
        visibility.toggle("conversation", descendantCount: 3, in: comments)
        visibility.observe(comments)
        XCTAssertTrue(visibility.isCollapsed("conversation", descendantCount: 3))
    }

    func testShrinkingOrEmptyBranchesDoNotTrapRepliesBehindADeadDisclosure() {
        var visibility = CommentReplyVisibility()
        let comments = branch("conversation")
        visibility.observe(comments)
        visibility.toggle("conversation", descendantCount: 3, in: comments)
        visibility.toggle("conversation", descendantCount: 3, in: comments)
        XCTAssertTrue(visibility.isCollapsed("conversation", descendantCount: 1))
        visibility.toggle("conversation", descendantCount: 1, in: comments)
        XCTAssertFalse(visibility.isCollapsed("conversation", descendantCount: 1))
        XCTAssertFalse(visibility.isCollapsed("conversation", descendantCount: 0))
    }

    func testMalformedCycleDoesNotLoopOrExpandUnrelatedBranches() {
        var visibility = CommentReplyVisibility()
        let comments = branch("other") + [
            Comment(id: "a", parentID: "b"),
            Comment(id: "b", parentID: "a"),
            Comment(id: "self", parentID: "self")
        ]
        visibility.observe(comments)
        visibility.reveal(["a", "self"], in: comments)
        XCTAssertFalse(visibility.isCollapsed("b", descendantCount: 3))
        XCTAssertTrue(visibility.isCollapsed("other", descendantCount: 3))
        XCTAssertFalse(visibility.isCollapsed("self", descendantCount: 0))
    }

    func testCollapsedLayoutDoesNotAppendHiddenRepliesAsOrphans() {
        var visibility = CommentReplyVisibility()
        let comments = branch("conversation") + branch("other")
        visibility.observe(comments)
        XCTAssertEqual(visibility.layout(comments).rows.map(\.id), ["conversation", "other"])
        visibility.toggle("conversation", descendantCount: 3, in: comments)
        XCTAssertEqual(visibility.layout(comments).rows.map(\.id),
                       ["conversation", "conversation-1", "conversation-2", "conversation-3", "other"])
        visibility.toggle("conversation", descendantCount: 3, in: comments)
        XCTAssertEqual(visibility.layout(comments).rows.map(\.id), ["conversation", "other"])
    }

    func testDeletedLeavesNeitherInflateReplyCountNorCauseAnInitialCollapse() {
        let comments = branch("conversation", count: 2) + [
            Comment(id: "deleted-1", parentID: "conversation", isDeleted: true),
            Comment(id: "deleted-2", parentID: "conversation", isDeleted: true)
        ]
        let layout = CommentReplyVisibility().layout(comments)
        XCTAssertEqual(layout.liveDescendantCounts["conversation"], 2)
        XCTAssertEqual(layout.rows.map(\.id), ["conversation", "conversation-1", "conversation-2"])
    }

    func testDeletedAncestorRemainsOnlyWhenItConnectsALiveReply() {
        let comments = [
            Comment(id: "root", parentID: nil),
            Comment(id: "deleted-parent", parentID: "root", isDeleted: true),
            Comment(id: "live-reply", parentID: "deleted-parent"),
            Comment(id: "deleted-only-parent", parentID: "root", isDeleted: true),
            Comment(id: "deleted-leaf", parentID: "deleted-only-parent", isDeleted: true)
        ]
        let layout = CommentReplyVisibility().layout(comments)
        XCTAssertEqual(layout.liveDescendantCounts["root"], 1)
        XCTAssertEqual(layout.rows, [.init(id: "root", depth: 0),
                                    .init(id: "deleted-parent", depth: 1),
                                    .init(id: "live-reply", depth: 2)])
        XCTAssertTrue(CommentReplyVisibility().layout(comments.map {
            Comment(id: $0.id, parentID: $0.parentID, isDeleted: true)
        }).rows.isEmpty)
    }

    func testDeletedRootStillOffersItsLiveRepliesWithAnAccurateCount() {
        var visibility = CommentReplyVisibility()
        let comments = [Comment(id: "root", parentID: nil, isDeleted: true)]
            + (1...3).map { Comment(id: "reply-\($0)", parentID: "root") }
            + [Comment(id: "deleted-leaf", parentID: "root", isDeleted: true)]
        let initial = visibility.layout(comments)
        XCTAssertEqual(initial.rows.map(\.id), ["root"])
        XCTAssertEqual(initial.liveDescendantCounts["root"], 3)
        visibility.toggle("root", descendantCount: 3, in: comments)
        XCTAssertEqual(visibility.layout(comments).rows.map(\.id), ["root", "reply-1", "reply-2", "reply-3"])
    }

    func testNewDeletedTombstoneDoesNotReopenALongBranch() {
        var visibility = CommentReplyVisibility()
        let comments = branch("conversation")
        visibility.observe(comments)
        let updated = comments + [Comment(id: "old-deletion", parentID: "conversation", isDeleted: true)]
        visibility.observe(updated, pendingIDs: ["old-deletion"])
        XCTAssertEqual(visibility.layout(updated).rows.map(\.id), ["conversation"])
        XCTAssertEqual(visibility.layout(updated).liveDescendantCounts["conversation"], 3)
    }

    func testOrphansAndCyclesRemainReachableWithoutDuplicatingRows() {
        let comments = [
            Comment(id: "orphan", parentID: "missing"),
            Comment(id: "a", parentID: "b"),
            Comment(id: "b", parentID: "a"),
            Comment(id: "self", parentID: "self"),
            Comment(id: "orphan", parentID: "missing")
        ]
        let rows = CommentReplyVisibility().layout(comments).rows
        XCTAssertEqual(rows.map(\.id), ["orphan", "a", "b", "self"])
    }

    func testNewNestedReplyAndItsContextAreActuallyPresentInTheLayout() {
        var visibility = CommentReplyVisibility()
        let comments = branch("conversation") + branch("other")
        visibility.observe(comments)
        let updated = comments + [Comment(id: "new", parentID: "conversation-1")]
        visibility.observe(updated)
        XCTAssertEqual(visibility.layout(updated).rows.map(\.id),
                       ["conversation", "conversation-1", "new", "conversation-2", "conversation-3", "other"])
    }

}
