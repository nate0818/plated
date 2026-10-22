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
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-plated-design-review", "-appearance", "dark", "-UIPreferredContentSizeCategoryName", ax ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"] + flags
        app.launch(); XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 20))
    }
    func testAXPlanRows() {
        launch([],ax:true)
        for index in 0..<7 { capture("ax-plan-scroll-\(index)"); app.swipeUp() }
    }
    func testEditCancel() {
        launch(["-plated-open-recipe-detail"])
        app.buttons["Recipe options"].tap()
        // SwiftUI's menu action is a Button on iOS 27 and a PopUpButton
        // in the iOS 26 accessibility tree.
        let edit = app.descendants(matching: .any).matching(identifier: "Edit recipe").firstMatch
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
        XCTAssertTrue(app.buttons["Keep writing"].waitForExistence(timeout: 8))
        capture("editor-cancel-guard")
        app.buttons["Keep writing"].tap()
        XCTAssertTrue((field.value as? String)?.contains("UX AUDIT") == true)
        app.buttons["Cancel"].tap()
        app.buttons["Discard"].tap()
        app.buttons["Recipe options"].tap()
        edit.tap(); XCTAssertTrue(field.waitForExistence(timeout: 8))
        XCTAssertEqual(field.value as? String, original)
        capture("editor-reopened-after-discard")
    }
    func testStartCookingRoute() {
        launch()
        let start = app.buttons["Start cooking"].firstMatch
        for _ in 0..<8 { if start.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(start.isHittable); capture("plan-start-cooking"); start.tap()
        XCTAssertTrue(app.buttons["Minimize cooking"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Finish cooking"].exists)
        capture("start-cooking-opens-cooking")
    }
    func testStartCookingRouteInPhoneLandscape() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let start = app.buttons["Start cooking"].firstMatch
        let scroll = app.scrollViews["plan-selected-day-content"]
        let window = app.windows.firstMatch
        for _ in 0..<12 {
            let center = start.frame.midY
            if center >= 115 && center <= window.frame.maxY - 85 { break }
            let from = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: center < 115 ? 0.35 : 0.65))
            let to = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: center < 115 ? 0.65 : 0.35))
            from.press(forDuration: 0.1, thenDragTo: to)
        }
        capture("plan-cooking-phone-landscape-before-tap")
        XCTAssertTrue(start.frame.midY >= 115 && start.frame.midY <= window.frame.maxY - 85,
                      "Start cooking must fit above the bottom chrome before tapping")
        // Tap at the verified window coordinate: XCUIElement.tap() can
        // auto-scroll this short viewport even when the button is in view.
        window.coordinate(withNormalizedOffset: CGVector(dx: start.frame.midX / window.frame.width,
                                                         dy: start.frame.midY / window.frame.height)).tap()
        capture("plan-cooking-phone-landscape-after-tap")
        XCTAssertTrue(app.buttons["Minimize cooking"].waitForExistence(timeout: 8),
                      "A visible Start cooking action must open the cooking session in landscape")
        capture("plan-cooking-phone-landscape")
    }
    func testTabletSurvey() {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        for (name,flags) in [("plan",[String]()),("recipes",["-plated-tab","cookbook"]),("groceries",["-plated-tab","groceries"]),("table",["-plated-tab","table"]),("thread",["-plated-open-thread"]),("detail",["-plated-open-recipe-detail"]),("profile",["-plated-open-profile"]),("post",["-plated-open-table-post"]),("settings",["-plated-open-profile","-plated-open-settings"])] {
            launch(flags); capture("ipad-" + name)
        }
    }
}
