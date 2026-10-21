import XCTest

/// Uses the actual VoiceOver service, not an accessibility-tree approximation.
@available(iOS 27.0, *)
@MainActor
final class ReleaseVoiceOverTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    var speech: [String] = []
    var voice: XCUIVoiceOverService { XCUIDevice.shared.voiceOverService }

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        let transcript = XCTAttachment(string: speech.joined(separator: "\n"))
        transcript.name = name + "-speech"; transcript.lifetime = .keepAlways; add(transcript)
        if voice.isEnabled { try voice.disable() }
        app.terminate()
    }
    func launch(_ flags: [String] = []) throws {
        if voice.isEnabled { try voice.disable() }
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-plated-design-review", "-appearance", "dark"] + flags
        app.launch()
        XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 20))
        try voice.enable()
        XCTAssertTrue(voice.isEnabled)
        speech.append("SCREEN " + flags.joined(separator: " "))
        speech.append(try voice.currentSpeech().utterance)
    }
    @discardableResult
    func seek(_ text: String, limit: Int = 40) throws -> String {
        let focused = try voice.currentSpeech().utterance
        if focused.localizedCaseInsensitiveContains(text) {
            speech.append(focused)
            return focused
        }
        var previous = "", repeated = 0
        for _ in 0..<limit {
            let utterance = try voice.moveForward().utterance
            speech.append(utterance)
            print("VOICEOVER: " + utterance)
            if utterance.localizedCaseInsensitiveContains(text) { return utterance }
            repeated = utterance == previous ? repeated + 1 : 0
            previous = utterance
            if repeated >= 2 { break }
        }
        XCTFail("VoiceOver could not reach \(text)")
        return ""
    }
    func testNativeInputActivationProbe() throws {
        guard ProcessInfo.processInfo.environment["PLATED_MANUAL_VOICEOVER_PROBE"] == "1" else {
            throw XCTSkip("Requires host-assisted accessibility activation; physical gestures remain a device check.")
        }
        try launch(["-plated-tab", "week"])
        try seek("Start cooking")
        print("VOICEOVER READY FOR NATIVE INPUT")
        let before = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        before.name = "voiceover-start-focused"; before.lifetime = .keepAlways; add(before)
        // A human double-taps on the physical phone while VoiceOver owns
        // focus. A synthesized XCTest tap is not a VoiceOver gesture test.
        XCTAssertTrue(app.buttons["Minimize cooking"].waitForExistence(timeout: 180))
        let after = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        after.name = "voiceover-native-activation"; after.lifetime = .keepAlways; add(after)
    }

    func testRootAndSheetReadingOrder() throws {
        let screens: [(String, [String], String)] = [
            ("plan", ["-plated-tab", "week"], "Start cooking"),
            ("recipes", ["-plated-tab", "cookbook"], "Dish or ingredient"),
            ("groceries", ["-plated-tab", "groceries"], "Asparagus"),
            ("table", ["-plated-tab", "table"], "Pancake Dinner"),
            ("thread", ["-plated-open-thread"], "Add a comment"),
            ("profile", ["-plated-open-profile", "-plated-open-edit-profile"], "Save"),
            ("gathering", ["-plated-review-plan-night", "-plated-review-gathering"], "Save gathering")
        ]
        for (name, flags, target) in screens {
            try launch(flags); speech.append("BEGIN " + name)
            try seek(target)
        }
    }

    func testHouseholdAndTableHeaderControlsAreAnnouncedAsButtons() throws {
        try launch(["-plated-tab", "home", "-householdName", "Meadows"])
        try seek("Meadows")
        let settings = try seek("Household settings")
        XCTAssertTrue(settings.localizedCaseInsensitiveContains("button"))
        let notifications = try seek("Notifications")
        XCTAssertTrue(notifications.localizedCaseInsensitiveContains("button"))

        try launch(["-plated-tab", "table"])
        try seek("The Table")
        let people = try seek("People and invitations")
        XCTAssertTrue(people.localizedCaseInsensitiveContains("button"))
    }

    func testFeaturedDinnerNameAndCookingReachability() throws {
        try launch(["-plated-tab", "week"])
        let dinner = try seek("Salmon Night")
        XCTAssertTrue(dinner.contains("Button"), "Dinner must be announced as its named control, not image-recognition objects")
        try seek("Start cooking")
        let date = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let today = app.sliders["week-date-\(date.year!)-\(date.month!)-\(date.day!)"]
        XCTAssertTrue(today.isSelected, "Reading through the date row must not change the selected day")
        let spokenDates = speech.filter { $0.localizedCaseInsensitiveContains("dinner planned") }
        XCTAssertEqual(spokenDates.count, 1, "VoiceOver reads only the selected date before continuing to dinner")
        // XCUIVoiceOverService truncates this date utterance after 80
        // characters; the adjustable trait begins before that cutoff.
        XCTAssertTrue(spokenDates.first?.localizedCaseInsensitiveContains("adjusta") == true)
        // A physical up/down VoiceOver gesture is a separate device check.
    }

    @discardableResult
    func hear(_ text: String, limit: Int = 55) throws -> String {
        let current = try voice.currentSpeech().utterance
        speech.append(current)
        if current.localizedCaseInsensitiveContains(text) { return current }
        for forward in [true, false] {
            var previous = "", repeated = 0
            for _ in 0..<limit {
                let utterance = try (forward ? voice.moveForward() : voice.moveBackward()).utterance
                speech.append(utterance); print("VOICEOVER: " + utterance)
                if utterance.localizedCaseInsensitiveContains(text) { return utterance }
                repeated = utterance == previous ? repeated + 1 : 0
                previous = utterance
                if repeated >= 2 { break }
            }
        }
        XCTFail("VoiceOver could not reach \(text)")
        return ""
    }

    func captureJourney(_ title: String) {
        let picture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        picture.name = title; picture.lifetime = .keepAlways; add(picture)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = title + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }

    // Speech is traversed by the real VoiceOver service; XCTest performs
    // form input. These do not claim physical gesture or rotor coverage.
    func testProfileFailureCanBeHeardAndDraftCanBeCancelled() throws {
        try launch(["-plated-open-profile", "-plated-open-edit-profile",
                    "-plated-review-fail-save", "save profile"])
        try hear("A short line about you")
        let bio = app.textFields["A short line about you"]
        bio.doubleTap(); bio.typeText("Release accessibility draft")
        if app.buttons["Done"].exists { app.buttons["Done"].doubleTap() }
        try hear("Save")
        app.buttons["Save"].firstMatch.doubleTap()
        captureJourney("voiceover-profile-after-save")
        XCTAssertTrue(app.staticTexts["That didn’t save. Your draft is still here."].waitForExistence(timeout: 8))
        try hear("didn’t save")
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value CONTAINS %@", "Release accessibility draft")).firstMatch.exists)
        try hear("Save")
        app.buttons["Save"].firstMatch.doubleTap()
        try hear("didn’t save")
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value CONTAINS %@", "Release accessibility draft")).firstMatch.exists)
        captureJourney("voiceover-profile-error-retains-draft")
        try hear("Cancel")
        app.buttons["Cancel"].doubleTap()
        XCTAssertTrue(app.buttons["Cancel"].waitForNonExistence(timeout: 10))
    }

    func testRecipeFailureAndDiscardRetainOriginalRecipe() throws {
        try launch(["-plated-open-recipe-detail", "-plated-review-fail-save", "save recipe"])
        try hear("Recipe options")
        app.buttons["Recipe options"].doubleTap()
        try hear("Edit recipe")
        app.buttons["Edit recipe"].doubleTap()
        let field = app.textFields["Name the dish"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let original = try XCTUnwrap(field.value as? String)
        try hear(original)
        field.doubleTap(); field.typeText(" release accessibility")
        if app.buttons["Done"].exists { app.buttons["Done"].doubleTap() }
        try hear("Save changes", limit: 110)
        app.buttons["Save changes"].doubleTap()
        captureJourney("voiceover-recipe-after-save-attempt")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Couldn't save the recipe")).firstMatch.waitForExistence(timeout: 8))
        try hear("Couldn't save the recipe", limit: 110)
        XCTAssertTrue((field.value as? String)?.contains("release accessibility") == true)
        captureJourney("voiceover-recipe-save-failure")
        app.buttons["Cancel"].doubleTap()
        try hear("Keep writing")
        app.buttons["Keep writing"].doubleTap()
        XCTAssertTrue((field.value as? String)?.contains("release accessibility") == true)
        app.buttons["Cancel"].doubleTap()
        try hear("Discard")
        app.buttons["Discard"].doubleTap()
        XCTAssertTrue(app.buttons["Recipe options"].waitForExistence(timeout: 10))
        app.buttons["Recipe options"].doubleTap()
        try hear("Edit recipe")
        app.buttons["Edit recipe"].doubleTap()
        XCTAssertEqual(field.value as? String, original)
        app.buttons["Cancel"].doubleTap()
    }

    func testGatheringFormControlsAndLocalSaveWithVoiceOver() throws {
        try launch(["-plated-review-plan-night", "-plated-review-gathering"])
        try hear("Text field")
        let title = app.textFields["Sunday dinner party"]
        title.doubleTap()
        if let value = title.value as? String, value != "Sunday dinner party" {
            title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        title.typeText("Accessible dinner")
        let done = app.buttons["Done editing gathering"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.doubleTap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        try hear("One more guest")
        app.buttons["One more guest"].doubleTap()
        XCTAssertTrue(app.staticTexts["5"].exists)
        try hear("Add to Apple Calendar")
        let calendar = app.switches["Add to Apple Calendar"]
        if calendar.value as? String == "1" { calendar.doubleTap() }
        XCTAssertEqual(calendar.value as? String, "0")
        try hear("Save gathering")
        XCTAssertTrue(app.buttons["Save gathering"].isEnabled)
        captureJourney("voiceover-gathering-ready-to-save")
        app.buttons["Save gathering"].doubleTap()
        XCTAssertTrue(app.buttons["Save gathering"].waitForNonExistence(timeout: 10))
        // This review route opens the first date of the week while Plan
        // retains today's selection; saving must dismiss the form.
        XCTAssertTrue(app.buttons["tray-week"].waitForExistence(timeout: 10))
        try hear("Calendar")
        captureJourney("voiceover-gathering-saved")
    }
}
