import XCTest

final class SelectedDayPlanTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    override func setUp() { continueAfterFailure = false }

    func launch(_ flags: [String] = [], largeText: Bool = false, light: Bool = false) {
        app.launchArguments = ["-plated-design-review", "-plated-tab", "week", "-appearance", light ? "light" : "dark",
                               "-UIPreferredContentSizeCategoryName", largeText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"] + flags
        app.launch()
        XCTAssertTrue(app.scrollViews["plan-date-wheel"].waitForExistence(timeout: 20))
    }
    func dateButton(_ offset: Int) -> XCUIElement {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date())!
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return app.buttons["week-date-\(c.year!)-\(c.month!)-\(c.day!)"]
    }
    func select(_ offset: Int) {
        let button = dateButton(offset)
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        XCTAssertTrue(button.isHittable)
        button.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
    }
    func expectDinner(_ title: String) {
        let card = app.buttons["featured-dinner-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        XCTAssertEqual(card.label, title)
        XCTAssertEqual(app.buttons.matching(identifier: "featured-dinner-card").count, 1)
        XCTAssertFalse(app.staticTexts["Coming up"].exists)
        XCTAssertFalse(app.staticTexts["Earlier meals"].exists)
    }
    func capture(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
        let t = XCTAttachment(string: app.debugDescription)
        t.name = name + "-tree"; t.lifetime = .keepAlways; add(t)
    }

    func testDateRowReplacesTheDayAndVerticalScrollCannotBrowseOtherDates() {
        launch()
        expectDinner("Salmon Night")
        capture("selected-day-today")
        let content = app.scrollViews["plan-selected-day-content"]
        for _ in 0..<3 { content.swipeUp() }
        expectDinner("Salmon Night")
        XCTAssertTrue(dateButton(0).isSelected)
        XCTAssertFalse(app.staticTexts["Pizza Night"].exists)
        select(1)
        expectDinner("Pizza Night")
        XCTAssertFalse(app.staticTexts["Salmon Night"].exists)
        capture("selected-day-tomorrow")
        select(2); select(1); select(0)
        expectDinner("Salmon Night")
        select(-1)
        XCTAssertFalse(app.buttons["featured-dinner-card"].exists)
        XCTAssertTrue(app.buttons["Plan the night"].exists)
        capture("selected-day-empty-past")
        app.buttons["Back to tonight"].tap()
        expectDinner("Salmon Night")
        XCTAssertTrue(dateButton(0).isSelected)
        app.buttons["Calendar"].tap()
        XCTAssertTrue(app.buttons["Choose a date"].waitForExistence(timeout: 8))
        app.buttons["Back to tonight"].tap()
        expectDinner("Salmon Night")
    }

    func testLargestTextRetainsSameDayMealsAndDateNavigation() {
        launch(["-plated-review-drag"], largeText: true, light: true)
        expectDinner("Drag test dinner")
        let content = app.scrollViews["plan-selected-day-content"]
        let breakfast = app.staticTexts["Morning pancakes"]
        for _ in 0..<5 {
            if breakfast.isHittable { break }
            content.swipeUp()
        }
        XCTAssertTrue(breakfast.isHittable)
        XCTAssertFalse(app.staticTexts["Second dinner"].exists)
        XCTAssertTrue(dateButton(0).isHittable)
        capture("selected-day-largest-text-breakfast")
        select(1)
        expectDinner("Second dinner")
        XCTAssertTrue(app.buttons["featured-dinner-card"].isHittable, "A changed day starts at the top of its content")
        XCTAssertFalse(breakfast.exists)
        capture("selected-day-largest-text-next-day")
    }

    func testSharedDaySwitchesWithoutLeakingIntoTheNextDate() {
        launch(["-plated-review-shared-tonight"])
        let shared = app.buttons["featured-remote-dinner-card"]
        XCTAssertTrue(shared.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["featured-dinner-card"].exists)
        capture("selected-day-shared")
        select(1)
        expectDinner("Pizza Night")
        XCTAssertFalse(shared.exists)
        select(0)
        XCTAssertTrue(shared.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["featured-dinner-card"].exists)
    }
}
