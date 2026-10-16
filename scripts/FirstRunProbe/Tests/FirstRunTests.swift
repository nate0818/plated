import XCTest

final class FirstRunTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["-plated-review-onboarding"]
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }

    private func enterRecipes() {
        app.launch()
        let local = app.buttons["welcome-local"]
        XCTAssertTrue(local.waitForExistence(timeout: 20))
        capture("01-welcome")
        reveal(local)
        XCTAssertGreaterThanOrEqual(local.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(local.frame.maxX, app.frame.maxX)
        local.tap()
        XCTAssertTrue(app.buttons["first-recipe-add"].waitForExistence(timeout: 15))
    }

    func testPasteReviewSaveOpensRecipeAndPlanning() {
        enterRecipes()
        capture("02-recipes-empty")
        app.buttons["first-recipe-add"].tap()
        XCTAssertTrue(app.textFields["recipe-link"].waitForExistence(timeout: 10))
        capture("03-add-recipe")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Paste recipe text'")).firstMatch.tap()
        let text = app.textViews.firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        text.typeText("Lemon pasta\nServes 2\nIngredients\n200 g pasta\n1 lemon\nInstructions\n1. Boil the pasta for 10 minutes.\n2. Add lemon and serve.")
        let preview = app.buttons["Preview recipe"]
        reveal(preview)
        preview.tap()
        XCTAssertTrue(app.staticTexts["Recipe preview"].waitForExistence(timeout: 15))
        let save = app.buttons["Save recipe"]
        reveal(save)
        save.tap()
        XCTAssertTrue(app.buttons["recipe-plan"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["recipe-saved"].exists)
        capture("04-saved-recipe")
        let groceries = app.buttons["recipe-groceries"]
        reveal(groceries)
        groceries.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'added to Groceries'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["recipe-plan"].tap()
        XCTAssertTrue(app.staticTexts["Plan a night"].waitForExistence(timeout: 8))
        capture("05-plan-recipe")
    }

    func testCancelAndInvitationValidationAndPlanRoute() {
        enterRecipes()
        app.buttons["first-recipe-add"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        let invitation = app.buttons["first-recipe-invitation"]
        reveal(invitation)
        invitation.tap()
        let link = app.textFields["household-invitation-link"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        link.typeText("https://example.com/not-an-invitation")
        let open = app.buttons["Open invitation"]
        reveal(open)
        open.tap()
        XCTAssertTrue(app.staticTexts["This isn't a Plated invitation. Check the full link and try again."].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        let plan = app.buttons["first-recipe-plan"]
        reveal(plan)
        plan.tap()
        XCTAssertTrue(app.buttons["tray-week"].isSelected)
    }

    func testManualRecipeAlsoOpensSavedDetail() {
        enterRecipes()
        app.buttons["first-recipe-add"].tap()
        let write = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Write your own'")).firstMatch
        XCTAssertTrue(write.waitForExistence(timeout: 5))
        reveal(write)
        write.tap()
        let name = app.textFields["Name the dish"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Weeknight toast")
        if app.buttons["Done"].exists { app.buttons["Done"].firstMatch.tap() }
        let save = app.buttons["Save to cookbook"]
        reveal(save)
        save.tap()
        XCTAssertTrue(app.buttons["recipe-plan"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Weeknight toast"].exists)
    }

    func testLargeTextWelcomeAndEmptyStateRemainReachable() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        enterRecipes()
        let add = app.buttons["first-recipe-add"]
        reveal(add)
        XCTAssertTrue(add.isHittable)
        capture("06-recipes-accessibility")
        add.tap()
        let write = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Write your own'")).firstMatch
        reveal(write)
        XCTAssertTrue(write.isHittable)
        capture("07-import-accessibility")
    }
}
