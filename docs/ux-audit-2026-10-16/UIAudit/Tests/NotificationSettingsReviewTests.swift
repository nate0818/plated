import XCTest
import UIKit

final class NotificationSettingsReviewTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    override func setUp() { continueAfterFailure = false }

    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }

    func testActivitySettingsRouteAndClearSignInAction() {
        for light in [false, true] {
            app.terminate()
            app.launchArguments = ["-plated-design-review", "-plated-open-activity",
                "-plated-review-notifications", "-appearance", light ? "light" : "dark",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
            app.launch()
            XCTAssertTrue(app.staticTexts["Get Table notifications"].waitForExistence(timeout: 20))
            capture("notifications-activity-\(light ? "light" : "dark")")
            app.buttons["Settings"].tap()
            let connect = app.buttons["phone-alert-connect"]
            for _ in 0..<6 {
                if connect.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(connect.isHittable)
            XCTAssertEqual(connect.label, "Sign in")
            XCTAssertGreaterThanOrEqual(connect.frame.height, 44)
            capture("notifications-settings-\(light ? "light" : "dark")")
        }
    }

    func testCookingUsesReadableWidth() {
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
        app.launchArguments = ["-plated-design-review", "-plated-review-cooking-timer",
            "-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let finish = app.buttons["Finish cooking"]
        XCTAssertTrue(finish.waitForExistence(timeout: 20))
        XCTAssertTrue(finish.isHittable)
        XCTAssertLessThanOrEqual(finish.frame.width, 760)
        XCTAssertGreaterThanOrEqual(finish.frame.height, 44)
        let pause = app.buttons["cooking-timer-pause"]
        pause.tap()
        XCTAssertEqual(pause.label, "Resume")
        capture("cooking-readable-width")
        app.buttons["Minimize cooking"].tap()
        // Minimize returns to the recipe; root chrome resumes after Back.
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.tap()
        let resume = app.buttons["cooking-resume-strip"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        resume.tap()
        XCTAssertTrue(finish.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["cooking-timer-pause"].label, "Resume")
    }
}
