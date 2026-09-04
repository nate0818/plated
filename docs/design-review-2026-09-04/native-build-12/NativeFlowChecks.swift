import XCTest
final class GalleryTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    func shot(_ name: String) throws {
        Thread.sleep(forTimeInterval: 1)
        let image = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        try image.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/plated-native-captures/\(name).png"))
        try app.debugDescription.write(toFile: "/tmp/plated-native-captures/\(name).txt", atomically: true, encoding: .utf8)
    }
    func tap(_ label: String) {
        let button = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing \(label)"); button.tap()
    }
    func testNativeScreens() throws {
        continueAfterFailure = false
        app.launchArguments = ["-plated-design-review", "-appearance", "light"]
        app.launch()
        app.activate()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.staticTexts["Your week"].waitForExistence(timeout: 8))
        try shot("01-plan")
        tap("Recipes")
        XCTAssertTrue(app.textFields["Find a dish or ingredient"].exists)
        try shot("02-recipes")
        tap("Groceries")
        XCTAssertTrue(app.buttons["By meal"].exists)
        try shot("03-groceries")
        tap("By meal")
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " selected")).firstMatch.tap()
        try shot("04-meal-picker")
        tap("Done")
        tap("Table")
        XCTAssertTrue(app.buttons["My Table"].exists)
        XCTAssertTrue(app.buttons["Household"].exists)
        try shot("05-table")
        tap("Your profile and settings")
        XCTAssertTrue(app.buttons["Conversations"].waitForExistence(timeout: 5))
        try shot("06-profile")
    }
    func testCookingAndCalendar() throws {
        continueAfterFailure = false
        app.launchArguments = ["-plated-design-review", "-appearance", "light"]
        app.launch()
        app.activate()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.staticTexts["Your week"].waitForExistence(timeout: 8))
        tap("Month")
        try shot("07-month")
        tap("Recipes")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pancake Dinner,")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Edit recipe"].waitForExistence(timeout: 5))
        try shot("08-recipe")
        tap("Edit recipe")
        try shot("09-editor")
        let firstStep = app.textFields["Step 1. What happens first?"]
        for _ in 0..<5 { if firstStep.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(firstStep.exists)
        firstStep.tap(); firstStep.typeText("Mix the batter until just combined.")
        tap("Add step")
        let secondStep = app.textFields["Step 2…"]
        secondStep.tap(); secondStep.typeText("Cook until golden, then serve with berries.")
        tap("Add step")
        app.swipeDown()
        if app.buttons["Done"].exists { tap("Done") }
        tap("Save changes")
        XCTAssertTrue(app.buttons["Start cooking"].waitForExistence(timeout: 5))
        tap("Start cooking")
        XCTAssertTrue(app.staticTexts["Cooking together"].waitForExistence(timeout: 5))
        try shot("10-cooking")
        tap("Ingredients")
        XCTAssertTrue(app.navigationBars["Ingredients"].waitForExistence(timeout: 5))
        try shot("11-cooking-ingredients")
        tap("Done")
        tap("Next step")
        tap("Minimize cooking")
        XCTAssertTrue(app.buttons["Resume cooking Pancake Dinner"].waitForExistence(timeout: 5))
        tap("Groceries")
        try shot("12-resume")
        tap("Resume cooking Pancake Dinner")
        XCTAssertTrue(app.staticTexts["STEP 2 OF 2"].waitForExistence(timeout: 5))
        tap("Finish cooking")
        XCTAssertTrue(app.staticTexts["Dinner, made."].waitForExistence(timeout: 5))
        try shot("13-complete")
        tap("Done")
        XCTAssertFalse(app.buttons["Resume cooking Pancake Dinner"].exists)
    }
    func testDarkAppearance() throws {
        app.launchArguments = ["-plated-design-review", "-appearance", "dark"]
        app.launch()
        app.activate()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.staticTexts["Your week"].waitForExistence(timeout: 8))
        try shot("14-plan-dark")
        tap("Recipes")
        try shot("15-recipes-dark")
    }

}
