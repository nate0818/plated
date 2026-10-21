import XCTest

final class ReleaseCalendarTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.resetAuthorizationStatus(for: .calendar)
    }
    func capture(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
        let t = XCTAttachment(string: app.debugDescription + "\n" + springboard.debugDescription)
        t.name = name + "-tree"; t.lifetime = .keepAlways; add(t)
    }
    func openGathering() {
        app.launchArguments = ["-plated-design-review", "-appearance", "dark", "-plated-review-plan-night", "-plated-review-gathering"]
        app.launch()
        let title = app.textFields["Sunday dinner party"]
        XCTAssertTrue(title.waitForExistence(timeout: 20)); title.tap()
        if let value = title.value as? String, value != "Sunday dinner party" {
            title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        title.typeText("Release Calendar check")
        app.swipeUp()
    }
    func testPermissionDeniedRetainsDraftAndLocalSaveCanFinish() {
        openGathering(); app.buttons["Save gathering"].tap()
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 15)); capture("calendar-permission-prompt")
        alert.buttons["Don’t Allow"].tap()
        let failure = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saved to your plan. Calendar' ")).firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Save changes"].exists)
        app.buttons["Save changes"].tap()
        XCTAssertTrue(failure.waitForExistence(timeout: 10))
        XCTAssertTrue(failure.isHittable, "Calendar failure is visible beside the retry action")
        capture("calendar-denied-retry")
        let toggle = app.switches["Add to Apple Calendar"]
        toggle.tap(); app.buttons["Save changes"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForNonExistence(timeout: 10))
        capture("calendar-denied-local-only-saved")
    }
    func testPermissionGrantedCreatesEvent() {
        openGathering(); app.buttons["Save gathering"].tap()
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 15)); capture("calendar-grant-prompt")
        alert.buttons["Allow Full Access"].tap()
        XCTAssertTrue(app.buttons["Save gathering"].waitForNonExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saved to your plan. Calendar' ")).firstMatch.exists)
        capture("calendar-granted-saved")
    }
}
