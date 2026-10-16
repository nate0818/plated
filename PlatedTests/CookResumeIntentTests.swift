import XCTest
@testable import Plated

final class CookResumeIntentTests: XCTestCase {
    func testQueuedPresentationDoesNotConsumeTheDeepLink() {
        var intent = CookResumeIntent()

        intent.request()
        XCTAssertTrue(intent.isPending)
        XCTAssertTrue(intent.beginPresentation())
        XCTAssertTrue(intent.isPending, "assigning a cover item is not proof that it appeared")
        XCTAssertFalse(intent.beginPresentation(), "only one cover attempt may be in flight")
    }

    func testRejectedPresentationCanBeRetriedAndAppearanceConsumesIt() {
        var intent = CookResumeIntent()

        intent.request()
        XCTAssertTrue(intent.beginPresentation())
        intent.presentationDidNotAppear()
        XCTAssertTrue(intent.isPending)
        XCTAssertTrue(intent.beginPresentation(), "a rejected UIKit presentation must remain retryable")

        intent.coverAppeared()
        XCTAssertFalse(intent.isPending)
        XCTAssertFalse(intent.needsPresentation)
        XCTAssertTrue(intent.isCoverVisible)
    }

    func testTimerTapWhileCoverIsVisibleDoesNotOpenADuplicate() {
        var intent = CookResumeIntent()

        intent.request()
        XCTAssertTrue(intent.beginPresentation())
        intent.coverAppeared()
        intent.request()

        XCTAssertFalse(intent.isPending)
        XCTAssertFalse(intent.beginPresentation())
    }
}
