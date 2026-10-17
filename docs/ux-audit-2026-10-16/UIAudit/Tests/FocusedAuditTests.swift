import XCTest
import UIKit

final class FocusedAuditTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    override func setUp() { continueAfterFailure = false }
    func capture(_ name: String) {
        let picture = XCTAttachment(screenshot: app.screenshot()); picture.name = name; picture.lifetime = .keepAlways; add(picture)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    func launch(_ flags: [String] = [], ax: Bool = false) {
        app.terminate()
        app.launchArguments = ["-plated-design-review", "-appearance", "dark", "-UIPreferredContentSizeCategoryName", ax ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"] + flags
        app.launch(); XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 20))
    }
    func testAXPlanRows() {
        launch([],ax:true)
        for index in 0..<7 { capture("ax-plan-scroll-\(index)"); app.swipeUp() }
    }
    func testEditCancel() {
        launch(["-plated-open-recipe-detail"])
        let edit = app.buttons["Edit recipe"]
        XCTAssertTrue(edit.waitForExistence(timeout: 8)); edit.tap()
        capture("editor-before-entry")
        let field = app.textFields["Name the dish"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        for _ in 0..<5 { if field.isHittable { break }; app.swipeUp() }
        capture("editor-name-revealed")
        let original = field.value as? String
        field.tap(); field.typeText(" UX AUDIT")
        capture("editor-with-unsaved-change")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Keep writing"].exists)
        capture("editor-cancel-no-warning")
        edit.tap(); XCTAssertTrue(field.waitForExistence(timeout: 8))
        XCTAssertEqual(field.value as? String, original)
        capture("editor-reopened-lost-change")
    }
    func testStartCookingRoute() {
        launch()
        let start = app.buttons["Start cooking"].firstMatch
        for _ in 0..<8 { if start.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(start.isHittable); capture("plan-start-cooking"); start.tap()
        XCTAssertTrue(app.buttons["Edit recipe"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Minimize cooking"].exists)
        capture("start-cooking-opens-detail")
    }
    func testTabletSurvey() {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        for (name,flags) in [("plan",[String]()),("recipes",["-plated-tab","cookbook"]),("groceries",["-plated-tab","groceries"]),("table",["-plated-tab","table"]),("thread",["-plated-open-thread"]),("detail",["-plated-open-recipe-detail"]),("profile",["-plated-open-profile"]),("post",["-plated-open-table-post"]),("settings",["-plated-open-profile","-plated-open-settings"])] {
            launch(flags); capture("ipad-" + name)
        }
    }
}
