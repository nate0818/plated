import XCTest

/// Memory-only publication presentation checks. These fixtures do not execute
/// CloudKit saves or establish delivery, reads, or cross-account behavior.
final class SocialPublicationUITests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    override func setUp() { continueAfterFailure = false }

    private func launch(light: Bool = false, large: Bool = false, waiting: Bool = false) {
        app.terminate()
        app.launchArguments = ["-plated-design-review", waiting ? "-plated-review-publication-waiting" : "-plated-review-publication-states",
            "-plated-tab", "table", "-userFirstName", "Nate", "-appearance", light ? "light" : "dark",
            "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.scrollViews["table-feed"].waitForExistence(timeout: 20))
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func reveal(_ item: XCUIElement) {
        let feed = app.scrollViews["table-feed"]
        XCTAssertTrue(feed.isHittable)
        for _ in 0..<18 {
            if item.exists && item.isHittable { return }
            feed.swipeUp()
        }
        XCTAssertTrue(item.isHittable, app.debugDescription)
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }

    func testPublicationStatesInEditorialAppearance() { verifyStates(light: false, large: false) }
    func testPublicationStatesInLightAppearance() { verifyStates(light: true, large: false) }
    func testPublicationStatesAtLargestText() { verifyStates(light: true, large: true) }

    private func verifyStates(light: Bool, large: Bool) {
        launch(light: light, large: large)
        for (state, label) in [
            ("saved", "Saved on this device · not shared yet"),
            ("sending", "Sending…"),
            ("failed", "Couldn’t share · saved on this device"),
            ("shared", "Shared with your Table")
        ] {
            let record = "post-review-publication-" + state
            let status = element("post-publication-" + record)
            reveal(status)
            XCTAssertEqual(status.label, label)
            XCTAssertGreaterThan(status.frame.width, 0)
            XCTAssertGreaterThan(status.frame.height, 0)
            XCTAssertGreaterThanOrEqual(status.frame.minX, 0)
            XCTAssertLessThanOrEqual(status.frame.maxX, app.frame.maxX)
            let retry = app.buttons["post-publication-retry-" + record]
            if state == "failed" {
                reveal(retry)
                XCTAssertTrue(retry.isEnabled)
                // Core Animation's frame conversion can report a 44-point
                // target as 43.99999999999997; compare at pixel precision.
                XCTAssertGreaterThanOrEqual((retry.frame.width * 1000).rounded() / 1000, 44)
                XCTAssertGreaterThanOrEqual((retry.frame.height * 1000).rounded() / 1000, 44)
                // Do not tap: this presentation fixture deliberately does not
                // substitute a fake network result for production publishing.
            } else {
                XCTAssertFalse(retry.exists, "Retry belongs only to a known failed attempt")
            }
            capture("publication-\(state)-\(large ? "AX5" : light ? "light" : "dark")")
        }
    }

    func testWaitingForConnectionInBothAppearances() {
        for light in [false, true] { verifyWaiting(light: light, large: false) }
    }

    func testWaitingForConnectionAtLargestText() { verifyWaiting(light: true, large: true) }

    private func verifyWaiting(light: Bool, large: Bool) {
        launch(light: light, large: large, waiting: true)
        let record = "post-review-publication-waiting"
        let status = element("post-publication-" + record)
        reveal(status)
        XCTAssertEqual(status.label, "Waiting for connection · Your post is saved")
        XCTAssertGreaterThan(status.frame.height, 0)
        XCTAssertGreaterThanOrEqual(status.frame.minX, 0)
        XCTAssertLessThanOrEqual(status.frame.maxX, app.frame.maxX)
        XCTAssertLessThanOrEqual(status.frame.maxY, app.buttons["tray-table"].frame.minY)
        XCTAssertFalse(app.buttons["post-publication-retry-" + record].exists,
                       "A known outage is a waiting state, not a false failed-send claim")
        capture("publication-waiting-\(large ? "AX5" : light ? "light" : "dark")")
    }

}
