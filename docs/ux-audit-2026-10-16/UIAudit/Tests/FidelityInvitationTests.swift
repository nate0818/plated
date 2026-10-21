import XCTest

/// These fixtures prove presentation states, never a live invitation acceptance.
final class FidelityInvitationTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    override func setUp() { continueAfterFailure = false }
    func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    func testInitialFreshAndRemovedInvitationsHaveOneConsistentMessage() {
        for light in [false, true] {
            for state in ["initial", "rejoin", "removed"] {
                app.terminate()
                app.launchArguments = ["-plated-design-review", "-householdName", "Meadows", "-userFirstName", "Nate", "-appearance", light ? "light" : "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL", "-plated-review-invitation-" + state]
                app.launch()
                let title = state == "removed" ? "New invitation needed" : state == "rejoin" ? "Rejoin Meadows?" : "Join Meadows?"
                XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 20))
                if state == "removed" {
                    XCTAssertFalse(app.buttons["Join household"].exists)
                    XCTAssertFalse(app.buttons["Rejoin household"].exists)
                    XCTAssertFalse(app.staticTexts["Join Meadows?"].exists)
                    XCTAssertFalse(app.staticTexts["Rejoin Meadows?"].exists)
                } else {
                    let action = app.buttons[state == "rejoin" ? "Rejoin household" : "Join household"]
                    XCTAssertTrue(action.waitForExistence(timeout: 5))
                    XCTAssertGreaterThanOrEqual(action.frame.height, 44)
                    XCTAssertFalse(app.staticTexts["New invitation needed"].exists)
                    if state == "rejoin" {
                        XCTAssertTrue(app.staticTexts["Nate Meadows invited you back. Joining restores your access to this household’s plan, groceries and cookbook."].exists)
                        XCTAssertFalse(app.buttons["Join household"].exists)
                    }
                }
                capture("fidelity-invitation-" + state + "-" + (light ? "light" : "dark"))
            }
        }
    }
}
