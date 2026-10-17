import XCTest

final class FailureRepairTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.natemeadows.plated")
    override func setUp() { continueAfterFailure = false }
    func launch(_ flags: [String], failure: String? = nil) {
        app.terminate()
        app.launchArguments = ["-plated-design-review", "-appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"] + flags
        if let failure { app.launchArguments += ["-plated-review-fail-save",failure] }
        app.launch(); XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout:20))
    }
    func tap(_ item: XCUIElement) {
        XCTAssertTrue(item.waitForExistence(timeout:8))
        item.coordinate(withNormalizedOffset: CGVector(dx:0.5,dy:0.5)).tap()
    }
    func reveal(_ item: XCUIElement) {
        for _ in 0..<8 {
            if item.exists && item.isHittable && item.frame.maxY < app.frame.maxY - 20 { return }
            app.swipeUp()
        }
    }
    func capture(_ name: String) {
        let a = XCTAttachment(screenshot:app.screenshot()); a.name=name;a.lifetime = .keepAlways;add(a)
        let t = XCTAttachment(string:app.debugDescription);t.name=name+"-tree";t.lifetime = .keepAlways;add(t)
    }
    func testRejectedRecipeEditCanDiscardWithoutChangingOriginal() {
        launch(["-plated-open-recipe-detail"],failure:"save recipe")
        tap(app.buttons["Edit recipe"])
        let field=app.textFields["Name the dish"]
        XCTAssertTrue(field.waitForExistence(timeout:8)); let original=field.value as? String
        tap(field);field.typeText(" FAILED SAVE")
        if app.buttons["Done"].exists { tap(app.buttons["Done"]) }
        tap(app.buttons["Save changes"])
        XCTAssertTrue(app.staticTexts["Couldn't save the recipe yet. Your work is still here."].waitForExistence(timeout:8))
        capture("failure-recipe-retained")
        tap(app.buttons["Cancel"]);tap(app.buttons["Discard"])
        tap(app.buttons["Edit recipe"])
        XCTAssertEqual(field.value as? String,original)
        capture("failure-recipe-original-restored")
    }
    func testProfileSaveFailureKeepsDraftOpen() {
        launch(["-plated-open-profile","-plated-open-edit-profile"],failure:"save profile")
        let bio=app.textFields["A short line about you"];reveal(bio);tap(bio);bio.typeText(" UX retained draft")
        tap(app.buttons["Done"])
        let save=app.buttons["Save"].firstMatch;reveal(save)
        capture("profile-save-reachable")
        XCTAssertTrue(save.isHittable)
        tap(save)
        let error=app.staticTexts["That didn’t save. Your draft is still here."]
        XCTAssertTrue(error.waitForExistence(timeout:8))
        XCTAssertTrue(app.buttons["Cancel"].exists)
        capture("failure-profile-draft-retained")
    }
    func testPlannerSaveFailureHasNoSuccessReceipt() {
        launch(["-plated-open-recipe-detail"],failure:"plan recipe")
        let plan=app.buttons["recipe-plan"];reveal(plan);tap(plan)
        // The graphical date picker starts on today's date.
        let replace=app.buttons.matching(NSPredicate(format:"label BEGINSWITH 'Replace '")).firstMatch
        tap(replace)
        XCTAssertTrue(app.staticTexts["Couldn't save this night. Your choices are still here. Try again."].waitForExistence(timeout:8))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH 'Plated for '")).firstMatch.exists)
        capture("failure-planner-no-success-receipt")
    }
    func testGatheringSaveFailureAndDraftReopen() {
        let flags=["-plated-review-plan-night","-plated-review-gathering"]
        launch(flags,failure:"save gathering")
        let title=app.textFields["Sunday dinner party"];tap(title)
        if let existing = title.value as? String, existing != "Sunday dinner party" {
            title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        title.typeText("UX gathering draft")
        app.swipeUp()
        tap(app.buttons["Save gathering"])
        XCTAssertTrue(app.staticTexts["Couldn't save the gathering. Your draft is still here."].waitForExistence(timeout:8))
        capture("failure-gathering-retained")
        app.terminate();launch(flags,failure:"save gathering")
        XCTAssertEqual(title.value as? String,"UX gathering draft")
        capture("failure-gathering-draft-reopened")
    }
    func testEmptySharedAndCompletedTonight() {
        launch(["-plated-tab","week","-plated-review-empty-tonight"])
        XCTAssertTrue(app.buttons["Plan tonight"].waitForExistence(timeout:8));capture("state-empty-tonight")
        launch(["-plated-tab","week","-plated-review-shared-tonight"])
        tap(app.buttons["Start cooking"].firstMatch)
        XCTAssertTrue(app.staticTexts["Serves 6"].waitForExistence(timeout:8));capture("state-shared-cooking-six")
        tap(app.buttons["End cooking"]);tap(app.buttons["End cooking"].firstMatch)
        launch(["-plated-tab","week"])
        tap(app.buttons["Start cooking"].firstMatch);tap(app.buttons["Finish cooking"])
        XCTAssertTrue(app.staticTexts["Dinner, made."].waitForExistence(timeout:8));capture("state-cooking-completed")
        tap(app.buttons["Done"])
        XCTAssertTrue(app.staticTexts["Dinner made"].waitForExistence(timeout:8));capture("state-tonight-completed")
    }
}
