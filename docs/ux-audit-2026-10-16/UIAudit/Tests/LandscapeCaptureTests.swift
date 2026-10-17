import XCTest

final class LandscapeCaptureTests: XCTestCase {
    func testSettledLandscapeScreen() {
        let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
        continueAfterFailure = false
        defer { XCUIDevice.shared.orientation = .portrait }
        for tab in ["week", "cookbook", "groceries", "table"] {
            XCUIDevice.shared.orientation = .portrait
            app.launchArguments = ["-plated-design-review", "-plated-tab", tab, "-appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
            app.launch()
            XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 20))
            XCUIDevice.shared.orientation = .landscapeLeft
            Thread.sleep(forTimeInterval: 2)
            let picture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            picture.name = "landscape-screen-" + tab
            picture.lifetime = .keepAlways
            add(picture)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "landscape-screen-" + tab + "-tree"
            tree.lifetime = .keepAlways
            add(tree)
            app.terminate()
        }
    }
}
