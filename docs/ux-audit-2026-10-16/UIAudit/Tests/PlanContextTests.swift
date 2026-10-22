import XCTest

final class PlanContextTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    override func setUp() { continueAfterFailure = false }
    func launch(_ flags: [String] = [], size: String = "UICTContentSizeCategoryL", light: Bool = false) {
        app.launchArguments = ["-plated-design-review", "-plated-tab", "week", "-plated-review-empty-tonight",
                               "-appearance", light ? "light" : "dark", "-UIPreferredContentSizeCategoryName", size] + flags
        app.launch()
        XCTAssertTrue(app.buttons["Choose a meal"].waitForExistence(timeout: 20))
    }
    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    func reveal(_ item: XCUIElement) {
        for _ in 0..<8 {
            // A partly visible tall row can report hittable while its default
            // tap point sits underneath the app's bottom navigation.
            let bottom = app.buttons["tray-week"].frame.minY
            if item.isHittable && item.frame.midY < bottom - 12 { return }
            app.scrollViews["plan-selected-day-content"].swipeUp()
        }
        XCTAssertTrue(item.isHittable, app.debugDescription)
    }
    func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }

    // Exercise the real Apple artwork: ordinary fake-weather previews only
    // showed "Preview weather" and concealed the reversed appearance variants.
    func testLiveWeatherAttributionOnGreen() { reviewWeatherAttribution(light: false) }
    func testLiveWeatherAttributionOnCream() { reviewWeatherAttribution(light: true) }
    func testLiveWeatherAttributionAtAccessibilitySize() { reviewWeatherAttribution(light: true, accessible: true) }

    func testCompactPhoneKeepsLiveWeatherAndDinnerCountsAboveTabs() {
        for light in [false, true] {
            if app.state != .notRunning { app.terminate() }
            launch(["-plated-review-dinner-history", "-plated-fake-weather",
                    "-plated-review-weather-attribution"], light: light)
            XCTAssertTrue(element("plan-weather-attribution-mark").waitForExistence(timeout: 20))
            let cooked = element("plan-history-cooked")
            let out = element("plan-history-eating-out")
            XCTAssertTrue(cooked.waitForExistence(timeout: 8))
            XCTAssertTrue(out.exists)
            let tabTop = app.buttons["tray-week"].frame.minY
            XCTAssertLessThan(cooked.frame.maxY, tabTop,
                              "Cooked count and label must be visible before scrolling")
            XCTAssertLessThan(out.frame.maxY, tabTop,
                              "Eating-out count and label must be visible before scrolling")
            capture("plan-compact-weather-history-\(light ? "cream" : "green")")
        }
    }

    private func reviewWeatherAttribution(light: Bool, accessible: Bool = false) {
        launch(["-plated-fake-weather", "-plated-review-weather-attribution"],
               size: accessible ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL", light: light)
        let credit = element("plan-weather-attribution")
        XCTAssertTrue(credit.waitForExistence(timeout: 20), "Apple's live attribution metadata must load")
        reveal(credit)
        XCTAssertTrue(element("plan-weather-attribution-mark").waitForExistence(timeout: 15),
                      "Review Apple's downloaded artwork, not the loading fallback")
        XCTAssertEqual(credit.label, "Apple Weather. Weather data sources")
        capture("weather-attribution-\(light ? "cream" : "green")\(accessible ? "-AX5" : "")")
    }

    func testEmptyDinnerForecastAndHistoryAreUsefulAndDateSpecific() {
        launch(["-plated-review-dinner-history", "-plated-fake-weather"])
        XCTAssertTrue(app.buttons["Eating out instead"].isHittable)
        let weather = element("plan-weather-conditions")
        XCTAssertTrue(weather.waitForExistence(timeout: 8))
        XCTAssertTrue(weather.label.contains("Mostly Clear"))
        let cooked = element("plan-history-cooked"), out = element("plan-history-eating-out")
        reveal(cooked)
        XCTAssertEqual(cooked.label, "2 cooked at home in the last 7 days")
        XCTAssertEqual(out.label, "1 ate out in the last 7 days")
        capture("plan-context-dark")
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let c = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
        app.buttons["week-date-\(c.year!)-\(c.month!)-\(c.day!)"].tap()
        XCTAssertEqual(app.buttons["featured-dinner-card"].label, "Pizza Night")
        reveal(weather)
        XCTAssertTrue(weather.label.contains("Partly Cloudy"))
        XCTAssertFalse(weather.label.contains("Mostly Clear"))
        XCTAssertEqual(cooked.label, "2 cooked at home in the last 7 days", "The labeled history period stays seven days through today")
        capture("plan-context-next-date")
    }

    func testEatingOutActionUpdatesDinnerAndHistoryWithoutCountingItAsCooking() {
        launch(["-plated-review-dinner-history", "-plated-fake-weather"])
        app.buttons["Eating out instead"].tap()
        let dinner = app.buttons["featured-dinner-card"]
        XCTAssertTrue(dinner.waitForExistence(timeout: 8)); XCTAssertEqual(dinner.label, "Eating out")
        let out = element("plan-history-eating-out")
        reveal(out)
        XCTAssertEqual(out.label, "2 ate out in the last 7 days")
        XCTAssertEqual(element("plan-history-cooked").label, "2 cooked at home in the last 7 days")
        capture("plan-context-eating-out")
    }

    func testPlanActionStillOpensMealChoices() {
        launch(["-plated-fake-weather"])
        app.buttons["Choose a meal"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Choose a recipe")).firstMatch.waitForExistence(timeout: 8))
    }

    func testAccessibilityPlanKeepsThePrimaryChoiceInView() {
        launch(["-plated-fake-weather"], size: "UICTContentSizeCategoryAccessibilityXXXL", light: true)
        let choose = app.buttons["Choose a meal"]
        let tabBarTop = app.buttons["tray-week"].frame.minY
        XCTAssertTrue(choose.isHittable)
        XCTAssertLessThan(choose.frame.midY, tabBarTop,
                          "The dinner decision should be visible before scrolling past cook assignment")
        capture("plan-open-accessibility-primary-action")
        choose.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Choose a recipe")).firstMatch.waitForExistence(timeout: 8))
    }

    func testEatingOutSaveFailureKeepsTheDayEmptyAndHistoryUnchanged() {
        launch(["-plated-review-dinner-history", "-plated-fake-weather", "-plated-review-fail-save", "plan eating out"])
        app.buttons["Eating out instead"].tap()
        XCTAssertTrue(app.alerts["Dinner didn’t save"].waitForExistence(timeout: 8))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["Choose a meal"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["featured-dinner-card"].exists)
        let out = element("plan-history-eating-out"); reveal(out)
        XCTAssertEqual(out.label, "1 ate out in the last 7 days")
        XCTAssertEqual(element("plan-history-cooked").label, "2 cooked at home in the last 7 days")
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
        XCTAssertTrue(app.buttons["Choose a meal"].exists)
        XCTAssertFalse(app.buttons["featured-dinner-card"].exists)
        capture("plan-cook-assigned-before-dish")
        app.buttons["Choose a meal"].tap()
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
        app.buttons["Choose a meal"].tap()
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
        XCTAssertTrue(app.buttons["Choose a meal"].exists)
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
        XCTAssertTrue(app.buttons["Choose a meal"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["plan-cook-assignment"].value as? String, "Sam is cooking")
        XCTAssertEqual(app.buttons["featured-remote-dinner-card"].label, "What sounds good tonight?")
        XCTAssertFalse(app.staticTexts["Unplanned"].exists)
        capture("plan-cook-shared-before-dish")
        app.buttons["Choose a meal"].tap()
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
        reveal(app.buttons["Eating out instead"])
        XCTAssertTrue(app.buttons["Eating out instead"].isHittable)
        capture("plan-context-ax-actions")
        reveal(element("plan-weather-conditions")); capture("plan-context-ax-weather")
        reveal(element("plan-history-eating-out"))
        XCTAssertEqual(element("plan-history-cooked").label, "2 cooked at home in the last 7 days")
        capture("plan-context-ax-history")
    }

    func testEmptyHistoryAndPastWeatherDoNotInventData() {
        launch(["-plated-fake-weather"], light: true)
        XCTAssertFalse(element("plan-history-cooked").exists)
        XCTAssertFalse(element("plan-history-eating-out").exists)
        let explanation = app.staticTexts["Your first dinner is a good place to start. Mark a meal cooked to build your household’s history."]
        reveal(explanation)
        XCTAssertTrue(explanation.isHittable)
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
        let sam = app.buttons["plan-household-seat-ux-sam"]
        reveal(sam)
        XCTAssertTrue(sam.label.contains("Sam Rivera"))
        XCTAssertTrue(sam.label.lowercased().contains("shared") || sam.label.lowercased().contains("cooked"), "An actor row names a recorded action")
        capture("plan-household-activity")
        sam.tap()
        XCTAssertTrue(app.staticTexts["Sam Rivera"].waitForExistence(timeout: 8))
        capture("profile-renamed-member-before-activity-assert")
        XCTAssertTrue(element("profile-recent-activity").label.contains("Shared Profile identity dinner"), element("profile-recent-activity").label)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "2 Dinners cooked")).firstMatch.exists)
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
        let sam = app.buttons["plan-household-seat-ux-sam"]
        reveal(sam)
        XCTAssertTrue(sam.label.lowercased().contains("shared") || sam.label.lowercased().contains("cooked"), "An actor row names a recorded action")
        capture("plan-household-ax")
        sam.tap()
        XCTAssertTrue(app.staticTexts["Sam Rivera"].waitForExistence(timeout: 8))
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
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 else {
            throw XCTSkip("The XCTest VoiceOver remote service is unavailable on this iOS 26 simulator; this reading-order check runs on iOS 27.")
        }
        if voice.isEnabled { try voice.disable() }
        app.launchArguments = ["-plated-design-review", "-plated-tab", "week", "-plated-review-empty-tonight",
                               "-plated-review-dinner-history", "-plated-fake-weather", "-appearance", "dark"]
        app.launch(); XCTAssertTrue(app.buttons["Choose a meal"].waitForExistence(timeout: 20))
        try voice.enable()
        var transcript = [try voice.currentSpeech().utterance]
        let targets = ["What sounds good tonight", "Suggested dinner cook", "Choose a meal", "Eating out", "Mostly Clear", "2 cooked at home", "1 ate out", "At home", "Manage household", "You planned Eating out"]
        var next = 0
        for _ in 0..<45 {
            let spoken = try voice.moveForward().utterance
            transcript.append(spoken)
            if spoken.localizedCaseInsensitiveContains(targets[next]) { next += 1 }
            if next == targets.count { break }
        }
        let attachment = XCTAttachment(string: transcript.joined(separator: "\n"))
        attachment.name = "plan-context-voiceover"; attachment.lifetime = .keepAlways; add(attachment)
        print("PLAN CONTEXT VOICEOVER:\n" + transcript.joined(separator: "\n"))
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "plan-context-voiceover-tree"; tree.lifetime = .keepAlways; add(tree)
        XCTAssertEqual(next, targets.count, "Dinner actions, weather, counts and household profiles should be read in order")
    }
}
