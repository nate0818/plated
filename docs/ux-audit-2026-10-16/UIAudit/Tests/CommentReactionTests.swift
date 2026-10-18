import XCTest

final class CommentReactionTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    override func setUp() { continueAfterFailure = false }
    var parent: XCUIElement { app.buttons["comment-like-note-review-parent"] }
    var reply: XCUIElement { app.buttons["comment-like-note-review-reply"] }
    func launch(thread: Bool = true, light: Bool = false, large: Bool = false, flags: [String] = []) {
        app.terminate()
        app.launchArguments = ["-plated-design-review", "-plated-review-comment-reactions",
            "-plated-tab", "table", "-appearance", light ? "light" : "dark",
            "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
            + (thread ? ["-plated-open-thread"] : []) + flags
        app.launch()
        XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 20))
    }
    func reveal(_ element: XCUIElement) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            let thread = app.scrollViews["table-post-thread"]
            (thread.exists ? thread : app.scrollViews.firstMatch).swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
    func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    func testCookbookSaveLivesInPostOptionsAndOpensRecipeDraft() {
        launch(flags: ["-plated-review-recipe-post"])
        let options = app.buttons["table-thread-options"]
        XCTAssertTrue(options.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Save"].exists)
        XCTAssertFalse(app.buttons["Save to cookbook"].exists)
        capture("recipe-thread-header")
        options.tap()
        let save = app.buttons["Save to cookbook"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        capture("recipe-thread-options")
        save.tap()
        let title = app.textFields["Name the dish"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertEqual(title.value as? String, "A market find")
        XCTAssertTrue(app.staticTexts["Save to your cookbook"].exists)
        capture("recipe-thread-save-draft")
        app.buttons["Cancel"].tap()
        if app.buttons["Discard"].waitForExistence(timeout: 2) { app.buttons["Discard"].tap() }
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        app.buttons["Back"].tap()
        let feedSave = app.buttons["Save to cookbook"].firstMatch
        XCTAssertTrue(feedSave.waitForExistence(timeout: 5))
        reveal(feedSave)
        capture("recipe-feed-save-label")
    }

    func testGeneralAndAlreadySavedPostsHaveNoCookbookSaveAction() {
        for flags in [[], ["-plated-review-recipe-post", "-plated-review-recipe-saved"]] {
            launch(flags: flags)
            let options = app.buttons["table-thread-options"]
            XCTAssertTrue(options.waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["Save"].exists)
            XCTAssertFalse(app.staticTexts["Saved"].exists)
            options.tap()
            XCTAssertTrue(app.buttons["Report post"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Save to cookbook"].exists)
        }
    }

    func testThreadLikeUnlikeReplyAndDeletedComment() {
        launch()
        reveal(parent)
        let hiddenPlan = app.scrollViews["plan-selected-day-content"]
        XCTAssertEqual(hiddenPlan.buttons.count, 0, "inactive Plan actions must not be exposed")
        XCTAssertEqual(hiddenPlan.staticTexts.count, 0, "inactive Plan text must not be exposed")
        XCTAssertTrue(app.staticTexts["COMMENTS · 2"].exists)
        XCTAssertEqual(parent.value as? String, "2 likes")
        XCTAssertGreaterThanOrEqual(parent.frame.width, 44)
        XCTAssertGreaterThanOrEqual(parent.frame.height, 44)
        parent.tap()
        XCTAssertEqual(parent.value as? String, "3 likes")
        XCTAssertEqual(parent.label, "Unlike Alessandra Schembari's comment")
        XCTAssertTrue(parent.isSelected)
        capture("comment-liked-dark")
        parent.tap()
        XCTAssertEqual(parent.value as? String, "2 likes")
        XCTAssertFalse(parent.isSelected)
        reveal(reply)
        XCTAssertEqual(reply.value as? String, "0 likes")
        reply.tap()
        XCTAssertEqual(reply.value as? String, "1 like")
        XCTAssertEqual(parent.value as? String, "2 likes")
        XCTAssertFalse(app.buttons["comment-like-note-review-deleted"].exists)
        capture("reply-liked-dark")
        app.buttons["Hide replies"].tap()
        XCTAssertFalse(reply.exists)
        app.buttons["Show 1 reply"].tap()
        XCTAssertTrue(reply.exists)
        XCTAssertEqual(reply.value as? String, "1 like")
    }
    func testFeedPreviewsLikeWithoutOpeningThread() {
        launch(thread: false, light: true)
        reveal(parent)
        parent.tap()
        XCTAssertEqual(parent.value as? String, "3 likes")
        XCTAssertTrue(app.buttons["tray-table"].exists)
        capture("comment-liked-feed-light")
    }
    func testLargestTextCommentAndReplyRemainOperable() {
        launch(light: true, large: true)
        reveal(parent)
        parent.tap()
        XCTAssertEqual(parent.value as? String, "3 likes")
        capture("comment-liked-ax5-light")
        reveal(reply)
        reply.tap()
        XCTAssertEqual(reply.value as? String, "1 like")
        capture("reply-liked-ax5-light")
    }
    /// Evidence capture, not a passing accessibility gate. Review the report
    /// alongside its screenshot; device VoiceOver remains a separate check.
    func testCaptureCommentAccessibilityAudit() throws {
        launch()
        reveal(parent)
        capture("comment-before-accessibility-audit")
        var issues: [String] = []
        let viewport = app.scrollViews["table-post-thread"].frame
        XCTAssertGreaterThan(viewport.height, 200)
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped]) { issue in
            issues.append(issue.compactDescription + "\n" + issue.detailedDescription + "\n" + (issue.element?.debugDescription ?? "No attributed element"))
            return true
        }
        let report = XCTAttachment(string: "Thread viewport: \(viewport)\n\n"
            + (issues.isEmpty ? "No issues returned." : issues.joined(separator: "\n\n")))
        report.name = "comment-accessibility"; report.lifetime = .keepAlways; add(report)
    }

    func testPlanAccessibilityReturnsWhenItsTabIsSelected() {
        launch(thread: false)
        reveal(parent)
        let plan = app.scrollViews["plan-selected-day-content"]
        XCTAssertEqual(plan.staticTexts.count, 0)
        app.buttons["tray-week"].tap()
        XCTAssertTrue(plan.staticTexts["Hi, Nate"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(plan.buttons.count, 0)
        app.buttons["tray-table"].tap()
        XCTAssertTrue(plan.staticTexts["Hi, Nate"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(plan.buttons.count, 0)
        XCTAssertTrue(parent.exists)
    }

}
