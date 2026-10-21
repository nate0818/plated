import XCTest

/// Exercises the previously unguarded preview entry points. The early source
/// guards establish network isolation; these native journeys verify that
/// exercising them preserves the fixture's explicit state and recovery controls.
/// They do not establish actual offline recovery or CloudKit delivery.
final class TablePreviewIsolationTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    private var feed: XCUIElement { app.scrollViews["table-feed"] }

    override func setUp() { continueAfterFailure = false }
    override func tearDown() { app.terminate() }

    private func launch(_ state: String) {
        app.launchArguments = [
            "-plated-design-review", state, "-plated-tab", "table",
            "-userFirstName", "Nate", "-appearance", "dark",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"
        ]
        app.launch()
        XCTAssertTrue(feed.waitForExistence(timeout: 20))
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func reveal(_ item: XCUIElement) {
        for _ in 0..<16 {
            if item.exists && item.isHittable { return }
            feed.swipeUp()
        }
        XCTAssertTrue(item.isHittable, app.debugDescription)
    }

    private func pullFromTop() {
        // These bounded fixtures contain at most four cards. Return to the
        // beginning before performing the actual refresh gesture.
        for _ in 0..<5 { feed.swipeDown() }
        feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            .press(forDuration: 0.05, thenDragTo:
                feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
    }

    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }

    func testPublicationRetryAndPullPreserveInjectedStates() {
        launch("-plated-review-publication-states")
        let failedRecord = "post-review-publication-failed"
        let failed = element("post-publication-" + failedRecord)
        let retry = app.buttons["post-publication-retry-" + failedRecord]
        reveal(retry)
        XCTAssertEqual(failed.label, "Couldn’t share · saved on this device")
        XCTAssertTrue(retry.isEnabled)
        retry.tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(retry.isEnabled)
        XCTAssertEqual(failed.label, "Couldn’t share · saved on this device")

        pullFromTop()
        for (state, label) in [
            ("saved", "Saved on this device · not shared yet"),
            ("sending", "Sending…"),
            ("failed", "Couldn’t share · saved on this device"),
            ("shared", "Shared with your Table")
        ] {
            let status = element("post-publication-post-review-publication-" + state)
            reveal(status)
            XCTAssertEqual(status.label, label,
                           "A preview refresh must not publish, replace, or resolve injected records.")
        }
        capture("table-preview-publication-actions-remain-isolated")
    }

    func testWaitingFixtureRefreshKeepsTheSavedPostAndWaitingState() {
        launch("-plated-review-publication-waiting")
        let status = element("post-publication-post-review-publication-waiting")
        reveal(status)
        XCTAssertEqual(status.label, "Waiting for connection · Your post is saved")
        pullFromTop()
        reveal(status)
        XCTAssertEqual(status.label, "Waiting for connection · Your post is saved")
        XCTAssertFalse(app.buttons["post-publication-retry-post-review-publication-waiting"].exists)
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Breakfast for dinner.")
        ).firstMatch.exists, "The saved fixture content must remain after refresh.")
        capture("table-preview-waiting-refresh-preserves-post")
    }

    func testErrorFixtureRetryReturnsToItsExplicitFailureState() {
        launch("-plated-review-table-error")
        let retry = app.buttons["Try again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Couldn't refresh the Table"].exists)
        retry.tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 5),
                      "The preview must not remain stuck in the transient checking state.")
        XCTAssertTrue(app.staticTexts["Couldn't refresh the Table"].exists)
        XCTAssertFalse(app.staticTexts["Checking the Table…"].exists)
        capture("table-preview-error-retry-preserves-recovery")
    }
}
