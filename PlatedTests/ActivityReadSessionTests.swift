import XCTest
@testable import Plated

final class ActivityReadSessionTests: XCTestCase {
    func testCommentDeepLinkKeepsPostAndEscapedCommentIdentity() {
        let link = DeepLink.url(post: "post with spaces", comment: "note/1?with=punctuation")
        XCTAssertEqual(DeepLink.postID(in: link), "post with spaces")
        XCTAssertEqual(DeepLink.commentID(in: link), "note/1?with=punctuation")
        XCTAssertNil(DeepLink.commentID(in: DeepLink.url(post: "post")))
        XCTAssertNil(DeepLink.commentID(in: URL(string: "plated://plan?comment=note")!))
    }

    func testOpeningInboxDoesNotReadOffscreenItems() {
        var session = ActivityReadSession<String>()
        session.enter()
        session.visibility("top", isVisible: true)
        XCTAssertEqual(session.leave(), ["top"])
    }

    func testScrollingPreservesViewedRowsAfterTheyLeaveViewport() {
        var session = ActivityReadSession<String>()
        session.enter()
        session.visibility("first", isVisible: true)
        session.visibility("first", isVisible: false)
        session.visibility("second", isVisible: true)
        XCTAssertEqual(session.leave(), ["first", "second"])
    }

    func testRetainedInactiveTabDoesNotReadNewActivity() {
        var session = ActivityReadSession<String>()
        session.visibility("arrivedWhileHidden", isVisible: true)
        XCTAssertTrue(session.leave().isEmpty)
        session.enter()
        XCTAssertEqual(session.leave(), ["arrivedWhileHidden"])
    }

    func testLeavingTwiceIsIdempotent() {
        var session = ActivityReadSession<String>()
        session.enter()
        session.visibility("one", isVisible: true)
        XCTAssertEqual(session.leave(), ["one"])
        XCTAssertTrue(session.leave().isEmpty)
    }
}
