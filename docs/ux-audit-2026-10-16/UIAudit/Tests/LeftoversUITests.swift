import XCTest

/// Focused interaction checks for the explicit leftovers choice. These preview
/// launches use an in-memory model container: date changes and reopening verify
/// retained UI/model state, not disk persistence or cross-account delivery.
final class LeftoversUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")

    override func setUp() { continueAfterFailure = false }
    override func tearDown() { app.terminate() }

    private func launch(_ flags: [String] = [], light: Bool = false, large: Bool = false) {
        app.terminate()
        app.launchArguments = [
            "-plated-design-review", "-plated-tab", "week", "-plated-fake-weather",
            "-appearance", light ? "light" : "dark",
            "-UIPreferredContentSizeCategoryName",
            large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"
        ] + flags
        app.launch()
        XCTAssertTrue(app.scrollViews["plan-date-wheel"].waitForExistence(timeout: 20))
    }

    private func option(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    private func reveal(_ item: XCUIElement, scrollingDown: Bool = false) {
        for _ in 0..<20 {
            if item.isHittable && app.frame.contains(CGPoint(x: item.frame.midX, y: item.frame.midY)) { return }
            guard let viewport = app.scrollViews.allElementsBoundByIndex.reversed().first(where: { $0.isHittable }) else {
                XCTFail("The current sheet must retain a reachable scroll view")
                return
            }
            // A full-page swipe can jump over a tall accessibility-size choice
            // on a short phone. Move by part of the visible sheet and reverse
            // when the target passes above it; verify reachability either way.
            let targetAbove = item.frame.midY < viewport.frame.minY + 24
            let moveDown = targetAbove || (scrollingDown && item.frame.midY <= viewport.frame.maxY)
            let start = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: moveDown ? 0.34 : 0.70))
            let end = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: moveDown ? 0.70 : 0.34))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(item.isHittable, app.debugDescription)
    }

    private func selectDate(_ offset: Int) {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date())!
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let button = app.buttons["week-date-\(components.year!)-\(components.month!)-\(components.day!)"]
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        XCTAssertTrue(button.isHittable)
        button.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
    }

    private func chooseLeftovers() {
        let choice = app.buttons["plan-eat-leftovers"]
        XCTAssertTrue(choice.waitForExistence(timeout: 8))
        reveal(choice)
        XCTAssertGreaterThanOrEqual(choice.frame.height, 44)
        choice.tap()
    }

    private func expectLeftovers() {
        let card = app.buttons["featured-dinner-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Leftovers"), object: card)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 8), .completed)
        XCTAssertEqual(card.value as? String, "Enjoy what’s already made. No new groceries.")
        XCTAssertEqual(app.buttons.matching(identifier: "featured-dinner-card").count, 1)
        XCTAssertFalse(app.buttons["plan-cook-assignment"].exists)
        XCTAssertFalse(app.buttons["Start cooking"].exists)
        XCTAssertFalse(app.buttons["Resume cooking"].exists)
        XCTAssertFalse(app.buttons["Add a place"].exists)
        XCTAssertTrue(app.buttons["plan-change-dinner-action"].exists)
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }

    func testEmptyDayChoiceIsRetainedAcrossDateChangesAndReopening() {
        launch(["-plated-review-empty-tonight"])
        app.buttons["Choose a meal"].tap()
        chooseLeftovers()
        expectLeftovers()
        capture("leftovers-selected-dark")
        selectDate(1)
        XCTAssertEqual(app.buttons["featured-dinner-card"].label, "Pizza Night", "Choosing leftovers must not replace another date")
        selectDate(0)
        expectLeftovers()
        app.buttons["plan-change-dinner-action"].tap()
        XCTAssertTrue(app.staticTexts["Leftovers"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Remove this meal"].exists)
        XCTAssertFalse(option("Cook,").exists, "A leftovers plan must not ask for a cook")
        capture("leftovers-reopened-dark")
    }

    func testReplacingRecipeThenChoosingRecipeAgainClearsOldCookResponsibility() {
        launch()
        XCTAssertEqual(app.buttons["featured-dinner-card"].label, "Salmon Night")
        XCTAssertTrue(app.buttons["Start cooking"].exists)
        app.buttons["Dinner options"].tap()
        app.buttons["Eat leftovers"].tap()
        expectLeftovers()
        app.buttons["plan-change-dinner-action"].tap()
        let change = option("Change dinner")
        XCTAssertTrue(change.waitForExistence(timeout: 8)); reveal(change); change.tap()
        let recipe = option("Lemon Butter Salmon,")
        XCTAssertTrue(recipe.waitForExistence(timeout: 8)); reveal(recipe); recipe.tap()
        let card = app.buttons["featured-dinner-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Lemon Butter Salmon"), object: card)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 8), .completed)
        XCTAssertEqual(app.buttons["plan-cook-assignment"].value as? String, "No cook assigned")
        XCTAssertTrue(app.buttons["Start cooking"].exists)
        capture("leftovers-changed-back-to-recipe")
    }

    func testFailedReplacementKeepsPreviousMealAndAllowsAnotherChoice() {
        launch(["-plated-review-cooked-tonight", "-plated-review-fail-save", "plan leftovers"])
        XCTAssertEqual(app.buttons["featured-dinner-card"].label, "Salmon Night")
        app.buttons["Dinner options"].tap()
        app.buttons["Change the dish"].tap()
        chooseLeftovers()
        let failure = app.staticTexts["Couldn’t save this meal. Try again."]
        XCTAssertTrue(failure.waitForExistence(timeout: 8))
        reveal(failure, scrollingDown: true)
        XCTAssertTrue(app.staticTexts["Salmon Night"].exists, "The sheet must restore the previous meal after a failed save")
        XCTAssertTrue(app.buttons["plan-eat-leftovers"].exists, "The sheet must remain open for recovery")
        capture("leftovers-replacement-save-failure")
        let eatingOut = option("Eating out")
        reveal(eatingOut); eatingOut.tap()
        let card = app.buttons["featured-dinner-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        XCTAssertEqual(card.label, "Eating out")
        XCTAssertFalse(app.buttons["Start cooking"].exists)
    }

    func testFailedNewChoiceDoesNotLeaveAnUnsavedMealInTheSheet() {
        launch(["-plated-review-empty-tonight", "-plated-review-fail-save", "plan leftovers"])
        app.buttons["Choose a meal"].tap()
        chooseLeftovers()
        XCTAssertTrue(app.staticTexts["Couldn’t save this meal. Try again."].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Remove this meal"].exists, "An unsaved inserted meal must be removed from the model")
        XCTAssertFalse(app.staticTexts["Leftovers"].exists)
        XCTAssertTrue(option("Choose a recipe").exists)
        capture("leftovers-new-save-failure")
    }

    func testFailedRecipeReplacementKeepsLeftoversAndTheSheetOpen() {
        launch(["-plated-review-empty-tonight", "-plated-review-fail-save", "plan meal"])
        app.buttons["Choose a meal"].tap()
        chooseLeftovers()
        expectLeftovers()
        app.buttons["plan-change-dinner-action"].tap()
        let change = option("Change dinner")
        XCTAssertTrue(change.waitForExistence(timeout: 8)); reveal(change); change.tap()
        let recipe = option("Lemon Butter Salmon,")
        XCTAssertTrue(recipe.waitForExistence(timeout: 8)); reveal(recipe); recipe.tap()
        let failure = app.staticTexts["Couldn’t save this meal. Try again."]
        XCTAssertTrue(failure.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Leftovers"].exists)
        XCTAssertTrue(app.buttons["Remove this meal"].exists)
        XCTAssertFalse(option("Cook,").exists)
        capture("leftovers-recipe-replacement-save-failure")
        let eatingOut = option("Eating out")
        reveal(eatingOut); eatingOut.tap()
        XCTAssertTrue(app.buttons["featured-dinner-card"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["featured-dinner-card"].label, "Eating out")
    }

    func testFailedRemovalRestoresLeftoversAndAllowsAnotherChoice() {
        launch(["-plated-review-empty-tonight", "-plated-review-fail-save", "remove planned meal"])
        app.buttons["Choose a meal"].tap()
        chooseLeftovers()
        expectLeftovers()
        app.buttons["plan-change-dinner-action"].tap()
        let remove = app.buttons["Remove this meal"]
        XCTAssertTrue(remove.waitForExistence(timeout: 8)); reveal(remove); remove.tap()
        XCTAssertTrue(app.staticTexts["Couldn’t remove this meal. Try again."].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Leftovers"].exists, "The failed delete must restore the same night")
        XCTAssertTrue(remove.exists, "The retained night must remain editable")
        capture("leftovers-removal-save-failure")
        let eatingOut = option("Eating out")
        reveal(eatingOut); eatingOut.tap()
        XCTAssertTrue(app.buttons["featured-dinner-card"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["featured-dinner-card"].label, "Eating out")
    }

    func testLightAppearanceLargestTextKeepsChoiceAndChangeActionReachable() {
        launch(["-plated-review-empty-tonight"], light: true, large: true)
        let open = app.buttons["Choose a meal"]
        reveal(open); open.tap()
        let choice = app.buttons["plan-eat-leftovers"]
        XCTAssertTrue(choice.waitForExistence(timeout: 8)); reveal(choice)
        XCTAssertGreaterThanOrEqual(choice.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(choice.frame.maxX, app.frame.maxX)
        capture("leftovers-choice-light-AX5")
        chooseLeftovers()
        expectLeftovers()
        let change = app.buttons["plan-change-dinner-action"]
        reveal(change)
        XCTAssertGreaterThanOrEqual(change.frame.height, 44)
        capture("leftovers-selected-light-AX5")
        change.tap()
        XCTAssertTrue(app.staticTexts["Leftovers"].waitForExistence(timeout: 8))
    }
}
