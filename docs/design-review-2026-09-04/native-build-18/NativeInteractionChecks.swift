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

    func testServingPlan() throws {
        continueAfterFailure = false
        app.launchArguments = ["-plated-design-review", "-appearance", "light"]
        app.launch(); app.activate()
        XCTAssertTrue(app.buttons["Recipes"].waitForExistence(timeout: 8))
        tap("Recipes")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pancake Dinner,")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Serves 4"].waitForExistence(timeout: 5))
        tap("Serves 4")
        tap("Serves 6")
        XCTAssertTrue(app.buttons["Serves 6"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        let plans = app.buttons.matching(NSPredicate(format: "label == %@", "Plan")).allElementsBoundByIndex
        let recipePlan = try XCTUnwrap(plans.first(where: { $0.frame.width > 100 && $0.frame.width < 160 }))
        recipePlan.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["PLAN A NIGHT"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Serves 6"].exists)
        try shot("16-plan-recipe")
    }

    func testHouseholdScope() throws {
        continueAfterFailure = false
        app.launchArguments = ["-plated-design-review", "-appearance", "light"]
        app.launch(); app.activate()
        XCTAssertTrue(app.buttons["Table"].waitForExistence(timeout: 8))
        tap("Table"); tap("Household")
        XCTAssertTrue(app.staticTexts["Sam Meadows"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Dan Alvarez"].exists)
        try shot("17-household")
    }

    func testTableNotificationsBell() throws {
        continueAfterFailure = false
        app.launchArguments = ["-plated-design-review", "-plated-review-notifications", "-appearance", "light"]
        app.launch(); app.activate()
        XCTAssertTrue(app.buttons["Table"].waitForExistence(timeout: 8))
        tap("Table")
        try shot("18-table-bell-inspect")
        let bell = app.buttons["table-notifications-bell"]
        XCTAssertTrue(bell.waitForExistence(timeout: 5))
        XCTAssertTrue(bell.isHittable)
        XCTAssertEqual(bell.value as? String, "12 unread notifications")
        XCTAssertLessThan(bell.frame.maxY, app.staticTexts["The Table"].frame.minY)
        XCTAssertTrue(app.buttons["Share a dish or question"].isHittable)
        XCTAssertTrue(app.buttons.matching(identifier: "Your profile and settings").allElementsBoundByIndex.contains { $0.isHittable })
        try shot("18-table-notifications-unread")
        tap("Household")
        XCTAssertTrue(bell.isHittable)
        bell.tap()
        XCTAssertTrue(app.staticTexts["Activity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(identifier: "A new update at your table.").firstMatch.exists)
        tap("Back")
        XCTAssertTrue(bell.waitForExistence(timeout: 5))
        XCTAssertEqual(bell.value as? String, "No unread notifications")
        tap("My Table")
        try shot("19-table-notifications-read")
    }

    func dragFixture() {
        continueAfterFailure = false
        app.launchArguments = ["-plated-design-review", "-plated-review-drag", "-appearance", "light"]
        app.launch(); app.activate()
        XCTAssertTrue(app.buttons["Recipes"].waitForExistence(timeout: 8))
    }
    func editorSteps() {
        tap("Edit recipe")
        let handle = app.descendants(matching: .any).matching(identifier: "recipe-step-handle-3").firstMatch
        for _ in 0..<8 { if handle.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(handle.isHittable)
    }
    func fieldStep(_ n: Int) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "recipe-step-field-\(n)").firstMatch
    }
    func stepHandle(_ n: Int) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "recipe-step-handle-\(n)").firstMatch
    }
    func testRecipeNativeDrag() throws {
        dragFixture(); tap("Recipes")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pancake Dinner,")).firstMatch.tap()
        editorSteps()
        try shot("20-steps-before-drag")
        stepHandle(1).press(forDuration: 1.0, thenDragTo: stepHandle(3))
        Thread.sleep(forTimeInterval: 1)
        try shot("21-steps-after-drag")
        XCTAssertEqual(fieldStep(1).value as? String, "Heat the pan.")
        XCTAssertEqual(fieldStep(3).value as? String, "Prep the vegetables.")
        tap("Save changes")
        editorSteps()
        XCTAssertEqual(fieldStep(1).value as? String, "Heat the pan.")
        fieldStep(3).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.0, thenDragTo: fieldStep(1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(fieldStep(1).value as? String, "Prep the vegetables.")
        tap("Cancel")
        if app.buttons["Discard"].exists { tap("Discard") }
        editorSteps()
        XCTAssertEqual(fieldStep(1).value as? String, "Heat the pan.")
        fieldStep(1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        stepHandle(1).press(forDuration: 1.0, thenDragTo: stepHandle(2))
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(fieldStep(1).value as? String, "Plate and serve.")
        try shot("22-steps-focused-handle")
    }
    func testWeekCardNativeDrag() throws {
        dragFixture()
        let today = Calendar.current.component(.day, from: Date())
        let tomorrow = Calendar.current.component(.day, from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        let card = app.buttons["featured-dinner-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.press(forDuration: 1.0, thenDragTo: app.buttons["week-date-\(tomorrow)"])
        Thread.sleep(forTimeInterval: 1)
        try shot("23-featured-after-drag")
        XCTAssertTrue(app.buttons["week-date-\(tomorrow)"].isSelected)
        app.buttons["week-date-\(today)"].tap()
        XCTAssertEqual(card.label, "Second dinner")
        let source = app.descendants(matching: .any).matching(identifier: "week-meal-\(today)").firstMatch
        let target = app.descendants(matching: .any).matching(identifier: "week-meal-\(tomorrow)").firstMatch
        for _ in 0..<6 { if source.isHittable && target.isHittable { break }; app.swipeUp() }
        source.press(forDuration: 1.0, thenDragTo: target)
        Thread.sleep(forTimeInterval: 1)
        try shot("23-week-card-moved")
        for _ in 0..<6 { if app.buttons["week-date-\(today)"].isHittable { break }; app.swipeDown() }
        app.buttons["week-date-\(today)"].tap()
        XCTAssertEqual(card.label, "Drag test dinner")
    }
    func testDayCardNativeDrag() throws {
        dragFixture()
        let tomorrow = Calendar.current.component(.day, from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        app.buttons["featured-dinner-card"].tap()
        let breakfast = app.descendants(matching: .any).matching(identifier: "day-meal-breakfast").firstMatch
        XCTAssertTrue(breakfast.waitForExistence(timeout: 5))
        breakfast.press(forDuration: 1.0, thenDragTo: app.buttons["day-date-\(tomorrow)"])
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.buttons["day-date-\(tomorrow)"].isSelected)
        XCTAssertTrue(app.staticTexts["Morning pancakes"].exists)
        XCTAssertTrue(app.staticTexts["Second dinner"].exists)
        try shot("24-day-card-moved")
    }
    func testMonthCardNativeDrag() throws {
        dragFixture(); tap("Month")
        let tomorrow = Calendar.current.component(.day, from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        let meal = app.descendants(matching: .any).matching(identifier: "month-meal-dinner").firstMatch
        XCTAssertTrue(meal.waitForExistence(timeout: 5))
        meal.press(forDuration: 1.0, thenDragTo: app.buttons["month-date-\(tomorrow)"])
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.buttons["month-date-\(tomorrow)"].isSelected)
        XCTAssertTrue(app.staticTexts["Drag test dinner"].exists)
        try shot("25-month-card-moved")
    }

    func visibleButton(_ label: String) -> XCUIElement? {
        app.buttons.matching(identifier: label).allElementsBoundByIndex.first(where: \.isHittable)
    }
    func openAccount() {
        let account = visibleButton("Account")
        XCTAssertNotNil(account)
        account?.tap()
        XCTAssertTrue(app.staticTexts["Account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["account-edit-profile"].isHittable)
        XCTAssertTrue(app.buttons["account-settings"].isHittable)
        XCTAssertTrue(app.buttons["account-your-household"].isHittable)
        XCTAssertTrue(app.buttons["account-view-your-table-profile"].isHittable)
    }
    func testAccountHubAndSettings() throws {
        continueAfterFailure = false
        app.launchArguments = ["-plated-design-review", "-appearance", "light"]
        app.launch(); app.activate()
        XCTAssertTrue(app.buttons["Recipes"].waitForExistence(timeout: 8))

        openAccount()
        try shot("26-account-hub")

        app.buttons["account-settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Done"].isHittable)
        XCTAssertTrue(app.staticTexts["Appearance"].exists)
        try shot("27-settings")
        app.buttons["Done"].tap()

        app.buttons["account-edit-profile"].tap()
        XCTAssertTrue(app.staticTexts["Edit profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        XCTAssertTrue(app.buttons["Save profile"].isHittable)
        XCTAssertTrue(app.staticTexts["Use my contact photo"].exists || app.buttons["Use my contact photo"].exists)
        try shot("28-edit-profile")
        app.buttons["Cancel"].tap()

        app.buttons["account-view-your-table-profile"].tap()
        XCTAssertTrue(app.buttons["Dishes"].waitForExistence(timeout: 5))
        app.buttons["Back"].tap()
        XCTAssertTrue(app.staticTexts["Account"].waitForExistence(timeout: 5))
        app.buttons["Close account"].tap()

        for tab in ["Recipes", "Groceries", "Table"] {
            tap(tab)
            openAccount()
            app.buttons["Close account"].tap()
        }
    }

    func testEndCookingSession() throws {
        dragFixture()
        tap("Let's cook")
        XCTAssertTrue(app.buttons["Start cooking"].waitForExistence(timeout: 5))
        tap("Start cooking")
        XCTAssertTrue(app.staticTexts["Cooking together"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["End cooking"].isHittable)
        tap("Next step")
        XCTAssertTrue(app.staticTexts["STEP 2 OF 3"].exists)
        app.buttons["End cooking"].tap()
        XCTAssertTrue(app.staticTexts["End cooking?"].waitForExistence(timeout: 3))
        try shot("29-end-cooking")
        let confirm = app.buttons.matching(identifier: "End cooking").allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(confirm)
        confirm?.tap()
        XCTAssertTrue(app.buttons["Start cooking"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Resume cooking")).firstMatch.exists)

        tap("Start cooking")
        XCTAssertTrue(app.staticTexts["STEP 1 OF 3"].waitForExistence(timeout: 5))
        app.buttons["End cooking"].tap()
        let cleanup = app.buttons.matching(identifier: "End cooking").allElementsBoundByIndex.first(where: \.isHittable)
        cleanup?.tap()
    }

}
