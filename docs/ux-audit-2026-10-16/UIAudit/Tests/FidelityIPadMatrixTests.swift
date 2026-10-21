import XCTest
import UIKit

/// Read-only native evidence of the installed frozen candidate. The review
/// launch flag uses isolated fixture data; this harness never installs Plated.
final class FidelityIPadMatrixTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")

    override func setUp() { continueAfterFailure = true }
    override func tearDown() {
        app.terminate()
        // The runner also executes phone tests after this matrix. Restore the
        // physical orientation so their starting viewport is deterministic.
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    private struct Screen {
        let name: String
        let flags: [String]
        let marker: String
    }

    private let screens: [Screen] = [
        Screen(name: "plan", flags: ["-plated-fake-weather", "-plated-review-household-activity"], marker: "plan-selected-day-content"),
        Screen(name: "table", flags: ["-plated-tab", "table"], marker: "table-people"),
        Screen(name: "composer", flags: ["-plated-open-table-post", "-plated-review-post-reset"], marker: "table-post-text"),
        Screen(name: "recipes", flags: ["-plated-tab", "cookbook"], marker: "Favorites"),
        Screen(name: "detail", flags: ["-plated-open-recipe-detail"], marker: "recipe-plan"),
        Screen(name: "groceries", flags: ["-plated-tab", "groceries"], marker: "Shopping and export options"),
        Screen(name: "household", flags: ["-plated-open-household"], marker: "household-settings"),
        Screen(name: "cooking", flags: ["-plated-review-cooking-timer"], marker: "Minimize cooking")
    ]

    private func matrix(light: Bool, large: Bool) {
        for screen in screens {
            XCTContext.runActivity(named: screen.name) { _ in
                app.terminate()
                XCUIDevice.shared.orientation = .landscapeLeft
                app.launchArguments = [
                    "-plated-design-review", "-householdName", "Meadows", "-userFirstName", "Nate",
                    "-appearance", light ? "light" : "dark",
                    "-UIPreferredContentSizeCategoryName",
                    large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"
                ] + screen.flags
                app.launch()
                let marker = app.descendants(matching: .any).matching(identifier: screen.marker).firstMatch
                XCTAssertTrue(marker.waitForExistence(timeout: 20), "Missing \(screen.name) marker: \(screen.marker)")
                XCTAssertGreaterThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height,
                                     "\(screen.name) must stay landscape")
                let name = "ipad-matrix-\(screen.name)-\(light ? "light" : "dark")-\(large ? "AX5" : "default")"
                // App-scoped screenshots can crop the landscape scene here.
                // XCUIScreen may serialize portrait-shaped pixels despite a
                // landscape app window; retain the tree and corroborate
                // orientation with a simctl display capture.
                let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                image.name = name; image.lifetime = .keepAlways; add(image)
                let tree = XCTAttachment(string: app.debugDescription)
                tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
            }
        }
    }

    func testDarkDefault() { matrix(light: false, large: false) }
    func testLightDefault() { matrix(light: true, large: false) }
    func testDarkAccessibility() { matrix(light: false, large: true) }
    func testLightAccessibility() { matrix(light: true, large: true) }
}
