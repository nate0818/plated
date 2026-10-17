import XCTest

final class ReleaseWidgetTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    var existingPlatedWidgets = 0
    override func setUp() { continueAfterFailure = false }
    func capture(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
        let t = XCTAttachment(string: home.debugDescription); t.name = name + "-tree"; t.lifetime = .keepAlways; add(t)
    }
    func testGalleryInstallAndOpen() {
        openGallery()
        for page in 1...13 {
            let indicator = home.pageIndicators.matching(NSPredicate(format: "value == %@", "page \(page) of 13")).firstMatch
            XCTAssertTrue(indicator.waitForExistence(timeout: 5))
            capture(String(format: "widget-family-%02d", page))
            if page < 13 { swipeGallery(left: true) }
        }
        for _ in 0..<6 { swipeGallery(left: false) }
        XCTAssertTrue(home.pageIndicators.matching(NSPredicate(format: "value == 'page 7 of 13'")).firstMatch.waitForExistence(timeout: 5))
        home.buttons[" Add Widget"].tap()
        XCUIDevice.shared.press(.home)
        capture("widget-cookbook-installed")
        let widget = home.icons.matching(NSPredicate(format: "identifier == 'Plated' AND value == 'Widget'")).firstMatch
        XCTAssertTrue(widget.waitForExistence(timeout: 10))
        widget.tap()
        XCTAssertTrue(app.buttons["Start cooking"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Pancake Dinner"].firstMatch.exists)
        let opened = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        opened.name = "widget-cookbook-opened-recipe"; opened.lifetime = .keepAlways; add(opened)
    }
    func testEmptyGroceryGallery() {
        openGallery(extra: ["-plated-review-onboarding"])
        for _ in 0..<8 { swipeGallery(left: true) }
        for page in 9...11 {
            // Gallery previews sometimes omit their hosted text from the AX
            // tree. Check the family position, then inspect the actual pixels.
            XCTAssertTrue(home.pageIndicators.matching(NSPredicate(format: "value == %@", "page \(page) of 13")).firstMatch.waitForExistence(timeout: 5))
            capture("widget-empty-grocery-\(page)")
            if page < 11 { swipeGallery(left: true) }
        }
        XCUIDevice.shared.press(.home)
    }
    func testTableAndGroceryWidgetTapThrough() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Use the isolated simulator for repeated widget installations")
        #else
        // Exit any system editor left by a previous gallery check before
        // inspecting Home Screen widgets on this dedicated simulator.
        app.launchArguments = ["-plated-design-review", "-plated-review-widgets", "-plated-tab", "week"]
        app.launch()
        XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 20))
        XCUIDevice.shared.press(.home)
        let leftover = home.icons.matching(NSPredicate(format: "identifier == 'Plated' AND value == 'Widget'")).firstMatch
        if leftover.waitForExistence(timeout: 5) {
            home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.81)).press(forDuration: 1.5)
            leftover.buttons["DeleteButton"].tap()
            home.alerts.buttons["Remove"].tap()
            XCTAssertTrue(leftover.waitForNonExistence(timeout: 5))
            XCUIDevice.shared.press(.home)
        }
        for (page, name) in [(4, "table"), (9, "grocery")] {
            openGallery()
            XCTAssertEqual(existingPlatedWidgets, 0)
            for _ in 1..<page { swipeGallery(left: true) }
            XCTAssertTrue(home.pageIndicators.matching(NSPredicate(format: "value == %@", "page \(page) of 13")).firstMatch.waitForExistence(timeout: 5))
            home.buttons[" Add Widget"].tap()
            XCUIDevice.shared.press(.home)
            let widget = home.icons.matching(NSPredicate(format: "identifier == 'Plated' AND value == 'Widget'")).firstMatch
            XCTAssertTrue(widget.waitForExistence(timeout: 10)); widget.tap()
            if name == "table" {
                XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 15))
                XCTAssertTrue(app.staticTexts["Pancake Dinner"].firstMatch.exists)
                XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'COMMENTS' ")).firstMatch.exists)
            } else {
                XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Asparagus,'")).firstMatch.waitForExistence(timeout: 15))
                XCTAssertTrue(app.buttons["tray-groceries"].isSelected)
            }
            let opened = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            opened.name = "widget-\(name)-opened-destination"; opened.lifetime = .keepAlways; add(opened)
            XCUIDevice.shared.press(.home)
            home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.81)).press(forDuration: 1.5)
            let remove = widget.buttons["DeleteButton"]
            XCTAssertTrue(remove.waitForExistence(timeout: 5)); remove.tap()
            let confirm = home.alerts.buttons["Remove"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
            XCTAssertTrue(widget.waitForNonExistence(timeout: 5))
            XCUIDevice.shared.press(.home)
        }
        #endif
    }
    func testPhysicalWidgetGallery() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical-device widget gallery check")
        #else
        openGallery()
        for page in 1...13 {
            XCTAssertTrue(home.pageIndicators.matching(NSPredicate(format: "value == %@", "page \(page) of 13")).firstMatch.waitForExistence(timeout: 5))
            capture(String(format: "device-widget-family-%02d", page))
            if page < 13 { swipeGallery(left: true) }
        }
        XCUIDevice.shared.press(.home)
        #endif
    }
    func testPhysicalWidgetInstallAndOpen() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical-device installed Tonight widget check")
        #else
        openGallery()
        guard existingPlatedWidgets == 0 else {
            XCUIDevice.shared.press(.home)
            throw XCTSkip("Preserve existing personal Plated widgets; installation needs an unambiguous test widget")
        }
        home.buttons[" Add Widget"].tap()
        XCUIDevice.shared.press(.home)
        let widget = home.icons.matching(NSPredicate(format: "identifier == 'Plated' AND value == 'Widget'")).firstMatch
        XCTAssertTrue(widget.waitForExistence(timeout: 10))
        capture("device-tonight-widget-installed")
        widget.tap()
        XCTAssertTrue(app.buttons["featured-dinner-card"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Start cooking"].firstMatch.exists)
        let opened = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        opened.name = "device-tonight-widget-opened-plan"; opened.lifetime = .keepAlways; add(opened)
        XCUIDevice.shared.press(.home)
        home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.81)).press(forDuration: 1.5)
        capture("device-tonight-widget-removal")
        let remove = widget.buttons["DeleteButton"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        let reachable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: remove)
        XCTAssertEqual(XCTWaiter.wait(for: [reachable], timeout: 30), .completed)
        remove.tap()
        let confirm = home.alerts.buttons["Remove"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(widget.waitForNonExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        #endif
    }
    func testLockScreenGalleryProbe() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Lock Screen discovery uses only the isolated simulator")
        #else
        app.launchArguments = ["-plated-design-review", "-plated-review-widgets", "-plated-tab", "week"]
        app.launch()
        XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 20))
        XCUIDevice.shared.press(.home)
        home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
            .press(forDuration: 0.05, thenDragTo: home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65)))
        capture("lock-screen-before-customization")
        home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.5)
        capture("lock-screen-customization")
        XCTAssertTrue(home.buttons["posterboard-customize-button"].waitForExistence(timeout: 5))
        home.buttons["posterboard-customize-button"].tap()
        capture("lock-screen-choice")
        let editor = XCUIApplication(bundleIdentifier: "com.apple.PosterBoard")
        let widgets = editor.buttons["grouped-widgets-reticle-view"]
        XCTAssertTrue(widgets.waitForExistence(timeout: 10)); widgets.tap()
        editor.swipeUp()
        capture("lock-screen-providers")
        let plated = editor.cells["Plated"]
        XCTAssertTrue(plated.waitForExistence(timeout: 10)); plated.tap()
        for page in 1...3 {
            XCTAssertTrue(editor.pageIndicators.matching(NSPredicate(format: "value == %@", "page \(page) of 3")).firstMatch.waitForExistence(timeout: 10))
            capture("lock-screen-family-pair-\(page)")
            if page < 3 {
                editor.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.66))
                    .press(forDuration: 0.05, thenDragTo: editor.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.66)))
            }
        }
        editor.buttons["close"].tap()
        XCTAssertTrue(editor.buttons["close"].waitForNonExistence(timeout: 5))
        let inline = editor.buttons["inline-widget-reticle-view"]
        XCTAssertTrue(inline.waitForExistence(timeout: 10))
        inline.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let tonight = editor.descendants(matching: .any).matching(identifier: "Plated, Tonight (Lock Screen), Top Widget").firstMatch
        if !tonight.waitForExistence(timeout: 3) {
            inline.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(tonight.waitForExistence(timeout: 10))
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
            .press(forDuration: 0.05, thenDragTo: editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
        for name in ["Tonight", "Grocery", "Whose Turn"] {
            XCTAssertTrue(editor.descendants(matching: .any).matching(identifier: "Plated, \(name) (Lock Screen), Top Widget").firstMatch.waitForExistence(timeout: 10))
        }
        capture("lock-screen-inline-three")
        print("LOCK SCREEN TREE: " + editor.debugDescription)
        #endif
    }
    func testRemoveReleaseWidget() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Cleanup of the test widget added on the authorized phone")
        #else
        guard ProcessInfo.processInfo.environment["PLATED_REMOVE_RELEASE_WIDGET"] == "1" else {
            throw XCTSkip("One-off recovery only after this session installed a temporary widget")
        }
        XCUIDevice.shared.press(.home)
        let widget = home.icons.matching(NSPredicate(format: "identifier == 'Plated' AND value == 'Widget'")).firstMatch
        XCTAssertTrue(widget.waitForExistence(timeout: 10))
        home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.81)).press(forDuration: 1.5)
        capture("device-release-widget-cleanup-edit")
        let remove = widget.buttons["DeleteButton"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        let reachable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: remove)
        XCTAssertEqual(XCTWaiter.wait(for: [reachable], timeout: 30), .completed)
        remove.tap()
        let confirm = home.alerts.buttons["Remove"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(widget.waitForNonExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        #endif
    }
    func openGallery(extra: [String] = []) {
        app.launchArguments = ["-plated-design-review", "-plated-review-widgets", "-plated-tab", "week"] + extra
        app.launch(); XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 20))
        XCUIDevice.shared.press(.home)
        existingPlatedWidgets = home.icons.matching(NSPredicate(format: "identifier == 'Plated' AND value == 'Widget'")).count
        capture("widget-home-before")
        home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.81)).press(forDuration: 1.5)
        capture("widget-home-edit")
        home.buttons["Edit"].tap()
        capture("widget-edit-menu")
        home.buttons["Add Widget"].tap()
        capture("widget-gallery")
        let search = home.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("Plated")
        capture("widget-gallery-search")
        print("WIDGET GALLERY: Plated cell navigation v2")
        let plated = home.cells.matching(identifier: "Plated").firstMatch
        XCTAssertTrue(plated.waitForExistence(timeout: 10)); plated.tap()
        capture("widget-plated-gallery")
    }
    func swipeGallery(left: Bool) {
        #if !targetEnvironment(simulator)
        // SpringBoard on the phone can interpret the timed drag as a widget
        // pickup. Its native swipe scrolls the family carousel instead.
        if left { home.swipeLeft(velocity: .slow) }
        else { home.swipeRight(velocity: .slow) }
        #else
        let from = home.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.85 : 0.15, dy: 0.58))
        let to = home.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.15 : 0.85, dy: 0.58))
        from.press(forDuration: 0.05, thenDragTo: to)
        #endif
    }
}
