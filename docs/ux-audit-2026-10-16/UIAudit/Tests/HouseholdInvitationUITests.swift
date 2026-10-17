import XCTest

final class HouseholdInvitationUITests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    override func setUp() { continueAfterFailure = false }

    func launch(_ state: String, large: Bool = false, light: Bool = false) {
        app.launchArguments = ["-plated-design-review", "-plated-review-invitation-" + state,
            "-appearance", light ? "light" : "dark", "-UIPreferredContentSizeCategoryName",
            large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
    }

    func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }

    func testRemovedInvitationShowsOnlyAccessExplanationAndClose() {
        launch("removed")
        XCTAssertTrue(app.staticTexts["New invitation needed"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Join Meadows?"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "invited you")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Join household"].exists)
        XCTAssertFalse(app.textFields["Your name"].exists)
        XCTAssertTrue(app.buttons["Close"].isHittable)
        capture("invitation-removed-dark")
    }

    func testRemovedInvitationAtLargestTextKeepsExitReachable() {
        launch("removed", large: true, light: true)
        XCTAssertTrue(app.staticTexts["New invitation needed"].waitForExistence(timeout: 15))
        capture("invitation-removed-ax5-light")
        for _ in 0..<6 where !app.buttons["Close"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["Close"].isHittable)
        XCTAssertFalse(app.buttons["Join household"].exists)
        app.swipeUp()
        capture("invitation-removed-ax5-scrolled")
    }

    func testFreshInvitationOffersJoinWithoutRemovalMessage() {
        launch("ready")
        XCTAssertTrue(app.staticTexts["Join Meadows?"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["New invitation needed"].exists)
        for _ in 0..<3 where !app.buttons["Join household"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["Join household"].isHittable)
        capture("invitation-fresh-dark")
    }

    func testInterruptedJoinAsksToFinishSetup() {
        launch("resume")
        XCTAssertTrue(app.staticTexts["Finish joining Meadows"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Join household"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "invited you")).firstMatch.exists)
        capture("invitation-resume-dark")
    }

    func testOwnLinkDoesNotOfferToInviteYourself() {
        launch("own", light: true)
        XCTAssertTrue(app.staticTexts["This is your household"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Join household"].exists)
        XCTAssertFalse(app.textFields["Your name"].exists)
        capture("invitation-own-light")
    }
}
