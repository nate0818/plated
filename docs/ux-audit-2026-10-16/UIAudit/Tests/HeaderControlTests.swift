import XCTest

final class HeaderControlTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    override func setUp() { continueAfterFailure = false }

    func launch(_ tab: String, light: Bool, large: Bool = false, name: String = "Meadows") {
        app.terminate()
        app.launchArguments = ["-plated-design-review", "-plated-tab", tab == "table" ? "week" : tab,
            "-appearance", light ? "light" : "dark", "-householdName", name,
            "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        if tab == "table" {
            let destination = app.buttons["tray-table"]
            XCTAssertTrue(destination.waitForExistence(timeout: 20))
            destination.tap()
        }
    }

    func capture(_ name: String) {
        let picture = XCTAttachment(screenshot: app.screenshot())
        picture.name = name; picture.lifetime = .keepAlways; add(picture)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }

    func checkHousehold(light: Bool, large: Bool = false, name: String = "Meadows") {
        launch("home", light: light, large: large, name: name)
        let settings = app.buttons["household-settings"]
        let bell = app.buttons["household-notifications-bell"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        let title = app.staticTexts["household-page-title"]
        XCTAssertEqual(title.label, name)
        XCTAssertTrue(settings.isHittable)
        XCTAssertTrue(bell.isHittable)
        XCTAssertGreaterThanOrEqual(settings.frame.width, 44)
        XCTAssertGreaterThanOrEqual(settings.frame.height, 44)
        XCTAssertEqual(settings.frame.midY, bell.frame.midY, accuracy: 1)
        XCTAssertGreaterThanOrEqual(bell.frame.minX, settings.frame.maxX)
        XCTAssertGreaterThan(title.frame.minY, settings.frame.maxY)
        XCTAssertLessThanOrEqual(title.frame.maxX, app.frame.maxX - 20)
        capture("household-header-\(light ? "light" : "dark")-\(large ? "ax5" : "default")")
        settings.tap()
        XCTAssertTrue(app.staticTexts["Household settings"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.textFields["Household name"].exists)
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        bell.tap()
        XCTAssertTrue(app.staticTexts["Activity"].waitForExistence(timeout: 8))
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()
        XCTAssertTrue(app.staticTexts["Household settings"].waitForExistence(timeout: 8))
    }

    func checkTable(light: Bool, large: Bool = false) {
        launch("table", light: light, large: large)
        capture("table-before-query")
        let people = app.buttons["table-people"]
        XCTAssertTrue(people.waitForExistence(timeout: 20))
        XCTAssertTrue(people.isHittable)
        XCTAssertGreaterThanOrEqual(people.frame.height, 44)
        XCTAssertFalse(app.staticTexts["Just you for now"].exists)
        capture("table-header-\(light ? "light" : "dark")-\(large ? "ax5" : "default")")
        people.tap()
        XCTAssertTrue(app.staticTexts["People at your Table"].waitForExistence(timeout: 8))
        capture("table-people-open-\(large ? "ax5" : "default")")
    }

    func testHouseholdLightControlsHaveSeparateAlignedTargets() { checkHousehold(light: true) }
    func testHouseholdDarkControlsHaveSeparateAlignedTargets() { checkHousehold(light: false) }
    func testHouseholdLongNameAtLargestTextKeepsControlsReachable() {
        checkHousehold(light: true, large: true, name: "Meadows and Schembari Family")
    }
    func testTableLightPeopleControlOpensMembership() { checkTable(light: true) }
    func testTableDarkPeopleControlOpensMembership() { checkTable(light: false) }
    func testTableAtLargestTextKeepsPeopleReachable() { checkTable(light: true, large: true) }

    func testHeaderAccessibilitySemanticsAndTouchRegions() throws {
        for tab in ["home", "table"] {
            launch(tab, light: true)
            let target = app.buttons[tab == "home" ? "household-settings" : "table-people"]
            XCTAssertTrue(target.waitForExistence(timeout: 20))
            var findings: [String] = []
            var headerFindings: [String] = []
            let labels = ["Household settings", "Notifications", "Meadows", "People", "The Table"]
            try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped]) { issue in
                let description = issue.compactDescription + "\n" + issue.detailedDescription
                    + "\n" + (issue.element?.debugDescription ?? "No element")
                findings.append(description)
                if let element = issue.element,
                   labels.contains(element.label) || element.identifier.hasPrefix("household-")
                    || element.identifier.hasPrefix("table-people") {
                    headerFindings.append(description)
                }
                return true
            }
            let report = XCTAttachment(string: findings.isEmpty ? "No automated issues returned." : findings.joined(separator: "\n\n"))
            report.name = "header-accessibility-" + tab; report.lifetime = .keepAlways; add(report)
            XCTAssertTrue(headerFindings.isEmpty, headerFindings.joined(separator: "\n\n"))
        }
    }
}
