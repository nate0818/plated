import XCTest

/// Local presentation fixtures only. No contact picker, real message, CloudKit
/// invitation, or remote acceptance is performed by these checks.
final class FidelityInviterReceiptTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    override func setUp() { continueAfterFailure = false }

    private func launch(_ state: String, light: Bool, accessibility: Bool = false) {
        app.terminate()
        app.launchArguments = ["-plated-design-review", "-householdName", "Meadows", "-userFirstName", "Nate",
            "-appearance", light ? "light" : "dark", "-UIPreferredContentSizeCategoryName",
            accessibility ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL",
            "-plated-open-household", "-plated-review-inviter-" + state]
        app.launch()
    }

    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }

    func testSentInvitationReceiptBothAppearancesAndSizes() {
        for light in [false, true] {
            for accessibility in [false, true] {
                launch("sent", light: light, accessibility: accessibility)
                XCTAssertTrue(app.staticTexts["Invitation sent"].waitForExistence(timeout: 20))
                XCTAssertTrue(app.staticTexts["Waiting for Alessandra to join Meadows."].exists)
                XCTAssertTrue(app.staticTexts["Pending · New invitation"].exists)
                XCTAssertFalse(app.staticTexts["Invitation accepted"].exists)
                let done = app.buttons["household-invitation-done"]
                let close = app.buttons["Close invitation"]
                let settledTarget = NSPredicate { _, _ in close.frame.height >= 44 }
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settledTarget, object: nil)], timeout: 5),
                               .completed, "The close target must reach 44 points after sheet presentation settles")
                capture("fidelity-household-inviter-sent-" + (light ? "light" : "dark") + (accessibility ? "-AX5" : ""))
                for _ in 0..<6 where !done.isHittable {
                    let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable })
                    XCTAssertNotNil(scroll)
                    scroll?.swipeUp()
                }
                XCTAssertTrue(done.isHittable)
                XCTAssertGreaterThanOrEqual(done.frame.height, 44)
                done.tap()
                XCTAssertTrue(app.staticTexts["Invitation sent"].waitForNonExistence(timeout: 8))
                XCTAssertTrue(app.buttons["household-settings"].isHittable)
                XCTAssertFalse(app.buttons["household-invitation-done"].exists)
            }
        }
    }

    func testResentAndJoinedReceiptsDoNotMisstateMembership() {
        for state in ["resent", "joined", "ended"] {
            launch(state, light: false)
            let title = state == "joined" ? "Invitation accepted" : state == "ended" ? "Access ended" : "Invitation sent"
            let heading = app.staticTexts["household-invitation-title"]
            XCTAssertTrue(heading.waitForExistence(timeout: 20))
            XCTAssertEqual(heading.label, title)
            if state == "ended" {
                XCTAssertTrue(app.staticTexts["Alessandra is no longer in Meadows."].exists)
                XCTAssertFalse(app.staticTexts["Invitation sent"].exists)
                XCTAssertFalse(app.staticTexts["Invitation accepted"].exists)
                XCTAssertFalse(app.staticTexts["Waiting for Alessandra to join Meadows."].exists)
                XCTAssertFalse(app.staticTexts["Pending · New invitation"].exists)
            } else if state == "joined" {
                XCTAssertTrue(app.staticTexts["Alessandra joined Meadows."].exists)
                XCTAssertFalse(app.staticTexts["Waiting for Alessandra to join Meadows."].exists)
                XCTAssertFalse(app.staticTexts["Pending · New invitation"].exists)
            } else {
                XCTAssertTrue(app.staticTexts["Pending · Invitation resent"].exists)
                XCTAssertFalse(app.staticTexts["Pending · New invitation"].exists)
            }
            capture("fidelity-household-inviter-" + state + "-dark")
            app.buttons["Close invitation"].tap()
            XCTAssertTrue(heading.waitForNonExistence(timeout: 8))
            XCTAssertTrue(app.buttons["household-settings"].isHittable)
        }
    }

    func testMissingMembershipDoesNotClaimWaitingJoinedOrRemoved() {
        for light in [false, true] {
            launch("unavailable", light: light)
            XCTAssertTrue(app.staticTexts["Invitation status unavailable"].waitForExistence(timeout: 20))
            XCTAssertTrue(app.staticTexts["Membership not confirmed"].exists)
            for invalid in ["Invitation sent", "Invitation accepted", "Access ended", "Pending · New invitation",
                            "Waiting for Alessandra to join Meadows."] {
                XCTAssertFalse(app.staticTexts[invalid].exists)
            }
            capture("fidelity-household-inviter-unavailable-" + (light ? "light" : "dark"))
            app.buttons["Close invitation"].tap()
            XCTAssertTrue(app.buttons["household-settings"].isHittable)
        }
    }

    func testCancelledAndFailedMessagesDoNotShowAnInvitationReceipt() {
        for state in ["cancelled", "failed"] {
            launch(state, light: false)
            XCTAssertTrue(app.buttons["household-settings"].waitForExistence(timeout: 20))
            XCTAssertFalse(app.staticTexts["Invitation sent"].exists)
            XCTAssertFalse(app.buttons["household-invitation-done"].exists)
            XCTAssertFalse(app.staticTexts["Pending · New invitation"].exists)
        }
    }
}
