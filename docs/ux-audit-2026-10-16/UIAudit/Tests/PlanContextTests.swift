import XCTest

final class PlanContextTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    override func setUp() { continueAfterFailure = false }
    func launch(_ flags: [String] = [], size: String = "UICTContentSizeCategoryL", light: Bool = false) {
        app.launchArguments = ["-plated-design-review", "-plated-tab", "week", "-plated-review-empty-tonight",
                               "-appearance", light ? "light" : "dark", "-UIPreferredContentSizeCategoryName", size] + flags
        app.launch()
        XCTAssertTrue(app.buttons["Plan tonight"].waitForExistence(timeout: 20))
    }
    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    func reveal(_ item: XCUIElement) {
        for _ in 0..<8 {
            if item.isHittable { return }
            app.scrollViews["plan-selected-day-content"].swipeUp()
        }
        XCTAssertTrue(item.isHittable, app.debugDescription)
    }
    func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }

    func testEmptyDinnerForecastAndHistoryAreUsefulAndDateSpecific() {
        launch(["-plated-review-dinner-history", "-plated-fake-weather"])
        XCTAssertTrue(app.buttons["Eating out"].isHittable)
        let weather = element("plan-weather-conditions")
        XCTAssertTrue(weather.waitForExistence(timeout: 8))
        XCTAssertTrue(weather.label.contains("Mostly Clear"))
        let cooked = element("plan-history-cooked"), out = element("plan-history-eating-out")
        reveal(cooked)
        XCTAssertEqual(cooked.label, "2 cooked in the last 7 days")
        XCTAssertEqual(out.label, "1 eating out in the last 7 days")
        capture("plan-context-dark")
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let c = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
        app.buttons["week-date-\(c.year!)-\(c.month!)-\(c.day!)"].tap()
        XCTAssertEqual(app.buttons["featured-dinner-card"].label, "Pizza Night")
        reveal(weather)
        XCTAssertTrue(weather.label.contains("Partly Cloudy"))
        XCTAssertFalse(weather.label.contains("Mostly Clear"))
        XCTAssertEqual(cooked.label, "2 cooked in the last 7 days", "The labeled history period stays seven days through today")
        capture("plan-context-next-date")
    }

    func testEatingOutActionUpdatesDinnerAndHistoryWithoutCountingItAsCooking() {
        launch(["-plated-review-dinner-history", "-plated-fake-weather"])
        app.buttons["Eating out"].tap()
        let dinner = app.buttons["featured-dinner-card"]
        XCTAssertTrue(dinner.waitForExistence(timeout: 8)); XCTAssertEqual(dinner.label, "Eating out")
        let out = element("plan-history-eating-out")
        reveal(out)
        XCTAssertEqual(out.label, "2 eating out in the last 7 days")
        XCTAssertEqual(element("plan-history-cooked").label, "2 cooked in the last 7 days")
        capture("plan-context-eating-out")
    }

    func testPlanActionStillOpensMealChoices() {
        launch(["-plated-fake-weather"])
        app.buttons["Plan tonight"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Choose a recipe")).firstMatch.waitForExistence(timeout: 8))
    }

    func testEatingOutSaveFailureKeepsTheDayEmptyAndHistoryUnchanged() {
        launch(["-plated-review-dinner-history", "-plated-fake-weather", "-plated-review-fail-save", "plan eating out"])
        app.buttons["Eating out"].tap()
        XCTAssertTrue(app.alerts["Dinner didn’t save"].waitForExistence(timeout: 8))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["Plan tonight"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["featured-dinner-card"].exists)
        let out = element("plan-history-eating-out"); reveal(out)
        XCTAssertEqual(out.label, "1 eating out in the last 7 days")
        XCTAssertEqual(element("plan-history-cooked").label, "2 cooked in the last 7 days")
        capture("plan-context-eating-out-save-failure")
    }

    func testChoosingCookBeforeRecipeKeepsDinnerOpenAndPreservesTheChoiceWhenPlanning() {
        launch(["-plated-fake-weather"])
        let cook = app.buttons["plan-cook-assignment"]
        XCTAssertTrue(cook.waitForExistence(timeout: 8))
        XCTAssertEqual(cook.label, "Suggested dinner cook")
        XCTAssertTrue((cook.value as? String)?.contains("from your rotation") == true)
        cook.tap(); app.buttons["Sam"].tap()
        XCTAssertEqual(cook.value as? String, "Sam is cooking")
        XCTAssertTrue(app.buttons["Plan tonight"].exists)
        XCTAssertFalse(app.buttons["featured-dinner-card"].exists)
        capture("plan-cook-assigned-before-dish")
        app.buttons["Plan tonight"].tap()
        let pick = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Pick for me")).firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 8)); pick.tap()
        XCTAssertTrue(app.buttons["featured-dinner-card"].waitForExistence(timeout: 8))
        reveal(cook)
        XCTAssertEqual(cook.value as? String, "Sam is cooking")
        capture("plan-cook-assigned-with-dish")
    }

    func testExplicitUnassignedCookIsNotReplacedByRotationWhenChoosingRecipe() {
        launch(["-plated-fake-weather"])
        let cook = app.buttons["plan-cook-assignment"]
        cook.tap(); app.buttons["No cook assigned"].tap()
        XCTAssertEqual(cook.value as? String, "No cook assigned")
        app.buttons["Plan tonight"].tap()
        let pick = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Pick for me")).firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 8)); pick.tap()
        XCTAssertTrue(app.buttons["featured-dinner-card"].waitForExistence(timeout: 8))
        reveal(cook)
        XCTAssertEqual(cook.value as? String, "No cook assigned")
        capture("plan-cook-unassigned-with-dish")
    }

    func testCookAssignmentFailureKeepsPreviousSuggestion() {
        launch(["-plated-fake-weather", "-plated-review-fail-save", "assign dinner cook"])
        let cook = app.buttons["plan-cook-assignment"]
        let previous = cook.value as? String
        cook.tap(); app.buttons["Sam"].tap()
        XCTAssertTrue(app.alerts["Dinner didn’t save"].waitForExistence(timeout: 8))
        app.alerts.buttons["OK"].tap()
        XCTAssertEqual(cook.value as? String, previous)
        XCTAssertEqual(cook.label, "Suggested dinner cook")
        XCTAssertTrue(app.buttons["Plan tonight"].exists)
    }

    func testSharedDinnerNamesTheCookAndOpensAssignmentControls() {
        app.launchArguments = ["-plated-design-review", "-plated-tab", "week", "-plated-fake-weather", "-plated-review-shared-tonight", "-appearance", "dark"]
        app.launch()
        XCTAssertTrue(app.buttons["featured-remote-dinner-card"].waitForExistence(timeout: 20))
        let cook = app.buttons["plan-cook-assignment"]; reveal(cook)
        XCTAssertEqual(cook.value as? String, "Sam is cooking")
        capture("plan-cook-shared")
        cook.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Cook, Sam Meadows")).firstMatch.waitForExistence(timeout: 8))
    }

    func testSharedCookOnlyReservationStillInvitesChoosingDinner() {
        app.launchArguments = ["-plated-design-review", "-plated-tab", "week", "-plated-fake-weather", "-plated-review-shared-tonight", "-plated-review-shared-cook-only", "-appearance", "dark"]
        app.launch()
        XCTAssertTrue(app.buttons["Plan tonight"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["plan-cook-assignment"].value as? String, "Sam is cooking")
        XCTAssertEqual(app.buttons["featured-remote-dinner-card"].label, "What’s for dinner?")
        XCTAssertFalse(app.staticTexts["Unplanned"].exists)
        capture("plan-cook-shared-before-dish")
        app.buttons["Plan tonight"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Choose a recipe")).firstMatch.waitForExistence(timeout: 8))
    }

    func testPermissionDenialAndFailureHaveVisibleRecovery() {
        for (flag, action) in [("-plated-review-weather-permission", "Show local weather"),
                               ("-plated-review-weather-denied", "Open Settings"),
                               ("-plated-review-weather-failed", "Try again")] {
            launch([flag])
            let recovery = app.buttons[action]; reveal(recovery)
            XCTAssertTrue(recovery.isHittable)
            XCTAssertFalse(element("plan-weather-conditions").exists)
            capture("plan-context" + flag)
        }
    }

    func testLargestTextLightAppearanceKeepsEverySectionReachable() {
        launch(["-plated-review-dinner-history", "-plated-fake-weather"], size: "UICTContentSizeCategoryAccessibilityXXXL", light: true)
        reveal(app.buttons["Eating out"])
        XCTAssertTrue(app.buttons["Eating out"].isHittable)
        capture("plan-context-ax-actions")
        reveal(element("plan-weather-conditions")); capture("plan-context-ax-weather")
        reveal(element("plan-history-eating-out"))
        XCTAssertEqual(element("plan-history-cooked").label, "2 cooked in the last 7 days")
        capture("plan-context-ax-history")
    }

    func testEmptyHistoryAndPastWeatherDoNotInventData() {
        launch(["-plated-fake-weather"], light: true)
        XCTAssertEqual(element("plan-history-cooked").label, "0 cooked in the last 7 days")
        XCTAssertEqual(element("plan-history-eating-out").label, "0 eating out in the last 7 days")
        capture("plan-context-light-empty")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let c = Calendar.current.dateComponents([.year, .month, .day], from: yesterday)
        app.buttons["week-date-\(c.year!)-\(c.month!)-\(c.day!)"].tap()
        let missing = app.staticTexts["Past weather isn’t available."]; reveal(missing)
        XCTAssertTrue(missing.exists)
        XCTAssertFalse(element("plan-weather-conditions").exists)
        capture("plan-context-past")
    }

    func testHouseholdActivityOpensRenamedMembersPhotoAndPosts() {
        launch(["-plated-review-dinner-history", "-plated-fake-weather", "-plated-review-household-activity"])
        let sam = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sam Rivera,")).firstMatch
        reveal(sam)
        XCTAssertTrue(sam.label.contains("Sam Rivera"))
        XCTAssertTrue(sam.label.contains("2 dinners cooked · 1 dish shared"))
        capture("plan-household-activity")
        sam.tap()
        XCTAssertTrue(app.staticTexts["Sam Rivera"].waitForExistence(timeout: 8))
        XCTAssertTrue(element("profile-recent-activity").label.contains("2 dinners cooked"))
        let dish = app.buttons["Profile identity dinner, by Sam Meadows"]
        for _ in 0..<5 where !dish.isHittable { app.swipeUp() }
        XCTAssertTrue(dish.isHittable, "An account’s post survives its display-name change")
        capture("profile-renamed-member")
        dish.tap()
        XCTAssertTrue(app.staticTexts["Profile identity dinner"].waitForExistence(timeout: 8))
    }

    func testHouseholdActivityRemainsReachableAtLargestText() {
        launch(["-plated-review-dinner-history", "-plated-fake-weather", "-plated-review-household-activity"],
            size: "UICTContentSizeCategoryAccessibilityXXXL", light: true)
        let sam = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sam Rivera,")).firstMatch
        reveal(sam)
        XCTAssertTrue(sam.label.contains("2 dinners cooked · 1 dish shared"))
        capture("plan-household-ax")
        sam.tap()
        let activity = element("profile-recent-activity")
        for _ in 0..<8 where !activity.isHittable { app.swipeUp() }
        XCTAssertTrue(activity.isHittable)
        capture("profile-household-ax")
    }
}

@available(iOS 27.0, *)
@MainActor
final class PlanContextVoiceOverTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    var voice: XCUIVoiceOverService { XCUIDevice.shared.voiceOverService }
    override func tearDownWithError() throws {
        if voice.isEnabled { try voice.disable() }
        app.terminate()
    }
    func testDinnerWeatherAndCountsReadInOrder() throws {
        if voice.isEnabled { try voice.disable() }
        app.launchArguments = ["-plated-design-review", "-plated-tab", "week", "-plated-review-empty-tonight",
                               "-plated-review-dinner-history", "-plated-fake-weather", "-appearance", "dark"]
        app.launch(); XCTAssertTrue(app.buttons["Plan tonight"].waitForExistence(timeout: 20))
        try voice.enable()
        var transcript = [try voice.currentSpeech().utterance]
        let targets = ["What’s for dinner", "Suggested dinner cook", "Plan tonight", "Eating out", "Mostly Clear", "2 cooked", "1 eating out", "Your household", "Manage household", "Riley"]
        var next = 0
        for _ in 0..<45 {
            let spoken = try voice.moveForward().utterance
            transcript.append(spoken)
            if spoken.localizedCaseInsensitiveContains(targets[next]) { next += 1 }
            if next == targets.count { break }
        }
        let attachment = XCTAttachment(string: transcript.joined(separator: "\n"))
        attachment.name = "plan-context-voiceover"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertEqual(next, targets.count, "Dinner actions, weather, counts and household profiles should be read in order")
    }
}
