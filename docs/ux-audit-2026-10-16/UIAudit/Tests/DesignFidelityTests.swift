import XCTest

/// Native evidence for the original approved states. Captures require manual
/// comparison; assertions cover specific layout/interaction contracts only.
final class DesignFidelityTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    override func setUp() { continueAfterFailure = false }
    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    func launch(_ flags: [String], light: Bool, large: Bool = false) {
        app.terminate()
        app.launchArguments = ["-plated-design-review", "-householdName", "Meadows", "-userFirstName", "Nate", "-appearance", light ? "light" : "dark", "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"] + flags
        app.launch()
    }
    func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    func reveal(_ item: XCUIElement) {
        for _ in 0..<10 {
            if item.isHittable { return }
            let viewport = app.scrollViews.allElementsBoundByIndex.first { $0.isHittable }
            XCTAssertNotNil(viewport, "A visible scrolling container is required")
            viewport?.swipeUp()
        }
        XCTAssertTrue(item.isHittable, app.debugDescription)
    }
    func settled(_ control: XCUIElement) {
        // Pixel stability is observed on the changed control, not inferred from
        // its new accessibility label while the old label is still fading.
        var previous: Data?
        var same = 0
        let stable = NSPredicate { _, _ in
            let next = control.screenshot().pngRepresentation
            same = next == previous ? same + 1 : 0
            previous = next
            return same >= 2
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: stable, object: nil)], timeout: 8), .completed)
    }
    func testPlanOpenAndEatingOutBothAppearances() {
        for light in [false, true] {
            let theme = light ? "light" : "dark"
            launch(["-plated-review-empty-tonight", "-plated-fake-weather"], light: light)
            XCTAssertTrue(app.buttons["Choose a meal"].waitForExistence(timeout: 20))
            let headline = element("plan-open-headline")
            XCTAssertTrue(headline.exists)
            if app.frame.width >= 390 && app.frame.width < 500 {
                XCTAssertLessThan(headline.frame.height, 80, "Approved standard-width question occupies two lines")
            }
            capture("fidelity-plan-open-\(theme)")
            app.buttons["Eating out instead"].tap()
            XCTAssertTrue(app.buttons["Add a place"].waitForExistence(timeout: 8))
            capture("fidelity-plan-out-\(theme)")
        }
    }
    func testScrolledContextSummaryTracksTheSelectedDate() {
        launch(["-plated-fake-weather", "-plated-review-household-activity", "-plated-review-dinner-history"], light: false)
        XCTAssertTrue(element("featured-dinner-card").waitForExistence(timeout: 20))
        XCTAssertFalse(element("plan-context-summary").exists)
        // The card height varies by device and content. Scroll until the
        // dinner actually passes the pinned date row, not a fixed gesture count.
        for _ in 0..<6 {
            if element("plan-context-summary").exists { break }
            app.scrollViews["plan-selected-day-content"].swipeUp()
        }
        capture("fidelity-plan-context-before-assert-dark")
        let card = element("featured-dinner-card")
        let dates = app.scrollViews["plan-date-wheel"]
        if element("plan-context-summary").exists {
            XCTAssertTrue(element("plan-context-summary").label.contains("Salmon Night"),
                          "The compact summary must name the selected dinner")
            capture("fidelity-plan-context-dark")
        } else {
            // A taller viewport can reach the bottom of the page while the
            // meal card is still below the pinned dates. Showing a duplicate
            // summary then would be the product defect.
            XCTAssertGreaterThan(card.frame.maxY, dates.frame.maxY,
                                 "Keep the summary hidden while the dinner remains visible")
            capture("fidelity-plan-context-card-still-visible-dark")
        }
        for _ in 0..<4 { app.scrollViews.firstMatch.swipeDown() }
        XCTAssertFalse(element("plan-context-summary").exists)
        XCTAssertTrue(app.buttons["Start cooking"].isHittable)
        capture("fidelity-plan-returned-top-dark")
    }
    func testScrolledContextSummaryAtLargestText() {
        launch(["-plated-fake-weather", "-plated-review-household-activity", "-plated-review-dinner-history"], light: true, large: true)
        let scroll = app.scrollViews["plan-selected-day-content"]
        let card = element("featured-dinner-card")
        let summary = element("plan-context-summary")
        let dates = app.scrollViews["plan-date-wheel"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        XCTAssertFalse(summary.exists)
        for _ in 0..<10 {
            if summary.exists { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(summary.exists, "The selected dinner needs a persistent name once its title/photo passes the pinned dates")
        XCTAssertTrue(summary.label.contains("Salmon Night"))
        XCTAssertLessThanOrEqual(card.frame.maxY, dates.frame.maxY)
        XCTAssertTrue(app.buttons["Start cooking"].isHittable,
                      "The primary dinner action remains reachable alongside the summary")
        capture("fidelity-plan-context-light-AX5")
        for _ in 0..<10 {
            if !summary.exists { break }
            scroll.swipeDown()
        }
        XCTAssertFalse(summary.exists)
        XCTAssertGreaterThan(card.frame.maxY, dates.frame.maxY,
                             "The summary leaves when the dinner identity returns below the dates")
    }
    func testMissingMediaAndPopulatedProfilesBothAppearances() {
        for light in [false, true] {
            let theme = light ? "light" : "dark"
            launch(["-plated-tab", "cookbook", "-plated-review-missing-recipe-photo"], light: light)
            XCTAssertTrue(app.buttons["All recipes"].waitForExistence(timeout: 20))
            capture("fidelity-recipes-missing-\(theme)")
            launch(["-plated-open-profile", "-plated-review-own-posts"], light: light)
            XCTAssertTrue(app.buttons["Edit profile"].waitForExistence(timeout: 20))
            capture("fidelity-profile-posts-\(theme)")
            app.buttons["Recipes"].tap()
            capture("fidelity-profile-recipes-\(theme)")
        }
    }
    func testEmptyRecipeDirectionsAreExplicitAndReachable() {
        for light in [false, true] {
            launch(["-plated-open-recipe-detail"], light: light)
            XCTAssertTrue(element("recipe-plan").waitForExistence(timeout: 20))
            let directions = app.buttons["Directions"]
            reveal(directions); directions.tap()
            let empty = app.staticTexts["No written steps added yet."]
            XCTAssertTrue(empty.waitForExistence(timeout: 8))
            XCTAssertTrue(empty.isHittable)
            capture("fidelity-detail-empty-directions-" + (light ? "light" : "dark"))
        }
    }

    func testLargestComposerPromptAndTextRemainUsableWithKeyboard() {
        launch(["-plated-open-table-post", "-plated-review-post-reset"], light: true, large: true)
        let field = element("table-post-text")
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        capture("fidelity-composer-empty-AX5")
        field.tap(); field.typeText("The market tomatoes were excellent.")
        XCTAssertEqual(field.value as? String, "The market tomatoes were excellent.")
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["table-post-submit"].isEnabled)
        capture("fidelity-composer-writing-AX5-keyboard")
        app.buttons["Done"].tap()
        capture("fidelity-composer-writing-AX5")
    }

    func testRecipeDirectionsJumpAndReturnBothAppearances() {
        for light in [false, true] {
            let theme = light ? "light" : "dark"
            launch(["-plated-open-recipe-detail", "-plated-review-recipe-directions"], light: light)
            XCTAssertTrue(element("recipe-plan").waitForExistence(timeout: 20))
            let directions = app.buttons["Directions"]
            reveal(directions); directions.tap()
            XCTAssertTrue(app.staticTexts["Whisk the dry ingredients together in a large bowl."].waitForExistence(timeout: 8))
            capture("fidelity-detail-directions-\(theme)")
        }
    }
    func testCookingStatesAndBackToPlanBothAppearances() {
        for light in [false, true] {
            let theme = light ? "light" : "dark"
            launch(["-plated-review-cooking-timer"], light: light)
            let pause = app.buttons["cooking-timer-pause"]
            XCTAssertTrue(pause.waitForExistence(timeout: 20))
            capture("fidelity-cooking-active-\(theme)")
            pause.tap(); XCTAssertEqual(pause.label, "Resume"); settled(pause)
            capture("fidelity-cooking-paused-\(theme)")
            app.buttons["Finish cooking"].tap()
            XCTAssertTrue(app.buttons["Back to Plan"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Nicely done, Nate."].exists)
            capture("fidelity-cooking-finished-\(theme)")
            app.buttons["Back to Plan"].tap()
            XCTAssertTrue(element("plan-selected-day-content").waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["Minimize cooking"].exists)
            capture("fidelity-cooking-returned-plan-\(theme)")
            launch(["-plated-review-cooking-timer", "-plated-review-recipe-directions"], light: light)
            XCTAssertTrue(app.buttons["Minimize cooking"].waitForExistence(timeout: 20))
            capture("fidelity-cooking-steps-\(theme)")
        }
    }
    func testCommentInputPaddingAcceptsFocus() {
        for edge in [0.08, 0.92] {
            launch(["-plated-review-comment-reactions", "-plated-open-thread", "-plated-review-comment-reset"], light: true)
            let field = app.textViews["post-comment-input"]
            XCTAssertTrue(field.waitForExistence(timeout: 20))
            XCTAssertGreaterThanOrEqual(field.frame.height, 44)
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: edge)).tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            XCTAssertEqual(field.value as? String, "")
            field.typeText("The padded input responds.")
            XCTAssertEqual(field.value as? String, "The padded input responds.")
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "The padded input responds.".count))
            capture("fidelity-comment-input-edge-" + String(edge))
        }
    }

    func testActivityBothAppearances() {
        for light in [false, true] {
            let theme = light ? "light" : "dark"
            launch(["-plated-open-activity", "-plated-review-notifications"], light: light)
            XCTAssertTrue(app.buttons["activity-mark-all-read"].waitForExistence(timeout: 20))
            capture("fidelity-activity-unread-\(theme)")
            app.buttons["activity-mark-all-read"].tap()
            XCTAssertFalse(app.buttons["activity-mark-all-read"].exists)
            capture("fidelity-activity-read-\(theme)")
        }
    }
    func testCookingPauseSettlesAtLargestText() {
        launch(["-plated-review-cooking-timer"], light: true, large: true)
        let pause = app.buttons["cooking-timer-pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 20)); reveal(pause)
        for _ in 0..<3 { pause.tap(); pause.tap() }
        pause.tap(); XCTAssertEqual(pause.label, "Resume"); settled(pause)
        capture("fidelity-cooking-paused-AX5")
    }
    func testProfileButtonEdgeAndNavigationTargets() {
        launch(["-plated-open-profile"], light: true)
        let edit = app.buttons["Edit profile"]
        XCTAssertTrue(edit.waitForExistence(timeout: 20))
        XCTAssertGreaterThanOrEqual(edit.frame.height, 44)
        XCTAssertGreaterThan(edit.frame.width, app.frame.width * 0.7)
        edit.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Edit profile"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        launch([], light: true)
        for tab in ["week", "cookbook", "groceries", "table"] {
            let button = app.buttons["tray-" + tab]
            XCTAssertTrue(button.waitForExistence(timeout: 20))
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.width)
            button.tap()
            XCTAssertTrue(button.isSelected)
        }
        capture("fidelity-navigation-targets-light")
    }
    func testApprovedPushedHouseholdHeaderAndActivityRoute() {
        for light in [false, true] {
            launch(["-plated-open-household"], light: light)
            let settings = app.buttons["household-settings"]
            let bell = app.buttons["household-notifications-bell"]
            XCTAssertTrue(settings.waitForExistence(timeout: 20))
            XCTAssertTrue(bell.exists)
            let back = app.buttons["Back"].firstMatch
            let title = app.staticTexts["household-page-title"]
            XCTAssertEqual(title.label, "Meadows")
            for control in [back, settings, bell] {
                XCTAssertTrue(control.isHittable)
                XCTAssertGreaterThanOrEqual(control.frame.width, 44)
                XCTAssertGreaterThanOrEqual(control.frame.height, 44)
            }
            XCTAssertEqual(back.frame.midY, settings.frame.midY, accuracy: 1)
            XCTAssertGreaterThanOrEqual(title.frame.minX, back.frame.maxX)
            XCTAssertGreaterThanOrEqual(settings.frame.minX, title.frame.maxX)
            XCTAssertGreaterThanOrEqual(bell.frame.minX, settings.frame.maxX - 1)
            capture("fidelity-household-header-\(light ? "light" : "dark")")
            bell.tap()
            XCTAssertTrue(app.staticTexts["Activity"].waitForExistence(timeout: 8))
            app.buttons["Back"].firstMatch.tap()
            XCTAssertTrue(settings.waitForExistence(timeout: 8))
            settings.tap()
            XCTAssertTrue(app.staticTexts["Household settings"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.textFields["Household name"].exists)
            app.buttons["Back"].firstMatch.tap()
            XCTAssertTrue(settings.waitForExistence(timeout: 8))
            back.tap()
            XCTAssertFalse(settings.exists)
            launch(["-plated-review-notifications"], light: light)
            let activity = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Activity", "Notifications")).firstMatch
            XCTAssertTrue(activity.waitForExistence(timeout: 20))
            activity.tap()
            XCTAssertTrue(app.staticTexts["Activity"].waitForExistence(timeout: 8))
            app.buttons["Back"].firstMatch.tap()
            XCTAssertTrue(app.buttons["Start cooking"].waitForExistence(timeout: 8))
        }
    }

    func testStationaryCreateControlsAndContextualTableEntry() {
        launch(["-plated-tab", "table", "-plated-review-post-reset"], light: true)
        let create = app.buttons["tray-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 20)); settled(create)
        XCTAssertGreaterThanOrEqual(create.frame.height, 44)
        capture("fidelity-table-stationary-light")
        create.tap()
        XCTAssertTrue(element("table-post-text").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["New post"].exists)
        capture("fidelity-table-contextual-create-light")
        launch(["-plated-open-create"], light: true)
        let close = app.buttons["Close create"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 20)); settled(close)
        capture("fidelity-create-before-assert-light")
        XCTAssertGreaterThanOrEqual(close.frame.height, 44)
        XCTAssertGreaterThanOrEqual(close.frame.width, 44)
        capture("fidelity-create-stationary-light")
        close.tap()
        XCTAssertTrue(app.buttons["Start cooking"].waitForExistence(timeout: 8))
    }

    func testMinimizedCookingDoesNotCoverGroceryFooterAtLargestText() {
        launch(["-plated-review-cooking-timer"], light: true, large: true)
        XCTAssertTrue(app.buttons["Minimize cooking"].waitForExistence(timeout: 20))
        app.buttons["Minimize cooking"].tap()
        // The fixture starts from recipe detail, which intentionally hides tabs.
        // Return to Recipes before checking the shell resume strip.
        XCTAssertTrue(app.buttons["Back"].firstMatch.waitForExistence(timeout: 8))
        app.buttons["Back"].firstMatch.tap()
        let resume = app.buttons["cooking-resume-strip"]
        XCTAssertTrue(resume.waitForExistence(timeout: 8))
        app.buttons["tray-groceries"].tap()
        let footer = element("grocery-shopping-footer")
        XCTAssertTrue(footer.waitForExistence(timeout: 8))
        XCTAssertLessThanOrEqual(footer.frame.maxY, resume.frame.minY + 1)
        XCTAssertGreaterThanOrEqual(resume.frame.height, 44)
        capture("fidelity-groceries-resume-AX5")
        resume.tap()
        XCTAssertTrue(app.buttons["Minimize cooking"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Finish cooking"].exists)
    }

}
