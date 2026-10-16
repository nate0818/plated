import XCTest

final class WheelProbeTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
        app.launchArguments = ["-plated-design-review"]
        app.launch()
    }
    private func dateID(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "week-date-\(c.year!)-\(c.month!)-\(c.day!)"
    }
    private func waitFor(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { _, _ in condition() }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 12)
        if result != .completed {
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "Wheel verification failure"
            capture.lifetime = .keepAlways
            add(capture)
            print(app.scrollViews["plan-date-wheel"].frame)
            for day in app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'week-date-'")).allElementsBoundByIndex {
                print(day.identifier, day.isSelected, day.frame)
            }
        }
        XCTAssertEqual(result, .completed, file: file, line: line)
    }
    func testRepeatedLaunchAndForegroundStaysCentered() {
        for _ in 0..<3 {
            app.terminate()
            app.launch()
            let wheel = app.scrollViews["plan-date-wheel"]
            XCTAssertTrue(wheel.waitForExistence(timeout: 15))
            let today = app.buttons[dateID(Date())]
            waitFor { today.exists && today.isSelected && abs(today.frame.midX - wheel.frame.midX) < 3 }
        }
        XCUIDevice.shared.press(.home)
        app.activate()
        let today = app.buttons[dateID(Date())]
        let wheel = app.scrollViews["plan-date-wheel"]
        waitFor { today.isSelected && abs(today.frame.midX - wheel.frame.midX) < 3 }
    }

    func testDateWheelTapsFlicksAndToday() {
        let wheel = app.scrollViews["plan-date-wheel"]
        XCTAssertTrue(wheel.waitForExistence(timeout: 15))
        let today = app.buttons[dateID(Date())]
        waitFor { today.exists && today.isSelected }
        XCTAssertLessThan(abs(today.frame.midX - wheel.frame.midX), 3)
        let tomorrowDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let tomorrow = app.buttons[dateID(tomorrowDate)]
        tomorrow.tap()
        waitFor { tomorrow.isSelected && abs(tomorrow.frame.midX - wheel.frame.midX) < 3 }
        wheel.swipeLeft(velocity: .slow)
        let selected = { self.app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'week-date-'")).allElementsBoundByIndex.filter { $0.identifier.hasPrefix("week-date-") && $0.isSelected } }
        waitFor { selected().count == 1 && abs(selected()[0].frame.midX - wheel.frame.midX) < 3 }
        wheel.swipeRight(velocity: .fast)
        app.buttons["Today"].tap()
        waitFor { today.exists && today.isSelected && abs(today.frame.midX - wheel.frame.midX) < 3 }
        XCTAssertEqual(selected().count, 1)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Date wheel after taps, flicks and Today"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
