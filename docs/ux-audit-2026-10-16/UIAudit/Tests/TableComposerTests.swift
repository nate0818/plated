import XCTest

final class TableComposerTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    override func setUp() { continueAfterFailure = false }
    var submit: XCUIElement { app.buttons["table-post-submit"] }
    var text: XCUIElement { app.descendants(matching: .any).matching(identifier: "table-post-text").firstMatch }

    func launch(light: Bool = false, large: Bool = false, reset: Bool = true, flags: [String] = []) {
        app.terminate()
        app.launchArguments = ["-plated-design-review", "-plated-open-table-post", "-appearance", light ? "light" : "dark",
            "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
            + (reset ? ["-plated-review-post-reset"] : []) + flags
        app.launch()
        XCTAssertTrue(submit.waitForExistence(timeout: 20))
    }
    func capture(_ name: String) {
        let picture = XCTAttachment(screenshot: app.screenshot()); picture.name = name; picture.lifetime = .keepAlways; add(picture)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    func reveal(_ target: XCUIElement) {
        for _ in 0..<6 {
            if target.isHittable { return }
            app.scrollViews["table-post-scroll"].swipeUp()
        }
        XCTAssertTrue(target.isHittable)
    }
    func write(_ value: String) { text.tap(); text.typeText(value) }
    func addTitle() {
        let more = app.buttons["More post options"]
        reveal(more); more.tap()
        let title = app.buttons["Add a title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap()
    }

    func testTextOnlyRestaurantCanPostAndOpenFromFeed() {
        launch()
        XCTAssertFalse(submit.isEnabled)
        XCTAssertTrue(app.buttons["Photo"].isHittable)
        capture("composer-dark-empty")
        write("We loved the cafe on Main Street. Try the fresh tomatoes!")
        XCTAssertTrue(submit.isEnabled)
        capture("composer-writing-keyboard")
        submit.tap()
        XCTAssertTrue(submit.waitForNonExistence(timeout: 8))
        app.buttons["tray-table"].tap()
        let posted = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "We loved the cafe")).firstMatch
        XCTAssertTrue(posted.waitForExistence(timeout: 10))
        capture("general-post-feed")
        posted.tap()
        XCTAssertTrue(app.staticTexts["Post"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Save"].exists)
        capture("general-post-thread")
    }

    func testLightEmptyAndPhotoRemoval() {
        launch(light: true)
        capture("composer-light-empty")
        launch(light: true, flags: ["-plated-review-post-photo"])
        XCTAssertTrue(submit.isEnabled)
        capture("composer-light-photo")
        app.buttons["Remove photo"].tap()
        XCTAssertFalse(submit.isEnabled)
        XCTAssertTrue(app.buttons["Photo"].exists)
    }

    func testPhotoFailureBlocksPostingUntilExplicitRemoval() {
        launch(flags: ["-plated-review-post-photo-error"])
        write("These market tomatoes look great.")
        XCTAssertFalse(submit.isEnabled)
        capture("composer-photo-failure")
        let remove = app.buttons["Remove photo"]; reveal(remove); remove.tap()
        XCTAssertTrue(submit.isEnabled)
    }

    func testPollAndDraftPreservePendingChoiceAndWriting() {
        launch()
        write("Where should we go on Friday?")
        app.buttons["Close post"].tap()
        app.buttons["Keep writing"].tap()
        let poll = app.buttons["Poll"]; reveal(poll); poll.tap()
        let choice = app.textFields["Add a choice"]; reveal(choice); choice.tap(); choice.typeText("Thai")
        XCTAssertFalse(submit.isEnabled)
        app.buttons["Add poll choice"].tap()
        choice.tap(); choice.typeText("Pizza")
        XCTAssertTrue(submit.isEnabled)
        capture("composer-poll-pending-choice")
        app.buttons["Close post"].tap(); app.buttons["Save draft"].tap()
        launch(reset: false)
        XCTAssertEqual(text.value as? String, "Where should we go on Friday?")
        reveal(choice)
        XCTAssertEqual(choice.value as? String, "Pizza")
        XCTAssertTrue(app.staticTexts["Thai"].exists)
        XCTAssertTrue(submit.isEnabled)
        capture("composer-restored-draft")
        app.buttons["Close post"].tap(); app.buttons["Discard post"].tap()
        launch(reset: false)
        XCTAssertFalse(submit.isEnabled)
    }

    func testPhotoAndPeopleSurviveDraftSaveAndReopen() {
        launch(flags: ["-plated-review-post-photo"])
        let people = app.buttons["People"]; reveal(people); people.tap()
        let sam = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Tag Sam")).firstMatch
        reveal(sam); sam.tap()
        XCTAssertTrue(sam.isSelected)
        app.buttons["Close post"].tap(); app.buttons["Save draft"].tap()
        launch(reset: false)
        XCTAssertTrue(submit.isEnabled)
        XCTAssertTrue(app.buttons["Remove photo"].exists)
        reveal(sam); XCTAssertTrue(sam.isSelected)
        capture("composer-photo-people-restored")
    }

    func testDoneDismissesFocusForEveryEditableField() {
        launch()
        write("Market finds")
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        addTitle()
        let title = app.descendants(matching: .any).matching(identifier: "table-post-title").firstMatch
        reveal(title); title.tap(); title.typeText("Tomatoes")
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        let poll = app.buttons["Poll"]; reveal(poll); poll.tap()
        let choice = app.textFields["Add a choice"]; reveal(choice); choice.tap(); choice.typeText("Yes")
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
    }

    func testPhotoLibraryOpensAndCanBeCancelled() {
        launch()
        app.buttons["Photo"].tap()
        let library = app.buttons["Choose from library"]
        if library.waitForExistence(timeout: 2) { library.tap() }
        let cancel = app.buttons.matching(NSPredicate(format: "label == 'Cancel' OR label == 'Close'")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8), app.buttons.allElementsBoundByIndex.map(\.label).joined(separator: ", "))
        capture("composer-system-photo-picker")
        cancel.tap()
        XCTAssertTrue(submit.waitForExistence(timeout: 8))
        XCTAssertFalse(submit.isEnabled)
    }

    func testLargestTextControlsAndAccessibility() throws {
        launch(light: true, large: true)
        XCTAssertTrue(submit.isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["Close post"].frame.width, 44)
        XCTAssertLessThan(app.staticTexts["New post"].frame.height, 150)
        capture("composer-ax5-empty")
        addTitle()
        let title = app.descendants(matching: .any).matching(identifier: "table-post-title").firstMatch
        reveal(title); title.tap(); title.typeText("A new restaurant with a very long name and a wonderful patio")
        XCTAssertTrue(submit.isEnabled)
        capture("composer-ax5-long-title-keyboard")
        app.buttons["Close post"].tap(); app.buttons["Keep writing"].tap()
        var issues: [String] = []
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped]) { issue in
            issues.append(issue.compactDescription + "\n" + issue.detailedDescription + "\n" + (issue.element?.debugDescription ?? "No attributed element")); return true
        }
        let report = XCTAttachment(string: issues.isEmpty ? "No issues returned." : issues.joined(separator: "\n\n"))
        report.name = "composer-accessibility"; report.lifetime = .keepAlways; add(report)
    }
}
