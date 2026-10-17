import XCTest

final class DeepSurveyTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    override func setUp() { continueAfterFailure = false }
    func capture(_ name: String) {
        let picture = XCTAttachment(screenshot: app.screenshot())
        picture.name = name; picture.lifetime = .keepAlways; add(picture)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    func launch(_ flags: [String] = [], ax: Bool = false, light: Bool = false) {
        app.terminate()
        app.launchArguments = ["-plated-design-review", "-appearance", light ? "light" : "dark", "-UIPreferredContentSizeCategoryName", ax ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"] + flags
        app.launch()
        XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 20))
    }
    func tap(_ label: String) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 8), label)
        for _ in 0..<6 { if button.isHittable { break }; app.swipeUp() }
        button.tap()
    }
    func testExtraRoutes() {
        for (name,flags) in [
            ("month", ["-plated-force-month"]),
            ("ingredients-corrected", ["-plated-open-recipe-detail","-plated-open-recipe-ingredients"]),
            ("recipe-share", ["-plated-review-recipe-share"]),
            ("stats", ["-plated-open-stats"]),
            ("banner-crop", ["-plated-open-profile","-plated-open-edit-profile","-plated-review-banner-crop"])
        ] {
            launch(flags); capture(name)
            app.swipeUp(); capture(name + "-scrolled")
        }
        launch(["-plated-tab","cookbook"]); tap("Filter and sort recipes"); capture("recipe-filters")
        launch(["-plated-open-recipe-detail"]); tap("recipe-plan"); capture("recipe-plan-picker")
        launch(["-plated-open-profile"])
        let household = app.buttons.matching(NSPredicate(format:"label BEGINSWITH 'Your household,'")).firstMatch
        for _ in 0..<6 { if household.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(household.exists); household.tap(); capture("household")
        app.swipeUp(); capture("household-scrolled")
    }
    func testMoreAccessibilityAndLight() {
        for (name,flags) in [
            ("month", ["-plated-force-month"]),
            ("share", ["-plated-review-recipe-share"]),
            ("gathering", ["-plated-review-plan-night","-plated-review-gathering"]),
            ("seats", ["-plated-open-seats"]),
            ("profile", ["-plated-open-profile"]),
            ("thread", ["-plated-open-thread"])
        ] { launch(flags,ax:true); capture("ax-" + name); app.swipeUp(); capture("ax-" + name + "-scrolled") }
        for tab in ["week","cookbook","groceries","table"] {
            launch(["-plated-tab",tab], light:true); capture("light-" + tab)
            app.swipeUp(); capture("light-" + tab + "-scrolled")
        }
    }
    func testExistingRecipeCancelLosesDraft() {
        launch(["-plated-open-recipe-detail"])
        tap("Edit recipe")
        let name = app.textFields["Name the dish"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let original = name.value as? String
        name.tap(); name.typeText(" UX AUDIT")
        capture("edit-unsaved-keyboard")
        tap("Cancel")
        XCTAssertTrue(app.buttons["Edit recipe"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Keep writing"].exists)
        capture("edit-dismissed-without-confirmation")
        tap("Edit recipe")
        XCTAssertEqual(name.value as? String, original)
        capture("edit-reopened-draft-lost")
    }
    func testRecipeTabReselectKeepsScroll() {
        launch(["-plated-tab","cookbook"])
        capture("recipes-before-scroll")
        app.swipeUp(); app.swipeUp(); capture("recipes-scrolled")
        tap("tray-cookbook"); capture("recipes-reselected")
    }
    func testLandscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        for tab in ["week","cookbook","groceries","table"] {
            launch(["-plated-tab",tab]); capture("landscape-" + tab)
        }
    }
    func testAccessibilityDiagnostics() throws {
        for (name,flags) in [("plan",[String]()),("groceries",["-plated-tab","groceries"]),("thread",["-plated-open-thread"])] {
            launch(flags,light:true)
            var findings = [String]()
            try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped]) { issue in
                findings.append(issue.compactDescription + "\n" + issue.detailedDescription + "\n" + (issue.element?.debugDescription ?? "No element"))
                return true // Diagnostic collection, not an accessibility pass assertion.
            }
            let report = XCTAttachment(string: findings.isEmpty ? "No automated issues returned." : findings.joined(separator:"\n\n"))
            report.name = "accessibility-diagnostics-" + name; report.lifetime = .keepAlways; add(report)
        }
    }

}
