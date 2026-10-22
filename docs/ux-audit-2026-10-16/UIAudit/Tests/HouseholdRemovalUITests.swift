import XCTest

final class HouseholdRemovalUITests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    override func setUp() { continueAfterFailure = false }

    func launch(_ flags: [String] = [], table: Bool = false, large: Bool = false) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-plated-design-review", "-plated-tab", table ? "week" : "home",
            "-appearance", "light", "-UIPreferredContentSizeCategoryName",
            large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"] + flags
        app.launch()
        if table {
            let tableTab = app.buttons["tray-table"]
            XCTAssertTrue(tableTab.waitForExistence(timeout: 20)); tableTab.tap()
            let audience = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Private to your Table")).firstMatch
            XCTAssertTrue(audience.waitForExistence(timeout: 20)); audience.tap()
        }
        let options = app.buttons["More options for Sam"]
        XCTAssertTrue(options.waitForExistence(timeout: 20))
        for _ in 0..<6 where !options.isHittable { app.swipeUp() }
        XCTAssertTrue(options.isHittable)
    }

    func confirmRemoval() {
        app.buttons["More options for Sam"].tap()
        app.buttons["Remove from household"].tap()
        let remove = app.buttons["Remove Sam"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5)); remove.tap()
    }

    func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }

    func testHouseholdCanRemoveConfirmedUnlinkedJoinedProfile() {
        launch(["-plated-review-removal-unlinked"])
        confirmRemoval()
        let notice = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "wasn’t linked to an iCloud account")).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["More options for Sam"].exists)
        capture("household-removal-unlinked")
    }

    func testCloudFailureKeepsProfileAndNamesTheActualProblem() {
        launch(["-plated-review-removal-unlinked", "-plated-review-removal-unavailable"])
        confirmRemoval()
        let error = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Couldn’t verify Sam’s shared account")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["More options for Sam"].exists)
        XCTAssertFalse(app.staticTexts["Couldn't remove Sam. Check your connection and try again."].exists)
        capture("household-removal-unavailable")
    }

    func testSaveFailureRestoresProfileAndShowsRecovery() {
        launch(["-plated-review-fail-save", "seat removed"])
        confirmRemoval()
        XCTAssertTrue(app.staticTexts["Couldn’t save the updated household on this phone. Try Remove again to finish."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["More options for Sam"].exists)
        capture("household-removal-save-failure")
    }

    func testCancelKeepsThePerson() {
        launch()
        app.buttons["More options for Sam"].tap()
        app.buttons["Remove from household"].tap()
        let remove = app.buttons["Remove Sam"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            // On iOS 26 this is a centered confirmation sheet without an
            // exposed Cancel action. Its underlying header is dimmed and
            // cannot receive a tap; dismiss at the unobscured lower edge.
            capture("household-removal-confirmation-before-outside-tap")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.7)).tap()
        }
        XCTAssertFalse(remove.exists)
        XCTAssertTrue(app.buttons["More options for Sam"].exists)
        capture("household-removal-cancel-preserves-person")
    }

    func testTablePeopleUsesTheSameRemovalFlowAtLargestText() {
        launch(["-plated-review-removal-unlinked"], table: true, large: true)
        confirmRemoval()
        let notice = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "wasn’t linked to an iCloud account")).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["More options for Sam"].exists)
        capture("table-household-removal-ax")
    }
}
