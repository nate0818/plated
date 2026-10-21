import XCTest

/// Exercises the real comment editor over the isolated comment fixture.
/// These journeys never send a comment; images and trees still need visual
/// review, and native IME/VoiceOver behavior requires separate device evidence.
final class FidelityCommentInputTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    private var input: XCUIElement { app.textViews["post-comment-input"] }
    private var send: XCUIElement { app.buttons["Send"] }

    override func setUp() { continueAfterFailure = false }
    override func tearDown() { app.terminate() }

    private func launch(light: Bool, large: Bool, reset: Bool) {
        app.terminate()
        app.launchArguments = [
            "-plated-design-review", "-plated-review-comment-reactions",
            "-plated-tab", "table", "-plated-open-thread",
            "-householdName", "Meadows", "-userFirstName", "Nate",
            "-appearance", light ? "light" : "dark",
            "-UIPreferredContentSizeCategoryName",
            large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"
        ] + (reset ? ["-plated-review-comment-reset"] : [])
        app.launch()
        XCTAssertTrue(input.waitForExistence(timeout: 20), app.debugDescription)
    }

    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }

    private func waitForValue(_ expected: String) {
        let predicate = NSPredicate(format: "value == %@", expected)
        XCTAssertEqual(XCTWaiter.wait(for: [
            XCTNSPredicateExpectation(predicate: predicate, object: input)
        ], timeout: 8), .completed, app.debugDescription)
        XCTAssertEqual(input.value as? String, expected)
    }

    private func checkKeyboardAndSendGeometry() {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let clear = NSPredicate { [self] _, _ in
            input.isHittable && send.isHittable && keyboard.frame.height > 0
                && input.frame.height >= 44
                && send.frame.width >= 44 && send.frame.height >= 44
                && input.frame.maxX <= send.frame.minX + 1
                && input.frame.minY >= 0 && send.frame.minY >= 0
                && input.frame.maxY <= keyboard.frame.minY + 1
                && send.frame.maxY <= keyboard.frame.minY + 1
        }
        XCTAssertEqual(XCTWaiter.wait(for: [
            XCTNSPredicateExpectation(predicate: clear, object: nil)
        ], timeout: 8), .completed,
        "The editable target and Send must remain separate and above the keyboard.\n" + app.debugDescription)
    }

    func testMultilineDraftGrowthAndRelaunchBothAppearances() {
        verifyMultilineDraft(large: false)
    }

    func testMultilineDraftGrowthAndRelaunchAtLargestTextBothAppearances() {
        verifyMultilineDraft(large: true)
    }

    private func verifyMultilineDraft(large: Bool) {
        for light in [false, true] {
            let variant = (large ? "AX5" : "default") + "-" + (light ? "light" : "dark")
            launch(light: light, large: large, reset: true)
            XCTAssertEqual(input.value as? String, "")
            XCTAssertFalse(send.isEnabled)
            input.tap()
            checkKeyboardAndSendGeometry()
            let emptyHeight = input.frame.height

            // Short explicit lines isolate vertical growth from word wrapping.
            let fourLines = "One.\nTwo.\nThree.\nFour."
            app.typeText(fourLines)
            waitForValue(fourLines)
            let grew = NSPredicate { [self] _, _ in
                input.frame.height >= emptyHeight + 20
            }
            XCTAssertEqual(XCTWaiter.wait(for: [
                XCTNSPredicateExpectation(predicate: grew, object: nil)
            ], timeout: 5), .completed, "A multiline draft must expand beyond its empty target.")
            let fourLineHeight = input.frame.height
            XCTAssertTrue(send.isEnabled)
            checkKeyboardAndSendGeometry()
            capture("fidelity-comment-four-lines-" + variant)

            let continuation = "\nFive.\nSix.\nSeven.\nEight.\nNine.\nTen."
            app.typeText(continuation)
            var expected = fourLines + continuation
            waitForValue(expected)
            XCTAssertEqual(input.frame.height, fourLineHeight, accuracy: 2,
                           "Additional lines must scroll within the four-line editor instead of covering the thread.")
            checkKeyboardAndSendGeometry()

            // Type via the app's current first responder, not a helper that
            // could re-focus the editor. Editing the tail proves that focus
            // and the insertion point survived its internal scrolling.
            app.typeText(" End")
            expected += " End"
            waitForValue(expected)
            app.typeText(XCUIKeyboardKey.delete.rawValue)
            expected.removeLast()
            waitForValue(expected)
            XCTAssertEqual(input.frame.height, fourLineHeight, accuracy: 2)
            capture("fidelity-comment-scrolled-caret-" + variant)

            // The second launch deliberately omits the reset flag. The real
            // per-post draft must restore the entire text, including newlines.
            launch(light: light, large: large, reset: false)
            waitForValue(expected)
            XCTAssertTrue(send.isEnabled)
            capture("fidelity-comment-restored-before-height-check-" + variant)
            // With the keyboard dismissed, the editor may show all four lines;
            // while typing, it has less room and scrolls its text internally.
            // Preserve a bounded composer and an available Send action in both.
            XCTAssertGreaterThanOrEqual(input.frame.height, fourLineHeight)
            XCTAssertLessThan(input.frame.height, app.frame.height / 2)
            XCTAssertTrue(send.isHittable)
            capture("fidelity-comment-restored-draft-" + variant)
            input.tap()
            checkKeyboardAndSendGeometry()
            waitForValue(expected)
            capture("fidelity-comment-restored-keyboard-" + variant)
        }
    }

    func testTypedAndAttachmentMentionsBothAppearances() {
        verifyMentions(large: false)
    }

    func testTypedAndAttachmentMentionsAtLargestTextBothAppearances() {
        verifyMentions(large: true)
    }

    func testMentionQueriesAndMiddleInsertionBothAppearances() {
        for light in [false, true] {
            let theme = light ? "light" : "dark"
            launch(light: light, large: false, reset: true)
            input.tap()
            app.typeText("Fresh basil @Sa")
            waitForValue("Fresh basil @Sa")
            mention("Sam").tap()
            waitForValue("Fresh basil @Sam ")
            app.typeText("and tomatoes")
            waitForValue("Fresh basil @Sam and tomatoes")

            // A real native caret move, not a test-only draft/selection setter.
            // Place the insertion point before the sentence suffix and verify
            // it remains there through the attachment picker round-trip.
            for _ in "and tomatoes" { app.typeKey(.leftArrow, modifierFlags: []) }
            app.buttons["Add attachment or mention"].tap()
            app.buttons["Mention someone"].tap()
            mention("Riley").tap()
            waitForValue("Fresh basil @Sam @Riley and tomatoes")
            app.typeText("with ")
            let expected = "Fresh basil @Sam @Riley with and tomatoes"
            waitForValue(expected)
            checkKeyboardAndSendGeometry()
            capture("fidelity-comment-middle-mention-" + theme)
            launch(light: light, large: false, reset: false)
            waitForValue(expected)
        }
    }

    func testLinkOnlyDraftRestoresVisibleAttachmentBothAppearances() {
        for light in [false, true] {
            let theme = light ? "light" : "dark"
            launch(light: light, large: false, reset: true)
            app.buttons["Add attachment or mention"].tap()
            app.buttons["Add a link"].tap()
            let link = app.textFields["Paste a link"]
            XCTAssertTrue(link.waitForExistence(timeout: 5))
            link.tap()
            link.typeText("https://example.com/menu")
            XCTAssertTrue(send.isEnabled)
            launch(light: light, large: false, reset: false)
            XCTAssertTrue(link.waitForExistence(timeout: 5), "A restored URL must not be hidden behind attachment controls.")
            XCTAssertEqual(link.value as? String, "https://example.com/menu")
            XCTAssertTrue(link.isHittable)
            XCTAssertTrue(app.buttons["Hide attachments"].exists)
            XCTAssertEqual(input.value as? String, "")
            XCTAssertTrue(send.isEnabled, "A visible link-only reply remains valid without invented caption text.")
            capture("fidelity-comment-link-draft-restored-" + theme)
        }
    }

    private func mention(_ name: String) -> XCUIElement {
        // SampleData seeds Nate, Sam and Riley. Alessandra is a comment
        // author in this fixture, not a member of the mention picker.
        let button = app.buttons.containing(.staticText, identifier: name).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        let picker = app.scrollViews.containing(.staticText, identifier: name).firstMatch
        for _ in 0..<4 {
            if button.isHittable && button.frame.minX >= 0
                && button.frame.maxX <= app.frame.maxX { break }
            XCTAssertTrue(picker.exists, "The horizontal mention picker must exist.")
            picker.swipeLeft()
        }
        XCTAssertTrue(button.isHittable)
        XCTAssertGreaterThanOrEqual(button.frame.width, 44)
        XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        return button
    }

    private func verifyMentions(large: Bool) {
        for light in [false, true] {
            let variant = (large ? "AX5" : "default") + "-" + (light ? "light" : "dark")
            launch(light: light, large: large, reset: true)
            XCTAssertEqual(input.value as? String, "")
            input.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            app.typeText("Fresh basil @")
            waitForValue("Fresh basil @")
            let sam = mention("Sam")
            capture("fidelity-comment-typed-mention-picker-" + variant)
            sam.tap()
            waitForValue("Fresh basil @Sam ")
            XCTAssertFalse(app.buttons.containing(.staticText, identifier: "Sam").firstMatch.exists,
                           "Choosing a person dismisses the mention picker.")
            checkKeyboardAndSendGeometry()
            app.typeText("and tomatoes")
            waitForValue("Fresh basil @Sam and tomatoes")

            app.buttons["Add attachment or mention"].tap()
            let openPicker = app.buttons["Mention someone"]
            XCTAssertTrue(openPicker.waitForExistence(timeout: 5))
            openPicker.tap()
            waitForValue("Fresh basil @Sam and tomatoes")
            let riley = mention("Riley")
            capture("fidelity-comment-attachment-mention-picker-" + variant)
            riley.tap()
            waitForValue("Fresh basil @Sam and tomatoes @Riley ")
            checkKeyboardAndSendGeometry()
            app.typeText("too.")
            let expected = "Fresh basil @Sam and tomatoes @Riley too."
            waitForValue(expected)
            XCTAssertTrue(send.isEnabled)
            capture("fidelity-comment-mentions-inserted-" + variant)

            launch(light: light, large: large, reset: false)
            waitForValue(expected)
            XCTAssertTrue(send.isEnabled)
            capture("fidelity-comment-mentions-restored-" + variant)
        }
    }
}
