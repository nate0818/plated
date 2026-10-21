import XCTest

final class ReleaseKeyboardTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    override func setUp() { continueAfterFailure = false }
    override func tearDown() { app.terminate() }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    func testRecipeTitleNotesAndDecimalFieldsHaveAWorkingDoneControl() {
        app.launchArguments = ["-plated-design-review", "-plated-open-recipe-detail", "-appearance", "dark"]
        app.launch()
        app.buttons["Recipe options"].tap()
        XCTAssertTrue(app.buttons["Edit recipe"].waitForExistence(timeout: 20))
        app.buttons["Edit recipe"].tap()
        let title = app.textFields["Name the dish"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        title.typeText(" keyboard check")
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))

        let notes = app.textFields["Anything worth remembering next time."]
        reveal(notes); notes.tap(); notes.typeText("Retained cooking note")
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))

        let details = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'More details'")).firstMatch
        reveal(details); details.tap()
        let calories = app.textFields["Calories per serving"]
        reveal(calories); calories.tap(); calories.typeText("450")
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        let picture = XCTAttachment(screenshot: app.screenshot())
        picture.name = "recipe-decimal-keyboard-done"; picture.lifetime = .keepAlways; add(picture)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(calories.value as? String, "450")
        app.buttons["Cancel"].tap(); app.buttons["Discard"].tap()
        app.buttons["Recipe options"].tap()
        XCTAssertTrue(app.buttons["Edit recipe"].waitForExistence(timeout: 10))
    }
}
