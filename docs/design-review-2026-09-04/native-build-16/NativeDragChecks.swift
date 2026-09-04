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

}
