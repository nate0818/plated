import XCTest
@testable import Plated

final class DateWheelInteractionTests: XCTestCase {
    private let first = Date(timeIntervalSince1970: 1_800_000_000)

    func testTouchDownAndRepeatedGeometryAreSilent() {
        var wheel = DateWheelInteraction()
        wheel.begin(at: first)
        wheel.cross(to: first, at: 1)
        XCTAssertEqual(wheel.feedbackRevision, 0)
        XCTAssertEqual(wheel.activity, .scrubbing)
    }

    func testFastFlingCoalescesFeedbackWithoutLosingThePreview() {
        var wheel = DateWheelInteraction()
        wheel.begin(at: first)
        wheel.cross(to: first.addingTimeInterval(86_400), at: 1)
        wheel.cross(to: first.addingTimeInterval(172_800), at: 1.01)
        XCTAssertEqual(wheel.feedbackRevision, 1)
        XCTAssertEqual(wheel.previewDate, first.addingTimeInterval(172_800))
        wheel.cross(to: first.addingTimeInterval(259_200), at: 1.06)
        XCTAssertEqual(wheel.feedbackRevision, 2)
    }

    func testSettlingCommitsOnceWithoutADuplicateTick() {
        var wheel = DateWheelInteraction()
        wheel.begin(at: first)
        let next = first.addingTimeInterval(86_400)
        wheel.cross(to: next, at: 1)
        XCTAssertEqual(wheel.settle(on: next, at: 1.1), next)
        XCTAssertNil(wheel.settle(on: next, at: 1.2))
        XCTAssertEqual(wheel.feedbackRevision, 1)
        XCTAssertNil(wheel.previewDate)
    }

    func testTodayInterruptsAnOldDeceleration() {
        var wheel = DateWheelInteraction()
        let oldTarget = first.addingTimeInterval(86_400)
        wheel.begin(at: oldTarget)
        wheel.navigate(to: first, feedback: false)
        wheel.cross(to: oldTarget, at: 1)
        XCTAssertNil(wheel.settle(on: oldTarget, at: 2))
        XCTAssertEqual(wheel.previewDate, first)
        XCTAssertEqual(wheel.feedbackRevision, 0)
    }

    func testCancelledScrubCannotOverwriteThePlan() {
        var wheel = DateWheelInteraction()
        wheel.begin(at: first)
        wheel.cancel()
        XCTAssertNil(wheel.settle(on: first.addingTimeInterval(86_400), at: 1))
        XCTAssertEqual(wheel.activity, .idle)
    }

    func testCenterGeometryClampsOverscrollAndRejectsInvalidLayouts() {
        XCTAssertEqual(DateWheelInteraction.centeredIndex(offset: -200, leadingInset: 200, stride: 48, count: 731), 0)
        XCTAssertEqual(DateWheelInteraction.centeredIndex(offset: -128, leadingInset: 200, stride: 48, count: 731), 2)
        XCTAssertEqual(DateWheelInteraction.centeredIndex(offset: 50_000, leadingInset: 200, stride: 48, count: 731), 730)
        XCTAssertNil(DateWheelInteraction.centeredIndex(offset: .nan, leadingInset: 0, stride: 48, count: 731))
        XCTAssertNil(DateWheelInteraction.centeredIndex(offset: 0, leadingInset: 0, stride: 0, count: 0))
    }
}
