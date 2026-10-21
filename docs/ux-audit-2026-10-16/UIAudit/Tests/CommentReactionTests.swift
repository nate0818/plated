import XCTest

final class CommentReactionTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    override func setUp() { continueAfterFailure = false }
    var parent: XCUIElement { app.buttons["comment-like-note-review-parent"] }
    var reply: XCUIElement { app.buttons["comment-like-note-review-reply"] }
    var fixtureComments: XCUIElement { app.buttons["table-comments-post-review-comment-reactions"] }
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
            let feed = app.scrollViews["table-feed"]
            if thread.exists && thread.isHittable { thread.swipeUp() }
            else if feed.exists && feed.isHittable { feed.swipeUp() }
            else { XCTFail("Neither the visible Table feed nor thread is available"); return }
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
        XCTAssertTrue(app.staticTexts["Comments 2"].exists)
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
        XCTAssertFalse(app.buttons["Hide replies"].exists, "A single reply stays visible without an unnecessary collapse row")
        XCTAssertTrue(reply.exists)
        XCTAssertEqual(reply.value as? String, "1 like")
    }
    func testCompactFeedOpensCommentsAndPreservesReactionState() {
        // The approved feed uses View comments instead of repeating two
        // interactive comments. Verify that route and the real thread action.
        launch(thread: false, light: true)
        let comments = fixtureComments
        reveal(comments)
        XCTAssertEqual(comments.label, "View 2 comments", "Exactly the fixture's two live comments must be counted")
        XCTAssertFalse(parent.exists)
        comments.tap()
        XCTAssertTrue(app.staticTexts["A market find"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Comments 2"].exists)
        XCTAssertTrue(parent.waitForExistence(timeout: 8))
        reveal(parent); parent.tap()
        XCTAssertEqual(parent.value as? String, "3 likes")
        XCTAssertTrue(parent.isSelected)
        capture("comment-liked-from-compact-feed-light")
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
        reveal(fixtureComments)
        XCTAssertEqual(fixtureComments.label, "View 2 comments")
        let plan = app.scrollViews["plan-selected-day-content"]
        XCTAssertEqual(plan.staticTexts.count, 0)
        app.buttons["tray-week"].tap()
        XCTAssertTrue(plan.buttons["featured-dinner-card"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(plan.buttons.count, 0)
        app.buttons["tray-table"].tap()
        XCTAssertTrue(plan.buttons["featured-dinner-card"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(plan.buttons.count, 0)
        reveal(fixtureComments)
        XCTAssertEqual(fixtureComments.label, "View 2 comments")
        fixtureComments.tap()
        XCTAssertTrue(app.staticTexts["A market find"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Comments 2"].exists)
        reveal(parent)
        XCTAssertEqual(parent.value as? String, "2 likes")
    }

    func testLongReplyBranchDisclosurePreservesReactions() {
        verifyLongBranch(large: false)
    }

    func testLongReplyBranchDisclosureAtLargestText() {
        verifyLongBranch(large: true)
    }

    private func verifyLongBranch(large: Bool) {
        launch(light: large, large: large, flags: ["-plated-review-long-replies"])
        let disclosure = app.buttons["table-replies-note-review-parent"]
        reveal(disclosure)
        XCTAssertTrue(app.staticTexts["Comments 5"].exists)
        XCTAssertEqual(disclosure.label, "View 4 replies")
        XCTAssertEqual(disclosure.value as? String, "Collapsed")
        XCTAssertFalse(reply.exists)
        XCTAssertGreaterThanOrEqual(disclosure.frame.height, 44)
        capture("long-replies-collapsed-" + (large ? "AX5" : "default"))
        disclosure.tap()
        XCTAssertEqual(disclosure.label, "Hide replies")
        XCTAssertEqual(disclosure.value as? String, "Expanded")
        reveal(reply); reply.tap()
        XCTAssertEqual(reply.value as? String, "1 like")
        XCTAssertEqual(parent.value as? String, "2 likes")
        // Return upward inside this thread, never the retained Plan scroll.
        let thread = app.scrollViews["table-post-thread"]
        for _ in 0..<12 {
            if disclosure.isHittable { break }
            thread.swipeDown()
        }
        XCTAssertTrue(disclosure.isHittable); disclosure.tap()
        XCTAssertEqual(disclosure.label, "View 4 replies")
        XCTAssertFalse(reply.exists)
        disclosure.tap(); reveal(reply)
        XCTAssertEqual(reply.value as? String, "1 like", "Collapsing cannot reset a reaction")
        capture("long-replies-expanded-" + (large ? "AX5" : "default"))
    }

    func testNotificationTargetOpensItsCollapsedReplyPath() {
        launch(thread: false, flags: ["-plated-review-long-replies", "-plated-review-target-reply"])
        let target = app.buttons["comment-like-note-review-target"]
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: target)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 10), .completed,
                       "The notification route must reveal and scroll to its target without a test swipe")
        let disclosure = app.buttons["table-replies-note-review-parent"]
        XCTAssertEqual(disclosure.value as? String, "Expanded")
        XCTAssertEqual(disclosure.label, "Hide replies")
        XCTAssertFalse(app.buttons["comment-like-note-review-deleted"].exists)
        XCTAssertEqual(target.value as? String, "0 likes")
        capture("long-replies-notification-target")
    }

}
