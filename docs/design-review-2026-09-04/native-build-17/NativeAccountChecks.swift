import XCTest
final class GalleryTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    func shot(_ name: String) throws {
        Thread.sleep(forTimeInterval: 1)
        let image = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        try image.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/plated-native-captures/\(name).png"))
        try app.debugDescription.write(toFile: "/tmp/plated-native-captures/\(name).txt", atomically: true, encoding: .utf8)
    }
    func tap(_ label: String) {
        let button = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing \(label)"); button.tap()
    }
    func visibleButton(_ label: String) -> XCUIElement? {
        app.buttons.matching(identifier: label).allElementsBoundByIndex.first(where: \.isHittable)
    }
    func openAccount() {
        let account = visibleButton("Account")
        XCTAssertNotNil(account)
        account?.tap()
        XCTAssertTrue(app.staticTexts["Account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["account-edit-profile"].isHittable)
        XCTAssertTrue(app.buttons["account-settings"].isHittable)
        XCTAssertTrue(app.buttons["account-your-household"].isHittable)
        XCTAssertTrue(app.buttons["account-view-your-table-profile"].isHittable)
    }
    func testAccountHubAndSettings() throws {
        continueAfterFailure = false
        app.launchArguments = ["-plated-design-review", "-appearance", "light"]
        app.launch(); app.activate()
        XCTAssertTrue(app.buttons["Recipes"].waitForExistence(timeout: 8))

        openAccount()
        try shot("26-account-hub")

        app.buttons["account-settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Done"].isHittable)
        XCTAssertTrue(app.staticTexts["Appearance"].exists)
        try shot("27-settings")
        app.buttons["Done"].tap()

        app.buttons["account-edit-profile"].tap()
        XCTAssertTrue(app.staticTexts["Edit profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        XCTAssertTrue(app.buttons["Save profile"].isHittable)
        XCTAssertTrue(app.staticTexts["Use my contact photo"].exists || app.buttons["Use my contact photo"].exists)
        try shot("28-edit-profile")
        app.buttons["Cancel"].tap()

        app.buttons["account-view-your-table-profile"].tap()
        XCTAssertTrue(app.buttons["Dishes"].waitForExistence(timeout: 5))
        app.buttons["Back"].tap()
        XCTAssertTrue(app.staticTexts["Account"].waitForExistence(timeout: 5))
        app.buttons["Close account"].tap()

        for tab in ["Recipes", "Groceries", "Table"] {
            tap(tab)
            openAccount()
            app.buttons["Close account"].tap()
        }
    }

}
