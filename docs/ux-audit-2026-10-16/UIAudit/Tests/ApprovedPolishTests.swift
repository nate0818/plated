import XCTest
import UIKit

final class ApprovedPolishTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    override func setUp() { continueAfterFailure = false }

    func launch(_ flags: [String] = [], light: Bool = false, large: Bool = false) {
        app.terminate()
        app.launchArguments = ["-plated-design-review", "-householdName", "Meadows", "-appearance", light ? "light" : "dark",
            "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"] + flags
        app.launch()
    }
    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    func reveal(_ item: XCUIElement) {
        for _ in 0..<10 {
            if item.isHittable { return }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(item.isHittable, app.debugDescription)
    }

    func testPlanMakesEatingOutAndCookResponsibilityExplicit() {
        launch(["-plated-review-empty-tonight", "-plated-fake-weather"])
        XCTAssertTrue(app.buttons["Choose a meal"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Eating out instead"].isHittable)
        XCTAssertTrue(element("plan-cook-assignment").exists)
        capture("polish-plan-open-dark")
        app.buttons["Eating out instead"].tap()
        XCTAssertTrue(app.buttons["featured-dinner-card"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["featured-dinner-card"].label, "Eating out")
        XCTAssertTrue(app.staticTexts["No cooking needed"].exists)
        capture("polish-plan-eating-out")
        app.buttons["Add a place"].tap()
        let place = element("dining-place")
        XCTAssertTrue(place.waitForExistence(timeout: 8))
        place.tap(); place.typeText("The Corner Cafe")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Change place"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["featured-dinner-card"].label, "Eating out at The Corner Cafe")
    }

    func testContextualTableCreationAndAutomaticDraftRecovery() {
        launch(["-plated-tab", "table", "-plated-review-post-reset"])
        let create = app.buttons["tray-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 20)); create.tap()
        XCTAssertTrue(app.staticTexts["New post"].waitForExistence(timeout: 8))
        let field = element("table-post-text")
        XCTAssertTrue(field.waitForExistence(timeout: 8)); field.tap(); field.typeText("The market tomatoes were excellent.")
        XCTAssertTrue(app.staticTexts["Draft saved on this device"].waitForExistence(timeout: 8))
        app.buttons["Done"].firstMatch.tap()
        capture("polish-composer-draft")
        app.terminate()
        launch(["-plated-open-table-post"])
        XCTAssertTrue(element("table-post-text").waitForExistence(timeout: 20))
        XCTAssertEqual(element("table-post-text").value as? String, "The market tomatoes were excellent.")
        app.buttons["Close post"].tap()
        XCTAssertTrue(app.buttons["Discard post"].waitForExistence(timeout: 5)); app.buttons["Discard post"].tap()
    }

    func testHouseholdRotationRequiresExplicitSave() {
        launch(["-plated-open-household"], light: true)
        XCTAssertTrue(app.buttons["household-settings"].waitForExistence(timeout: 20))
        capture("polish-household-light")
        let day = Calendar.current.weekdaySymbols[Calendar.current.firstWeekday - 1]
        let cell = app.buttons["household-rotation-\(Calendar.current.firstWeekday)"]
        reveal(cell)
        let old = cell.label
        cell.tap()
        XCTAssertTrue(app.navigationBars["Who cooks \(day)?"].waitForExistence(timeout: 8))
        capture("polish-rotation-picker")
        app.buttons["Unassigned"].tap(); app.buttons["Cancel"].tap()
        XCTAssertEqual(cell.label, old, "Browsing a rotation must not change the standing cook")
        cell.tap(); app.buttons["Unassigned"].tap(); app.buttons["Save"].tap()
        XCTAssertEqual(cell.label, "\(day), nobody yet")
    }

    func testActivitySeparatesMarkReadFromClearing() {
        launch(["-plated-open-activity", "-plated-review-notifications"])
        XCTAssertTrue(app.staticTexts["Activity"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["activity-mark-all-read"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Clear all"].exists)
        capture("polish-activity-unread")
        app.buttons["activity-mark-all-read"].tap()
        XCTAssertFalse(app.buttons["activity-mark-all-read"].exists)
        XCTAssertTrue(app.buttons["Activity options"].exists)
        capture("polish-activity-read")
    }

    func testCookingShowsIngredientsBeforeCompletionNotes() {
        launch(["-plated-review-cooking-timer"])
        XCTAssertTrue(app.buttons["Minimize cooking"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.textFields["Cooking note, optional"].exists)
        XCTAssertFalse(app.buttons["End cooking"].exists)
        capture("polish-cooking-active")
        let finish = app.buttons["Finish cooking"]
        XCTAssertTrue(finish.waitForExistence(timeout: 8)); finish.tap()
        XCTAssertTrue(app.staticTexts["Dinner, made."].waitForExistence(timeout: 10))
        XCTAssertTrue(element("Cooking note, optional").exists)
        capture("polish-cooking-finished")
    }

    func testNativeScreenMatrix() {
        let cases: [(String, [String], String)] = [
            ("plan", ["-plated-fake-weather", "-plated-review-household-activity"], "plan-selected-day-content"),
            ("table", ["-plated-tab", "table"], "table-people"),
            ("create", ["-plated-open-create"], "Create"),
            ("composer", ["-plated-open-table-post", "-plated-review-post-reset"], "table-post-text"),
            ("thread", ["-plated-review-comment-reactions", "-plated-open-thread"], "table-post-thread"),
            ("recipes", ["-plated-tab", "cookbook"], "Recipes"),
            ("detail", ["-plated-open-recipe-detail"], "Ingredients"),
            ("groceries", ["-plated-tab", "groceries"], "Groceries"),
            ("profile", ["-plated-open-profile", "-plated-review-household-activity"], "Profile")
        ]
        for light in [false, true] {
            for (name, flags, marker) in cases {
                launch(flags, light: light)
                XCTAssertTrue(element(marker).waitForExistence(timeout: 20), "Missing \(name)")
                capture("polish-\(name)-\(light ? "light" : "dark")")
            }
        }
    }

    func testAccessibilitySizeMatrix() {
        for (name, flags, marker) in [
            ("plan", ["-plated-review-empty-tonight", "-plated-fake-weather"], "Choose a meal"),
            ("groceries", ["-plated-tab", "groceries"], "Groceries"),
            ("composer", ["-plated-open-table-post", "-plated-review-post-reset"], "table-post-text"),
            ("household", ["-plated-open-household"], "household-settings")
        ] {
            launch(flags, light: true, large: true)
            XCTAssertTrue(element(marker).waitForExistence(timeout: 20))
            capture("polish-\(name)-AX5")
            if name == "composer" {
                let people = app.buttons["People"]
                reveal(people)
                XCTAssertGreaterThan(people.frame.width, 300, "Accessibility attachment controls use the full row")
                capture("polish-composer-AX5-attachments")
                people.tap()
                XCTAssertTrue(app.buttons["Tag Sam"].waitForExistence(timeout: 5))
            }
        }
    }

    func testIPadStaysLandscapeAndUsesTwoColumns() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad orientation contract") }
        defer { XCUIDevice.shared.orientation = .portrait }
        launch(["-plated-fake-weather", "-plated-review-household-activity"])
        XCTAssertTrue(element("plan-selected-day-content").waitForExistence(timeout: 20))
        XCUIDevice.shared.orientation = .portrait
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait, .landscapeRight, .portraitUpsideDown] {
            XCUIDevice.shared.orientation = orientation
            // XCTest frames are in physical display coordinates. When the
            // device is upright, a landscape-locked app's horizontal CTA
            // is vertical in those coordinates; window.width alone lies.
            let action = app.buttons["Start cooking"]
            XCTAssertTrue(action.waitForExistence(timeout: 10))
            let meal = app.buttons["featured-dinner-card"]
            let weather = app.staticTexts["Today’s weather"].firstMatch
            XCTAssertTrue(meal.isHittable)
            XCTAssertTrue(weather.exists)
            if orientation.isLandscape {
                XCTAssertGreaterThan(action.frame.width, action.frame.height)
                XCTAssertGreaterThan(weather.frame.minX, meal.frame.midX, "Weather belongs beside the meal on iPad")
                XCTAssertLessThan(app.windows.firstMatch.frame.minY, 50, "Landscape fills the display")
            } else {
                XCTAssertGreaterThan(action.frame.height, action.frame.width,
                    "The horizontal interface must stay rotated when the device is held upright")
            }
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "polish-ipad-display-\(orientation.rawValue)"; shot.lifetime = .keepAlways; add(shot)
            capture("polish-ipad-orientation-\(orientation.rawValue)")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        launch(["-plated-open-table-post", "-plated-review-post-reset"])
        let field = element("table-post-text")
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        field.tap(); field.typeText("Keep this draft while rotating.")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(field.isHittable, "The sheet stays available in the locked landscape interface")
        capture("polish-ipad-portrait-draft")
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(field.isHittable)
        XCTAssertEqual(field.value as? String, "Keep this draft while rotating.")
        capture("polish-ipad-restored-draft")
    }
}
