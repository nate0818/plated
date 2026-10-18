import XCTest
@testable import Plated

final class TablePostContentTests: XCTestCase {
    func testWritingAboutAnIngredientOrRestaurantNeedsNoDishTitleOrPhoto() {
        for text in ["These tomatoes are finally in season.", "We loved the little cafe on Main Street."] {
            let post = TablePostContent(title: "", caption: text, hasPhoto: false)
            XCTAssertTrue(post.isValid)
            XCTAssertEqual(post.wireKind, "post")
        }
    }

    func testWhitespaceCannotPublishAndPhotoAloneCan() {
        XCTAssertFalse(TablePostContent(title: " \n", caption: "\t ", hasPhoto: false).isValid)
        XCTAssertTrue(TablePostContent(title: "", caption: "", hasPhoto: true).isValid)
        XCTAssertTrue(TablePostContent(title: " Farmers market ", caption: "", hasPhoto: false).isValid)
    }

    func testPendingPollChoiceCountsAndDuplicateChoicesDoNot() {
        let poll = TablePostContent(title: "Friday", caption: "Where should we go?", hasPhoto: true,
                                    choices: [" Thai "], pendingChoice: "Pizza")
        XCTAssertTrue(poll.isValid)
        XCTAssertEqual(poll.choices, ["Thai", "Pizza"])
        XCTAssertEqual(poll.wireKind, "ask")
        XCTAssertFalse(TablePostContent(title: "", caption: "Where?", hasPhoto: false,
                                        choices: ["Thai"], pendingChoice: " thai ").isValid)
        XCTAssertFalse(TablePostContent(title: "Friday", caption: " ", hasPhoto: true,
                                        choices: ["Thai", "Pizza"]).isValid)
    }

    func testPollRemainsBoundedAndRecipeSharingRetainsItsMeaning() {
        let poll = TablePostContent(title: "", caption: "Pick one", hasPhoto: false,
                                    choices: ["A", "B", "C", "D"], pendingChoice: "E", isRecipe: true)
        XCTAssertEqual(poll.choices.count, 4)
        XCTAssertEqual(poll.wireKind, "ask")
        XCTAssertEqual(TablePostContent(title: "Soup", caption: "", hasPhoto: true, isRecipe: true).wireKind, "dish")
    }

    func testGeneralDraftRetainsEveryOptionalAttachment() throws {
        let draft = TableComposerDraft(title: "Cafe", caption: "Worth a visit", kind: "Post",
            poll: [], pollEntry: "", tags: ["Alessandra"], destination: "chosen-table", photo: Data([1, 2, 3]))
        let decoded = try JSONDecoder().decode(TableComposerDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(decoded, draft)
        let legacy = TableComposerDraft(title: "Soup", caption: "Dinner", kind: "Dish", poll: [],
                                       pollEntry: "", tags: [], destination: nil, photo: nil)
        XCTAssertEqual(try JSONDecoder().decode(TableComposerDraft.self, from: JSONEncoder().encode(legacy)), legacy)
    }
}
