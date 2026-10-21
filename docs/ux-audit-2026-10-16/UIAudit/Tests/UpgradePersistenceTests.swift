import XCTest

/// Run `testSeedBuild45Recipe` with the exact build-45 simulator app installed,
/// then install the candidate over that app without uninstalling or erasing the
/// simulator, and run `testVerifyRecipeAfterUpgrade` on the same simulator.
/// Neither method uses the memory-only design preview.
final class UpgradePersistenceTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    private let recipeTitle = "Upgrade basil toast 45"

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = []
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
    }

    func testSeedBuild45Recipe() {
        app.launch()
        let local = app.buttons["welcome-local"]
        XCTAssertTrue(local.waitForExistence(timeout: 25), "Use a clean isolated simulator for the old-build seed")
        reveal(local)
        local.tap()
        let add = app.buttons["first-recipe-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 20))
        add.tap()
        let write = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Write your own'")).firstMatch
        XCTAssertTrue(write.waitForExistence(timeout: 10))
        reveal(write)
        write.tap()
        let name = app.textFields["Name the dish"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText(recipeTitle)
        if app.buttons["Done"].firstMatch.exists { app.buttons["Done"].firstMatch.tap() }
        let save = app.buttons["Save to cookbook"]
        reveal(save)
        save.tap()
        XCTAssertTrue(app.buttons["recipe-plan"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts[recipeTitle].firstMatch.exists)
        app.terminate()

        app.launch()
        let recipes = app.buttons["tray-cookbook"]
        XCTAssertTrue(recipes.waitForExistence(timeout: 15))
        recipes.tap()
        XCTAssertTrue(app.staticTexts[recipeTitle].firstMatch.waitForExistence(timeout: 20),
                      "The old build must retain the recipe before the upgrade")
    }

    func testVerifyRecipeAfterUpgrade() {
        app.launch()
        let recipes = app.buttons["tray-cookbook"]
        if recipes.waitForExistence(timeout: 15) { recipes.tap() }
        let saved = app.staticTexts[recipeTitle].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 20),
                      "The candidate must preserve the persisted build-45 recipe")
        saved.tap()
        XCTAssertTrue(app.buttons["recipe-plan"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts[recipeTitle].firstMatch.exists)
    }
}
