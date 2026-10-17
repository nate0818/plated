import XCTest
final class SurveyTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    func capture(_ name: String) {
        let picture = XCTAttachment(screenshot: app.screenshot())
        picture.name = name; picture.lifetime = .keepAlways; add(picture)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    func survey(_ name: String, _ flags: [String], ax: Bool = false, light: Bool = false) {
        app.launchArguments = ["-plated-design-review"] + flags
        if ax { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        if light { app.launchArguments += ["-platedAppearance", "light"] }
        app.launch()
        XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 20), name)
        capture(name)
        app.terminate()
    }
    func testSurveyDefault() {
        let cases: [(String,[String])] = [
            ("01-plan", []), ("02-recipes", ["-plated-tab","cookbook"]),
            ("03-groceries", ["-plated-tab","groceries"]), ("04-table", ["-plated-tab","table"]),
            ("05-create", ["-plated-open-create"]), ("06-import", ["-plated-open-recipe"]),
            ("07-post", ["-plated-open-table-post"]), ("08-ask", ["-plated-open-ask"]),
            ("09-profile", ["-plated-open-profile"]), ("10-edit-profile", ["-plated-open-profile","-plated-open-edit-profile"]),
            ("11-settings", ["-plated-open-profile","-plated-open-settings"]),
            ("12-detail", ["-plated-open-recipe-detail"]),
            ("13-ingredients", ["-plated-open-recipe-ingredients"]),
            ("14-cooking", ["-plated-review-cooking-timer"]),
            ("15-activity", ["-plated-open-activity","-plated-review-notifications"]),
            ("16-plan-night", ["-plated-review-plan-night"]),
            ("17-recipe-picker", ["-plated-review-plan-night","-plated-review-recipe-picker"]),
            ("18-gathering", ["-plated-review-plan-night","-plated-review-gathering"]),
            ("19-move", ["-plated-review-move-meal"]),
            ("20-seats", ["-plated-open-seats"]), ("21-thread", ["-plated-open-thread"]),
            ("22-welcome", ["-plated-review-sign-in"]), ("23-tour", ["-plated-review-tour"])
        ]
        for (name,flags) in cases { survey(name, flags) }
    }
    func testSurveyAccessibility() {
        for (name,flags) in [
            ("ax-plan", [String]()), ("ax-recipes", ["-plated-tab","cookbook"]),
            ("ax-groceries", ["-plated-tab","groceries"]), ("ax-table", ["-plated-tab","table"]),
            ("ax-edit-profile", ["-plated-open-profile","-plated-open-edit-profile"]),
            ("ax-settings", ["-plated-open-profile","-plated-open-settings"]),
            ("ax-detail", ["-plated-open-recipe-detail"]), ("ax-cooking", ["-plated-review-cooking-timer"]),
            ("ax-plan-night", ["-plated-review-plan-night"]), ("ax-post", ["-plated-open-table-post"]),
            ("ax-ask", ["-plated-open-ask"]), ("ax-move", ["-plated-review-move-meal"])
        ] { survey(name, flags, ax: true) }
    }
}
