import XCTest

/// Missing states from the unchanged October 18 approval. These are native
/// journeys over memory-only fixtures, not proof of live CloudKit or WeatherKit.
/// Every saved image still requires element-by-element visual review.
final class FidelityAdditionalStatesTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    override func setUp() { continueAfterFailure = false }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func launch(_ flags: [String], light: Bool) {
        app.terminate()
        app.launchArguments = ["-plated-design-review", "-householdName", "Meadows", "-userFirstName", "Nate",
            "-appearance", light ? "light" : "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"] + flags
        app.launch()
    }

    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }

    private func reveal(_ item: XCUIElement, in scroll: XCUIElement? = nil) {
        guard let viewport = scroll ?? app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            XCTFail("No visible scroll view for the active screen: " + app.debugDescription)
            return
        }
        for _ in 0..<10 {
            let tab = app.buttons["tray-week"]
            let bottom = tab.exists ? tab.frame.minY : app.frame.maxY
            if item.isHittable && item.frame.maxY < bottom - 4 { return }
            viewport.swipeUp()
        }
        XCTAssertTrue(item.isHittable, app.debugDescription)
        let tab = app.buttons["tray-week"]
        if tab.exists { XCTAssertLessThan(item.frame.maxY, tab.frame.minY, "Capture the full element above navigation") }
    }

    private func waitFor(_ predicate: String, on item: XCUIElement, timeout: TimeInterval = 8) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: item)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, app.debugDescription)
    }

    func testFuturePlanFromTomorrowPreviewBothAppearances() {
        for light in [false, true] {
            let theme = light ? "light" : "dark"
            launch(["-plated-fake-weather", "-plated-review-household-activity"], light: light)
            XCTAssertTrue(app.buttons["Start cooking"].waitForExistence(timeout: 20))
            let next = app.buttons["plan-next-day"]
            reveal(next, in: app.scrollViews["plan-selected-day-content"])
            XCTAssertTrue(next.label.contains("Tomorrow"))
            XCTAssertTrue(next.label.contains("Pizza Night"))
            next.tap()
            let action = app.buttons["View recipe"]
            XCTAssertTrue(action.waitForExistence(timeout: 8))
            waitFor("hittable == true", on: action)
            let meal = app.buttons["featured-dinner-card"]
            XCTAssertEqual(meal.label, "Pizza Night")
            let dates = element("plan-date-wheel")
            let tab = app.buttons["tray-week"]
            let visibleDinner = NSPredicate { _, _ in
                meal.isHittable && action.isHittable
                    && dates.frame.minY >= 0
                    && meal.frame.minY >= dates.frame.maxY
                    && meal.frame.maxY <= action.frame.minY
                    && action.frame.minY >= 0
                    && action.frame.maxY < tab.frame.minY
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visibleDinner, object: nil)], timeout: 8), .completed,
                "After tapping Tomorrow, the full title/photo and action must be below dates and above tabs without a corrective swipe")
            XCTAssertFalse(app.buttons["Start cooking"].exists)
            XCTAssertFalse(element("plan-context-summary").exists, "No stale previous-day pill after changing dates")
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            let c = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
            XCTAssertTrue(app.buttons["week-date-\(c.year!)-\(c.month!)-\(c.day!)"].isSelected)
            let dateText = "Tomorrow · " + tomorrow.formatted(.dateTime.month(.abbreviated).day())
            XCTAssertTrue(app.staticTexts[dateText.uppercased()].exists)
            capture("fidelity-plan-future-\(theme)")
            action.tap()
            XCTAssertTrue(app.buttons["Change this night"].waitForExistence(timeout: 8),
                          "The already-planned future recipe opens with its current plan action")
            XCTAssertTrue(app.staticTexts["Pizza Night"].exists)
            app.buttons["Back"].firstMatch.tap()
            XCTAssertTrue(action.waitForExistence(timeout: 8))
            XCTAssertEqual(meal.label, "Pizza Night")
        }
    }

    func testEmptyHouseholdHistoryBothAppearances() {
        for light in [false, true] {
            launch(["-plated-review-empty-tonight", "-plated-fake-weather"], light: light)
            XCTAssertTrue(app.buttons["Choose a meal"].waitForExistence(timeout: 20))
            let explanation = app.staticTexts["Your first dinner is a good place to start. Mark a meal cooked to build your household’s history."]
            reveal(explanation, in: app.scrollViews["plan-selected-day-content"])
            XCTAssertTrue(app.staticTexts["Household dinners"].exists)
            XCTAssertTrue(app.staticTexts["Last 7 days"].exists)
            XCTAssertFalse(element("plan-history-cooked").exists)
            XCTAssertFalse(element("plan-history-eating-out").exists)
            XCTAssertTrue(element("plan-weather-conditions").exists)
            capture("fidelity-context-empty-" + (light ? "light" : "dark"))
        }
    }

    func testForecastUnavailableAndRetryKeepTheDinnerBothAppearances() {
        for light in [false, true] {
            launch(["-plated-review-weather-failed", "-plated-review-dinner-history"], light: light)
            XCTAssertTrue(app.buttons["Start cooking"].waitForExistence(timeout: 20))
            let message = app.staticTexts["Your dinner plan is still available."]
            let retry = app.buttons["Try again"]
            reveal(retry, in: app.scrollViews["plan-selected-day-content"])
            XCTAssertTrue(app.staticTexts["Forecast unavailable"].exists)
            XCTAssertTrue(message.exists)
            XCTAssertFalse(element("plan-weather-conditions").exists)
            XCTAssertFalse(element("plan-weather-attribution").exists)
            capture("fidelity-context-forecast-unavailable-" + (light ? "light" : "dark"))
            retry.tap()
            // This fixture intentionally fails again. It tests retained state,
            // not successful network recovery or the live Apple service.
            XCTAssertTrue(message.waitForExistence(timeout: 8))
            XCTAssertEqual(app.buttons["featured-dinner-card"].label, "Salmon Night")
            XCTAssertTrue(retry.isEnabled)
        }
    }

    func testUnderThirtyCollectionAndResetBothAppearances() {
        for light in [false, true] {
            let theme = light ? "light" : "dark"
            launch(["-plated-tab", "cookbook"], light: light)
            XCTAssertTrue(app.buttons["Recipe collections"].waitForExistence(timeout: 20))
            app.buttons["Recipe collections"].tap()
            let underThirty = app.buttons["Under 30 min"]
            XCTAssertTrue(underThirty.waitForExistence(timeout: 5))
            underThirty.tap()
            waitFor("selected == true", on: underThirty)
            XCTAssertFalse(app.buttons["All recipes"].exists)
            capture("fidelity-recipes-under-thirty-\(theme)")
            let count = element("recipes-under-thirty-count")
            reveal(count)
            // Existing SampleData has five recipes at 15/20/25/25/27 minutes;
            // the proposal's three illustrative records must not be fabricated.
            XCTAssertEqual(count.label, "5 recipes under 30 minutes.")
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pizza Night,")).firstMatch.exists)
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "BBQ Skewers,")).firstMatch.exists)
            capture("fidelity-recipes-under-thirty-count-\(theme)")
            XCTAssertTrue(underThirty.isHittable, "The collection rail remains outside the scrolling recipe grid")
            underThirty.tap()
            XCTAssertTrue(app.buttons["All recipes"].isSelected)
            XCTAssertFalse(count.exists)
            let pizza = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pizza Night,")).firstMatch
            reveal(pizza)
            XCTAssertTrue(pizza.exists, "Clearing the filter restores the longer dinner")
        }
    }

    func testCheckedGroceryAndUndoBothAppearances() {
        for light in [false, true] {
            let theme = light ? "light" : "dark"
            launch(["-plated-tab", "groceries"], light: light)
            XCTAssertTrue(app.buttons["Shopping and export options"].waitForExistence(timeout: 20))
            let asparagus = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Asparagus,")).firstMatch
            reveal(asparagus)
            XCTAssertEqual(asparagus.value as? String, "To buy")
            asparagus.tap()
            waitFor("value == 'Purchased'", on: asparagus)
            let undo = app.buttons["Undo last check"]
            XCTAssertTrue(undo.waitForExistence(timeout: 5))
            XCTAssertTrue(undo.isHittable)
            capture("fidelity-groceries-checked-\(theme)")
            undo.tap()
            waitFor("value == 'To buy'", on: asparagus)
            XCTAssertFalse(undo.exists)
            capture("fidelity-groceries-undone-\(theme)")
        }
    }

    func testHouseholdMemberProfileAndReturnBothAppearances() {
        for light in [false, true] {
            launch(["-plated-open-household", "-plated-review-household-activity"], light: light)
            XCTAssertTrue(app.buttons["household-settings"].waitForExistence(timeout: 20))
            let sam = app.buttons["Sam Rivera"]
            reveal(sam)
            sam.tap()
            let household = app.buttons["View household"]
            XCTAssertTrue(household.waitForExistence(timeout: 8))
            XCTAssertTrue(app.staticTexts["Sam Rivera"].exists)
            XCTAssertTrue(app.staticTexts["Meadows · Member"].exists)
            XCTAssertTrue(element("profile-contributions").exists)
            XCTAssertTrue(app.buttons["Posts"].exists)
            XCTAssertTrue(app.buttons["Recipes"].exists)
            XCTAssertFalse(app.buttons["Saved"].exists)
            XCTAssertFalse(app.buttons["Edit profile"].exists)
            let options = app.buttons["Profile options"]
            XCTAssertTrue(options.isHittable)
            XCTAssertGreaterThanOrEqual(options.frame.height, 44)
            capture("fidelity-profile-member-" + (light ? "light" : "dark"))
            options.tap()
            app.buttons["View recipes"].tap()
            XCTAssertTrue(app.buttons["Recipes"].isSelected)
            options.tap()
            app.buttons["View posts"].tap()
            XCTAssertTrue(app.buttons["Posts"].isSelected)
            options.tap()
            app.buttons["person.2"].tap()
            XCTAssertTrue(app.buttons["household-settings"].waitForExistence(timeout: 8))
            app.buttons["Back"].firstMatch.tap()
            XCTAssertTrue(household.waitForExistence(timeout: 8))
            XCTAssertTrue(app.staticTexts["Sam Rivera"].exists)
        }
    }
}
