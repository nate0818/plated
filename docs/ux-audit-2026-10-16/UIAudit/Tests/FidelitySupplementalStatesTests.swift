import XCTest
import UIKit

/// Additional exact approval variants reachable through existing native paths.
/// Source-only until executed; screenshots do not establish live delivery.
final class FidelitySupplementalStatesTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    override func setUp() { continueAfterFailure = false }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func launch(_ flags: [String], light: Bool, ax: Bool = false) {
        app.terminate()
        // Start in the supported physical orientation for each device. On a
        // portrait-held landscape-only iPad, swipeUp runs across the app scene.
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad
            ? .landscapeLeft : .portrait
        app.launchArguments = ["-plated-design-review", "-householdName", "Meadows", "-userFirstName", "Nate",
            "-appearance", light ? "light" : "dark", "-UIPreferredContentSizeCategoryName",
            ax ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"] + flags
        app.launch()
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    private func reveal(_ item: XCUIElement, scroll: XCUIElement? = nil) {
        guard let viewport = scroll ?? app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            XCTFail("No active scroll view: " + app.debugDescription); return
        }
        for _ in 0..<12 {
            let tab = app.buttons["tray-week"]
            let bottom = tab.exists ? tab.frame.minY : app.frame.maxY
            if item.isHittable && item.frame.maxY < bottom - 4 { return }
            viewport.swipeUp()
        }
        XCTAssertTrue(item.isHittable, app.debugDescription)
    }
    private func waitFor(_ predicate: NSPredicate, item: XCUIElement, timeout: TimeInterval = 8) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: item)], timeout: timeout), .completed, app.debugDescription)
    }

    func testReplyingToTheParentBothAppearances() {
        for light in [false, true] {
            launch(["-plated-tab", "table", "-plated-review-comment-reactions", "-plated-open-thread"], light: light)
            let thread = app.scrollViews["table-post-thread"]
            XCTAssertTrue(thread.waitForExistence(timeout: 20))
            let parent = app.buttons["comment-like-note-review-parent"]
            reveal(parent, scroll: thread)
            // In this fixture the deleted row has no Reply action, followed
            // by Alessandra's parent, then Nate's reply. The exact target
            // banner below verifies that first Reply selected the parent.
            let reply = app.buttons["Reply"].firstMatch
            reveal(reply, scroll: thread); reply.tap()
            let target = app.staticTexts["Replying to Alessandra Schembari"]
            XCTAssertTrue(target.waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["Cancel reply"].isHittable)
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(app.textViews["post-comment-input"].exists)
            capture("fidelity-comments-replying-" + (light ? "light" : "dark"))
            app.buttons["Cancel reply"].tap()
            XCTAssertTrue(target.waitForNonExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Cancel reply"].exists)
        }
    }

    func testPendingReplyBothAppearances() {
        for light in [false, true] {
            launch(["-plated-tab", "table", "-plated-review-comment-reactions", "-plated-open-thread",
                    "-plated-review-comment-pending", "-plated-review-comment-reset"], light: light)
            let thread = app.scrollViews["table-post-thread"]
            XCTAssertTrue(thread.waitForExistence(timeout: 20))
            let sending = app.staticTexts["Sending…"]
            reveal(sending, scroll: thread)
            XCTAssertTrue(sending.isHittable)
            XCTAssertTrue(app.buttons["comment-like-note-review-reply"].exists)
            XCTAssertEqual(app.textViews["post-comment-input"].value as? String, "")
            capture("fidelity-comments-sending-" + (light ? "light" : "dark"))
        }
    }

    func testSavedTextComposerBothAppearances() {
        for light in [false, true] {
            launch(["-plated-open-table-post", "-plated-review-post-reset"], light: light)
            let field = element("table-post-text")
            XCTAssertTrue(field.waitForExistence(timeout: 20))
            field.tap(); field.typeText("A little place worth coming back to.")
            let done = app.buttons["Done"].firstMatch
            XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
            let status = element("table-post-draft-status")
            XCTAssertTrue(status.waitForExistence(timeout: 8))
            waitFor(NSPredicate(format: "label == %@", "Draft saved"), item: status)
            XCTAssertEqual(field.value as? String, "A little place worth coming back to.")
            XCTAssertTrue(app.buttons["table-post-submit"].isEnabled)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            capture("fidelity-composer-saved-" + (light ? "light" : "dark"))
            app.buttons["Close post"].tap()
            XCTAssertTrue(app.buttons["Discard post"].waitForExistence(timeout: 5))
            app.buttons["Discard post"].tap()
        }
    }

    func testAttachedPhotoComposerBothAppearances() {
        for light in [false, true] {
            launch(["-plated-open-table-post", "-plated-review-post-reset", "-plated-review-post-photo"], light: light)
            let remove = app.buttons["Remove photo"]
            XCTAssertTrue(remove.waitForExistence(timeout: 20))
            XCTAssertTrue(remove.isHittable, "Capture the attached photo viewport, not the tagging panel")
            XCTAssertTrue(app.buttons["table-post-submit"].isEnabled)
            capture("fidelity-composer-photo-" + (light ? "light" : "dark"))
            remove.tap()
            XCTAssertTrue(remove.waitForNonExistence(timeout: 5))
            XCTAssertFalse(app.buttons["table-post-submit"].isEnabled, "An empty draft after photo removal cannot post")
        }
    }
    func testAttachedPhotoComposerRemainsUsableInPhoneLandscape() {
        launch(["-plated-open-table-post", "-plated-review-post-reset", "-plated-review-post-photo"], light: false)
        XCUIDevice.shared.orientation = .landscapeLeft
        let remove = app.buttons["Remove photo"]
        XCTAssertTrue(remove.waitForExistence(timeout: 20))
        let scroll = app.scrollViews["table-post-scroll"]
        for _ in 0..<12 {
            if remove.isHittable { break }
            scroll.swipeUp()
        }
        // In a short landscape viewport, the control may pass above the top
        // while the attachment tools enter from below. Check both directions.
        for _ in 0..<12 {
            if remove.isHittable { break }
            scroll.swipeDown()
        }
        XCTAssertTrue(remove.isHittable, "The attached photo must be removable in landscape")
        XCTAssertTrue(app.buttons["table-post-submit"].isEnabled)
        capture("fidelity-composer-photo-phone-landscape")
        remove.tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["table-post-submit"].isEnabled)
    }
    func testAttachedPhotoControlsAtLargestText() {
        launch(["-plated-open-table-post", "-plated-review-post-reset", "-plated-review-post-photo"],
               light: true, ax: true)
        let scroll = app.scrollViews["table-post-scroll"]
        let remove = app.buttons["Remove photo"]
        let change = app.buttons["Change photo"]
        XCTAssertTrue(remove.waitForExistence(timeout: 20))
        for _ in 0..<12 {
            if remove.isHittable && change.isHittable { break }
            scroll.swipeUp()
        }
        capture("fidelity-composer-photo-accessibility-reachability")
        XCTAssertTrue(remove.isHittable && change.isHittable,
                      "Both photo actions must remain reachable at the largest text size")
        XCTAssertGreaterThanOrEqual(remove.frame.height, 44)
        XCTAssertGreaterThanOrEqual(change.frame.height, 44)
        XCTAssertGreaterThanOrEqual(change.frame.width, scroll.frame.width * 0.75,
                                    "Photo action labels need full-row space at accessibility sizes")
        XCTAssertGreaterThanOrEqual(remove.frame.width, scroll.frame.width * 0.75,
                                    "Photo action labels need full-row space at accessibility sizes")
        XCTAssertLessThanOrEqual(change.frame.maxY, remove.frame.minY,
                                 "Photo actions should stack instead of splitting words at large text sizes")
        capture("fidelity-composer-photo-compact-ax5")
        remove.tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["table-post-submit"].isEnabled)
    }

    func testDarkRotationPickerCancelsWithoutSaving() {
        launch(["-plated-open-household"], light: false)
        XCTAssertTrue(app.buttons["household-settings"].waitForExistence(timeout: 20))
        let weekday = Calendar.current.firstWeekday
        let name = Calendar.current.weekdaySymbols[weekday - 1]
        let cell = app.buttons["household-rotation-\(weekday)"]
        reveal(cell); let original = cell.label; cell.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Save cook"].exists)
        XCTAssertTrue(app.staticTexts["Choose a cook. Changes apply after saving."].exists)
        XCTAssertTrue(app.buttons["Cancel"].exists)
        capture("fidelity-household-assign-dark")
        app.buttons["Unassigned"].tap(); app.buttons["Cancel"].tap()
        XCTAssertEqual(cell.label, original, "Cancel must keep the saved rotation")
    }

    func testTonightRecipeDetailThroughPlannedDayBothAppearances() {
        for light in [false, true] {
            launch([], light: light)
            let meal = app.buttons["featured-dinner-card"]
            XCTAssertTrue(meal.waitForExistence(timeout: 20))
            XCTAssertEqual(meal.label, "Salmon Night")
            meal.tap()
            let dinner = element("day-meal-dinner")
            XCTAssertTrue(dinner.waitForExistence(timeout: 8))
            reveal(dinner); dinner.tap()
            XCTAssertTrue(app.staticTexts["Lemon Butter Salmon"].waitForExistence(timeout: 8))
            let start = app.buttons["Start cooking"]
            XCTAssertTrue(start.waitForExistence(timeout: 8))
            XCTAssertTrue(start.isHittable)
            XCTAssertFalse(element("recipe-plan").exists, "Tonight detail must carry its actual PlannedMeal")
            XCTAssertFalse(app.buttons["Minimize cooking"].exists, "This is recipe detail, not an active session")
            capture("fidelity-recipe-detail-tonight-" + (light ? "light" : "dark"))
            app.buttons["Back"].firstMatch.tap()
            XCTAssertTrue(dinner.waitForExistence(timeout: 8))
        }
    }

    func testRecordedContextBothAppearances() {
        for light in [false, true] {
            let theme = light ? "light" : "dark"
            launch(["-plated-fake-weather", "-plated-review-household-activity", "-plated-review-dinner-history"], light: light)
            XCTAssertTrue(app.buttons["Start cooking"].waitForExistence(timeout: 20))
            let scroll = app.scrollViews["plan-selected-day-content"]
            let weather = element("plan-weather-conditions")
            reveal(weather, scroll: scroll)
            capture("fidelity-context-recorded-weather-\(theme)")
            let cooked = element("plan-history-cooked")
            reveal(cooked, scroll: scroll)
            XCTAssertEqual(cooked.label, "2 cooked at home in the last 7 days")
            XCTAssertEqual(element("plan-history-eating-out").label, "1 ate out in the last 7 days")
            XCTAssertTrue(app.staticTexts["Based on 3 recorded dinners."].exists)
            capture("fidelity-context-recorded-history-\(theme)")
            reveal(app.buttons["plan-next-day"], scroll: scroll)
            XCTAssertTrue(app.staticTexts["At home"].exists)
            XCTAssertTrue(app.buttons["plan-next-day"].label.contains("Pizza Night"))
            let summary = element("plan-context-summary")
            let card = element("featured-dinner-card")
            let dates = element("plan-date-wheel")
            if summary.exists {
                XCTAssertTrue(summary.label.contains("Salmon Night"))
            } else {
                XCTAssertGreaterThan(card.frame.maxY, dates.frame.maxY,
                                     "Do not duplicate the dinner while its card remains below the pinned dates")
            }
            capture("fidelity-context-recorded-household-\(theme)")
        }
    }
}
