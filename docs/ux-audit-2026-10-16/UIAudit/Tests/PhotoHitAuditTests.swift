import XCTest

final class PhotoHitAuditTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    func capture(_ name: String) {
        let picture = XCTAttachment(screenshot: app.screenshot()); picture.name = name; picture.lifetime = .keepAlways; add(picture)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    func testVisibleRecipeTitleHitRegion() {
        continueAfterFailure = false
        app.launchArguments = ["-plated-design-review", "-plated-tab", "cookbook", "-plated-open-recipe-detail", "-appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.buttons["Edit recipe"].waitForExistence(timeout: 20))
        app.buttons["Edit recipe"].tap()
        let field = app.textFields["Name the dish"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        capture("photo-hit-before-title-tap")
        let evidence = XCTAttachment(string: "Title frame: \(field.frame), reported hittable: \(field.isHittable)")
        evidence.name = "photo-hit-region"; evidence.lifetime = .keepAlways; add(evidence)
        field.coordinate(withNormalizedOffset: CGVector(dx:0.5,dy:0.5)).tap()
        capture("photo-hit-after-title-tap")
        let original = field.value as? String
        field.typeText(" UX AUDIT")
        capture("recipe-edit-unsaved-value")
        app.buttons["Cancel"].coordinate(withNormalizedOffset: CGVector(dx:0.5,dy:0.5)).tap()
        XCTAssertTrue(app.buttons["Edit recipe"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Keep writing"].exists)
        capture("recipe-edit-cancelled-no-confirmation")
        app.buttons["Edit recipe"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        XCTAssertEqual(field.value as? String, original)
        capture("recipe-edit-reopened-original-value")
    }
    func testLocalStartCookingOpensRecipeDetail() {
        continueAfterFailure = false
        app.launchArguments = ["-plated-design-review", "-plated-tab", "week", "-appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let start = app.buttons["Start cooking"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout:20))
        capture("local-start-cooking-before")
        start.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        XCTAssertTrue(app.buttons["Edit recipe"].waitForExistence(timeout:8))
        XCTAssertFalse(app.buttons["Minimize cooking"].exists)
        capture("local-start-cooking-opens-detail")
    }

}
