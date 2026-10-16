import XCTest
@testable import Plated

final class PlanEmptyCopyTests: XCTestCase {
    func testHardEmptyRowTitle() {
        XCTAssertEqual(PlanEmptyCopy.rowTitle, "No meal planned yet")
        XCTAssertEqual(PlanEmptyCopy.pastRowTitle, "No meal planned")
        XCTAssertEqual(PlanEmptyCopy.rowTitle(past: false), "No meal planned yet")
        XCTAssertEqual(PlanEmptyCopy.rowTitle(past: true), "No meal planned")
    }

    func testPlanCTAs() {
        XCTAssertEqual(PlanEmptyCopy.rowAction, "Plan")
        XCTAssertEqual(PlanEmptyCopy.planNight, "Plan the night")
        XCTAssertEqual(PlanEmptyCopy.planNightA11y, "Plan the night")
        XCTAssertEqual(PlanEmptyCopy.eatOutAction, "Eat out")
        XCTAssertEqual(PlanEmptyCopy.noOneAssigned, "No one assigned")
    }

    func testKillsSoftAmbientPosters() {
        let banned = [
            "Something good starts here.",
            "Nothing plated",
            "Nothing plated yet",
            "Nothing plated for tonight",
            "Plan dinner",
            "Plan this night",
            "Plan tonight",
            "A night off the menu",
        ]
        let stamped = [
            PlanEmptyCopy.rowTitle,
            PlanEmptyCopy.pastRowTitle,
            PlanEmptyCopy.planNight,
            PlanEmptyCopy.rowAction,
            PlanEmptyCopy.heroSubcopy,
            PlanEmptyCopy.detailBody,
        ]
        for bad in banned {
            for good in stamped {
                XCTAssertFalse(good == bad, "stamped string must not equal banned \(bad)")
            }
        }
    }

    func testSlice3ContinuumAndLongPressVerbs() {
        XCTAssertEqual(PlanEmptyCopy.nextWeekEyebrow, "Next week")
        XCTAssertEqual(PlanEmptyCopy.planMealAction, "Plan a meal")
        XCTAssertEqual(PlanEmptyCopy.assignSomeoneAction, "Assign someone")
        XCTAssertEqual(PlanEmptyCopy.illCookAction, "I'll cook")
        XCTAssertEqual(PlanEmptyCopy.clearNightAction, "Clear night")
        XCTAssertEqual(PlanEmptyCopy.eatOutAction, "Eat out")
    }
}
