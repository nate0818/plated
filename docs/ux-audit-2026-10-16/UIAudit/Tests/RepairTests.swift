import XCTest

final class RepairTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    override func setUp() { continueAfterFailure = false }
    func capture(_ name: String) {
        let picture = XCTAttachment(screenshot: app.screenshot()); picture.name = name; picture.lifetime = .keepAlways; add(picture)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    func launch(_ flags: [String] = [], ax: Bool = false, light: Bool = false) {
        app.terminate()
        app.launchArguments = ["-plated-design-review", "-appearance", light ? "light" : "dark", "-UIPreferredContentSizeCategoryName", ax ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"] + flags
        app.launch(); XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 20))
    }
    func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 8))
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
    func testTonightOpensCookingAndCalendarReturnsToTonight() {
        launch(["-plated-tab", "week"])
        let start = app.buttons["Start cooking"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        XCTAssertLessThan(start.frame.maxY, app.frame.maxY - 70, "Tonight's primary action is above the tab bar")
        capture("repaired-plan")
        tap(start)
        XCTAssertTrue(app.buttons["Minimize cooking"].waitForExistence(timeout: 8))
        capture("repaired-direct-cooking")
        tap(app.buttons["Minimize cooking"])
        XCTAssertTrue(app.buttons["Resume cooking"].firstMatch.waitForExistence(timeout: 8))
        capture("repaired-resume-plan")
        tap(app.buttons["Calendar"])
        capture("repaired-calendar")
        tap(app.buttons["Back to tonight"])
        XCTAssertTrue(app.buttons["Resume cooking"].firstMatch.waitForExistence(timeout: 8))
        tap(app.buttons["Resume cooking"].firstMatch)
        tap(app.buttons["End cooking"])
        tap(app.buttons["End cooking"].firstMatch)
    }
    func testExistingRecipeEditHasKeepAndDiscard() {
        launch(["-plated-tab", "cookbook", "-plated-open-recipe-detail"])
        tap(app.buttons["Edit recipe"])
        let field = app.textFields["Name the dish"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        let original = field.value as? String
        tap(field); field.typeText(" UX REPAIR")
        tap(app.buttons["Cancel"])
        XCTAssertTrue(app.buttons["Keep writing"].waitForExistence(timeout: 8))
        capture("repaired-edit-discard-guard")
        tap(app.buttons["Keep writing"])
        XCTAssertTrue((field.value as? String)?.contains("UX REPAIR") == true)
        tap(app.buttons["Cancel"]); tap(app.buttons["Discard"])
        tap(app.buttons["Edit recipe"])
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        XCTAssertEqual(field.value as? String, original)
        tap(app.buttons["Cancel"])
        XCTAssertTrue(app.buttons["Edit recipe"].waitForExistence(timeout: 8), "An untouched edit closes without a discard prompt")
    }
    func testRepairedScreensDefaultAndLargestText() {
        let cases: [(String,[String])] = [
            ("plan", ["-plated-tab", "week"]), ("groceries", ["-plated-tab","groceries"]),
            ("table", ["-plated-tab","table"]), ("thread", ["-plated-open-thread"]),
            ("profile", ["-plated-open-profile"]), ("edit-profile", ["-plated-open-profile","-plated-open-edit-profile"]),
            ("cooking", ["-plated-review-cooking-timer"]),
            ("gathering", ["-plated-review-plan-night","-plated-review-gathering"]),
            ("share", ["-plated-review-recipe-share"]), ("people", ["-plated-open-seats"])
        ]
        for ax in [false,true] {
            for (name,flags) in cases {
                launch(flags,ax:ax)
                capture((ax ? "ax-" : "normal-") + name)
                if ["plan", "table", "groceries", "cooking"].contains(name) {
                    app.swipeUp(); capture((ax ? "ax-" : "normal-") + name + "-scrolled")
                }
            }
        }
    }
    func testSelectedTabsReturnToTop() {
        for (tab,label,heading) in [("week","Plan","Calendar"),("cookbook","Recipes","The recipe book"),("groceries","Groceries","Groceries"),("table","Table","The Table")] {
            launch(["-plated-tab",tab])
            app.swipeUp(); app.swipeUp()
            capture("reselect-before-" + tab)
            let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).matching(NSPredicate(format: "identifier CONTAINS %@", "tab")).firstMatch
            // The app exposes stable identifiers on the native tab controls.
            let fallback = app.buttons[label].firstMatch
            tap(button.exists ? button : fallback)
            capture("reselect-after-" + tab)
            XCTAssertTrue(app.staticTexts[heading].exists || app.buttons[heading].exists)
        }
    }
    func testLightPlanAndGroceries() {
        for tab in ["week", "groceries", "table"] {
            launch(["-plated-tab", tab], light:true); capture("light-"+tab)
        }
    }
    func testShortWindowGroceriesExposeAnItem() {
        defer { XCUIDevice.shared.orientation = .portrait }
        launch(["-plated-tab", "groceries"])
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 2)
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Asparagus,'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        XCTAssertTrue(first.isHittable, "A shopping item is reachable without scrolling in landscape")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "final-landscape-groceries"; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "final-landscape-groceries-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    func testFinalLargeTextTimerControls() {
        launch(["-plated-review-cooking-timer"], ax:true)
        for step in 0..<3 { app.swipeUp(); capture("final-ax-timer-\(step)") }
    }

    func testFinalLargeTextThreadComposer() {
        launch(["-plated-open-thread"], ax:true)
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 8))
        capture("final-ax-thread")
    }

}
